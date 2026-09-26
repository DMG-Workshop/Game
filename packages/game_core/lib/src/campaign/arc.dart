import 'economy.dart';

/// One step of a campaign arc.
class ArcObjective {
  const ArcObjective({
    required this.id,
    required this.task,
    required this.condition,
  });

  /// Ordinal within its arc.
  final int id;

  /// What the player is asked to do, in their words.
  final String task;

  /// The flag that marks it done, e.g. `boss_defeated_hollow_avatar`.
  ///
  /// Conditions are flags in the session's flag set, which is why an arc can
  /// be driven by ordinary scene outcomes without a second mechanism.
  final String condition;

  @override
  String toString() => '$id. $task ($condition)';
}

/// A quest: a tier of the main story, or a side quest along the way.
///
/// Both are the same thing to the engine — a trigger, some objectives, and
/// what finishing changes — so a side quest is an arc marked as one, not a
/// second system with its own rules to learn.
class CampaignArc {
  const CampaignArc({
    required this.id,
    required this.name,
    required this.levels,
    required this.startTrigger,
    required this.objectives,
    this.worldStateChanges = const [],
    this.isSide = false,
    this.reward,
    this.zone,
  });

  final String id;
  final String name;

  /// Inclusive `[min, max]` character levels.
  final List<int> levels;

  /// The flag that opens this arc, e.g. `enter_MH_001`.
  final String startTrigger;

  final List<ArcObjective> objectives;

  /// Flags set when every objective is met.
  final List<String> worldStateChanges;

  /// True for a side quest rather than a tier of the main story.
  final bool isSide;

  /// What finishing it pays, once.
  final Payout? reward;

  /// The part of the map it is set in, or null for one that follows the
  /// party wherever they go.
  final String? zone;

  /// Set the moment this arc is finished, which is what its reward is paid on.
  String get completionFlag => 'completed_$id';

  int get minLevel => levels.isEmpty ? 1 : levels.first;
  int get maxLevel => levels.length < 2 ? minLevel : levels[1];

  bool suitsLevel(int level) => level >= minLevel && level <= maxLevel;

  bool hasStarted(Set<String> flags) => flags.contains(startTrigger);

  bool isObjectiveMet(ArcObjective objective, Set<String> flags) =>
      flags.contains(objective.condition);

  List<ArcObjective> completed(Set<String> flags) => [
        for (final o in objectives)
          if (flags.contains(o.condition)) o
      ];

  List<ArcObjective> remaining(Set<String> flags) => [
        for (final o in objectives)
          if (!flags.contains(o.condition)) o
      ];

  /// The next thing to do, or null when the arc is finished.
  ArcObjective? nextObjective(Set<String> flags) {
    final left = remaining(flags);
    return left.isEmpty ? null : left.first;
  }

  bool isComplete(Set<String> flags) => remaining(flags).isEmpty;

  /// Progress as completed over total, for a status line.
  ({int done, int total}) progress(Set<String> flags) =>
      (done: completed(flags).length, total: objectives.length);

  @override
  String toString() => '$name (levels $minLevel-$maxLevel)';
}

/// The campaign's arcs in order.
class ArcTrack {
  ArcTrack(List<CampaignArc> arcs) : _arcs = List.of(arcs);

  final List<CampaignArc> _arcs;

  List<CampaignArc> get all => List.unmodifiable(_arcs);

  int get length => _arcs.length;

  CampaignArc? byId(String id) {
    for (final arc in _arcs) {
      if (arc.id == id) return arc;
    }
    return null;
  }

  /// Arcs that have started and are not yet finished.
  List<CampaignArc> active(Set<String> flags) => [
        for (final arc in _arcs)
          if (arc.hasStarted(flags) && !arc.isComplete(flags)) arc,
      ];

  /// Arcs whose last objective has been met but that have not yet been
  /// marked finished — and paid.
  List<CampaignArc> justCompleted(Set<String> flags) => [
        for (final arc in _arcs)
          if (arc.hasStarted(flags) &&
              arc.isComplete(flags) &&
              !flags.contains(arc.completionFlag))
            arc,
      ];

  /// The arc [flag] marks as finished, if it is a completion flag.
  CampaignArc? completedBy(String flag) {
    for (final arc in _arcs) {
      if (arc.completionFlag == flag) return arc;
    }
    return null;
  }

  /// Flags that should be set now, because their arc just finished.
  ///
  /// Returned rather than applied: the caller owns the flag set, and an arc
  /// completing is something a client will usually want to announce.
  List<String> pendingWorldStateChanges(Set<String> flags) => [
        for (final arc in _arcs)
          if (arc.hasStarted(flags) && arc.isComplete(flags))
            ...arc.worldStateChanges.where((c) => !flags.contains(c)),
      ];

  @override
  String toString() => '$length arcs';
}
