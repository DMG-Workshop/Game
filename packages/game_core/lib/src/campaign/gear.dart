/// How hard an item is to come by.
///
/// Pathfinder's rarity traits, used here for what they actually mean: not how
/// powerful an item is, but how available. Most magic gear in Pathfinder is
/// common, including the expensive kind, so an item says otherwise only when
/// the campaign means it to be unobtainable by ordinary means.
enum ItemRarity {
  common,
  uncommon,
  rare,
  unique;

  /// Reads a rarity, returning null when [source] is not one.
  ///
  /// Null rather than a default, so a misspelt rarity is caught by whoever
  /// is reading the file instead of quietly making a rare item buyable.
  static ItemRarity? tryParse(String? source) {
    final needle = source?.trim().toLowerCase();
    for (final rarity in values) {
      if (rarity.name == needle) return rarity;
    }
    return null;
  }

  /// Rare and unique items are the ones that must be found rather than bought.
  bool get mustBeFound => index >= ItemRarity.rare.index;

  String get label => name[0].toUpperCase() + name.substring(1);
}

/// A creature that may be carrying an item, and how often it is.
///
/// The chance is a percentage rolled on the session's own dice, so a
/// playthrough replays identically from its seed — a rare drop that changed
/// between a phone and a browser would not be a rare drop, it would be a bug.
class DropSource {
  const DropSource({required this.creatureId, required this.chance});

  /// Creature whose defeat rolls for this item.
  final String creatureId;

  /// Percentage chance, 1 to 100. 100 is a guaranteed reward.
  final int chance;

  bool get isGuaranteed => chance >= 100;

  @override
  String toString() => '$creatureId ($chance%)';
}

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
    this.rarity = ItemRarity.common,
    this.drops = const [],
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

  /// How available it is.
  final ItemRarity rarity;

  /// Creatures that may be carrying it, if it is something to be found.
  final List<DropSource> drops;

  bool get isMagical => stats['magic'] == true;

  /// True when this can only be had by killing something for it.
  bool get isDrop => drops.isNotEmpty;

  /// The chance [creatureId] is carrying this, or null when it never is.
  DropSource? dropFrom(String creatureId) {
    for (final drop in drops) {
      if (drop.creatureId == creatureId) return drop;
    }
    return null;
  }

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
  String toString() => rarity == ItemRarity.common
      ? '$name (level $level $type)'
      : '$name (level $level ${rarity.name} $type)';
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

  List<GearItem> ofRarity(ItemRarity rarity) => [
        for (final item in _items)
          if (item.rarity == rarity) item,
      ]..sort((a, b) => a.level.compareTo(b.level));

  /// Items that have to be found rather than bought.
  List<GearItem> get rareDrops => [
        for (final item in _items)
          if (item.rarity.mustBeFound) item,
      ]..sort((a, b) => a.level.compareTo(b.level));

  /// Items [creatureId] may be carrying, cheapest chance last.
  List<GearItem> droppedBy(String creatureId) => [
        for (final item in _items)
          if (item.dropFrom(creatureId) != null) item,
      ]..sort((a, b) {
          final byChance = b
              .dropFrom(creatureId)!
              .chance
              .compareTo(a.dropFrom(creatureId)!.chance);
          return byChance != 0 ? byChance : a.level.compareTo(b.level);
        });

  /// Drops naming a creature the bestiary does not have.
  ///
  /// A drop table pointing at a creature nobody wrote is an item that can
  /// never be found, which is the same bug as a quest step nothing can set.
  List<({GearItem item, String creatureId})> danglingDrops(
      Set<String> knownCreatureIds) {
    final out = <({GearItem item, String creatureId})>[];
    for (final item in _items) {
      for (final drop in item.drops) {
        if (!knownCreatureIds.contains(drop.creatureId)) {
          out.add((item: item, creatureId: drop.creatureId));
        }
      }
    }
    return out;
  }

  /// Rare items nothing drops, which no amount of playing would turn up.
  List<GearItem> get unobtainableRarities => [
        for (final item in _items)
          if (item.rarity.mustBeFound && item.drops.isEmpty) item,
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
