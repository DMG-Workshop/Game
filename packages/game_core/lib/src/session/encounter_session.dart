import 'package:pf2e_core/pf2e_core.dart';

import '../campaign/creature.dart';
import '../campaign/gear.dart';
import '../party/equipment.dart';
import '../party/experience.dart';
import 'session_actor.dart';

/// Thrown when an action is not legal right now.
class InvalidActionException implements Exception {
  InvalidActionException(this.message);

  final String message;

  @override
  String toString() => 'InvalidActionException: $message';
}

/// How a fight ended.
enum EncounterOutcome { victory, defeat, fled }

/// Someone taking part in a fight.
class Combatant {
  Combatant({
    required this.id,
    required this.name,
    required this.isEnemy,
    required this.armorClass,
    required this.maxHp,
    required this.attackBonus,
    required this.damage,
    required this.perception,
    required this.zoneIndex,
    this.reachZones = 0,
    this.agile = false,
    this.creature,
    this.actor,
  }) : hp = maxHp;

  final String id;
  final String name;
  final bool isEnemy;

  final int armorClass;
  final int maxHp;
  final int attackBonus;
  final DamageExpression damage;
  final int perception;

  /// How many zones this combatant's attack can cross. 0 is melee.
  final int reachZones;

  /// Agile weapons take a smaller multiple attack penalty.
  final bool agile;

  final Creature? creature;
  final SessionActor? actor;

  int hp;
  int zoneIndex;
  int initiative = 0;

  /// Attacks already made this turn, which drives the multiple attack penalty.
  int attacksThisTurn = 0;

  bool get isDown => hp <= 0;

  /// The multiple attack penalty for this combatant's next strike.
  ///
  /// Pathfinder's second attack in a turn takes -5 and the third -10, halved
  /// for agile weapons. It is the main reason a third attack is usually a bad
  /// idea, so it has to be visible rather than silent.
  int get nextAttackPenalty {
    if (attacksThisTurn == 0) return 0;
    final step = agile ? 4 : 5;
    return -(step * (attacksThisTurn > 2 ? 2 : attacksThisTurn));
  }

  void takeDamage(int amount) {
    hp -= amount;
    if (hp < 0) hp = 0;
  }

  @override
  String toString() => '$name ($hp/$maxHp)';
}

/// One combatant's initiative: a d20 plus their Perception.
class InitiativeRoll {
  const InitiativeRoll({
    required this.combatant,
    required this.die,
    required this.modifier,
  });

  final Combatant combatant;
  final int die;
  final int modifier;

  int get total => die + modifier;

  @override
  String toString() {
    final sign = modifier >= 0 ? '+' : '';
    return '${combatant.name}: d20($die) $sign$modifier = $total';
  }
}

/// One d100 against a creature's drop table.
class LootRoll {
  const LootRoll({
    required this.creature,
    required this.item,
    required this.die,
    required this.chance,
  });

  final Creature creature;
  final GearItem item;

  /// The d100's face; the item drops on [chance] or under.
  final int die;
  final int chance;

  bool get dropped => die <= chance;

  @override
  String toString() => '${item.name} from ${creature.name}: d100($die) '
      'against $chance% — ${dropped ? 'found' : 'not there'}';
}

/// What one defeated creature was worth.
class XpAward {
  const XpAward({
    required this.creature,
    required this.partyLevel,
    required this.xp,
  });

  final Creature creature;
  final int partyLevel;
  final int xp;

  int get difference => creature.level - partyLevel;

  @override
  String toString() {
    final sign = difference >= 0 ? '+' : '';
    return '${creature.name} (level ${creature.level}, $sign$difference): '
        '$xp XP';
  }
}

/// The record of one strike.
class StrikeResult {
  const StrikeResult({
    required this.attacker,
    required this.target,
    required this.outcome,
    required this.damage,
    required this.penalty,
    this.damageRoll,
    this.targetDropped = false,
  });

  final Combatant attacker;
  final Combatant target;
  final CheckOutcome outcome;

  /// Damage dealt; zero on a miss.
  final int damage;

  /// The damage dice as they fell, or null on a miss.
  final DamageRoll? damageRoll;

