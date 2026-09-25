import 'package:pf2e_core/pf2e_core.dart';

import '../campaign/creature.dart';
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

/// The record of one strike.
class StrikeResult {
  const StrikeResult({
    required this.attacker,
    required this.target,
    required this.outcome,
    required this.damage,
    required this.penalty,
    this.targetDropped = false,
  });

  final Combatant attacker;
  final Combatant target;
  final CheckOutcome outcome;

  /// Damage dealt; zero on a miss.
  final int damage;

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
  })  : _roller = roller,
        _resolver = CheckResolver(roller) {
    if (actors.isEmpty) {
      throw ArgumentError.value(actors, 'actors', 'a fight needs a party');
    }

    for (final actor in actors) {
      _combatants.add(_combatantFor(actor));
    }

    final startIndex = encounter.zones.indexOf(encounter.startZone);
    var n = 0;
    for (final id in encounter.creatureIds) {
      final creature = bestiary.creatureById(id);
      if (creature == null) {
        throw ArgumentError('Encounter "${encounter.id}" names unknown '
            'creature "$id".');
      }
      _combatants.add(_combatantForCreature(
        creature,
        suffix: ++n,
        zoneIndex: startIndex < 0 ? encounter.zones.length - 1 : startIndex,
      ));
    }

    _rollInitiative();
  }

  final Encounter encounter;
  final DiceRoller _roller;
  final CheckResolver _resolver;

  final List<Combatant> _combatants = [];
  int _turnIndex = 0;
  int _round = 1;
  int _actionsLeft = actionsPerTurn;
  EncounterOutcome? _outcome;

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

    var damage = 0;
    if (outcome.degree == DegreeOfSuccess.criticalSuccess) {
      damage = attacker.damage.rollCritical(_roller);
    } else if (outcome.degree == DegreeOfSuccess.success) {
      damage = attacker.damage.roll(_roller);
    }

    final wasStanding = !target.isDown;
    if (damage > 0) target.takeDamage(damage);

    return StrikeResult(
      attacker: attacker,
      target: target,
      outcome: outcome,
      damage: damage,
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
    } else if (party.every((c) => c.isDown)) {
      _outcome = EncounterOutcome.defeat;
    }
  }

  void _rollInitiative() {
    for (final c in _combatants) {
      c.initiative = _roller.d20() + c.perception;
    }
    // Ties go to the party, which is the usual table convention and spares a
    // tie-breaking roll nobody wants to narrate.
    _combatants.sort((a, b) {
      final byRoll = b.initiative.compareTo(a.initiative);
      if (byRoll != 0) return byRoll;
      if (a.isEnemy == b.isEnemy) return a.name.compareTo(b.name);
      return a.isEnemy ? 1 : -1;
    });
    _turnIndex = 0;
    _actionsLeft = actionsPerTurn;

    // An enemy may act before anyone in the party does.
    if (current.isEnemy) {
      while (!isOver && current.isEnemy) {
        _runEnemyTurn();
        if (isOver) break;
        _advanceTurn();
      }
    }
  }

  Combatant _combatantFor(SessionActor actor) {
    final stats = actor.stats;
    final weapon =
        actor.character.weapons.isEmpty ? null : actor.character.weapons.first;

    final damage = weapon == null
        ? DamageExpression.parse('1d4')
        : DamageExpression.tryParse(weapon.damageFormula) ??
            DamageExpression.parse('1d4');

    return Combatant(
      id: actor.id,
      name: actor.name,
      isEnemy: false,
      armorClass: stats.armorClass,
      maxHp: stats.maxHp,
      attackBonus: weapon?.attackBonus ?? stats.perception.total,
      damage: damage,
      perception: stats.perception.total,
      zoneIndex: 0,
      agile: weapon?.runes.any((r) => r.toLowerCase() == 'agile') ?? false,
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
