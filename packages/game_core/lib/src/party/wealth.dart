import '../campaign/gear.dart';
import 'equipment.dart';

/// What one character of each level is expected to own in all, in gold.
///
/// Pathfinder's lump-sum Character Wealth, the figure a character made at a
/// higher level is given to spend: coin and gear together. Index 0 is level 1.
const List<int> characterWealthGold = [
  15, 30, 75, 140, 270, 450, 720, 1100, 1600, 2300, //
  3200, 4500, 6400, 9300, 13500, 20000, 30000, 45000, 69000, 112000,
];

/// What a party of [partySize] characters of [level] is expected to be
/// worth, in copper. Levels outside 1–20 are read as the nearest end.
int expectedWealth({required int level, required int partySize}) {
  final index = (level - 1).clamp(0, characterWealthGold.length - 1);
  final size = partySize < 1 ? 1 : partySize;
  return characterWealthGold[index] * 100 * size;
}

/// What the party is worth right now.
class Wealth {
  const Wealth({
    required this.coin,
    required this.gear,
    required this.expected,
  });

  /// In the purse, in copper.
  final int coin;

  /// What everything carried would cost, in copper — worn or in the pack.
  final int gear;

  /// What Pathfinder expects a party like this one to be worth, in copper.
  final int expected;

  int get total => coin + gear;

  /// The party's worth against what is expected of it, as a percentage.
  int get percentOfExpected => expected <= 0 ? 0 : total * 100 ~/ expected;

  @override
  String toString() => '${formatCoin(total)} '
      '(${formatCoin(coin)} coin, ${formatCoin(gear)} gear; '
      '$percentOfExpected% of ${formatCoin(expected)})';
}

/// Whether a line of the ledger was coin or a thing.
enum LootKind { coin, item }

/// One thing the party came away with, and where from.
class LootEntry {
  const LootEntry({
    required this.source,
    required this.kind,
    required this.copper,
    this.itemId,
  });

  /// Who or what it came from: a fight, a quest, a person.
  final String source;
  final LootKind kind;

  /// What it was worth when it was found, in copper.
  final int copper;

  /// The item, for [LootKind.item].
  final String? itemId;

  Map<String, Object?> toJson() => {
        'source': source,
        'kind': kind.name,
        'copper': copper,
        if (itemId != null) 'item': itemId,
      };

  static LootEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = LootKind.values
        .where((k) => k.name == json['kind']?.toString())
        .firstOrNull;
    final copper = (json['copper'] as num?)?.toInt();
    if (kind == null || copper == null) return null;
    return LootEntry(
      source: json['source']?.toString() ?? '',
      kind: kind,
      copper: copper,
      itemId: json['item']?.toString(),
    );
  }

  @override
  String toString() => '${formatCoin(copper)} from $source';
}

/// Everything the party has come away with, in the order it came.
///
/// Kept apart from the pack and the purse, which say what the party has now:
/// this says what it has *found*, which selling a sword or spending the coin
/// does not undo.
class LootLedger {
  LootLedger([Iterable<LootEntry> entries = const []])
      : _entries = List.of(entries);

  final List<LootEntry> _entries;

  List<LootEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  void recordCoin(String source, int copper) {
    if (copper <= 0) return;
    _entries
        .add(LootEntry(source: source, kind: LootKind.coin, copper: copper));
  }

  /// Records [item] at what it costs, which is what it is worth to the party
  /// and to anyone who has heard they have it.
  void recordItem(String source, GearItem item) => _entries.add(LootEntry(
        source: source,
        kind: LootKind.item,
        copper: item.price,
        itemId: item.id,
      ));

  int get totalCopper => _entries.fold(0, (sum, e) => sum + e.copper);

  int get coinCopper => _entries
      .where((e) => e.kind == LootKind.coin)
      .fold(0, (sum, e) => sum + e.copper);

  int get itemCopper => totalCopper - coinCopper;

  int get itemCount => _entries.where((e) => e.kind == LootKind.item).length;

  List<Object?> toJson() => [for (final e in _entries) e.toJson()];

  static LootLedger fromJson(Object? json) => LootLedger([
        for (final raw in (json is List ? json : const []))
          if (LootEntry.fromJson(raw) case final entry?) entry,
      ]);

  @override
  String toString() => '${_entries.length} finds, ${formatCoin(totalCopper)}';
}
