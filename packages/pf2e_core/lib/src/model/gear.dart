/// Number of weapon damage dice granted by a striking rune.
enum StrikingRune {
  none(1, ''),
  striking(2, 'striking'),
  greaterStriking(3, 'greaterStriking'),
  majorStriking(4, 'majorStriking');

  const StrikingRune(this.diceCount, this.key);

  final int diceCount;
  final String key;

  static StrikingRune parse(Object? raw) {
    if (raw == null) return StrikingRune.none;
    final needle = raw.toString().trim().toLowerCase();
    if (needle.isEmpty) return StrikingRune.none;
    for (final r in StrikingRune.values) {
      if (r.key.toLowerCase() == needle) return r;
    }
    return StrikingRune.none;
  }
}

/// A weapon as exported by Pathbuilder.
///
/// Note the field named `str` in the payload is the *striking rune*, not
/// Strength. The same three letters mean Strength under `abilities`.
class ImportedWeapon {
  const ImportedWeapon({
    required this.name,
    required this.display,
    required this.quantity,
    required this.proficiencyCategory,
    required this.damageDie,
    required this.potencyRune,
    required this.strikingRune,
    required this.material,
    required this.damageType,
    required this.attackBonus,
    required this.damageBonus,
    required this.runes,
  });

  final String name;

  /// Pathbuilder's assembled label, e.g. `+1 Striking Scythe`.
  final String display;
  final int quantity;

  /// `simple`, `martial`, `advanced`, or `unarmed`.
  final String proficiencyCategory;

  /// Damage die as written, e.g. `d10`.
  final String damageDie;
  final int potencyRune;
  final StrikingRune strikingRune;
  final String? material;

  /// Single-letter code: `S` slashing, `P` piercing, `B` bludgeoning.
  final String damageType;

  /// Attack bonus precomputed by Pathbuilder.
  final int attackBonus;

  /// Flat damage bonus precomputed by Pathbuilder.
  final int damageBonus;
  final List<String> runes;

  /// Damage expression, e.g. `2d10+4`.
  String get damageFormula {
    final flat = damageBonus == 0
        ? ''
        : (damageBonus > 0 ? '+$damageBonus' : '$damageBonus');
    return '${strikingRune.diceCount}$damageDie$flat';
  }

  @override
  String toString() => '$display (+$attackBonus, $damageFormula $damageType)';
}

/// A suit of armour as exported by Pathbuilder.
class ImportedArmor {
  const ImportedArmor({
    required this.name,
    required this.display,
    required this.quantity,
    required this.proficiencyCategory,
    required this.potencyRune,
    required this.resilientRune,
    required this.material,
    required this.worn,
    required this.runes,
  });

  final String name;
  final String display;
  final int quantity;

  /// `unarmored`, `light`, `medium`, or `heavy`.
  final String proficiencyCategory;
  final int potencyRune;
  final String? resilientRune;
  final String? material;
  final bool worn;
  final List<String> runes;

  @override
  String toString() => worn ? '$display (worn)' : display;
}

/// Carried coin, in the four PF2e denominations.
class Money {
  const Money({this.cp = 0, this.sp = 0, this.gp = 0, this.pp = 0});

  final int cp;
  final int sp;
  final int gp;
  final int pp;

  /// Total value expressed in copper.
  int get totalInCopper => cp + sp * 10 + gp * 100 + pp * 1000;

  @override
  String toString() => [
        if (pp > 0) '${pp}pp',
        if (gp > 0) '${gp}gp',
        if (sp > 0) '${sp}sp',
        if (cp > 0) '${cp}cp',
      ].join(' ');
}

/// A generic inventory line. Pathbuilder stores these as `[name, quantity]`.
class ImportedItem {
  const ImportedItem(this.name, this.quantity);

  final String name;
  final int quantity;

  @override
  String toString() => quantity == 1 ? name : '$name x$quantity';
}