  /// The multiple attack penalty that applied.
  final int penalty;
  final bool targetDropped;

  bool get isHit => outcome.degree.isSuccess;
  bool get isCritical => outcome.degree == DegreeOfSuccess.criticalSuccess;

  @override
  String toString() {
    if (!isHit) return '${attacker.name} misses ${target.name}.';
    final crit = isCritical ? ' critically' : '';
    return '${attacker.name}$crit hits ${target.name} for $damage.';
  }
}

/// A fight, run a turn at a time.
///
/// Positions are zones rather than squares: ordered bands of distance that
/// keep reach and closing meaningful without asking a phone to render a grid.
/// Everything else is the ordinary check resolver, so a strike is the same
/// arithmetic as picking a lock.
class EncounterSession {
  EncounterSession({
    required this.encounter,
    required Bestiary bestiary,
    required List<SessionActor> actors,
    required DiceRoller roller,
    GearTable? gear,
    Map<String, Loadout> loadouts = const {},
    List<Creature>? foes,
  })  : _roller = roller,
        _gear = gear,
        _loadouts = loadouts,
        _resolver = CheckResolver(roller) {
    if (actors.isEmpty) {
      throw ArgumentError.value(actors, 'actors', 'a fight needs a party');
    }

    for (final actor in actors) {
      _combatants.add(_combatantFor(actor));
    }

    final startIndex = encounter.zones.indexOf(encounter.startZone);
    var n = 0;
    for (final creature in foes ?? _lookUp(encounter, bestiary)) {
      _combatants.add(_combatantForCreature(
        creature,
        suffix: ++n,
        zoneIndex: startIndex < 0 ? encounter.zones.length - 1 : startIndex,
      ));
    }

    _rollInitiative();
  }

  static List<Creature> _lookUp(Encounter encounter, Bestiary bestiary) => [
        for (final id in encounter.creatureIds)
          bestiary.creatureById(id) ??
              (throw ArgumentError('Encounter "${encounter.id}" names unknown '
                  'creature "$id".')),
      ];

  final Encounter encounter;
  final DiceRoller _roller;
  final CheckResolver _resolver;

  /// The campaign's loot tables, when the caller wants drops rolled.
  final GearTable? _gear;

  /// What each actor is wielding and wearing, keyed by actor id. An actor
  /// with no entry fights with the kit their sheet was imported with.
  final Map<String, Loadout> _loadouts;

  final List<Combatant> _combatants = [];
  int _turnIndex = 0;
  int _round = 1;
  int _actionsLeft = actionsPerTurn;
  EncounterOutcome? _outcome;
  List<GearItem> _loot = const [];
  int _coinEarned = 0;
  int _xpEarned = 0;
  final List<InitiativeRoll> _initiative = [];
  final List<StrikeResult> _opening = [];
  DamageRoll? _coinRoll;
  final List<LootRoll> _lootRolls = [];
  final List<XpAward> _xpAwards = [];

  /// Pathfinder gives three actions a turn, which is what makes a third
  /// attack a real choice rather than a free one.
  static const int actionsPerTurn = 3;

  List<Combatant> get combatants => List.unmodifiable(_combatants);
  List<Combatant> get party => [
        for (final c in _combatants)
          if (!c.isEnemy) c
      ];
  List<Combatant> get enemies => [
        for (final c in _combatants)
          if (c.isEnemy) c
      ];

  int get round => _round;
  int get actionsLeft => _actionsLeft;
  EncounterOutcome? get outcome => _outcome;
  bool get isOver => _outcome != null;

  Combatant get current => _combatants[_turnIndex];
  bool get isPartyTurn => !current.isEnemy;

  List<String> get zones => encounter.zones;

  /// Flags the party earns by winning.
  List<String> get victoryFlags =>
      _outcome == EncounterOutcome.victory ? encounter.victoryFlags : const [];

  /// What the defeated were carrying.
  ///
  /// Rolled once, at the moment the fight is won, rather than each time this
  /// is read — a drop that changed depending on how often the client asked
  /// about it would be no drop at all.
  List<GearItem> get loot => _loot;

