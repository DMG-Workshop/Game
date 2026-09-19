/// A Pathfinder 2e proficiency rank.
///
/// Pathbuilder stores ranks as the *bonus value* (0/2/4/6/8) rather than an
/// ordinal 0-4, so the stored number can be used directly in the math.
enum Proficiency {
  untrained(0, 'U', 'Untrained'),
  trained(2, 'T', 'Trained'),
  expert(4, 'E', 'Expert'),
  master(6, 'M', 'Master'),
  legendary(8, 'L', 'Legendary');

  const Proficiency(this.bonus, this.letter, this.displayName);

  final int bonus;
  final String letter;
  final String displayName;

  static Proficiency fromPathbuilder(int raw) => switch (raw) {
        0 => Proficiency.untrained,
        2 => Proficiency.trained,
        4 => Proficiency.expert,
        6 => Proficiency.master,
        8 => Proficiency.legendary,
        _ => throw ArgumentError('Unknown Pathbuilder proficiency value: $raw'),
      };

  /// Proficiency contribution to a check, including the level term.
  ///
  /// Untrained adds neither the rank bonus nor the character's level. This is
  /// the single rule most easily lost when porting the math: an untrained
  /// skill is the bare ability modifier.
  int totalBonusAtLevel(int level) =>
      this == Proficiency.untrained ? 0 : bonus + level;
}
