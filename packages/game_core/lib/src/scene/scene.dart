import 'package:pf2e_core/pf2e_core.dart';

/// A statistic to roll and the DC to beat.
class StatCheck {
  const StatCheck({required this.statKey, required this.dc});

  /// A key understood by [DerivedStats.statByKey], e.g. `deception` or
  /// `lore:undead`.
  final String statKey;
  final int dc;

  @override
  String toString() => '$statKey DC $dc';
}

/// What happens after an option is taken.
class Outcome {
  const Outcome({
    required this.text,
    this.goTo,
    this.setFlags = const [],
    this.clearFlags = const [],
  });

  /// Narration shown to the player.
  final String text;

  /// Scene to move to, or null to stay put.
  final String? goTo;

  final List<String> setFlags;
  final List<String> clearFlags;
}

/// A condition on whether an option is offered at all.
class OptionGate {
  const OptionGate({
    this.requiredFlags = const [],
    this.forbiddenFlags = const [],
    this.minProficiencyStat,
    this.minProficiency,
  });

  final List<String> requiredFlags;
  final List<String> forbiddenFlags;

  /// Statistic whose rank is tested, e.g. `lore:undead`.
  final String? minProficiencyStat;
  final Proficiency? minProficiency;

  bool get isEmpty =>
      requiredFlags.isEmpty &&
      forbiddenFlags.isEmpty &&
      minProficiencyStat == null;

  /// Whether this gate opens for the given flags and character.
  bool allows(Set<String> flags, DerivedStats stats) {
    for (final flag in requiredFlags) {
      if (!flags.contains(flag)) return false;
    }
    for (final flag in forbiddenFlags) {
      if (flags.contains(flag)) return false;
    }
    final statKey = minProficiencyStat;
    final minimum = minProficiency;
    if (statKey != null && minimum != null) {
      final stat = stats.statByKey(statKey);
      if (stat == null) return false;
      if (stat.proficiency.index < minimum.index) return false;
    }
    return true;
  }
}

/// One thing a player can do in a scene.
class SceneOption {
  const SceneOption({
    required this.id,
    required this.label,
    this.check,
    this.outcomes = const {},
    this.automatic,
    this.gate = const OptionGate(),
  });

  final String id;
  final String label;

  /// Null for an option that simply happens, with no roll.
  final StatCheck? check;

  /// Outcome per degree, used when [check] is set.
  final Map<DegreeOfSuccess, Outcome> outcomes;

  /// Outcome used when there is no [check].
  final Outcome? automatic;

  final OptionGate gate;

  /// The outcome for [degree], falling back one step toward the middle.
  ///
  /// Authors routinely write only success and failure; a critical then reads
  /// as its ordinary counterpart rather than dropping the player into silence.
  Outcome? outcomeFor(DegreeOfSuccess degree) {
    if (outcomes[degree] case final exact?) return exact;
    return switch (degree) {
      DegreeOfSuccess.criticalSuccess => outcomes[DegreeOfSuccess.success],
      DegreeOfSuccess.criticalFailure => outcomes[DegreeOfSuccess.failure],
      _ => null,
    };
  }

  @override
  String toString() => check == null ? label : '$label ($check)';
}

/// A location, with the things a player can do in it.
class Scene {
  const Scene({
    required this.id,
    required this.title,
    required this.body,
    this.options = const [],
    this.isEnding = false,
  });

  final String id;
  final String title;

  /// Narration shown on arrival.
  final String body;
  final List<SceneOption> options;

  /// True when reaching this scene ends the session.
  final bool isEnding;

  SceneOption? optionById(String id) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  @override
  String toString() => '$id: $title';
}

/// A named set of scenes with a starting point.
class Adventure {
  const Adventure({
    required this.id,
    required this.title,
    required this.startSceneId,
    required this.scenes,
  });

  final String id;
  final String title;
  final String startSceneId;
  final Map<String, Scene> scenes;

  Scene? sceneById(String id) => scenes[id];

  Scene get startScene {
    final scene = scenes[startSceneId];
    if (scene == null) {
      throw StateError('Adventure "$id" has no start scene "$startSceneId".');
    }
    return scene;
  }

  @override
  String toString() => '$title (${scenes.length} scenes)';
}
