/// One way a creature can hurt someone.
class CreatureAttack {
  const CreatureAttack({
    required this.name,
    required this.attackBonus,
    required this.damage,
    this.damageType = 'B',
    this.traits = const [],
    this.reach = 'engaged',
    this.onCritical,
  });

  final String name;
  final int attackBonus;

  /// Damage expression, e.g. `2d8+6`.
  final String damage;
  final String damageType;
  final List<String> traits;

  /// The furthest zone this can reach from.
  final String reach;

  /// Free text describing what a critical hit adds, not yet mechanised.
  final String? onCritical;

  @override
  String toString() => '$name +$attackBonus ($damage $damageType)';
}

/// A creature's statblock.
///
/// Deliberately flat: level, defences, and attacks. Pathfinder creatures have
/// far more, but implementing half a statblock badly is worse than
/// implementing a small one honestly, and the parts absent here are the parts
/// the engine cannot yet act on.
class Creature {
  const Creature({
    required this.id,
    required this.name,
    required this.level,
    required this.armorClass,
    required this.maxHp,
    required this.attacks,
    this.description = '',
    this.perception = 0,
    this.fortitude = 0,
    this.reflex = 0,
    this.will = 0,
    this.traits = const [],
    this.speed = 25,
    this.specials = const [],
    this.isBoss = false,
  });

  final String id;
  final String name;
  final int level;
  final String description;

  final int armorClass;
  final int maxHp;
  final int perception;
  final int fortitude;
  final int reflex;
  final int will;

  final List<String> traits;
  final int speed;
  final List<CreatureAttack> attacks;

  /// Abilities described in text. Carried through rather than interpreted,
  /// so a reader sees the whole creature even where the engine cannot run it.
  final List<String> specials;

  final bool isBoss;

  CreatureAttack? get bestAttack {
    if (attacks.isEmpty) return null;
    return attacks.reduce((a, b) => b.attackBonus > a.attackBonus ? b : a);
  }

  /// The save bonus for [key], or null when it is not a save.
  int? saveFor(String key) => switch (key.trim().toLowerCase()) {
        'fortitude' || 'fort' => fortitude,
        'reflex' || 'ref' => reflex,
        'will' => will,
        'perception' => perception,
        _ => null,
      };

  @override
  String toString() => '$name (level $level, AC $armorClass, $maxHp HP)';
}

/// A fight waiting in a room.
class Encounter {
  const Encounter({
    required this.id,
    required this.location,
    required this.name,
    required this.creatureIds,
    this.description = '',
    this.zones = const ['engaged', 'near', 'far'],
    this.startZone = 'near',
    this.victoryFlags = const [],
    this.requiredFlags = const [],
    this.repeatable = false,
    this.rearmOn = const [],
    this.rearmDescription,
    this.ambush = false,
    this.coin,
  });

  final String id;

  /// Room this happens in.
  final String location;
  final String name;
  final String description;

  /// Creatures that show up, by id. A creature may appear more than once.
  final List<String> creatureIds;

  /// Ordered nearest-first. Position is abstract rather than a grid, which
  /// keeps reach and closing distance meaningful in a text game without
  /// asking a phone to render squares.
  final List<String> zones;

  /// Where the enemies begin.
  final String startZone;

  /// Flags set when the party wins.
  final List<String> victoryFlags;

  /// Flags that must be set before this encounter triggers at all.
  final List<String> requiredFlags;

  /// Whether it can happen again once resolved.
  final bool repeatable;

  /// Flags that bring this fight back after it has been won.
  ///
  /// Each one set is another wave: the road the party fought down is full
  /// again on the way back, because whoever sent them down it was waiting
  /// for them to reach the end.
  final List<String> rearmOn;

  /// What the party sees when the fight has come back, if it differs.
  final String? rearmDescription;

  /// What the defeated were carrying, in gold, as dice: `3d6`, `2d10+40`.
  ///
  /// Rolled every time the fight is won, waves included: whoever came back
  /// up the road came back with their own purses.
  final String? coin;

  /// True when it stops the party walking on past it.
  ///
  /// An ambush leaves exactly one way out, the way the party came in. Without
  /// that, a fight is scenery the party can stroll through, and a road that
  /// fills up behind them costs nothing.
  final bool ambush;

  /// How many times this fight has been brought back.
  int waveFor(Set<String> flags) => rearmOn.where(flags.contains).length;

  /// The flag that records winning [wave] of this fight.
  String wonFlag(int wave) => 'won_${id}_wave_$wave';

  bool isAvailable(Set<String> flags) {
    if (!requiredFlags.every(flags.contains)) return false;
    if (repeatable) return true;

    final wave = waveFor(flags);
    if (flags.contains(wonFlag(wave))) return false;
    // The first time through, a win is also known by its victory flags —
    // which is all a save from before waves existed has to go on.
    if (wave == 0 && victoryFlags.any(flags.contains)) return false;
    return true;
  }

  /// The description for the wave the party is facing.
  String descriptionFor(Set<String> flags) {
    final rearmed = rearmDescription;
    return waveFor(flags) > 0 && rearmed != null ? rearmed : description;
  }

  @override
  String toString() => '$name @ $location';
}

/// The campaign's creatures and encounters.
class Bestiary {
  Bestiary({
    List<Creature> creatures = const [],
    List<Encounter> encounters = const [],
  })  : _creatures = List.of(creatures),
        _encounters = List.of(encounters) {
    for (final encounter in _encounters) {
      _byRoom.putIfAbsent(encounter.location, () => []).add(encounter);
    }
  }

  final List<Creature> _creatures;
  final List<Encounter> _encounters;
  final Map<String, List<Encounter>> _byRoom = {};

  List<Creature> get creatures => List.unmodifiable(_creatures);
  List<Encounter> get encounters => List.unmodifiable(_encounters);

  Creature? creatureById(String id) {
    for (final creature in _creatures) {
      if (creature.id == id) return creature;
    }
    return null;
  }

  Encounter? encounterById(String id) {
    for (final encounter in _encounters) {
      if (encounter.id == id) return encounter;
    }
    return null;
  }

  List<Encounter> inRoom(String roomId) =>
      List.unmodifiable(_byRoom[roomId] ?? const []);

  /// Encounters in [roomId] that are currently available.
  List<Encounter> availableIn(String roomId, Set<String> flags) => [
        for (final e in inRoom(roomId))
          if (e.isAvailable(flags)) e
      ];

  /// The ambush waiting in [roomId], if one is.
  Encounter? ambushIn(String roomId, Set<String> flags) {
    for (final e in availableIn(roomId, flags)) {
      if (e.ambush) return e;
    }
    return null;
  }

  /// Encounters placed in a room that does not exist.
  List<Encounter> misplacedIn(Set<String> knownRoomIds) => [
        for (final e in _encounters)
          if (!knownRoomIds.contains(e.location)) e,
      ];

  /// Encounters naming a creature the bestiary does not have.
  List<({Encounter encounter, String creatureId})> get missingCreatures {
    final out = <({Encounter encounter, String creatureId})>[];
    for (final encounter in _encounters) {
      for (final id in encounter.creatureIds) {
        if (creatureById(id) == null) {
          out.add((encounter: encounter, creatureId: id));
        }
      }
    }
    return out;
  }

  /// Every flag winning a fight can set.
  Set<String> get victoryFlags =>
      {for (final e in _encounters) ...e.victoryFlags};

  @override
  String toString() =>
      '${_creatures.length} creatures, ${_encounters.length} encounters';
}
