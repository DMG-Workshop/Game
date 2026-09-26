import 'package:pf2e_core/pf2e_core.dart';

import '../party/experience.dart';
import '../party/wealth.dart';
import 'creature.dart';

/// How dangerous a fight is meant to be, as Pathfinder budgets it.
///
/// A budget in XP for four characters, and what each character more or fewer
/// adds or takes away.
enum Threat {
  trivial(40, 10),
  low(60, 15),
  moderate(80, 20),
  severe(120, 30),
  extreme(160, 40);

  const Threat(this.budget, this.perCharacter);

  final int budget;
  final int perCharacter;

  /// The budget for a party of [partySize].
  int budgetFor(int partySize) =>
      budget + ((partySize < 1 ? 1 : partySize) - 4) * perCharacter;

  /// How many levels above the party a creature can be, alone, and still fit
  /// this threat for a party of [partySize].
  ///
  /// The largest difference whose creature XP fits the budget. Four characters
  /// facing a moderate threat meet one creature two levels up; one character
  /// facing the same meets one two levels down.
  int loneCreatureOffset(int partySize) {
    final budget = budgetFor(partySize);
    for (var difference = 4; difference > -5; difference--) {
      if (creatureXp(difference) <= budget) return difference;
    }
    return -4;
  }

  static Threat? tryParse(String source) {
    final needle = source.trim().toLowerCase();
    for (final t in values) {
      if (t.name == needle) return t;
    }
    return null;
  }
}

/// How far word of the party has spread, by how rich they are.
class NotorietyTier {
  const NotorietyTier({
    required this.name,
    required this.fromPercent,
    this.threat,
    this.chance = 0,
    this.description = '',
  });

  final String name;

  /// The party's worth, as a percentage of what is expected of it, at which
  /// this tier begins.
  final int fromPercent;

  /// How hard whatever comes after them is, or null for nothing coming.
  final Threat? threat;

  /// The chance, in percent, that something finds them each step they take.
  final int chance;

  /// What it feels like, for a status line.
  final String description;

  bool get isHunted => threat != null && chance > 0;

  @override
  String toString() => name;
}

/// Something that comes after a party worth robbing.
class Hunter {
  const Hunter({
    required this.creatureId,
    required this.coin,
    this.arrival = '',
  });

  final String creatureId;

  /// What it was carrying, in gold, as dice — rolled when it is beaten.
  final String coin;

  /// What the party sees when it finds them.
  final String arrival;
}

/// A hunter at the level it came at.
class Pursuer {
  const Pursuer({
    required this.hunter,
    required this.creature,
    this.adjustment,
  });

  final Hunter hunter;

  /// The creature as it arrives, adjustments applied.
  final Creature creature;

  /// `elite`, `weak`, or null for the creature as written.
  final String? adjustment;

  /// The fight it brings, standing in [roomId].
  Encounter encounterIn(String roomId) => Encounter(
        id: 'hunt_${hunter.creatureId}',
        location: roomId,
        name: 'Hunted: ${creature.name}',
        description: hunter.arrival,
        creatureIds: [creature.id],
        startZone: 'near',
        coin: hunter.coin,
      );
}

/// How rich a party is against what is expected of it, and what that brings.
class Notoriety {
  const Notoriety({
    required this.wealth,
    required this.tier,
    required this.partyLevel,
    required this.partySize,
  });

  final Wealth wealth;
  final NotorietyTier tier;
  final int partyLevel;
  final int partySize;

  int get percent => wealth.percentOfExpected;

  /// The level a hunter would come at, or null when nothing is coming.
  ///
  /// The party's level, moved by what the tier's threat allows one creature
  /// to be against a party this size. Richer is a harder threat, and a higher
  /// party level lifts every threat with it.
  int? get hunterLevel {
    final threat = tier.threat;
    if (threat == null) return null;
    final level = partyLevel + threat.loneCreatureOffset(partySize);
    return level < -1 ? -1 : level;
  }

  @override
  String toString() => '$tier ($percent%)';
}

/// Who comes after a party that has got rich, and when.
class HuntTable {
  HuntTable({
    List<NotorietyTier> tiers = const [],
    List<Hunter> hunters = const [],
    this.restSteps = 6,
    this.robPercent = 0,
  })  : _tiers = List.of(tiers)
          ..sort((a, b) => a.fromPercent.compareTo(b.fromPercent)),
        _hunters = List.of(hunters);

  final List<NotorietyTier> _tiers;
  final List<Hunter> _hunters;

  /// Steps after one hunt before another can find the party.
  final int restSteps;

  /// How much of the purse, in percent, a hunter takes from a party it beats.
  final int robPercent;

  List<NotorietyTier> get tiers => List.unmodifiable(_tiers);
  List<Hunter> get hunters => List.unmodifiable(_hunters);

