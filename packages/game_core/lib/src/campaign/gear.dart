/// An item in the campaign's loot tables.
///
/// Traits are Pathfinder traits and stay as written strings: the engine does
/// not implement them yet, and inventing a partial interpretation would be
/// worse than carrying them through untouched.
class GearItem {
  const GearItem({
    required this.id,
    required this.name,
    required this.level,
    required this.type,
    required this.description,
    this.traits = const [],
    this.stats = const {},
    this.special,
  });

  final String id;
  final String name;
  final int level;

  /// `weapon`, `armor`, or another category the campaign uses.
  final String type;
  final String description;
  final List<String> traits;

  /// Raw stat block, e.g. `{damage: 1d8, bonus: 0, magic: false}`.
  final Map<String, Object?> stats;

  /// Free-text rule this item adds, not yet machine-readable.
  final String? special;

  bool get isMagical => stats['magic'] == true;

  bool hasTrait(String trait) {
    final needle = trait.trim().toLowerCase();
    return traits.any((t) => t.toLowerCase() == needle);
  }

  /// Potency or enhancement bonus, if the item carries one.
  int get bonus => switch (stats['bonus']) {
        final int b => b,
        final num b => b.round(),
        _ => 0,
      };

  String? get damage => stats['damage']?.toString();

  int? get armorClass => switch (stats['ac']) {
        final int ac => ac,
        final num ac => ac.round(),
        _ => null,
      };

  @override
  String toString() => '$name (level $level $type)';
}

/// The campaign's items, with a little reporting over the whole table.
class GearTable {
  GearTable(List<GearItem> items) : _items = List.of(items);

  final List<GearItem> _items;

  List<GearItem> get all => List.unmodifiable(_items);

  int get length => _items.length;

  GearItem? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Items appropriate to a character of [level], within [slack] levels.
  List<GearItem> forLevel(int level, {int slack = 2}) => [
        for (final item in _items)
          if ((item.level - level).abs() <= slack) item,
      ]..sort((a, b) => a.level.compareTo(b.level));

  List<GearItem> ofType(String type) {
    final needle = type.trim().toLowerCase();
    return [
      for (final item in _items)
        if (item.type.toLowerCase() == needle) item,
    ]..sort((a, b) => a.level.compareTo(b.level));
  }

  /// Levels between 1 and [levelCap] with no item at all.
  ///
  /// Loot pacing is a content problem long before it is a balance problem, so
  /// it is worth seeing the gaps early.
  List<int> levelGaps(int levelCap) {
    final covered = {for (final item in _items) item.level};
    return [
      for (var level = 1; level <= levelCap; level++)
        if (!covered.contains(level)) level,
    ];
  }

  @override
  String toString() => '$length items';
}