  /// Coin found on the defeated, in copper. Zero unless the fight was won.
  int get coinEarned => _coinEarned;

  /// XP each member of the party earns for winning.
  ///
  /// Pathfinder's: each creature is worth XP by its level against the party's,
  /// and everyone in the party earns the total. Worked out here because the
  /// fight is the one place that knows both who fought and what they fought.
  int get xpEarned => _xpEarned;

  /// Everyone's initiative roll, in the order they act.
  List<InitiativeRoll> get initiativeRolls => List.unmodifiable(_initiative);

  /// Strikes made before anyone in the party had a turn: enemies that beat
  /// the whole party's initiative act first, and the party should see it.
  List<StrikeResult> get openingStrikes => List.unmodifiable(_opening);

  /// The dice the coin was rolled on, once the fight is won.
  DamageRoll? get coinRoll => _coinRoll;

  /// Every d100 rolled against a drop table, found or not.
  List<LootRoll> get lootRolls => List.unmodifiable(_lootRolls);

  /// What each defeated creature was worth, adding up to [xpEarned].
  List<XpAward> get xpAwards => List.unmodifiable(_xpAwards);

  /// The loot as flags, so recovering something is recorded the same way as
  /// everything else the party has done.
  List<String> get lootFlags => [for (final item in _loot) 'loot_${item.id}'];

