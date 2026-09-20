import 'package:pf2e_core/pf2e_core.dart';

/// One resolved player action.
///
/// The log of these is the session: replaying it from the starting snapshot
/// reproduces the state exactly, which is what an asynchronous turn needs in
/// order to be verified on someone else's device.
class GameEvent {
  const GameEvent({
    required this.index,
    required this.sceneId,
    required this.optionId,
    required this.optionLabel,
    required this.actorId,
    required this.actorName,
    required this.narration,
    this.check,
    this.movedTo,
    this.flagsSet = const [],
    this.flagsCleared = const [],
  });

  /// Position in the session log, starting at zero.
  final int index;

  /// Scene the action was taken in.
  final String sceneId;
  final String optionId;
  final String optionLabel;

  /// Who took the action. With a party this is the difference between a check
  /// that succeeded and one that was never going to.
  final String actorId;
  final String actorName;

  /// Narration produced by the outcome.
  final String narration;

  /// Null for an option that needed no roll.
  final CheckOutcome? check;

  /// Scene moved to, or null when the player stayed put.
  final String? movedTo;

  final List<String> flagsSet;
  final List<String> flagsCleared;

  @override
  String toString() => check == null
      ? '[$index] $sceneId/$optionId ($actorName)'
      : '[$index] $sceneId/$optionId $actorName '
          '${check!.degree.displayName}';
}

/// Everything needed to resume a session, or to replay it from the start.
class SessionSnapshot {
  const SessionSnapshot({
    required this.adventureId,
    required this.sceneId,
    required this.flags,
    required this.rollerState,
    required this.eventCount,
  });

  final String adventureId;
  final String sceneId;
  final Set<String> flags;

  /// The dice roller's position, so resuming does not change future rolls.
  final int rollerState;
  final int eventCount;

  Map<String, Object?> toJson() => {
        'adventureId': adventureId,
        'sceneId': sceneId,
        'flags': flags.toList()..sort(),
        'rollerState': rollerState,
        'eventCount': eventCount,
      };

  static SessionSnapshot fromJson(Map<String, Object?> json) => SessionSnapshot(
        adventureId: json['adventureId']!.toString(),
        sceneId: json['sceneId']!.toString(),
        flags: {
          for (final f in (json['flags'] as List? ?? const [])) f.toString(),
        },
        rollerState: (json['rollerState'] as num).toInt(),
        eventCount: (json['eventCount'] as num?)?.toInt() ?? 0,
      );
}
