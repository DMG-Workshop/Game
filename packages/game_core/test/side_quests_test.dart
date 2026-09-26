import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;

WorldSession _world(String room, {Set<String> flags = const {}}) =>
    WorldSession(
      campaign: _campaign,
      actors: [SessionActor(id: 'korash', character: loadKorash())],
      roller: DiceRoller(3),
      roomId: room,
      flags: flags,
    );

/// The same game, picked up somewhere else, with [flags] added: the long walk
/// between two ends of a side quest is not what these tests are about.
WorldSession _resume(WorldSession world, String room,
    {Set<String> flags = const {}}) {
  final snapshot =
      jsonDecode(jsonEncode(world.snapshot())) as Map<String, Object?>;
  snapshot['roomId'] = room;
  snapshot['cameFrom'] = null;
  snapshot['flags'] = [...(snapshot['flags'] as List), ...flags];
  return WorldSession.restore(
      campaign: _campaign, actors: world.actors, snapshot: snapshot);
}

/// Talks to [who], making [choices] in order, and brings the result home.
List<String> _talk(WorldSession world, String who, List<String> choices) {
  final opened = world.beginConversation(who);
  expect(opened, isNotNull, reason: '$who has nothing to say');
  for (final choice in choices) {
    final offered = opened!.talk.availableOptions().map((o) => o.id);
    expect(offered, contains(choice),
        reason: '${opened.talk.currentScene.id} offers $offered');
    opened.talk.choose(choice);
  }
  return world.concludeConversation(opened!.talk);
}