  bool get isEmpty => _hunters.isEmpty;

  static const _unremarked = NotorietyTier(name: 'Unremarked', fromPercent: 0);

  /// The tier a party worth [percent] of what is expected of it is in.
  NotorietyTier tierFor(int percent) {
    var found = _unremarked;
    for (final tier in _tiers) {
      if (percent >= tier.fromPercent) found = tier;
    }
    return found;
  }

  /// Every level a hunter could be sent at, adjustments included.
  Map<int, List<Pursuer>> reachableLevels(Bestiary bestiary) {
    final out = <int, List<Pursuer>>{};
    for (final hunter in _hunters) {
      final creature = bestiary.creatureById(hunter.creatureId);
      if (creature == null) continue;
      for (final pursuer in [
        Pursuer(hunter: hunter, creature: creature),
        Pursuer(
            hunter: hunter, creature: creature.elite(), adjustment: 'elite'),
        Pursuer(hunter: hunter, creature: creature.weak(), adjustment: 'weak'),
      ]) {
        out.putIfAbsent(pursuer.creature.level, () => []).add(pursuer);
      }
    }
    return out;
  }

  /// Picks a hunter to come at [level], on [dice].
  ///
  /// A creature written at that level is preferred to one adjusted to it,
  /// because the one written for the level is the better statblock. With
  /// nothing at the level at all, the nearest below it comes — the party
  /// should not be sent something harder than its wealth has earned.
  Pursuer? choose(int level, Bestiary bestiary, DiceRoller dice) {
    final byLevel = reachableLevels(bestiary);
    if (byLevel.isEmpty) return null;
    var target = level;
    final lowest = byLevel.keys.reduce((a, b) => a < b ? a : b);
    while (!byLevel.containsKey(target) && target > lowest) {
      target--;
    }
    final candidates = byLevel[target] ?? byLevel[lowest]!;
    final written = candidates.where((p) => p.adjustment == null).toList();
    final pool = written.isNotEmpty ? written : candidates;
    return pool[dice.rollDie(pool.length) - 1];
  }

  /// A hunter as it was when a game was saved.
  Pursuer? restore(String creatureId, String? adjustment, Bestiary bestiary) {
    final hunter =
        _hunters.where((h) => h.creatureId == creatureId).firstOrNull;
    final creature = bestiary.creatureById(creatureId);
    if (hunter == null || creature == null) return null;
    return Pursuer(
      hunter: hunter,
      creature: switch (adjustment) {
        'elite' => creature.elite(),
        'weak' => creature.weak(),
        _ => creature,
      },
      adjustment:
          adjustment == 'elite' || adjustment == 'weak' ? adjustment : null,
    );
  }

  /// Flags hunting sets: `hunted_first` the first time something finds the
  /// party, and `hunt_survived_<n>` each time they beat one.
  bool producesFlag(String flag) {
    if (isEmpty) return false;
    if (flag == 'hunted_first') return true;
    const prefix = 'hunt_survived_';
    return flag.startsWith(prefix) &&
        (int.tryParse(flag.substring(prefix.length)) ?? 0) > 0;
  }

  /// What is wrong with the roster, in words an author can act on.
  ///
  /// [levels] are the party levels the campaign runs through; a hunt has to
  /// be able to find a hunter for every one of them at every threat the
  /// tiers name, or a party that reaches that level is never hunted.
  List<String> problems(Bestiary bestiary, {required Iterable<int> levels}) {
    final out = <String>[];
    if (isEmpty) return out;
    for (final hunter in _hunters) {
      if (bestiary.creatureById(hunter.creatureId) == null) {
        out.add('Hunter "${hunter.creatureId}" is not in the bestiary');
      }
      final coin = DamageExpression.tryParse(hunter.coin);
      if (coin == null || coin.maximum <= 0) {
        out.add('Hunter "${hunter.creatureId}" pays "${hunter.coin}", which '
            'is not dice of gold');
      }
    }
    final reachable = reachableLevels(bestiary).keys.toSet();
    final wanted = <int>{};
    for (final tier in _tiers) {
      final threat = tier.threat;
      if (threat == null) continue;
      for (final level in levels) {
        for (var size = 1; size <= 4; size++) {
          final hunterLevel = level + threat.loneCreatureOffset(size);
          wanted.add(hunterLevel < -1 ? -1 : hunterLevel);
        }
      }
    }
    final missing = wanted.difference(reachable).toList()..sort();
    if (missing.isNotEmpty) {
      out.add('No hunter can be sent at level ${missing.join(', ')}');
    }
    return out;
  }

  @override
  String toString() => '${_tiers.length} tiers, ${_hunters.length} hunters';
}
