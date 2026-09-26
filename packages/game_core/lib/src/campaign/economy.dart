import 'gear.dart';
import 'npc.dart';

/// One thing a shop sells, and when.
class StockLine {
  const StockLine({required this.itemId, this.requiredFlags = const []});

  final String itemId;

  /// Flags that must be set before it is on the shelf: a wagon has come in,
  /// a road has opened, a debt has been paid.
  final List<String> requiredFlags;

  bool isOnSale(Set<String> flags) => requiredFlags.every(flags.contains);
}

/// A change to a shop's prices once a flag is set, in percent.
///
/// Negative is a discount. They add together, so a merchant who likes the
/// party and has also been insulted by them comes out somewhere in between.
class PriceModifier {
  const PriceModifier({required this.flag, required this.percent});

  final String flag;
  final int percent;
}

/// Somewhere the party can buy and sell gear.
///
/// A shop is a keeper standing in a room. Pathfinder's rules, not a MUD's:
/// stock is sold at its price and bought back at half, and rare things are not
/// on any shelf, because being unbuyable is what makes them rare.
class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.keeperId,
    required this.location,
    this.stock = const [],
    this.modifiers = const [],
  });

  final String id;
  final String name;
  final String keeperId;

  /// The room the keeper trades from.
  final String location;
  final List<StockLine> stock;
  final List<PriceModifier> modifiers;

  /// Item ids on the shelf for a party with [flags].
  List<String> onSaleFor(Set<String> flags) => [
        for (final line in stock)
          if (line.isOnSale(flags)) line.itemId,
      ];

  /// The combined percentage the party pays over or under the price.
  int percentFor(Set<String> flags) => modifiers
      .where((m) => flags.contains(m.flag))
      .fold(0, (sum, m) => sum + m.percent);

  /// What [item] costs here, in copper, for a party with [flags].
  ///
  /// Never less than a copper: a discount is a kindness, not a gift.
  int priceFor(GearItem item, Set<String> flags) {
    final adjusted = (item.price * (100 + percentFor(flags)) / 100).round();
    return adjusted < 1 ? 1 : adjusted;
  }

  @override
  String toString() => '$name ($location)';
}

/// Coin paid out once, the first time a flag is set.
///
/// A flag can only be set once, so a reward keyed to one cannot be claimed
/// twice however many ways there are of setting it.
class CoinReward {
  const CoinReward({required this.flag, required this.copper});

  final String flag;
  final int copper;
}

/// The campaign's shops and the coin it pays out.
class Economy {
  Economy({List<Shop> shops = const [], List<CoinReward> rewards = const []})
      : _shops = List.of(shops),
        _rewards = {for (final r in rewards) r.flag: r.copper};

  final List<Shop> _shops;
  final Map<String, int> _rewards;

  List<Shop> get shops => List.unmodifiable(_shops);

  Shop? shopIn(String roomId) {
    for (final shop in _shops) {
      if (shop.location == roomId) return shop;
    }
    return null;
  }

  /// Copper paid for setting [flag], or 0.
  int rewardFor(String flag) => _rewards[flag] ?? 0;

  Set<String> get rewardFlags => _rewards.keys.toSet();

  /// What is wrong with the shops, in words an author can act on.
  List<String> problems({
    required GearTable gear,
    required NpcDirectory npcs,
    required Set<String> roomIds,
  }) {
    final out = <String>[];
    for (final shop in _shops) {
      if (!roomIds.contains(shop.location)) {
        out.add('${shop.name} is in "${shop.location}", which does not exist');
      }
      final keeper = npcs.byId(shop.keeperId);
      if (keeper == null) {
        out.add('${shop.name} is kept by "${shop.keeperId}", who does not '
            'exist');
      } else if (keeper.location != shop.location) {
        out.add('${shop.name} is in ${shop.location}, but ${keeper.name} is '
            'standing in ${keeper.location}');
      }
      for (final line in shop.stock) {
        final item = gear.byId(line.itemId);
        if (item == null) {
          out.add('${shop.name} sells "${line.itemId}", which does not exist');
        } else if (item.rarity.mustBeFound) {
          out.add('${shop.name} sells ${item.name}, which is '
              '${item.rarity.name} and should only be found');
        } else if (item.listedPrice == null &&
            (item.isConsumable || !item.isMagical)) {
          out.add('${shop.name} sells ${item.name} with no price of its own; '
              'the default is for permanent magic items and would overcharge');
        }
      }
    }
    return out;
  }

  @override
  String toString() => '${_shops.length} shops';
}
