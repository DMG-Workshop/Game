/// The four outcomes of a Pathfinder 2e check.
///
/// Declaration order is worst to best so that a one-step shift is an index
/// move; [shiftedBy] depends on it.
enum DegreeOfSuccess {
  criticalFailure('Critical Failure'),
  failure('Failure'),
  success('Success'),
  criticalSuccess('Critical Success');

  const DegreeOfSuccess(this.displayName);

  final String displayName;

  bool get isSuccess =>
      this == DegreeOfSuccess.success ||
      this == DegreeOfSuccess.criticalSuccess;

  bool get isFailure => !isSuccess;

  bool get isCritical =>
      this == DegreeOfSuccess.criticalSuccess ||
      this == DegreeOfSuccess.criticalFailure;

  /// Moves [steps] degrees better (positive) or worse (negative), clamped at
  /// the ends — nothing is better than a critical success.
  DegreeOfSuccess shiftedBy(int steps) {
    final target = (index + steps).clamp(0, DegreeOfSuccess.values.length - 1);
    return DegreeOfSuccess.values[target];
  }

  DegreeOfSuccess get improved => shiftedBy(1);
  DegreeOfSuccess get worsened => shiftedBy(-1);

  /// The degree implied by a check [total] against [dc], before any natural
  /// 20 or natural 1 adjustment.
  ///
  /// Beating the DC by 10 or more is a critical success; missing it by 10 or
  /// more is a critical failure.
  static DegreeOfSuccess fromTotal({required int total, required int dc}) {
    if (total >= dc + 10) return DegreeOfSuccess.criticalSuccess;
    if (total <= dc - 10) return DegreeOfSuccess.criticalFailure;
    return total >= dc ? DegreeOfSuccess.success : DegreeOfSuccess.failure;
  }
}
