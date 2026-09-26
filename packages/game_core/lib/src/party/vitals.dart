import 'package:pf2e_core/pf2e_core.dart';

import '../campaign/weather.dart';

/// How one character is holding up: hit points, and what they have left to
/// cast with.
///
/// Spell slots and focus points are tracked from the character's own
/// Pathbuilder sheet and restored by rest. Casting in a fight is not built
/// yet, so nothing spends them; they are here so that rest has something true
/// to restore the day it is.
class ActorVitals {
  ActorVitals({
    required this.maxHp,
    int? hp,
    this.maxFocus = 0,
    int? focus,
    Map<int, int> slots = const {},
    Map<int, int>? slotsLeft,
    this.lastTreatedAt,
  })  : hp = (hp ?? maxHp).clamp(0, maxHp),
        focus = (focus ?? maxFocus).clamp(0, maxFocus),
        slots = Map.unmodifiable(slots),
        slotsLeft = {...(slotsLeft ?? slots)};

  /// Everything the sheet says, at full strength.
  factory ActorVitals.fresh(DerivedStats stats) {
    final character = stats.character;
    final slots = <int, int>{};
    for (final entry in character.spellcasting) {
      for (var rank = 1; rank < entry.slotsPerDay.length; rank++) {
        final n = entry.slotsPerDay[rank];
        if (n > 0) slots.update(rank, (s) => s + n, ifAbsent: () => n);
      }
    }
    return ActorVitals(
      maxHp: stats.maxHp,
      maxFocus: character.focusPoints,
      slots: slots,
    );
  }

  final int maxHp;
  int hp;
  final int maxFocus;
  int focus;

  /// Slots per spell rank, and how many of each are left today.
  final Map<int, int> slots;
  final Map<int, int> slotsLeft;

  /// When Treat Wounds last landed on them, in minutes since day 1 began.
  /// Pathfinder makes a patient immune to it for an hour afterwards.
  int? lastTreatedAt;

  bool get isDown => hp <= 0;
  bool get isHurt => hp < maxHp;

  /// Heals up to [amount], returning how much it actually healed.
  int heal(int amount) {
    final before = hp;
    hp = (hp + amount).clamp(0, maxHp);
    return hp - before;
  }

  /// Takes up to [amount], returning how much it actually took.
  int hurt(int amount) {
    final before = hp;
    hp = (hp - amount).clamp(0, maxHp);
    return before - hp;
  }

  /// A night's rest's daily preparations: every slot and focus point back.
  void prepare() {
    focus = maxFocus;
    slotsLeft
      ..clear()
      ..addAll(slots);
  }

  Map<String, Object?> toJson() => {
        'hp': hp,
        'focus': focus,
        'slotsLeft': {
          for (final e in slotsLeft.entries) '${e.key}': e.value,
        },
        if (lastTreatedAt != null) 'treatedAt': lastTreatedAt,
      };

  /// Restores a character from [json] onto their sheet's [fresh] numbers.
  ///
  /// The sheet decides the maximums, so a character re-imported a level up
  /// keeps the hurt they were carrying but not their old ceiling.
  static ActorVitals restore(ActorVitals fresh, Object? json) {
    if (json is! Map) return fresh;
    final left = json['slotsLeft'];
    return ActorVitals(
      maxHp: fresh.maxHp,
      hp: (json['hp'] as num?)?.toInt(),
      maxFocus: fresh.maxFocus,
      focus: (json['focus'] as num?)?.toInt(),
      slots: fresh.slots,
      slotsLeft: left is Map
          ? {
              for (final e in left.entries)
                if (int.tryParse(e.key.toString()) case final rank?)
                  rank: ((e.value as num?)?.toInt() ?? 0)
                      .clamp(0, fresh.slots[rank] ?? 0),
            }
          : null,
      lastTreatedAt: (json['treatedAt'] as num?)?.toInt(),
    );
  }

  @override
  String toString() => '$hp/$maxHp HP'
      '${maxFocus > 0 ? ', $focus/$maxFocus focus' : ''}';
}

/// How far the party can go before it has to stop.
///
/// Party-wide, because a marching order travels together and sleeps
/// together. Road time is counted as the weather made it: an hour's walk in a
/// storm is two hours of being out in it.
class Endurance {
  Endurance({this.travelMinutes = 0, this.awakeMinutes = 0});

  /// On the road since the last rest.
  int travelMinutes;

  /// Awake since the last rest.
  int awakeMinutes;

  /// Pathfinder's Fatigued: -1 to AC and saving throws, until rested.
  bool isFatigued(TravelTimes limits) =>
      travelMinutes >= limits.fatiguedAfterHours * 60 ||
      awakeMinutes >= limits.awakeHours * 60;

  /// Too tired to take on another long stretch of road.
  bool isSpent(TravelTimes limits) =>
      travelMinutes >= limits.exhaustedAfterHours * 60;

  /// Hours of road left before [isFatigued], or 0.
  double roadLeftHours(TravelTimes limits) {
    final byRoad = limits.fatiguedAfterHours * 60 - travelMinutes;
    final byDay = limits.awakeHours * 60 - awakeMinutes;
    final left = byRoad < byDay ? byRoad : byDay;
    return left <= 0 ? 0 : left / 60;
  }

  void rested() {
    travelMinutes = 0;
    awakeMinutes = 0;
  }

  Map<String, Object?> toJson() =>
      {'travel': travelMinutes, 'awake': awakeMinutes};

  static Endurance fromJson(Object? json) => json is Map
      ? Endurance(
          travelMinutes: (json['travel'] as num?)?.toInt() ?? 0,
          awakeMinutes: (json['awake'] as num?)?.toInt() ?? 0,
        )
      : Endurance();
}

/// Hit points recovered by a night's rest, as Pathfinder has it: the
/// Constitution modifier, at least 1, times the character's level.
int restHealing(ImportedCharacter character) {
  final con = character.abilities.modifier(Ability.constitution);
  return (con < 1 ? 1 : con) * character.level;
}
