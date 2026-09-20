import 'package:pf2e_core/pf2e_core.dart';

import '../scene/scene.dart';
import 'game_event.dart';
import 'session_actor.dart';

/// Thrown when an option is chosen that is not currently available.
class InvalidChoiceException implements Exception {
  InvalidChoiceException(this.message);

  final String message;

  @override
  String toString() => 'InvalidChoiceException: $message';
}

/// A party playing through an adventure.
///
/// Holds no I/O and no UI: a client renders [currentScene] and
/// [availableOptions], then calls [choose]. That keeps the loop identical for
/// the terminal build, the phone, the tablet, and the browser.
///
/// On who rolls: this deliberately does not decide. [candidatesFor] ranks
/// everyone who could attempt a check and [suggestedActorFor] names the best,
/// but [choose] accepts any of them. A client is free to roll the suggestion
/// silently, to offer the ranked list, or to let a scene constrain it — the
/// engine forecloses none of those.
class GameSession {
  GameSession({
    required this.adventure,
    required List<SessionActor> actors,
    required DiceRoller roller,
    String? sceneId,
    Set<String>? flags,
  })  : _actors = List.of(actors),
        _roller = roller,
        _sceneId = sceneId ?? adventure.startSceneId,
        _flags = flags ?? <String>{} {
    if (_actors.isEmpty) {
      throw ArgumentError.value(actors, 'actors', 'a session needs an actor');
    }
    final ids = <String>{};
    for (final actor in _actors) {
      if (!ids.add(actor.id)) {
        throw ArgumentError.value(
            actors, 'actors', 'duplicate id "${actor.id}"');
      }
    }
    _resolver = CheckResolver(_roller);
    if (adventure.sceneById(_sceneId) == null) {
      throw ArgumentError.value(_sceneId, 'sceneId', 'no such scene');
    }
  }

  /// A session for one character, without needing a roster.
  factory GameSession.solo({
    required Adventure adventure,
    required ImportedCharacter character,
    required DiceRoller roller,
    String actorId = 'pc',
    String? sceneId,
    Set<String>? flags,
  }) =>
      GameSession(
        adventure: adventure,
        actors: [SessionActor(id: actorId, character: character)],
        roller: roller,
        sceneId: sceneId,
        flags: flags,
      );

  final Adventure adventure;

  final List<SessionActor> _actors;
  final DiceRoller _roller;
  late final CheckResolver _resolver;
  String _sceneId;
  final Set<String> _flags;
  final List<GameEvent> _log = [];

  List<SessionActor> get actors => List.unmodifiable(_actors);

  /// The first actor. Convenient for a solo session; means little for a party.
  SessionActor get primary => _actors.first;

  /// The primary actor's character. Prefer [actors] for a party.
  ImportedCharacter get character => primary.character;

  /// The primary actor's sheet. Prefer [candidatesFor] for a party.
  DerivedStats get stats => primary.stats;

  Scene get currentScene => adventure.sceneById(_sceneId)!;

  Set<String> get flags => Set.unmodifiable(_flags);

  List<GameEvent> get log => List.unmodifiable(_log);

  /// True once the party reaches a scene marked as an ending.
  bool get isFinished => currentScene.isEnding;

  SessionActor? actorById(String id) {
    for (final actor in _actors) {
      if (actor.id == id) return actor;
    }
    return null;
  }

  /// Options whose gates currently open.
  ///
  /// A gate is satisfied when *any* actor satisfies it, since a party only
  /// needs one member who knows the dead. The gate is re-checked against the
  /// specific actor when the option is taken.
  List<SceneOption> availableOptions() => [
        for (final option in currentScene.options)
          if (_anyActorPasses(option)) option,
      ];

  bool _anyActorPasses(SceneOption option) {
    for (final actor in _actors) {
      if (option.gate.allows(_flags, actor.stats)) return true;
    }
    return false;
  }

  /// Everyone who could attempt [optionId], best bonus first.
  ///
  /// Empty for an option with no check. An actor who fails the option's gate,
  /// or who has no such statistic at all, is left out rather than ranked last.
  List<ActorCandidate> candidatesFor(String optionId) {
    final option = currentScene.optionById(optionId);
    final check = option?.check;
    if (option == null || check == null) return const [];

    final rows = <ActorCandidate>[];
    for (final actor in _actors) {
      if (!option.gate.allows(_flags, actor.stats)) continue;
      final stat = actor.statFor(check.statKey);
      if (stat != null) rows.add((actor: actor, stat: stat));
    }
    rows.sort((a, b) => b.stat.total.compareTo(a.stat.total));
    return rows;
  }

  /// The actor a client would pick by default: the best of [candidatesFor].
  ActorCandidate? suggestedActorFor(String optionId) {
    final candidates = candidatesFor(optionId);
    return candidates.isEmpty ? null : candidates.first;
  }

  /// Takes [optionId], rolling its check if it has one.
  ///
  /// [actorId] names who attempts it; omitted, the best candidate does. An
  /// option with no check needs no actor and records the primary.
  GameEvent choose(String optionId, {String? actorId}) {
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
    SessionActor actor;

    final check = option.check;
    if (check == null) {
      actor = actorId == null ? primary : _requireActor(actorId, option);
      result = option.automatic;
    } else {
      final ActorCandidate candidate;
      if (actorId != null) {
        final named = _requireActor(actorId, option);
        final stat = named.statFor(check.statKey);
        if (stat == null) {
          throw InvalidChoiceException(
              '${named.name} has no "${check.statKey}" to roll.');
        }
        candidate = (actor: named, stat: stat);
      } else {
        final best = suggestedActorFor(optionId);
        if (best == null) {
          throw InvalidChoiceException(
              'Nobody present can roll "${check.statKey}".');
        }
        candidate = best;
      }
      actor = candidate.actor;
      outcome = _resolver.resolveStat(candidate.stat, dc: check.dc);
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
        throw InvalidChoiceException(
            'Option "$optionId" leads to missing scene "$goTo".');
      }
      _sceneId = goTo;
    }

    final event = GameEvent(
      index: _log.length,
      sceneId: from,
      optionId: option.id,
      optionLabel: option.label,
      actorId: actor.id,
      actorName: actor.name,
      narration: result.text,
      check: outcome,
      movedTo: goTo,
      flagsSet: result.setFlags,
      flagsCleared: result.clearFlags,
    );
    _log.add(event);
    return event;
  }

  SessionActor _requireActor(String actorId, SceneOption option) {
    final actor = actorById(actorId);
    if (actor == null) {
      throw InvalidChoiceException('No actor "$actorId" in this session.');
    }
    if (!option.gate.allows(_flags, actor.stats)) {
      throw InvalidChoiceException('${actor.name} cannot take "${option.id}".');
    }
    return actor;
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
    required List<SessionActor> actors,
    required SessionSnapshot snapshot,
  }) {
    if (snapshot.adventureId != adventure.id) {
      throw ArgumentError('Snapshot belongs to adventure '
          '"${snapshot.adventureId}", not "${adventure.id}".');
    }
    return GameSession(
      adventure: adventure,
      actors: actors,
      roller: DiceRoller.fromState(snapshot.rollerState),
      sceneId: snapshot.sceneId,
      flags: Set.of(snapshot.flags),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => iterator.moveNext() ? first : null;
}