EncounterSession _fightOut(EncounterSession fight) {
  var guard = 0;
  while (!fight.isOver && guard++ < 500) {
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
  return fight;
}

bool _isActive(WorldSession world, String arcId) =>
    world.activeArcs().any((a) => a.id == arcId);

/// Settles the arcs and checks [arcId] finished, paying what it promised.
void _expectFinished(WorldSession world, String arcId) {
  final arc = _campaign.arcs.byId(arcId)!;
  final coin = world.inventory.coin;
  final settled = world.settleArcs();
  expect(settled.completed.map((a) => a.id), contains(arcId));
  expect(world.inventory.coin, coin + arc.reward!.copper);
  expect(world.ledger.entries.last.source, arc.name);
}

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  group('the whole map', () {
    test('every region has a side quest set in it', () {
      final regions = {
        for (final town in _campaign.locations.towns)
          for (final zone in town.zones) zone.id,
      };
      final covered = {
        for (final arc in _campaign.arcs.all)
          if (arc.isSide && arc.zone != null) arc.zone,
      };
      expect(covered, containsAll(regions));
      expect(_campaign.survey().sideQuestGaps, isEmpty);
    });

    test('and one follows the party wherever they are hunted', () {
      final roaming =
          _campaign.arcs.all.where((a) => a.isSide && a.zone == null);
      expect(roaming.map((a) => a.id), ['side_price_on_your_heads']);
    });

    test('side quests run the whole level range, 1 to 20', () {
      final side = _campaign.arcs.all.where((a) => a.isSide);
      for (var level = 1; level <= 20; level++) {
        expect(side.where((a) => a.suitsLevel(level)), isNotEmpty,
            reason: 'level $level');
      }
    });

    test('every side quest pays coin and XP', () {
      for (final arc in _campaign.arcs.all.where((a) => a.isSide)) {
        expect(arc.reward!.copper, greaterThan(0), reason: arc.name);
        expect(arc.reward!.xp, greaterThan(0), reason: arc.name);
      }
    });

    test('the survey notices a region left out, and a region made up', () {
      final report = Campaign(
        id: 'x',
        title: 'x',
        world: _campaign.world,
        locations: _campaign.locations,
        npcs: _campaign.npcs,
        gear: _campaign.gear,
        arcs: ArcTrack([
          for (final arc in _campaign.arcs.all)
            if (arc.zone != 'z_03_ravencrest') arc,
          const CampaignArc(
            id: 'side_nowhere',
            name: 'Nowhere',
            levels: [1, 2],
            startTrigger: 'enter_MH_001',
            objectives: [],
            isSide: true,
            zone: 'z_99_atlantis',
          ),
        ]),
      ).survey();
      expect(report.sideQuestGaps, [
        'No side quest in z_03_ravencrest',
        'Nowhere is set in "z_99_atlantis", which is not on the map',
      ]);
    });
  });

  group('finding things by what a player types', () {
    test('hyphenated names answer to either half', () {
      final items = _campaign.items;
      expect(items.findInRoom('WW_002_Deep', 'tokens')?.id, 'i_name_tokens');
      expect(
          items.findInRoom('WW_002_Deep', 'name tokens')?.id, 'i_name_tokens');
      expect(
          items.findInRoom('MR_002_ReedBeds', 'stone')?.id, 'i_drowning_stone');
      expect(items.findInRoom('MR_002_ReedBeds', 'drowning')?.id,
          'i_drowning_stone');
    });

    test('possessives answer with or without the apostrophe', () {
      final items = _campaign.items;
      for (final query in [
        'reader',
        'readers',
        "reader's",
        'day book',
        'day-book',
        "reader's day-book"
      ]) {
        expect(items.findInRoom('UA_002_OssuaryStair', query)?.id,
            'i_readers_daybook',
            reason: query);
      }
    });

    test('a word has to be a whole word', () {
      expect(_campaign.items.findInRoom('WW_002_Deep', 'toke'), isNull);
      expect(_campaign.items.findInRoom('WW_002_Deep', 'tokens of'), isNull);
    });
  });

  group('Names for the Hollow', () {
    test('the tokens turn up once the thralls are down', () {
      final before = _world('WW_002_Deep');
      expect(before.look().items.map((i) => i.id),
          isNot(contains('i_name_tokens')));
      final after =
          _world('WW_002_Deep', flags: {'cleared_whisperwood_thralls'});
      expect(after.look().items.map((i) => i.id), contains('i_name_tokens'));
    });

    test('taking them to Aldus lays it to rest', () {
      var world = _world('WW_002_Deep', flags: {'cleared_whisperwood_thralls'});
      world.take('tokens');
      expect(_isActive(world, 'side_names_for_the_hollow'), isTrue);

      world = _resume(world, 'MH_004_Temple');
      _talk(world, 'aldus', ['ask_burials', 'give_names']);
      _expectFinished(world, 'side_names_for_the_hollow');
    });

    test('Aldus takes them after the grove as well as before', () {
      final world = _world('MH_004_Temple', flags: {
        'boss_defeated_hollow_avatar',
        'item_acquired_name_tokens',
      });
      expect(_talk(world, 'aldus', ['give_names']),
          contains('aldus_took_the_names'));
    });
  });

  group('The Scarecrow Walks', () {
    test('Marta starts it, the grove holds it, Marta hears the end', () {
      var world = _world('RF_001_Farm');
      expect(world.availableEncounters(), isEmpty);
      _talk(world, 'marta', ['gentle', 'ask_scarecrow']);
      expect(_isActive(world, 'side_scarecrow_walks'), isTrue);

      world = _resume(world, 'RF_002_OakGrove');
      final fight = _fightOut(world.beginEncounter());
      expect(fight.encounter.id, 'e_oak_grove_scarecrow');
      expect(fight.outcome, EncounterOutcome.victory);
      expect(world.concludeEncounter(fight), contains('scarecrow_burned'));
      expect(fight.coinEarned, greaterThan(0));

      world = _resume(world, 'RF_001_Farm');
      _talk(world, 'marta', ['ask', 'scarecrow_done']);
      _expectFinished(world, 'side_scarecrow_walks');
    });

    test('with Elara home, she is the one who points it out', () {
      final world =
          _world('RF_001_Farm', flags: {'boss_defeated_hollow_avatar'});
      _talk(world, 'marta', ['elara_scarecrow']);
      expect(_isActive(world, 'side_scarecrow_walks'), isTrue);
    });
  });

  group('Stones on the Rope', () {
    test('from the reeds, to the Guard Hall, to the temple', () {
      var world = _world('MR_002_ReedBeds', flags: {
        'heard_of_the_mere_road',
        'cleared_mere_road',
        'cleared_reed_beds',
      });
      world.take('stone');
      expect(_isActive(world, 'side_stones_on_the_rope'), isTrue);

      world = _resume(world, 'MH_002_GuardHall');
      _talk(world, 'thorne', ['ask_quest', 'show_stone']);

      world = _resume(world, 'MH_004_Temple');
      _talk(world, 'aldus', ['ask_burials', 'bless_drowned']);
      _expectFinished(world, 'side_stones_on_the_rope');
    });

    test('Aldus will not bless what nobody has named', () {
      final world = _world('MH_004_Temple',
          flags: {'item_acquired_drowning_stone', 'met_aldus'});
      final talk = world.beginConversation('aldus')!.talk..choose('ask');
      expect(talk.availableOptions().map((o) => o.id),
          isNot(contains('bless_drowned')));
    });
  });

  group('The Lost Shift', () {
    test('Brask asks, the deep workings answer, the board is wiped', () {
      var world = _world('BM_001_Entrance');
      _talk(world, 'brask', ['ask_board']);
      expect(_isActive(world, 'side_lost_shift'), isTrue);

      world.move('down');
      expect(world.availableEncounters().map((e) => e.id),
          contains('e_lost_shift'));

      // Two level 12 miners are not a fight for one level 6 magus; the
      // quest's flow is what is under test.
      world =
          _resume(world, 'BM_002_DeepMine', flags: {'freed_the_lost_shift'});
      world.take('tallies');

      world = _resume(world, 'BM_001_Entrance');
      _talk(world, 'brask', ['give']);
      _expectFinished(world, 'side_lost_shift');
    });

    test('nothing is working the deep face until somebody asks', () {
      final world = _world('BM_002_DeepMine');
      expect(world.availableEncounters().map((e) => e.id),
          isNot(contains('e_lost_shift')));
    });
  });

  group('The Families in the Gatehouse', () {
    test('starts at the gates, and the door waits on the watch', () {
      var world = _world('VC_001_Plaza');
      world.move('west');
      expect(_isActive(world, 'side_families_in_the_gatehouse'), isTrue);
      expect(world.availableEncounters().map((e) => e.id),
          contains('e_thornhaven_watch'));
      expect(() => world.destroy('door'), throwsA(isA<InvalidMoveException>()));

      world =
          _resume(world, 'TH_001_Gates', flags: {'thornhaven_watch_broken'});
      final broken = world.destroy('door');
      expect(broken.flagsSet, contains('freed_the_families'));
      _expectFinished(world, 'side_families_in_the_gatehouse');
    });

    test('the watch is not in the way of the stair up', () {
      final watch = _campaign.bestiary.encounterById('e_thornhaven_watch')!;
      expect(watch.ambush, isFalse);
    });
  });

  group("The Readers' Names", () {
    test('the day-book, from the stair to Hale', () {
      var world = _world('UA_002_OssuaryStair', flags: {
        'met_hale',
        'heard_of_the_under_archive',
        'cleared_sealed_stacks',
        'cleared_ossuary_stair',
      });
      world.take('day-book');
      expect(_isActive(world, 'side_readers_names'), isTrue);

      world = _resume(world, 'VC_003_GrandLibrary');
      _talk(world, 'hale', ['desk', 'give_daybook']);
      _expectFinished(world, 'side_readers_names');
    });

    test('Hale will take it whatever has passed between you', () {
      for (final state in [
        {'deception_revealed_under_archive'},
        {'hale_confessed'},
        {'boss_defeated_malachai_vex'},
      ]) {
        final world = _world('VC_003_GrandLibrary', flags: {
          'met_hale',
          'item_acquired_readers_daybook',
          ...state,
        });
        expect(_talk(world, 'hale', ['give_daybook']),
            contains('hale_given_the_daybook'),
            reason: '$state');
      }
    });
  });

  group('A Price on Your Heads', () {
    test('starts the first time something finds the party', () {
      final world = WorldSession(
        campaign: _campaign,
        actors: [SessionActor(id: 'korash', character: loadKorash())],
        roller: DiceRoller(3),
        roomId: 'MH_001_Square',
        inventory: PartyInventory(gear: _campaign.gear, coin: 190000),
      );
      MoveResult? found;
      for (var i = 0; i < 2000 && found == null; i++) {
        final step =
            world.move(world.roomId == 'MH_001_Square' ? 'west' : 'east');
        if (step.hunt != null) found = step;
      }
      expect(found, isNotNull);
      expect(_isActive(world, 'side_price_on_your_heads'), isTrue);
    });

    test('three hunts survived and a word with Sal settle it', () {
      var world = _world('MH_001_Square',
          flags: {'hunted_first', 'hunt_survived_1', 'hunt_survived_2'});
      expect(_isActive(world, 'side_price_on_your_heads'), isTrue);

      // Sal is wherever her road has taken her; go to her.
      var guard = 0;
      while (world.whereIs('npc_010_sal') == null && guard++ < 200) {
        world.move(world.roomId == 'MH_001_Square' ? 'west' : 'east');
      }
      world = _resume(world, world.whereIs('npc_010_sal')!,
          flags: {'hunt_survived_3'});
      _talk(world, 'sal', ['greet', 'ask_bounty']);
      _expectFinished(world, 'side_price_on_your_heads');
    });

    test('Sal has nothing to say about it to a party nobody is hunting', () {
      final world = _world('MH_001_Square');
      final where = world.whereIs('npc_010_sal') ??
          _campaign.npcs.byId('npc_010_sal')!.route!.stops.first;
      final there = _resume(world, where);
      if (there.whereIs('npc_010_sal') == null) return;
      final talk = there.beginConversation('sal')!.talk..choose('greet');
      expect(talk.availableOptions().map((o) => o.id),
          isNot(contains('ask_bounty')));
    });
  });
}