  Combatant? combatantById(String id) {
    for (final c in _combatants) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Enemies the current combatant could strike without moving.
  List<Combatant> targetsInReach() {
    final actor = current;
    return [
      for (final c in _combatants)
        if (c.isEnemy != actor.isEnemy &&
            !c.isDown &&
            _distance(actor, c) <= actor.reachZones)
          c,
    ];
  }

  /// Strikes [targetId] with the current combatant.
  StrikeResult strike(String targetId) {
    _requirePartyTurn();
    _requireActions(1);

    final attacker = current;
    final target = combatantById(targetId);
    if (target == null || target.isEnemy == attacker.isEnemy) {
      throw InvalidActionException('There is no enemy called "$targetId".');
    }
    if (target.isDown) {
      throw InvalidActionException('${target.name} is already down.');
    }
    if (_distance(attacker, target) > attacker.reachZones) {
      throw InvalidActionException(
          '${target.name} is too far away. Close the distance first.');
    }

    final result = _resolveStrike(attacker, target);
    _actionsLeft--;
    _checkOutcome();
    return result;
  }

  /// Moves the current combatant one zone toward the enemy, or away.
  ({String zone, bool closer}) stride({bool closer = true}) {
    _requirePartyTurn();
    _requireActions(1);

    final actor = current;
    final target = _nearestOpponent(actor);
    if (target == null) {
      throw InvalidActionException('There is nobody left to close on.');
    }

    // Level with the nearest enemy is as close as it gets. Without this check,
    // "not further along" read as "behind", and closing on someone already at
    // arm's length walked you a zone away from them.
    if (closer && actor.zoneIndex == target.zoneIndex) {
      throw InvalidActionException('You are already as close as you can get.');
    }

    final before = actor.zoneIndex;
    if (closer) {
      actor.zoneIndex += actor.zoneIndex < target.zoneIndex ? 1 : -1;
    } else {
      actor.zoneIndex += actor.zoneIndex < target.zoneIndex ? -1 : 1;
    }
    actor.zoneIndex = actor.zoneIndex.clamp(0, encounter.zones.length - 1);

    if (actor.zoneIndex == before) {
      throw InvalidActionException(closer
          ? 'You are already as close as you can get.'
          : 'There is '
              'nowhere further to go.');
    }

    _actionsLeft--;
    return (zone: encounter.zones[actor.zoneIndex], closer: closer);
  }

  /// Ends the current turn and runs everything up to the next party turn.
  ///
  /// Enemy turns resolve here rather than being stepped through, because a
  /// client should render them as a block of narration, not as prompts.
  List<StrikeResult> endTurn() {
    if (isOver) throw InvalidActionException('The fight is over.');
    final log = <StrikeResult>[];

    _advanceTurn();
    while (!isOver && current.isEnemy) {
      log.addAll(_runEnemyTurn());
      if (isOver) break;
      _advanceTurn();
    }
    return log;
  }

  /// Leaves the fight. Whether that is allowed is the caller's decision.
  void flee() {
    if (isOver) throw InvalidActionException('The fight is over.');
    _outcome = EncounterOutcome.fled;
  }

  // --- internals -----------------------------------------------------------

  void _requirePartyTurn() {
    if (isOver) throw InvalidActionException('The fight is over.');
    if (current.isEnemy) {
      throw InvalidActionException('It is ${current.name}\'s turn.');
    }
    if (current.isDown) {
      throw InvalidActionException('${current.name} is down.');
    }
  }

  void _requireActions(int cost) {
    if (_actionsLeft < cost) {
      throw InvalidActionException('No actions left this turn.');
    }
  }

  int _distance(Combatant a, Combatant b) => (a.zoneIndex - b.zoneIndex).abs();

  Combatant? _nearestOpponent(Combatant actor) {
    Combatant? best;
    for (final c in _combatants) {
      if (c.isEnemy == actor.isEnemy || c.isDown) continue;
      if (best == null || _distance(actor, c) < _distance(actor, best)) {
        best = c;
      }
    }
    return best;
  }

  StrikeResult _resolveStrike(Combatant attacker, Combatant target) {
    final penalty = attacker.nextAttackPenalty;
    final outcome = _resolver.resolve(
      modifier: attacker.attackBonus + penalty,
      dc: target.armorClass,
      label: '${attacker.name} strikes ${target.name}',
    );
    attacker.attacksThisTurn++;

    final damageRoll = outcome.degree.isSuccess
        ? attacker.damage.rollDetailed(
            _roller,
            critical: outcome.degree == DegreeOfSuccess.criticalSuccess,
          )
        : null;
    final damage = damageRoll?.total ?? 0;

    final wasStanding = !target.isDown;
    if (damage > 0) target.takeDamage(damage);

    return StrikeResult(
      attacker: attacker,
      target: target,
      outcome: outcome,
      damage: damage,
      damageRoll: damageRoll,
      penalty: penalty,
      targetDropped: wasStanding && target.isDown,
    );
  }

  List<StrikeResult> _runEnemyTurn() {
    final actor = current;
    final log = <StrikeResult>[];
    if (actor.isDown) return log;

    var actions = actionsPerTurn;
    while (actions > 0 && !isOver) {
      final target = _nearestOpponent(actor);
      if (target == null) break;

      if (_distance(actor, target) <= actor.reachZones) {
        log.add(_resolveStrike(actor, target));
        _checkOutcome();
      } else {
        // Close the distance rather than stand there; a creature that cannot
        // reach anyone and does not move is just a spectator.
        actor.zoneIndex += actor.zoneIndex < target.zoneIndex ? 1 : -1;
        actor.zoneIndex = actor.zoneIndex.clamp(0, encounter.zones.length - 1);
      }
      actions--;
    }
    return log;
  }

  void _advanceTurn() {
    current.attacksThisTurn = 0;
    var guard = 0;
    do {
      _turnIndex++;
      if (_turnIndex >= _combatants.length) {
        _turnIndex = 0;
        _round++;
      }
      guard++;
    } while (current.isDown && guard <= _combatants.length);

    _actionsLeft = actionsPerTurn;
    current.attacksThisTurn = 0;
  }

  void _checkOutcome() {
    if (_outcome != null) return;
    if (enemies.every((c) => c.isDown)) {
      _outcome = EncounterOutcome.victory;
      _rollLoot();
      _rollCoin();
      _countXp();
    } else if (party.every((c) => c.isDown)) {
      _outcome = EncounterOutcome.defeat;
    }
  }

  void _rollCoin() {
    final dice = encounter.coin;
    if (dice == null) return;
    final roll = DamageExpression.parse(dice).rollDetailed(_roller);
    _coinRoll = roll;
    _coinEarned = roll.total * 100;
  }

  void _countXp() {
    final level = partyLevel([
      for (final c in party)
        if (c.actor case final actor?) actor.character.level,
    ]);
    for (final c in enemies) {
      final creature = c.creature;
      if (creature == null) continue;
      _xpAwards.add(XpAward(
        creature: creature,
        partyLevel: level,
        xp: creatureXp(creature.level - level),
      ));
    }
    _xpEarned = _xpAwards.fold(0, (sum, a) => sum + a.xp);
  }

  /// Rolls each defeated creature's drop table.
  ///
  /// Rolled on the session's own dice, so a seed replays the same loot on a
  /// phone as in a browser. The same item never drops twice from one fight:
  /// three thralls is three chances at the nail, not three nails.
  void _rollLoot() {
    final gear = _gear;
    if (gear == null) return;

    final found = <String, GearItem>{};
    for (final enemy in enemies) {
      final creature = enemy.creature;
      if (creature == null) continue;
      for (final item in gear.droppedBy(creature.id)) {
        if (found.containsKey(item.id)) continue;
        final roll = LootRoll(
          creature: creature,
          item: item,
          die: _roller.rollDie(100),
          chance: item.dropFrom(creature.id)!.chance,
        );
        _lootRolls.add(roll);
        if (roll.dropped) found[item.id] = item;
      }
    }

    _loot = found.values.toList()..sort((a, b) => a.level.compareTo(b.level));
  }

  void _rollInitiative() {
    final rolls = <Combatant, InitiativeRoll>{};
    for (final c in _combatants) {
      final roll = InitiativeRoll(
          combatant: c, die: _roller.d20(), modifier: c.perception);
      rolls[c] = roll;
      c.initiative = roll.total;
    }
    // Ties go to the party, which is the usual table convention and spares a
    // tie-breaking roll nobody wants to narrate.
    _combatants.sort((a, b) {
      final byRoll = b.initiative.compareTo(a.initiative);
      if (byRoll != 0) return byRoll;
      if (a.isEnemy == b.isEnemy) return a.name.compareTo(b.name);
      return a.isEnemy ? 1 : -1;
    });
    _initiative.addAll([for (final c in _combatants) rolls[c]!]);
    _turnIndex = 0;
    _actionsLeft = actionsPerTurn;

    // An enemy may act before anyone in the party does. What it does is kept:
    // a party that opens the fight already bleeding should know why.
    if (current.isEnemy) {
      while (!isOver && current.isEnemy) {
        _opening.addAll(_runEnemyTurn());
        if (isOver) break;
        _advanceTurn();
      }
    }
  }

  Combatant _combatantFor(SessionActor actor) {
    // Equipment is applied here rather than baked into the sheet: what a
    // character is holding changes between fights, and the import does not.
    final equipped = EquippedStats(
      actor.stats,
      _loadouts[actor.id] ?? const Loadout(),
    );

    return Combatant(
      id: actor.id,
      name: actor.name,
      isEnemy: false,
      armorClass: equipped.armorClass,
      maxHp: actor.stats.maxHp,
      attackBonus: equipped.attackBonus,
      damage: equipped.damage,
      perception: actor.stats.perception.total,
      zoneIndex: 0,
      agile: equipped.isAgile,
      actor: actor,
    );
  }

  Combatant _combatantForCreature(
    Creature creature, {
    required int suffix,
    required int zoneIndex,
  }) {
    final attack = creature.bestAttack;
    final reach = attack == null
        ? 0
        : encounter.zones
            .indexOf(attack.reach)
            .clamp(0, encounter.zones.length);

    return Combatant(
      id: '${creature.id}_$suffix',
      name: creature.name,
      isEnemy: true,
      armorClass: creature.armorClass,
      maxHp: creature.maxHp,
      attackBonus: attack?.attackBonus ?? 0,
      damage: attack == null
          ? DamageExpression.parse('1d4')
          : DamageExpression.tryParse(attack.damage) ??
              DamageExpression.parse('1d4'),
      perception: creature.perception,
      zoneIndex: zoneIndex,
      reachZones: reach < 0 ? 0 : reach,
      agile:
          attack?.traits.any((t) => t.trim().toLowerCase() == 'agile') ?? false,
      creature: creature,
    );
  }
}
