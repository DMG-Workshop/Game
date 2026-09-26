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
    this.location,
    this.stock = const [],
    this.modifiers = const [],
    this.carries,
    this.lines = const ShopLines(),
  });

  final String id;
  final String name;
  final String keeperId;

  /// The room the keeper trades from, or null for a shop that travels with
  /// its keeper and is wherever they are.
  final String? location;

  /// How many things from [stock] are on hand at any one stop, for a shop
  /// that carries a different selection each time; null for all of it.
  final int? carries;

  bool get travels => location == null;

  /// What the keeper says across the counter.
  final ShopLines lines;
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

/// What a shopkeeper says across the counter.
class ShopLines {
  const ShopLines({
    this.greet = const [],
    this.buy = const [],
    this.sell = const [],
    this.broke = const [],
  });

  /// When the party looks over the stock.
  final List<String> greet;

  /// When the party buys something.
  final List<String> buy;

  /// When the party sells something.
  final List<String> sell;

  /// When the party cannot afford it.
  final List<String> broke;

  bool get isEmpty =>
      greet.isEmpty && buy.isEmpty && sell.isEmpty && broke.isEmpty;

  List<String> gaps() => [
        if (greet.isEmpty) 'nothing to greet a customer with',
        if (buy.isEmpty) 'nothing when something is bought',
        if (sell.isEmpty) 'nothing when something is sold',
        if (broke.isEmpty) 'nothing for a customer who cannot pay',
      ];
}

/// Coin and experience paid out together.
class Payout {
  const Payout({this.copper = 0, this.xp = 0});

  final int copper;

  /// XP each member of the party earns.
  final int xp;

  bool get isEmpty => copper <= 0 && xp <= 0;

  @override
  String toString() => '$copper cp, $xp XP';
}

/// A payout made once, the first time a flag is set.
///
/// A flag can only be set once, so a reward keyed to one cannot be claimed
/// twice however many ways there are of setting it.
class Reward {
  const Reward({required this.flag, required this.payout, this.from});

  final String flag;
  final Payout payout;

  /// Who pays it, for the party's ledger.
  final String? from;
}

/// The campaign's shops and the coin it pays out.
class Economy {
  Economy({List<Shop> shops = const [], List<Reward> rewards = const []})
      : _shops = List.of(shops),
        _rewards = {for (final r in rewards) r.flag: r};

  final List<Shop> _shops;
  final Map<String, Reward> _rewards;

  List<Shop> get shops => List.unmodifiable(_shops);

  /// The shop that stays in [roomId], if one does.
  Shop? shopIn(String roomId) {
    for (final shop in _shops) {
      if (shop.location == roomId) return shop;
    }
    return null;
  }

  /// The shop [npcId] keeps, wherever it is.
  Shop? shopKeptBy(String npcId) {
    for (final shop in _shops) {
      if (shop.keeperId == npcId) return shop;
    }
    return null;
  }

  /// What setting [flag] pays, if anything.
  Payout? rewardFor(String flag) => _rewards[flag]?.payout;

  /// Who pays for setting [flag], if anybody is named.
  String? payerFor(String flag) => _rewards[flag]?.from;

  Set<String> get rewardFlags => _rewards.keys.toSet();

  /// What is wrong with the shops, in words an author can act on.
  List<String> problems({
    required GearTable gear,
    required NpcDirectory npcs,
    required Set<String> roomIds,
  }) {
    final out = <String>[];
    for (final shop in _shops) {
      final location = shop.location;
      if (location != null && !roomIds.contains(location)) {
        out.add('${shop.name} is in "$location", which does not exist');
      }
      final keeper = npcs.byId(shop.keeperId);
      if (keeper == null) {
        out.add('${shop.name} is kept by "${shop.keeperId}", who does not '
            'exist');
      } else if (shop.travels && !keeper.travels) {
        out.add('${shop.name} travels, but ${keeper.name} never goes '
            'anywhere');
      } else if (!shop.travels && keeper.travels) {
        out.add('${shop.name} stays in $location, but ${keeper.name} '
            'travels');
      } else if (!shop.travels && keeper.location != location) {
        out.add('${shop.name} is in $location, but ${keeper.name} is '
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
