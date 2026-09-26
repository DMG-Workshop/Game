import 'package:pf2e_core/pf2e_core.dart';

/// What a spell is rolled against.
enum SpellDefense {
  /// A spell attack roll against Armor Class.
  ac,

  /// A basic save by the target against the caster's spell DC.
  fortitude,
  reflex,
  will;

  bool get isSave => this != ac;

  static SpellDefense? tryParse(String source) {
    final needle = source.trim().toLowerCase();
    for (final d in values) {
      if (d.name == needle) return d;
    }
    return null;
  }
}

/// The numbers the engine needs to resolve a damaging spell in a fight.
///
/// Deliberately only numbers: how far, against what, how much, and how it
/// grows. The spell's name is what matches it to a character's own list;
/// its rules text is not stored here, and the engine does not need it. Riders
/// the engine cannot yet run — persistent damage, a condition on a critical
/// failure — are left out rather than half-done.
class Spell {
  const Spell({
    required this.name,
    required this.rank,
    required this.defense,
    required this.damage,
    this.actions = 2,
    this.range = 'far',
    this.area = false,
    this.heightenEvery = 1,
    this.heightenDamage,
  });

  final String name;

  /// Its lowest rank; 0 for a cantrip.
  final int rank;

  final SpellDefense defense;

  /// Damage at [rank].
  final DamageExpression damage;

  final int actions;

  /// The furthest zone it reaches: `engaged`, `near` or `far`.
  final String range;

  /// True for a burst that catches everybody in one zone, friend or foe.
  final bool area;

  /// Ranks between each step of [heightenDamage].
  final int heightenEvery;

  /// Added for each [heightenEvery] ranks above [rank].
  final DamageExpression? heightenDamage;

  bool get isCantrip => rank == 0;

  /// The damage when cast at [castRank].
  ///
  /// Extra dice for every [heightenEvery] ranks above the spell's own; a
  /// cantrip counts from rank 1.
  DamageExpression damageAt(int castRank) {
    final base = rank < 1 ? 1 : rank;
    final extra = heightenDamage;
    if (extra == null || castRank <= base) return damage;
    final steps = (castRank - base) ~/ heightenEvery;
    return DamageExpression(
      diceCount: damage.diceCount + extra.diceCount * steps,
      dieSize: damage.dieSize,
      flatBonus: damage.flatBonus + extra.flatBonus * steps,
    );
  }

  @override
  String toString() => '$name (${isCantrip ? 'cantrip' : 'rank $rank'})';
}

/// The spells the engine knows the numbers for, by name.
class SpellBook {
  SpellBook([Iterable<Spell> spells = const []])
      : _byName = {for (final s in spells) _key(s.name): s};

  final Map<String, Spell> _byName;

  static String _key(String name) => name.trim().toLowerCase();

  bool get isEmpty => _byName.isEmpty;
  int get length => _byName.length;
  List<Spell> get all => List.unmodifiable(_byName.values);

  Spell? byName(String name) => _byName[_key(name)];
}

/// The rank a cantrip is cast at: half the caster's level, rounded up.
int cantripRank(int level) => (level + 1) ~/ 2;
