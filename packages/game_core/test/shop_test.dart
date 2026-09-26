import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;

WorldSession _world({
  String room = 'MH_001_Square',
  Set<String>? flags,
  List<SessionActor>? actors,
}) =>
    WorldSession(
      campaign: _campaign,
      actors: actors ?? [SessionActor(id: 'korash', character: loadKorash())],
      roller: DiceRoller(3),
      roomId: room,
      flags: flags,
    );

int _gp(num gold) => (gold * 100).round();

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  group('prices', () {
    test('follow the fundamental runes', () {
      // The anchors the whole table hangs off: +1 weapon, +1 striking,
      // +1 armour, +1 resilient armour, +2 striking, +3 major resilient.
      expect(permanentItemPrice(2), _gp(35));
      expect(permanentItemPrice(4), _gp(100));
      expect(permanentItemPrice(5), _gp(160));
      expect(permanentItemPrice(8), _gp(500));
      expect(permanentItemPrice(10), _gp(1000));
      expect(permanentItemPrice(20), _gp(70000));
    });

    test('climb with every level', () {
      for (var level = 2; level <= 20; level++) {
        expect(permanentItemPrice(level),
            greaterThan(permanentItemPrice(level - 1)),
            reason: 'level $level');
      }
    });

    test('an item the campaign priced keeps its own price', () {
      // A plain longsword is a gold piece, not the price of a magic item.
      expect(_campaign.gear.byId('w_001_guard_sword')!.price, _gp(1));
      expect(_campaign.gear.byId('g_003_charm_of_iron_nails')!.price, _gp(10));
    });

    test('everything else is priced by its level', () {
      expect(_campaign.gear.byId('w_006_shadowbane_dagger')!.price, _gp(160));
      expect(_campaign.gear.byId('w_019_the_last_nail')!.price, _gp(40000));
    });

    test('sells back for half', () {
      expect(
          _campaign.gear.byId('w_002_nail_iron_spade')!.resalePrice, _gp(17.5));
    });

    test('nothing cheap is priced like a magic item', () {
      // The default is for permanent magic items. Anything else without a
      // price of its own would be sold for many times what it is worth.
      for (final item in _campaign.gear.all) {
        if (item.isConsumable || !item.isMagical) {
          expect(item.listedPrice, isNotNull, reason: item.name);
        }
      }
    });

    test('refuses a price that is not an amount of gold', () {
      expect(
        () => const CampaignLoader().readGear(
            '{"gear":[{"item_id":"i","name":"I","level":1,"price":"lots"}]}'),
        throwsA(isA<CampaignFormatException>()),
      );
    });
  });

  group('the purse', () {
    test('starts with what the character sheet says they carry', () {
      // Korash's Pathbuilder export has 270 gp in it, and it is his.
      expect(_world().inventory.coin, _gp(270));
    });

    test('pools a party', () {
      final world = _world(actors: [
        SessionActor(id: 'korash', character: loadKorash()),
        SessionActor(id: 'sela', character: loadSela()),
      ]);
      expect(world.inventory.coin, _gp(270 + 95));
    });

    test('survives a save exactly', () {
      final world = _world()..buy('spade');
      final restored = WorldSession.restore(
        campaign: _campaign,
        actors: world.actors,
        snapshot:
            jsonDecode(jsonEncode(world.snapshot())) as Map<String, Object?>,
      );
      expect(restored.inventory.coin, world.inventory.coin);
      expect(restored.inventory.countOf('w_002_nail_iron_spade'), 1);
    });

    test('a save from before coin existed gets the sheet coin back', () {
      final restored = WorldSession.restore(
        campaign: _campaign,
        actors: [SessionActor(id: 'korash', character: loadKorash())],
        snapshot: {
          'campaignId': _campaign.id,
          'roomId': 'MH_001_Square',
          'flags': <String>[],
          'rollerState': 1,
          'inventory': {'carried': <String>[], 'equipped': {}},
        },
      );
      expect(restored.inventory.coin, _gp(270));
    });
  });

  group("Tallow's Cart", () {
    test('is in the market square, and nowhere else', () {
      expect(_world().shopHere?.name, "Tallow's Cart");
      expect(_world(room: 'MH_002_GuardHall').shopHere, isNull);
      expect(
          () => _world(room: 'MH_002_GuardHall').wares(),
          throwsA(isA<InvalidMoveException>()
              .having((e) => e.message, 'message', contains('nobody'))));
    });

    test('sells what a stranded pedlar would, cheapest first', () {
      final wares = _world().wares();
      expect(wares.map((r) => r.item.id), [
        'w_001_guard_sword',
        'g_033_hearth_water_minor',
        'g_034_hearth_water_lesser',
        'w_002_nail_iron_spade',
        'g_035_hearth_water_moderate',
        'w_004_whisperwood_bow',
        'w_006_shadowbane_dagger',
        'a_006_ravencrest_hide',
      ]);
      final prices = wares.map((r) => r.price).toList();
      expect(prices, orderedEquals(prices.toList()..sort()));
    });

    test('gets a wagon from the capital once the road opens', () {
      final wares = _world(flags: {'Unlock_Travel_to_Valorheim'}).wares();
      expect(wares, hasLength(14));
      expect(wares.map((r) => r.item.id), contains('a_011_palace_cuirass'));
      expect(wares.map((r) => r.item.level).reduce((a, b) => a > b ? a : b),
          lessThanOrEqualTo(12),
          reason: 'a market town does not stock level 20 gear');
    });

    test('never has anything rare on the shelf', () {
      final wares = _world(flags: {'Unlock_Travel_to_Valorheim'}).wares();
      for (final row in wares) {
        expect(row.item.rarity.mustBeFound, isFalse, reason: row.item.name);
      }
    });

    test('takes the price and hands over a copy', () {
      final world = _world();
      final bought = world.buy('whisperwood');
      expect(bought.item.id, 'w_004_whisperwood_bow');
      expect(bought.price, _gp(100));
      expect(world.inventory.coin, _gp(170));
      expect(world.inventory.countOf('w_004_whisperwood_bow'), 1);
    });

    test('sells as many copies as the party can pay for', () {
      final world = _world()
        ..buy('guard sword')
        ..buy('guard sword')
        ..buy('guard sword');
      expect(world.inventory.countOf('w_001_guard_sword'), 3);
      expect(world.inventory.coin, _gp(267));
    });

    test('will not sell what the party cannot afford, or charge for trying',
        () {
      final world = _world()
        ..buy('ravencrest')
        ..buy('guard sword');
      final before = world.inventory.coin;
      expect(
        () => world.buy('shadowbane'),
        throwsA(isA<InvalidMoveException>()
            .having((e) => e.message, 'message', contains('160 gp'))),
      );
      expect(world.inventory.coin, before);
      expect(world.inventory.isCarrying('w_006_shadowbane_dagger'), isFalse);
    });

    test('has nothing it does not stock', () {
      expect(
        () => _world().buy('last nail'),
        throwsA(isA<InvalidMoveException>()
            .having((e) => e.message, 'message', contains('Jory Tallow'))),
      );
    });

    test('buys anything back for half, rare things included', () {
      final world = _world(flags: {'loot_w_024_crown_spike'});
      final sold = world.sell('crown spike');
      expect(sold.price, _gp(500));
      expect(world.inventory.isCarrying('w_024_crown_spike'), isFalse);
      expect(world.inventory.coin, _gp(270 + 500));
    });

    test('quotes a price without taking anything', () {
      final world = _world()..buy('spade');
      expect(world.valueOf('spade').price, _gp(17.5));
      expect(world.inventory.countOf('w_002_nail_iron_spade'), 1);
    });

    test('will not buy what somebody is holding, and says who', () {
      final world = _world()..buy('shadowbane');
      world.equip('shadowbane');
      expect(
        () => world.sell('shadowbane'),
        throwsA(isA<InvalidMoveException>().having((e) => e.message, 'message',
            contains('Korash Blackearth is using'))),
      );
      world.unequip('weapon');
      expect(world.sell('shadowbane').price, _gp(80));
    });

    test('a haggled discount comes off every price', () {
      final list = _world().wares().first.price;
      expect(_world(flags: {'jory_discount'}).wares().first.price,
          (list * 0.9).round());
      expect(_world(flags: {'jory_discount_large'}).wares().first.price,
          (list * 0.8).round());
      expect(_world(flags: {'jory_offended'}).wares().first.price,
          (list * 1.1).round());
    });

    test('a discount does not raise what he pays for things', () {
      final world = _world(flags: {'jory_discount_large'})..buy('spade');
      expect(world.valueOf('spade').price, _gp(17.5));
    });

    test('talking him down is a real roll', () {
      final world = _world();
      final talk = world.beginConversation('jory')!.talk..choose('look');
      final event = talk.choose('haggle');
      expect(event.check?.label, 'Diplomacy');
      world.concludeConversation(talk);
      expect(world.flags, contains('jory_haggled'));
    });
  });

  group('rewards', () {
    WorldSession paidBy(String flag) {
      final world = _world(
        room: 'MH_002_GuardHall',
        flags: {'boss_defeated_hollow_avatar', 'met_thorne', flag},
      );
      final talk = world.beginConversation('thorne')!.talk;
      final pay = talk.availableOptions().firstWhere(
            (o) => o.id.startsWith('paid_'),
          );
      talk.choose(pay.id);
      world.concludeConversation(talk);
      return world;
    }

    test("Thorne pays what was haggled for, in coin", () {
      expect(paidBy('thorne_offended').inventory.coin, _gp(270 + 50));
      expect(paidBy('thorne_reward_raised').inventory.coin, _gp(270 + 75));
      expect(paidBy('thorne_reward_doubled').inventory.coin, _gp(270 + 100));
    });

    test('a reward is paid once, however it is reached again', () {
      final world = paidBy('thorne_reward_raised');
      final paid = world.inventory.coin;
      // Talking to him again offers nothing more to collect...
      final again = world.beginConversation('thorne')!.talk;
      expect(again.availableOptions().map((o) => o.id),
          isNot(contains('paid_raised')));
      world.concludeConversation(again);
      // ...and a session rebuilt from the same flags does not pay twice.
      final restored = WorldSession.restore(
        campaign: _campaign,
        actors: world.actors,
        snapshot: world.snapshot(),
      );
      expect(world.inventory.coin, paid);
      expect(restored.inventory.coin, paid);
    });
  });

  group('the survey', () {
    Economy economy(String stock, {String keeperRoom = 'A'}) =>
        const CampaignLoader().readEconomy('''
{"shops": [{"shop_id": "s", "name": "Stall", "keeper": "npc_k",
  "location": "A", "stock": $stock}]}''');

    final gear = const CampaignLoader().readGear('''
{"gear": [
  {"item_id": "w_plain", "name": "Plain Club", "level": 1, "type": "weapon",
   "stats": {"damage": "1d6", "magic": false}},
  {"item_id": "w_rare", "name": "Rare Blade", "level": 5, "type": "weapon",
   "rarity": "rare", "stats": {"magic": true},
   "drops": [{"from": "c_x", "chance": 5}]}
]}''');

    NpcDirectory keeperIn(String room) => const CampaignLoader().readNpcs(
        '{"npcs": [{"npc_id": "npc_k", "name": "Kit", "location": "$room", '
        '"appearance": "x", "greeting": "y"}]}');

    test('reports stock that is rare, missing, or priced like magic', () {
      final problems = economy(
        '[{"item": "w_plain"}, {"item": "w_rare"}, {"item": "w_ghost"}]',
      ).problems(gear: gear, npcs: keeperIn('A'), roomIds: {'A'});
      expect(problems, hasLength(3));
      expect(problems, anyElement(contains('Rare Blade, which is rare')));
      expect(problems, anyElement(contains('"w_ghost"')));
      expect(problems, anyElement(contains('Plain Club with no price')));
    });

    test('reports a keeper standing somewhere else', () {
      final problems = economy('[]')
          .problems(gear: gear, npcs: keeperIn('B'), roomIds: {'A', 'B'});
      expect(problems.single, contains('Kit is standing in B'));
    });

    test('is clean for the real campaign', () {
      expect(_campaign.survey().shopProblems, isEmpty);
    });
  });
}
