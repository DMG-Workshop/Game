import 'package:pf2e_core/pf2e_core.dart';

import '../campaign/weather.dart';
import 'session_actor.dart';

/// Something that happened in the world while time passed, for a client to
/// tell the player about.
///
/// Collected rather than returned from whichever call caused it, because the
/// same hour can hold a storm breaking, a new day, and somebody getting
/// tired, and any of walking, waiting, resting or fighting can be the call
/// that crossed it.
sealed class WorldEvent {
  const WorldEvent();
}

/// A region's weather for the day, rolled on its table.
final class WeatherRolled extends WorldEvent {
  const WeatherRolled(this.weather);

  final DayWeather weather;

  @override
  String toString() => 'Weather: $weather';
}

/// Midnight passed.
final class NewDay extends WorldEvent {
  const NewDay({
    required this.day,
    required this.season,
    required this.dayOfSeason,
    required this.year,
  });

  final int day;
  final Season season;
  final int dayOfSeason;
  final int year;

  @override
  String toString() => 'Day $day: day $dayOfSeason of ${season.name}, '
      'year $year';
}

/// The sun came up, or went down.
final class DawnOrDusk extends WorldEvent {
  const DawnOrDusk({required this.isDawn, this.echo});

  final bool isDawn;
  final String? echo;

  @override
  String toString() => isDawn ? 'Dawn' : 'Dusk';
}

/// A storm broke over the party.
final class StormBroke extends WorldEvent {
  const StormBroke({required this.weather, required this.sheltered});

  final DayWeather weather;

  /// True when the party was under a roof, or under a shelter of their own.
  final bool sheltered;

  @override
  String toString() => '${weather.type.name} breaks'
      '${sheltered ? ' overhead' : ' over you in the open'}';
}

/// An hour out in severe weather, and what it cost one character.
final class Exposure extends WorldEvent {
  const Exposure({
    required this.actor,
    required this.save,
    required this.damage,
    required this.hpLost,
  });

  final SessionActor actor;

  /// Their Fortitude save against the weather.
  final CheckOutcome save;

  /// The weather's damage as rolled, before the save halved or doubled it.
  final DamageRoll damage;
  final int hpLost;

  @override
  String toString() => '${actor.name}: $save; loses $hpLost HP';
}

/// A storm blew over, and the party came through it.
final class StormPassed extends WorldEvent {
  const StormPassed({
    required this.weather,
    required this.xp,
    required this.ownShelter,
  });

  final DayWeather weather;

  /// XP each earned for weathering it, or 0 for having stood out in it.
  final int xp;

  /// True when they rode it out under a shelter they made themselves.
  final bool ownShelter;

  @override
  String toString() => '${weather.type.name} passes'
      '${xp > 0 ? ' (+$xp XP each)' : ''}';
}

/// The party has been going too long.
final class GrewTired extends WorldEvent {
  const GrewTired({required this.spent});

  /// True when they are past taking on another long road, not just tired.
  final bool spent;

  @override
  String toString() => spent ? 'Spent' : 'Fatigued';
}
