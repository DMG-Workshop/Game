import 'package:pf2e_core/pf2e_core.dart';

/// Gold pieces for a permanent magic item of each level, 1 to 20.
///
/// Anchored on the fundamental runes, which the rest of Pathfinder's item
/// prices are built around: a +1 weapon is level 2 at 35 gp; +1 striking,
/// level 4 at 100; +1 armour, level 5 at 160; +1 resilient armour, level 8 at
/// 500; +2 striking, level 10 at 1,000; and so on to +3 major resilient armour
/// at level 20 for 70,000.
const List<int> permanentItemGold = [
  20, 35, 60, 100, 160, 250, 360, 500, 700, 1000, //
  1400, 2000, 3000, 4500, 6500, 10000, 15000, 24000, 40000, 70000,
];

/// The price in copper of a permanent magic item of [level].
int permanentItemPrice(int level) =>
    permanentItemGold[level.clamp(1, permanentItemGold.length) - 1] * 100;

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

/// An item bonus an item gives to a check, and when.
///
/// The part of an item's text the engine can act on. [when] is null for a
/// bonus that always applies; otherwise `exposure` (saves against the
/// weather), `region:<id>` or `zone:<id>` (only there). Anything more
/// situational than that stays in the item's text for the table to apply.
class CheckBonus {
  const CheckBonus({required this.stat, required this.bonus, this.when});

  /// The statistic it applies to: a skill, a save, or `perception`.
  final String stat;
  final int bonus;
  final String? when;

  @override
  String toString() => '+$bonus $stat${when == null ? '' : ' ($when)'}';
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
    this.listedPrice,
    this.checkBonuses = const [],
  });

  /// Item bonuses to checks, where the item's text can be put into numbers.
  final List<CheckBonus> checkBonuses;

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

  /// The price the campaign set, in copper, if it set one.
  final int? listedPrice;

  bool get isMagical => stats['magic'] == true;

  bool get isConsumable => hasTrait('consumable');

  /// What it costs to buy, in copper.
  ///
  /// The campaign's own price if it gave one; otherwise Pathfinder's usual
  /// price for a permanent magic item of this level. Consumables and mundane
  /// gear cost a small fraction of that, which is why those should always
  /// carry a price of their own.
  int get price => listedPrice ?? permanentItemPrice(level);

  /// What a merchant pays for it: half, as Pathfinder has it.
  int get resalePrice => price ~/ 2;

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

  /// The armour class as the campaign author wrote it.
  ///
  /// Kept for display. The engine computes AC from [acBonus], [dexCap] and
  /// the potency rune instead, because Pathfinder armour is a bonus and a
  /// Dexterity cap rather than a number that replaces the total.
  int? get armorClass => _asInt(stats['ac']);

  /// The armour's own bonus to AC, before any potency rune.
  int? get acBonus => _asInt(stats['ac_bonus']);

  /// The most Dexterity this armour lets through.
  int? get dexCap => _asInt(stats['dex_cap']);

  /// Weapon damage dice, which a striking rune multiplies.
  StrikingRune get striking => StrikingRune.parse(stats['striking']);

  static int? _asInt(Object? raw) => switch (raw) {
        final int value => value,
        final num value => value.round(),
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
