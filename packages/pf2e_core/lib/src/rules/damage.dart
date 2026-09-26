import 'dice.dart';

/// A damage expression such as `2d10+4`, `1d6`, or `7`.
///
/// Parsed rather than evaluated on the spot so a statblock can be validated
/// when it loads instead of throwing mid-fight, and so the dice and the flat
/// modifier stay separately inspectable — doubling on a critical hit doubles
/// the whole thing, and a reader should be able to see what that was.
class DamageExpression {
  const DamageExpression({
    required this.diceCount,
    required this.dieSize,
    required this.flatBonus,
  });

  final int diceCount;

  /// Faces per die; 0 when the expression is a flat number.
  final int dieSize;
  final int flatBonus;

  // The sign is optional so a statblock may say plain "7" for flat damage;
  // requiring one meant a bare number parsed as nothing at all.
  static final RegExp _pattern =
      RegExp(r'^\s*(?:(\d+)\s*d\s*(\d+))?\s*([+-]?\s*\d+)?\s*$');

  /// Parses [source], returning null when it is not a damage expression.
  static DamageExpression? tryParse(String source) {
    final match = _pattern.firstMatch(source);
    if (match == null) return null;

    final count = match.group(1);
    final size = match.group(2);
    final flat = match.group(3)?.replaceAll(RegExp(r'\s'), '');
    if (count == null && flat == null) return null;

    final dice = int.tryParse(count ?? '0') ?? 0;
    final faces = int.tryParse(size ?? '0') ?? 0;
    if (dice < 0 || faces < 0) return null;
    if (dice > 0 && (faces < 1 || faces > DiceRoller.maxSides)) return null;

    return DamageExpression(
      diceCount: dice,
      dieSize: faces,
      flatBonus: int.tryParse(flat ?? '0') ?? 0,
    );
  }

  /// Parses [source] or throws.
  static DamageExpression parse(String source) {
    final parsed = tryParse(source);
    if (parsed == null) {
      throw FormatException('Not a damage expression: "$source"');
    }
    return parsed;
  }

  /// Smallest and largest this can roll.
  int get minimum => diceCount + flatBonus;
  int get maximum => diceCount * dieSize + flatBonus;

  /// Mean result, for comparing statblocks without rolling.
  double get average => diceCount * (dieSize + 1) / 2 + flatBonus;

  /// Rolls the expression, never returning less than zero.
  ///
  /// Pathfinder floors damage at 0 rather than letting a large penalty heal
  /// the target.
  int roll(DiceRoller roller) => rollDetailed(roller).total;

  /// Rolls with the dice doubled, as a critical hit does.
  ///
  /// Pathfinder doubles the whole result rather than rolling twice the dice,
  /// so this rolls once and doubles — the distribution differs, and the rules
  /// are explicit about which one applies.
  int rollCritical(DiceRoller roller) =>
      rollDetailed(roller, critical: true).total;

  /// Rolls the expression and keeps every die, so a player can see the roll
  /// and not just its sum.
  ///
  /// [roll] and [rollCritical] are this with the dice thrown away, which is
  /// what guarantees all three take the same dice from the same seed.
  DamageRoll rollDetailed(DiceRoller roller, {bool critical = false}) =>
      DamageRoll(
        expression: this,
        dice: diceCount > 0 && dieSize > 0
            ? roller.rollDice(diceCount, dieSize)
            : const [],
        critical: critical,
      );

  @override
  String toString() {
    final dice = diceCount > 0 && dieSize > 0 ? '${diceCount}d$dieSize' : '';
    if (flatBonus == 0) return dice.isEmpty ? '0' : dice;
    final sign = flatBonus > 0 ? '+' : '';
    return dice.isEmpty ? '$flatBonus' : '$dice$sign$flatBonus';
  }

  @override
  bool operator ==(Object other) =>
      other is DamageExpression &&
      other.diceCount == diceCount &&
      other.dieSize == dieSize &&
      other.flatBonus == flatBonus;

  @override
  int get hashCode => Object.hash(diceCount, dieSize, flatBonus);
}

/// One roll of a [DamageExpression], with every die it threw.
class DamageRoll {
  const DamageRoll({
    required this.expression,
    required this.dice,
    this.critical = false,
  });

  final DamageExpression expression;

  /// Each die's face, in the order rolled.
  final List<int> dice;

  /// True when the result is doubled, as on a critical hit.
  final bool critical;

  /// Dice plus the flat bonus, floored at zero, before any doubling.
  int get base {
    final sum = dice.fold(0, (a, b) => a + b) + expression.flatBonus;
    return sum < 0 ? 0 : sum;
  }

  int get total => critical ? base * 2 : base;

  /// The roll as a player reads it: `2d10+4 (7+3+4) = 14`, or with a
  /// critical, `2d10+4 (7+3+4) = 14, doubled to 28`.
  @override
  String toString() {
    final doubled = critical ? ', doubled to $total' : '';
    if (dice.isEmpty) return '$base$doubled';
    final flat = expression.flatBonus;
    final working = [
      ...dice.map((d) => '$d'),
      if (flat != 0) '$flat',
    ].join('+').replaceAll('+-', '-');
    return '$expression ($working) = $base$doubled';
  }
}
