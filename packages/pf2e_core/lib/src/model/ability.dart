/// The six Pathfinder 2e ability scores (attributes, post-Remaster).
enum Ability {
  strength('str', 'Strength', 'Str'),
  dexterity('dex', 'Dexterity', 'Dex'),
  constitution('con', 'Constitution', 'Con'),
  intelligence('int', 'Intelligence', 'Int'),
  wisdom('wis', 'Wisdom', 'Wis'),
  charisma('cha', 'Charisma', 'Cha');

  const Ability(this.key, this.displayName, this.abbreviation);

  /// Lower-case key as used by Pathbuilder's `abilities` map and `keyability`.
  final String key;
  final String displayName;

  /// Capitalised short form, as used inside `abilities.breakdown`.
  final String abbreviation;

  /// Resolves either casing Pathbuilder uses. `abilities.str` is lower-case but
  /// `breakdown.classBoosts` holds `"Str"`, so both must round-trip.
  static Ability? tryParse(String raw) {
    final needle = raw.trim().toLowerCase();
    for (final a in Ability.values) {
      if (a.key == needle) return a;
    }
    return null;
  }
}

/// Ability scores for one character, stored as raw scores.
///
/// Pathbuilder exports final scores, so the boost chain in
/// `abilities.breakdown` never needs replaying to derive modifiers.
class AbilityScores {
  const AbilityScores(this._scores);

  final Map<Ability, int> _scores;

  int score(Ability a) => _scores[a] ?? 10;

  /// PF2e modifier: floor((score - 10) / 2).
  ///
  /// Uses floored — not truncated — division so that scores below 10 give the
  /// correct negative modifier (a score of 9 is -1, not 0).
  int modifier(Ability a) => ((score(a) - 10) / 2).floor();

  Map<Ability, int> get all => Map.unmodifiable(_scores);

  @override
  String toString() => Ability.values
      .map((a) => '${a.abbreviation} ${score(a)} '
          '(${modifier(a) >= 0 ? '+' : ''}${modifier(a)})')
      .join(', ');
}
