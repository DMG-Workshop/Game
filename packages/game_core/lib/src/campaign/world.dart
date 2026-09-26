/// Global facts about a campaign world.
class WorldMetadata {
  const WorldMetadata({
    required this.name,
    required this.theme,
    required this.levelCap,
    required this.backgroundLore,
  });

  final String name;
  final String theme;
  final int levelCap;
  final String backgroundLore;

  @override
  String toString() => '$name ($theme, to level $levelCap)';
}

/// A group of towns sharing weather and ambiance.
class Region {
  const Region({
    required this.id,
    required this.towns,
    required this.ambianceEchoes,
    required this.weatherStates,
  });

  final String id;

  /// Town names, as written in the locations data.
  final List<String> towns;

  /// Lines echoed at intervals to everyone in the region.
  final List<String> ambianceEchoes;

  /// Weather key to the line describing it.
  final Map<String, String> weatherStates;

  bool get hasWeather => weatherStates.isNotEmpty;

  @override
  String toString() => '$id (${towns.join(', ')})';
}

/// Day length and what nightfall does to a check.
///
/// The modifiers are circumstance bonuses and penalties in Pathfinder terms,
/// which is what keeps them from stacking with another circumstance effect.
class TimeSystem {
  const TimeSystem({
    required this.dayCycleHours,
    this.nightStealthBonus = 0,
    this.nightPerceptionPenalty = 0,
    this.dawnEcho,
    this.duskEcho,
  });

  final int dayCycleHours;
  final int nightStealthBonus;

  /// Stored as written — negative for a penalty.
  final int nightPerceptionPenalty;

  final String? dawnEcho;
  final String? duskEcho;

  /// A quarter of the way through the cycle: six in the morning.
  int get dawnHour => dayCycleHours ~/ 4;

  /// Three quarters of the way through: six in the evening.
  int get duskHour => dayCycleHours * 3 ~/ 4;

  /// Dark from dusk until dawn. This used to be the second half of the
  /// cycle, noon to midnight, which made two in the morning broad day.
  bool isNight(int hour) => hour < dawnHour || hour >= duskHour;

  /// The circumstance modifier this time of day applies to [statKey].
  int modifierFor(String statKey, {required int hour}) {
    if (!isNight(hour)) return 0;
    return switch (statKey.trim().toLowerCase()) {
      'stealth' => nightStealthBonus,
      'perception' => nightPerceptionPenalty,
      _ => 0,
    };
  }
}

/// The world a campaign takes place in.
class WorldConfig {
  const WorldConfig({
    required this.metadata,
    required this.regions,
    required this.time,
  });

  final WorldMetadata metadata;
  final List<Region> regions;
  final TimeSystem time;

  Region? regionById(String id) {
    for (final region in regions) {
      if (region.id == id) return region;
    }
    return null;
  }

  /// The region a town belongs to, matched on the town's name.
  Region? regionForTown(String townName) {
    final needle = townName.trim().toLowerCase();
    for (final region in regions) {
      for (final town in region.towns) {
        if (town.trim().toLowerCase() == needle) return region;
      }
    }
    return null;
  }

  @override
  String toString() => '${metadata.name} (${regions.length} regions)';
}
