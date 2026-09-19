import 'package:pf2e_core/pf2e_core.dart';

import '../scene/scene.dart';
import 'game_event.dart';

/// Thrown when an option is chosen that is not currently available.
class InvalidChoiceException implements Exception {
  InvalidChoiceException(this.message);

  final String message;

  @override
  String toString() => 'InvalidChoiceException: $message';
}

/// A single character playing through an adventure.
///
/// Holds no I/O and no UI: a client renders [currentScene] and
/// [availableOptions], then calls [choose]. That keeps the loop identical for
/// the terminal build, the phone, and the browser.
class GameSession {
  GameSession({
    required this.adventure,
    required this.character,
    required DiceRoller roller,
    String? sceneId,
    Set<String>? flags,
  })  : stats = DerivedStats(character),
        _roller = roller,
        _sceneId = sceneId ?? adventure.startSceneId,
        _flags = flags ?? <String>{} {
    _resolver = CheckResolver(_roller);
    if (adventure.sceneById(_sceneId) == null) {
      throw ArgumentError.value(_sceneId, 'sceneId', 'no such scene');
    }
  }

  final Adventure adventure;
  final ImportedCharacter character;
  final DerivedStats stats;

  final DiceRoller _roller;
  late final CheckResolver _resolver;
  String _sceneId;
  final Set<String> _flags;
  final List<GameEvent> _log = [];

  Scene get currentScene => adventure.sceneById(_sceneId)!;

  Set<String> get flags => Set.unmodifiable(_flags);

  List<GameEvent> get log => List.unmodifiable(_log);

  /// True once the player reaches a scene marked as an ending.
  bool get isFinished => currentScene.isEnding;

  /// Options whose gates currently open.
  ///
  /// A gated option is hidden rather than shown-and-refused, so the menu
  /// reflects what this particular character can actually do.
  List<SceneOption> availableOptions() => [
        for (final option in currentScene.options)
          if (option.gate.allows(_flags, stats)) option,
      ];

  /// Takes [optionId], rolling its check if it has one.
  GameEvent choose(String optionId) {
    if (isFinished) {
      throw InvalidChoiceException('The session has already ended.');
    }
    final option =
        availableOptions().where((o) => o.id == optionId).firstOrNull;
    if (option == null) {
      throw InvalidChoiceException(
          'Option "$optionId" is not available in scene "$_sceneId".');
    }

    CheckOutcome? outcome;
    Outcome? result;

    final check = option.check;
    if (check == null) {
      result = option.automatic;
    } else {
      final stat = stats.statByKey(check.statKey);
      if (stat == null) {
        throw InvalidChoiceException(
            'Option "$optionId" rolls unknown statistic "${check.statKey}".');
      }
      outcome = _resolver.resolveStat(stat, dc: check.dc);
      result = option.outcomeFor(outcome.degree);
    }

    if (result == null) {
      throw InvalidChoiceException('Option "$optionId" produced no outcome for '
          '${outcome?.degree.displayName ?? 'an automatic result'}.');
    }

    for (final flag in result.clearFlags) {
      _flags.remove(flag);
    }
    _flags.addAll(result.setFlags);

    final from = _sceneId;
    final goTo = result.goTo;
    if (goTo != null) {
      if (adventure.sceneById(goTo) == null) {
        throw InvalidChoiceException('Option "$optionId" leads to missing '
            'scene "$goTo".');
      }
      _sceneId = goTo;
    }

    final event = GameEvent(
      index: _log.length,
      sceneId: from,
      optionId: option.id,
      optionLabel: option.label,
      narration: result.text,
      check: outcome,
      movedTo: goTo,
      flagsSet: result.setFlags,
      flagsCleared: result.clearFlags,
    );
    _log.add(event);
    return event;
  }

  /// Captures enough state to resume exactly where this left off.
  SessionSnapshot snapshot() => SessionSnapshot(
        adventureId: adventure.id,
        sceneId: _sceneId,
        flags: Set.of(_flags),
        rollerState: _roller.state,
        eventCount: _log.length,
      );

  /// Rebuilds a session from a [snapshot].
  ///
  /// The roller resumes at its recorded position, so a session suspended and
  /// restored rolls exactly what it would have rolled had it continued.
  static GameSession restore({
    required Adventure adventure,
    required ImportedCharacter character,
    required SessionSnapshot snapshot,
  }) {
    if (snapshot.adventureId != adventure.id) {
      throw ArgumentError('Snapshot belongs to adventure '
          '"${snapshot.adventureId}", not "${adventure.id}".');
    }
    return GameSession(
      adventure: adventure,
      character: character,
      roller: DiceRoller.fromState(snapshot.rollerState),
      sceneId: snapshot.sceneId,
      flags: Set.of(snapshot.flags),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => iterator.moveNext() ? first : null;
}
