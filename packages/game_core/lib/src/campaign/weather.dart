import 'package:pf2e_core/pf2e_core.dart';

/// How bad weather is to be out in.
enum WeatherSeverity {
  /// Nothing to worry about.
  fair,

  /// Slows the road and spoils a shot, but nobody dies of it.
  foul,

  /// Dangerous to be out in: find shelter or pay for it.
  severe;

  static WeatherSeverity? tryParse(String source) {
    final needle = source.trim().toLowerCase();
    for (final s in values) {
      if (s.name == needle) return s;
    }
    return null;
  }
}

/// One kind of weather, and what it does.
class WeatherType {
  const WeatherType({
    required this.id,
    required this.name,
    this.severity = WeatherSeverity.fair,
    this.travel = 1.0,
    this.rangedPenalty = 0,
    this.text = '',
    this.exposure,
    this.after,
    this.remark,
  });

  final String id;
  final String name;
  final WeatherSeverity severity;

  /// What somebody in the party says, looking up at it.
  final String? remark;

  /// How much longer the road takes in it: 1.5 is half as long again.
  final double travel;

  /// Taken off any attack that has to cross open ground to land.
  final int rangedPenalty;

  /// What it looks like, where a region has not said otherwise.
  final String text;

  /// Damage dice for being caught out in it, for severe weather.
  final String? exposure;

  /// What it settles into once the worst has passed, for severe weather.
  final String? after;

  bool get isSevere => severity == WeatherSeverity.severe;

  @override
  String toString() => name;
}

/// A season of the year.
class Season {
  const Season({required this.id, required this.name, required this.days});

  final String id;
  final String name;
  final int days;

  @override
  String toString() => name;
}

/// Days, seasons and years.
///
/// Day 1 is the day the campaign opens, which falls on [startDayOfSeason] of
/// the season [startSeason] names. The year turns after the last season.
class Calendar {
  const Calendar({
    required this.seasons,
    this.startSeason = 0,
    this.startDayOfSeason = 1,
  });

  final List<Season> seasons;
  final int startSeason;
  final int startDayOfSeason;

  static const fallback = Calendar(seasons: [
    Season(id: 'spring', name: 'Spring', days: 30),
    Season(id: 'summer', name: 'Summer', days: 30),
    Season(id: 'autumn', name: 'Autumn', days: 30),
    Season(id: 'winter', name: 'Winter', days: 30),
  ]);

  int get daysInYear => seasons.fold(0, (sum, s) => sum + s.days);

  /// Days since the first day of the starting year's first season.
  int _dayOfYearZero(int day) {
    var offset = startDayOfSeason - 1;
    for (var i = 0; i < startSeason; i++) {
      offset += seasons[i].days;
    }
    return offset + day - 1;
  }

  ({Season season, int dayOfSeason, int year}) dateOf(int day) {
    final absolute = _dayOfYearZero(day < 1 ? 1 : day);
    final year = absolute ~/ daysInYear + 1;
    var rest = absolute % daysInYear;
    for (final season in seasons) {
      if (rest < season.days) {
        return (season: season, dayOfSeason: rest + 1, year: year);
      }
      rest -= season.days;
    }
    return (season: seasons.last, dayOfSeason: seasons.last.days, year: year);
  }

  Season seasonOf(int day) => dateOf(day).season;
}

/// One band of a d100 weather table: a roll of [upTo] or under, down to the
/// band before it, gives [weather].
class WeatherBand {
  const WeatherBand({required this.upTo, required this.weather});

  final int upTo;
  final String weather;
}

/// How long the road takes, before weather.
class TravelTimes {
  const TravelTimes({
    this.sameZoneMinutes = 15,
    this.newZoneMinutes = 60,
    this.newTownMinutes = 480,
    this.fatiguedAfterHours = 8,
    this.exhaustedAfterHours = 12,
    this.awakeHours = 16,
  });

  /// Across a town, or from one clearing of a wood to the next.
  final int sameZoneMinutes;

  /// From one part of the map to the next: the forge to the wood.
  final int newZoneMinutes;

  /// From one town to another, by road.
  final int newTownMinutes;

  /// Hours on the road before the party is fatigued.
  final int fatiguedAfterHours;

  /// Hours on the road before the party cannot start another long stretch.
  final int exhaustedAfterHours;

  /// Hours awake before the party is fatigued whatever it has been doing.
  final int awakeHours;
}

/// The calendar, the road, and what the sky does in each region, by season.
class WeatherBook {
  WeatherBook({
    this.calendar = Calendar.fallback,
    this.travel = const TravelTimes(),
    List<WeatherType> types = const [],
    Map<String, Map<String, List<WeatherBand>>> tables = const {},
    this.restLines = const RestLines(),
  })  : _types = {for (final t in types) t.id: t},
        _tables = tables;

