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
  int seed = 3,
  List<SessionActor>? actors,
}) =>
    WorldSession(
      campaign: _campaign,
      actors: actors ?? [SessionActor(id: 'korash', character: loadKorash())],
      roller: DiceRoller(seed),
      roomId: room,
      flags: flags,
    );

WorldSession _restored(WorldSession world) => WorldSession.restore(
      campaign: _campaign,
      actors: world.actors,
      snapshot:
          jsonDecode(jsonEncode(world.snapshot())) as Map<String, Object?>,
    );

/// Fights whatever is here to the end. The thralls are level 3 and Korash is
/// level 6, so this is a win; the tests are about what the win pays.
EncounterSession _winHere(WorldSession world) {
  final fight = world.beginEncounter();
  var guard = 0;
  while (!fight.isOver && guard++ < 300) {
    if (fight.isPartyTurn) {
      final targets = fight.targetsInReach();
      if (targets.isEmpty) {
        fight.stride();
      } else {
        fight.strike(targets.first.id);
      }
      if (fight.actionsLeft == 0 && !fight.isOver) fight.endTurn();
    } else {
      fight.endTurn();
    }
  }
  expect(fight.outcome, EncounterOutcome.victory);
  return fight;
}

/// Walks back and forth between two rooms [steps] times, starting south.
void _pace(WorldSession world, int steps) {
  for (var i = 0; i < steps; i++) {
    world.move(i.isEven ? 'south' : 'north');
  }
}

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  group('experience', () {
    test("is Pathfinder's table", () {
      expect(creatureXp(-5), 0);
      expect(creatureXp(-4), 10);
      expect(creatureXp(-3), 15);
      expect(creatureXp(-2), 20);
      expect(creatureXp(-1), 30);
      expect(creatureXp(0), 40);
      expect(creatureXp(1), 60);
      expect(creatureXp(2), 80);
      expect(creatureXp(3), 120);
      expect(creatureXp(4), 160);
      expect(creatureXp(9), 160, reason: 'off the end of the table');
    });

    test('accomplishments come in three sizes', () {
      expect(Accomplishment.minor.xp, 10);
      expect(Accomplishment.moderate.xp, 30);
      expect(Accomplishment.major.xp, 80);
    });

    test('a mixed party fights at its average level, rounded down', () {
      expect(partyLevel([6, 7]), 6);
      expect(partyLevel([5, 6, 7, 8]), 6);
      expect(partyLevel(const []), 1);
    });

    test('starts from what the sheet says', () {
      final xp = Experience()
        ..reconcile([(id: 'korash', level: 6, sheetXp: 350)]);
      expect(xp.xpOf('korash'), 350);
    });

    test('a thousand is enough to level', () {
      final xp = Experience()
        ..reconcile([(id: 'korash', level: 6, sheetXp: 0)])
        ..award(['korash'], 990);
      expect(xp.readyToLevel('korash'), isFalse);
      xp.award(['korash'], 10);
      expect(xp.readyToLevel('korash'), isTrue);
    });

    test('a re-imported sheet a level higher takes the thousand off', () {
      final xp = Experience()
        ..reconcile([(id: 'korash', level: 6, sheetXp: 0)])
        ..award(['korash'], 1120);
      final settled = xp.reconcile([(id: 'korash', level: 7, sheetXp: 0)]);
      expect(settled.single.levels, 1);
      expect(xp.xpOf('korash'), 120);
      expect(xp.readyToLevel('korash'), isFalse);
    });

    test('survives a save', () {
      final xp = Experience()
        ..reconcile([(id: 'korash', level: 6, sheetXp: 0)])
        ..award(['korash'], 450);
      final back = Experience.fromJson(jsonDecode(jsonEncode(xp.toJson())));
      expect(back.xpOf('korash'), 450);
      // And it still knows which level it was counting from.
      back.reconcile([(id: 'korash', level: 7, sheetXp: 0)]);
      expect(back.xpOf('korash'), 0);
    });
  });

  group('the track from level 1 to level 20', () {
    Experience at(int level, int xp) =>
        Experience()..reconcile([(id: 'pc', level: level, sheetXp: xp)]);

    test('is a thousand a level, nineteen thousand end to end', () {
      expect(xpForLevel(1), 0);
      expect(xpForLevel(2), 1000);
      expect(xpForLevel(20), 19000);
      expect(XpProgress.fullTrack, 19000);
    });

    test('counts every level before the sheet toward the total', () {
      final p = at(6, 450).progressOf('pc');
      expect(p.level, 6);
      expect(p.total, 5450);
      expect(p.toNext, 550);
      expect(p.earnedLevel, 6);
      expect(p.levelsToGo, 14);
    });

    test('runs ahead of the sheet until it is levelled in Pathbuilder', () {
      final xp = at(6, 0)..award(['pc'], 2500);
      final p = xp.progressOf('pc');
      expect(p.earnedLevel, 8);
      expect(p.toNext, 0);
      expect(xp.readyToLevel('pc'), isTrue);
    });

    test('stops at level 20', () {
      final top = at(20, 0)..award(['pc'], 5000);
      expect(top.xpOf('pc'), 0);
      expect(top.readyToLevel('pc'), isFalse);
      expect(top.progressOf('pc').isMax, isTrue);
      expect(top.progressOf('pc').total, 19000);

      final nearly = at(19, 900)..award(['pc'], 500);
      expect(nearly.xpOf('pc'), 1000, reason: 'enough for 20, and no more');
      expect(nearly.progressOf('pc').earnedLevel, 20);
    });

    test('a character new to the party starts at level 1', () {
      expect(Experience().progressOf('nobody').total, 0);
    });
  });

  group('every fight pays', () {
    test('coin and XP, to everyone in the party', () {
      final world = _world(
        room: 'WW_002_Deep',
        actors: [
          SessionActor(id: 'korash', character: loadKorash()),
          SessionActor(id: 'sela', character: loadSela()),
        ],
      );
      final coinBefore = world.inventory.coin;
      final fight = _winHere(world);
      world.concludeEncounter(fight);

      // Two level 3 thralls against a level 6 party: 15 XP each, 30 in all,
      // and each character earns all 30.
      expect(fight.xpEarned, 30);
      expect(world.experience.xpOf('korash'), 30);
      expect(world.experience.xpOf('sela'), 30);
      // 2d6 gp.
      expect(world.inventory.coin - coinBefore, inInclusiveRange(200, 1200));
    });

    test('nothing for a fight that was not won', () {
      final world = _world(room: 'WW_002_Deep');
      final fight = world.beginEncounter()..flee();
      world.concludeEncounter(fight);
      expect(fight.coinEarned, 0);
      expect(fight.xpEarned, 0);
      expect(world.experience.xpOf('korash'), 0);
    });

    test('every fight in the campaign has coin on it', () {
      for (final e in _campaign.bestiary.encounters) {
        expect(e.coin, isNotNull, reason: e.name);
        expect(DamageExpression.tryParse(e.coin!), isNotNull, reason: e.name);
      }
      expect(_campaign.survey().unpaidEncounters, isEmpty);
    });

    test('refuses coin that is not dice of gold', () {
      expect(
        () => const CampaignLoader().readBestiary('''
{"creatures": [], "encounters": [{"encounter_id": "e", "location": "A",
 "name": "E", "creatures": [], "coin": "a fistful"}]}'''),
        throwsA(isA<CampaignFormatException>()),
      );
    });

    test('the survey reports a fight that pays nothing', () {
      final campaign = const CampaignLoader().load(
        id: 'x',
        title: 'X',
        worldConfigJson: '{"world_metadata": {"name": "X"}}',
        locationsJson: '{"towns": {}, "rooms": [{"room_id": "A", '
            '"title": "A", "description": "a"}]}',
        npcsJson: '{"npcs": []}',
        bestiaryJson: '{"creatures": [], "encounters": [{"encounter_id": '
            '"e_free", "location": "A", "name": "Free Lunch", '
            '"creatures": []}]}',
      );
      expect(campaign.survey().unpaidEncounters.single.name, 'Free Lunch');
    });
  });

  group('quests pay', () {
    test('every quest, main or side, pays coin and XP', () {
      for (final arc in _campaign.arcs.all) {
        expect(arc.reward?.copper, greaterThan(0), reason: arc.name);
        expect(arc.reward?.xp, greaterThan(0), reason: arc.name);
      }
      expect(_campaign.survey().unrewardedArcs, isEmpty);
    });

    test('there are side quests, and they say so', () {
      final side = _campaign.arcs.all.where((a) => a.isSide).map((a) => a.id);
      expect(
          side,
          containsAll([
            'side_liar_at_the_sparrow',
            'side_undertakers_ledger',
            'side_archivists_secret',
          ]));
    });

    test('accomplishment sizes read as Pathfinder XP', () {
      expect(_campaign.arcs.byId('tier_1_local_threat')!.reward!.xp, 80);
      expect(_campaign.arcs.byId('side_liar_at_the_sparrow')!.reward!.xp, 30);
      expect(_campaign.arcs.byId('side_undertakers_ledger')!.reward!.xp, 10);
    });

    test('a side quest starts, finishes, and pays once', () {
      final world = _world(room: 'MH_005_Forge')..take('ledger');
      expect(world.activeArcs().map((a) => a.id),
          contains('side_undertakers_ledger'));

      final coin = world.inventory.coin;
      world
        ..move('east')
        ..move('south');
      final aldus = world.beginConversation('aldus')!.talk
        ..choose('ask_burials');
      world.concludeConversation(aldus);
      world
        ..move('north')
        ..move('west');
      final harrow = world.beginConversation('harrow')!.talk
        ..choose('commissions')
        ..choose('ask_ledger');
      world.concludeConversation(harrow);

      final settled = world.settleArcs();
      expect(settled.completed.single.id, 'side_undertakers_ledger');
      expect(world.inventory.coin, coin + 1000);
      expect(world.experience.xpOf('korash'), 10);

      // Settling again pays nothing more.
      expect(world.settleArcs().completed, isEmpty);
      expect(world.inventory.coin, coin + 1000);
      expect(world.flags, contains('completed_side_undertakers_ledger'));
    });

    test('finishing the first tier pays the council, once', () {
      final world = _world(flags: {
        'enter_MH_001',
        'keyword_quest_unlocked',
        'item_acquired_elaras_doll',
        'boss_defeated_hollow_avatar',
      });
      final coin = world.inventory.coin;
      final settled = world.settleArcs();
      expect(settled.completed.map((a) => a.id), ['tier_1_local_threat']);
      expect(settled.worldState, contains('Unlock_Travel_to_Valorheim'));
      expect(world.inventory.coin, coin + 5000);
      expect(world.experience.xpOf('korash'), 80);
      expect(world.applyPendingWorldState(), isEmpty);
    });

    test('catching the liar any of four ways starts his quest', () {
      final routes = {
        'caught_wendel_lying': 'a Perception roll, or a second opinion',
        'deception_revealed_mere_road': 'the sack at the mill',
      };
      for (final flag in routes.keys) {
        final conversationSets = _campaign.conversations.producibleFlags;
        final itemSets = _campaign.items.producibleFlags;
        expect(
            conversationSets.contains(flag) || itemSets.contains(flag), isTrue,
            reason: routes[flag]);
      }
      final quest = _campaign.arcs.byId('side_liar_at_the_sparrow')!;
      expect(quest.hasStarted({'wendel_lie_uncovered'}), isTrue);
    });

    test('reads XP as a number or an accomplishment size', () {
      final economy = const CampaignLoader().readEconomy('''
{"rewards": [{"flag": "a", "gp": 5, "xp": "major"},
             {"flag": "b", "xp": 12}]}''');
      expect(economy.rewardFor('a')!.xp, 80);
      expect(economy.rewardFor('a')!.copper, 500);
      expect(economy.rewardFor('b')!.xp, 12);
      expect(
        () => const CampaignLoader()
            .readEconomy('{"rewards": [{"flag": "c", "xp": "enormous"}]}'),
        throwsA(isA<CampaignFormatException>()),
      );
    });
  });

  group('Sal Mercy', () {
    Npc sal() => _campaign.npcs.byId('npc_010_sal')!;

    test('travels, and is never simply standing in one room', () {
      expect(sal().travels, isTrue);
      expect(_campaign.npcs.inRoom(sal().location), isNot(contains(sal())));
      expect(_campaign.npcs.travellers, contains(sal()));
    });

    test('is somewhere on her route, or on the road between', () {
      for (var seed = 1; seed <= 20; seed++) {
        final where = _world(seed: seed).whereIs('npc_010_sal');
        expect(where == null || sal().route!.stops.contains(where), isTrue,
            reason: 'seed $seed: $where');
      }
    });

    test('moves on as the party walks, and is sometimes nowhere', () {
      final world = _world(room: 'MH_002_GuardHall');
      final seen = <String?>{world.whereIs('npc_010_sal')};
      for (var i = 0; i < 40; i++) {
        _pace(world, sal().route!.every);
        seen.add(world.whereIs('npc_010_sal'));
      }
      expect(seen.whereType<String>().length, greaterThan(2),
          reason: 'she should get about');
      expect(seen, contains(null), reason: 'and be on the road sometimes');
    });

    test("wanders on her own dice and never the world's", () {
      // A campaign seeded before she existed plays out exactly as it did:
      // walking about rolls nothing on the world's dice, however far she goes.
      final world = _world(room: 'MH_002_GuardHall');
      final before = world.snapshot()['rollerState'];
      _pace(world, 50);
      expect(world.snapshot()['rollerState'], before);
    });

    test('can be talked to and traded with only where she is', () {
      for (var seed = 1; seed <= 60; seed++) {
        final probe = _world(seed: seed);
        final where = probe.whereIs('npc_010_sal');
        if (where == null) continue;

        final here = _world(seed: seed, room: where);
        expect(here.shopHere?.name, "Sal Mercy's Mule");
        expect(here.beginConversation('sal'), isNotNull);

        final elsewhere = _world(
            seed: seed,
            room: where == 'RF_001_Farm' ? 'MH_002_GuardHall' : 'RF_001_Farm');
        expect(elsewhere.shopHere, isNull);
        expect(() => elsewhere.beginConversation('sal'),
            throwsA(isA<InvalidMoveException>()));
        return;
      }
      fail('sixty seeds and she was never anywhere');
    });

    test('carries three things, none of them from the town cart', () {
      final jory = _campaign.economy.shopKeptBy('npc_009_jory')!;
      final joryStock = jory.stock.map((l) => l.itemId).toSet();
      final mule = _campaign.economy.shopKeptBy('npc_010_sal')!;
      expect(mule.stock.map((l) => l.itemId).toSet().intersection(joryStock),
          isEmpty);

      for (var seed = 1; seed <= 30; seed++) {
        final probe = _world(seed: seed);
        final where = probe.whereIs('npc_010_sal');
        if (where == null) continue;
        final wares = _world(seed: seed, room: where).wares();
        expect(wares, hasLength(3), reason: 'seed $seed');
        for (final row in wares) {
          expect(joryStock, isNot(contains(row.item.id)));
          expect(row.item.rarity.mustBeFound, isFalse);
        }
      }
    });

    test('keeps her relics for when there is a road to their buyers', () {
      final mule = _campaign.economy.shopKeptBy('npc_010_sal')!;
      expect(
          mule.onSaleFor(const {}).map((id) => _campaign.gear.byId(id)!.level),
          everyElement(lessThanOrEqualTo(9)));
      expect(mule.onSaleFor({'Unlock_Travel_to_Valorheim'}),
          contains('w_016_sundering_edge'));
    });

    test('is where she was, with what she had, after a save', () {
      final world = _world(room: 'MH_002_GuardHall');
      _pace(world, 11);
      final back = _restored(world);
      expect(back.whereIs('npc_010_sal'), world.whereIs('npc_010_sal'));
      expect(back.onHandAt('s_002_mercys_mule'),
          world.onHandAt('s_002_mercys_mule'));
      // And her next move is the one she would have made anyway.
      _pace(world, sal().route!.every);
      _pace(back, sal().route!.every);
      expect(back.whereIs('npc_010_sal'), world.whereIs('npc_010_sal'));
      expect(back.onHandAt('s_002_mercys_mule'),
          world.onHandAt('s_002_mercys_mule'));
    });

    test('her rumour is a way to catch Wendel out', () {
      final world = _world(
        room: 'MH_003_Tavern',
        flags: {
          'met_wendel',
          'heard_of_the_mere_road',
          'sal_warned_of_the_mere'
        },
      );
      final talk = world.beginConversation('wendel')!.talk
        ..choose('bar')
        ..choose('pedlar');
      world.concludeConversation(talk);
      expect(world.flags,
          containsAll(['caught_wendel_lying', 'wendel_lie_uncovered']));
    });

    test('the survey catches a shop that travels with somebody who does not',
        () {
      final economy = const CampaignLoader().readEconomy('''
{"shops": [{"shop_id": "s", "name": "Cart", "keeper": "npc_k"}]}''');
      final npcs = const CampaignLoader().readNpcs(
          '{"npcs": [{"npc_id": "npc_k", "name": "Kit", "location": "A", '
          '"appearance": "x", "greeting": "y"}]}');
      final problems = economy
          .problems(gear: GearTable(const []), npcs: npcs, roomIds: {'A'});
      expect(problems.single, contains('never goes anywhere'));
    });

    test('the survey catches a route through a room that does not exist', () {
      final npcs = const CampaignLoader().readNpcs(
          '{"npcs": [{"npc_id": "npc_k", "name": "Kit", "location": "A", '
          '"appearance": "x", "greeting": "y", '
          '"route": {"stops": ["A", "Nowhere"]}}]}');
      expect(npcs.misplacedIn({'A'}).single.name, 'Kit');
    });
  });
}
