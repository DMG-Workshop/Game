import 'degree_of_success.dart';
import 'derived_stats.dart';
import 'dice.dart';

/// The full record of one resolved check.
///
/// Every input is retained rather than just the verdict, so a turn log can be
/// audited or replayed and a text client can narrate exactly what happened.
class CheckOutcome {
  const CheckOutcome({
    required this.label,
    required this.dieRoll,
    required this.modifier,
    required this.dc,
    required this.degree,
    required this.degreeBeforeNatural,
  });

  /// What was being attempted, e.g. `Deception`.
  final String label;

  /// The raw d20 face, before modifiers.
  final int dieRoll;
  final int modifier;
  final int dc;

  /// The final degree, after any natural 20 or 1 adjustment.
  final DegreeOfSuccess degree;

  /// The degree implied by the total alone, before that adjustment.
  final DegreeOfSuccess degreeBeforeNatural;

  int get total => dieRoll + modifier;

  bool get isNaturalTwenty => dieRoll == 20;
  bool get isNaturalOne => dieRoll == 1;

  /// True when a natural 20 or 1 changed the result.
  bool get wasShiftedByNatural => degree != degreeBeforeNatural;

  /// How far the total beat the DC; negative when it missed.
  int get margin => total - dc;

  @override
  String toString() {
    final sign = modifier >= 0 ? '+' : '';
    final natural = wasShiftedByNatural
        ? ' (natural $dieRoll: ${degreeBeforeNatural.displayName} -> '
            '${degree.displayName})'
        : '';
    return '$label: d20($dieRoll) $sign$modifier = $total vs DC $dc '
        '-> ${degree.displayName}$natural';
  }
}

/// Resolves Pathfinder 2e checks against a DC.
///
/// DCs are supplied by the caller. The level-based and simple DC tables are
/// rules content rather than arithmetic, so they belong in the content package
/// described in NOTICE.md, not here.
class CheckResolver {
  CheckResolver(this.roller);

  final DiceRoller roller;

  /// Rolls a d20, adds [modifier], and compares against [dc].
  CheckOutcome resolve({
    required int modifier,
    required int dc,
    String label = 'Check',
  }) {
    final die = roller.d20();
    return outcomeFor(dieRoll: die, modifier: modifier, dc: dc, label: label);
  }

  /// Resolves a check using a statistic derived from an imported character.
  CheckOutcome resolveStat(CheckValue stat, {required int dc}) =>
      resolve(modifier: stat.total, dc: dc, label: stat.label);

  /// Builds an outcome from an already-known die face.
  ///
  /// Kept separate from [resolve] so the rules can be exercised without a
  /// roller, and so a replayed log can be re-derived from its recorded roll.
  static CheckOutcome outcomeFor({
    required int dieRoll,
    required int modifier,
    required int dc,
    String label = 'Check',
  }) {
    if (dieRoll < 1 || dieRoll > 20) {
      throw ArgumentError.value(dieRoll, 'dieRoll', 'must be between 1 and 20');
    }
    final base = DegreeOfSuccess.fromTotal(total: dieRoll + modifier, dc: dc);

    // The natural 20 and natural 1 adjustments apply *after* the total has
    // settled the degree, so a natural 20 on what the total made a failure is
    // a success rather than an automatic critical success.
    final adjusted = switch (dieRoll) {
      20 => base.improved,
      1 => base.worsened,
      _ => base,
    };

    return CheckOutcome(
      label: label,
      dieRoll: dieRoll,
      modifier: modifier,
      dc: dc,
      degree: adjusted,
      degreeBeforeNatural: base,
    );
  }
}