  final Calendar calendar;
  final TravelTimes travel;

  /// What is said and heard when the party beds down.
  final RestLines restLines;
  final Map<String, WeatherType> _types;

  /// Region id to season id to its d100 table.
  final Map<String, Map<String, List<WeatherBand>>> _tables;

  bool get isEmpty => _types.isEmpty;

  List<WeatherType> get types => List.unmodifiable(_types.values);

  WeatherType? typeById(String id) => _types[id];

  Set<String> get regionIds => _tables.keys.toSet();

  List<WeatherBand> tableFor(String regionId, String seasonId) =>
      List.unmodifiable(_tables[regionId]?[seasonId] ?? const []);

  /// The weather a d100 roll of [die] gives in [regionId] in [seasonId].
  WeatherType? lookUp(String regionId, String seasonId, int die) {
    for (final band in tableFor(regionId, seasonId)) {
      if (die <= band.upTo) return _types[band.weather];
    }
    return null;
  }

  /// What is wrong with the weather, in words an author can act on.
  ///
  /// Every region needs a table for every season that covers the whole d100
  /// and names only weather that exists; severe weather needs exposure dice
  /// and something to settle into.
  List<String> problems({required Iterable<String> regionIds}) {
    final out = <String>[];
    if (isEmpty) return out;
    for (final type in _types.values) {
      if (type.isSevere) {
        final dice = type.exposure;
        if (dice == null || DamageExpression.tryParse(dice) == null) {
          out.add('${type.name} is severe but does no harm to be out in');
        }
        final after = type.after;
        if (after == null || !_types.containsKey(after)) {
          out.add('${type.name} is severe and settles into nothing');
        }
      }
    }
    for (final region in regionIds) {
      for (final season in calendar.seasons) {
        final table = tableFor(region, season.id);
        if (table.isEmpty) {
          out.add('$region has no weather in ${season.name}');
          continue;
        }
        var last = 0;
        for (final band in table) {
          if (band.upTo <= last) {
            out.add('$region in ${season.name}: ${band.weather} is out of '
                'order at ${band.upTo}');
          }
          if (!_types.containsKey(band.weather)) {
            out.add('$region in ${season.name} rolls "${band.weather}", '
                'which is not a kind of weather');
          }
          last = band.upTo;
        }
        if (last != 100) {
          out.add('$region in ${season.name} stops at $last, not 100');
        }
      }
    }
    return out;
  }

  @override
  String toString() => '${_types.length} kinds of weather';
}

/// What is said and heard when the party beds down for the night.
class RestLines {
  const RestLines({
    this.indoors = const [],
    this.outdoors = const [],
    this.pc = const [],
    this.wake = const [],
  });

  /// The night, under a roof.
  final List<String> indoors;

  /// The night, out in the open.
  final List<String> outdoors;

  /// What somebody in the party says, settling down.
  final List<String> pc;

  /// Waking.
  final List<String> wake;

  List<String> gaps() => [
        if (indoors.isEmpty) 'no night under a roof',
        if (outdoors.isEmpty) 'no night in the open',
        if (pc.isEmpty) 'nothing said settling down',
        if (wake.isEmpty) 'no waking',
      ];
}

/// The weather for one region on one day, as rolled.
class DayWeather {
  const DayWeather({
    required this.regionId,
    required this.day,
    required this.season,
    required this.die,
    required this.type,
    this.stormStartHour,
    this.stormHours,
  });

  final String regionId;
  final int day;
  final Season season;

  /// The d100 the table was rolled with.
  final int die;

  /// The day's weather. For severe weather, the worst of it: see [isStormAt].
  final WeatherType type;

  /// When a severe day's storm breaks, and how long it lasts.
  final int? stormStartHour;
  final int? stormHours;

  bool get hasStorm => stormStartHour != null && stormHours != null;

  int get stormEndMinute => (stormStartHour! + stormHours!) * 60;

  /// Whether the storm is on at [minute] of the day.
  bool isStormAt(int minute) =>
      hasStorm && minute >= stormStartHour! * 60 && minute < stormEndMinute;

  Map<String, Object?> toJson() => {
        'region': regionId,
        'day': day,
        'die': die,
        'type': type.id,
        if (stormStartHour != null) 'stormStart': stormStartHour,
        if (stormHours != null) 'stormHours': stormHours,
      };

  @override
  String toString() => 'day $day, ${season.name}: d100($die) — ${type.name}'
      '${hasStorm ? ', from ${stormStartHour!}:00 for $stormHours hours' : ''}';
}
