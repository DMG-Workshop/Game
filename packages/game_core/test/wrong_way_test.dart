import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;

WorldSession _world({
  String room = 'MH_001_Square',
  Set<String>? flags,
  String? cameFrom,
  int seed = 5,
  bool armed = false,
}) {
  final world = WorldSession(
    campaign: _campaign,
    actors: [SessionActor(id: 'korash', character: loadKorash())],
    roller: DiceRoller(seed),
    roomId: room,
    flags: flags,
    cameFrom: cameFrom,
  );
  if (armed) {
    // Late-game kit, so a level 6 character walking a level 3 road is a test
    // of the road rather than of the dice.
    world.inventory
      ..add('w_019_the_last_nail')
      ..add('a_011_monarchs_vestment');
    world
      ..equip('last nail')
      ..equip('monarch');
  }
  return world;
}

/// Fights whatever has sprung, to the end, and records it.
List<String> _fightItOut(WorldSession world) {
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
  expect(fight.outcome, EncounterOutcome.victory,
      reason: '${fight.encounter.name} was lost');
  return world.concludeEncounter(fight);
}

/// Every flag anything in the campaign could ever set.
Set<String> _producible(Campaign c) => {
      for (final arc in c.arcs.all) ...arc.worldStateChanges,
      ...c.bestiary.victoryFlags,
      for (final e in c.bestiary.encounters)
        for (var wave = 0; wave <= e.rearmOn.length; wave++) e.wonFlag(wave),
      ...c.items.producibleFlags,
      ...c.conversations.producibleFlags,
      for (final npc in c.npcs.all) ...[
        'dialogue_complete_${npc.slug}',
        for (final topic in npc.keywords.keys) 'keyword_${topic}_unlocked',
      ],
      for (final id in c.locations.rooms.keys) ...[
        'enter_$id',
        'enter_${id.split('_').take(2).join('_')}',
      ],
      for (final item in c.gear.all) 'loot_${item.id}',
    };

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  group('conversations', () {
    test('everybody in the campaign has something to say', () {
      for (final npc in _campaign.npcs.all) {
        expect(_campaign.conversations.forNpc(npc.id), isNotNull,
            reason: npc.name);
      }
    });

    test('every conversation opens for a party that has done nothing', () {
      for (final c in _campaign.conversations.all) {
        expect(c.openingFor(const {}), isNotNull, reason: c.npcId);
      }
    });

    test('every roll is one a real character can make', () {
      final stats = DerivedStats(loadKorash());
      for (final c in _campaign.conversations.all) {
        expect(const AdventureLoader().unresolvableStats(c.adventure, stats),
            isEmpty,
            reason: c.npcId);
      }
    });

    test('every roll is something the character says', () {
      for (final c in _campaign.conversations.all) {
        for (final scene in c.adventure.scenes.values) {
          for (final option in scene.options) {
            if (option.check == null) continue;
            expect(option.say, isNotNull,
                reason: '${c.npcId}/${scene.id}/${option.id}');
          }
        }
      }
    });

    test('no conversation can trap the party', () {
      // From every line, some sequence of choices reaches a goodbye. A
      // conversation with no way out would hold the player at the prompt.
      for (final c in _campaign.conversations.all) {
        final scenes = c.adventure.scenes;
        final canEnd = {
          for (final s in scenes.values)
            if (s.isEnding) s.id,
        };
        var grew = true;
        while (grew) {
          grew = false;
          for (final s in scenes.values) {
            if (canEnd.contains(s.id)) continue;
            final next = [
              for (final o in s.options) ...[
                o.automatic?.goTo,
                for (final out in o.outcomes.values) out.goTo,
              ],
            ];
            if (next.any(canEnd.contains)) grew = canEnd.add(s.id);
          }
        }
        expect(scenes.keys.toSet().difference(canEnd), isEmpty,
            reason: c.npcId);
      }
    });

    test('every gate in the campaign can open', () {
      // A gate waiting on a flag nothing sets is a door that is a wall, and a
      // line that is never said. Typos in flag names look exactly like this.
      final referenced = <String>{
        for (final c in _campaign.conversations.all) ...[
          for (final e in c.entries) ...[
            ...e.requiredFlags,
            ...e.forbiddenFlags,
          ],
          for (final s in c.adventure.scenes.values)
            for (final o in s.options) ...[
              ...o.gate.requiredFlags,
              ...o.gate.forbiddenFlags,
            ],
        ],
        for (final room in _campaign.locations.rooms.values)
          for (final exit in room.exits.values) ...exit.requiredFlags,
        for (final e in _campaign.bestiary.encounters) ...[
          ...e.requiredFlags,
          ...e.rearmOn,
        ],
        for (final i in _campaign.items.all) ...[
          ...i.requiredFlags,
          ...i.hiddenUntilFlags,
        ],
        // A shelf that never fills, a discount never earned, and a reward
        // never paid are the same bug as a door that never opens.
        for (final shop in _campaign.economy.shops) ...[
          for (final line in shop.stock) ...line.requiredFlags,
          for (final m in shop.modifiers) m.flag,
        ],
        ..._campaign.economy.rewardFlags,
        // What somebody says walking in is a gate on the story too.
        for (final npc in _campaign.npcs.all)
          for (final bark in npc.barks) ...[
            ...bark.requiredFlags,
            ...bark.forbiddenFlags,
          ],
      };
      // Being hunted sets flags of its own, counted rather than listed.
      expect(
          referenced
              .difference(_producible(_campaign))
              .where((f) => !_campaign.hunts.producesFlag(f)),
          isEmpty);
    });

    test("the court's audience can complete its objective", () {
      expect(_campaign.conversations.producibleFlags,
          contains('dialogue_complete_queen_liora'));
    });

    test("Thorne's conversation starts the first arc", () {
      final world = _world(room: 'MH_002_GuardHall');
      final talk = world.beginConversation('thorne')!.talk;
      final event = talk.choose('ask_quest');
      expect(event.said, 'What kind of dark times?');
      world.concludeConversation(talk);
      expect(world.flags, contains('keyword_quest_unlocked'));
    });
  });

  group('the Mere Road', () {
    test('is shut until somebody gives the party a reason to take it', () {
      final world = _world(room: 'MH_004_Temple');
      expect(
        () => world.move('south'),
        throwsA(isA<InvalidMoveException>()
            .having((e) => e.message, 'message', contains('Mere Road'))),
      );
    });

    test("Wendel's story opens it, whether or not it is believed", () {
      final story = _campaign.conversations
          .forNpc('npc_007_wendel')!
          .adventure
          .sceneById('wendel_story')!;
      for (final option in story.options) {
        final outcomes = [
          if (option.automatic case final automatic?) automatic,
          ...option.outcomes.values,
        ];
        for (final outcome in outcomes) {
          expect(outcome.setFlags, contains('heard_of_the_mere_road'),
              reason: option.id);
        }
      }
    });

    test('believing him sends the party south', () {
      final world = _world(room: 'MH_003_Tavern');
      final talk = world.beginConversation('wendel')!.talk
        ..choose('ask_elara')
        ..choose('believe');
      world.concludeConversation(talk);
      expect(world.flags, containsAll(['believed_wendel', 'met_wendel']));

      world
        ..move('west')
        ..move('south');
      expect(world.move('south').to, 'MR_001_MereRoad');
    });

    test('down it, found out, and all the way back out again', () {
      // The whole wrong turn: three ambushes going in, the decoy at the end,
      // and the same road full again on the way home.
      final world = _world(
        room: 'MH_004_Temple',
        flags: {'heard_of_the_mere_road'},
        armed: true,
      );

      expect(world.move('south').ambush?.id, 'e_mere_road_cutthroats');
      expect(() => world.move('south'), throwsA(isA<InvalidMoveException>()));
      _fightItOut(world);

      expect(world.move('south').ambush?.id, 'e_reed_beds_drowned');
      _fightItOut(world);

      expect(world.move('south').ambush?.id, 'e_drowned_mill');
      expect(() => world.take('bundle'), throwsA(isA<InvalidMoveException>()),
          reason: 'not while they are still standing over it');
      _fightItOut(world);

      final reveal = world.take('bundle');
      expect(reveal.flagsSet,
          ['deception_revealed_mere_road', 'wendel_lie_uncovered']);
      expect(reveal.said, contains('a bell begins to ring'));

      // Turn round. The reed beds are full again, and this time home is the
      // way on.
      final back = world.move('north');
      expect(back.ambush?.id, 'e_reed_beds_drowned');
      expect(world.describeEncounter(back.ambush!),
          contains('the same something that rang the bell'));
      expect(() => world.move('north'), throwsA(isA<InvalidMoveException>()));
      expect(_fightItOut(world), contains('won_e_reed_beds_drowned_wave_1'));

      final road = world.move('north');
      expect(road.ambush?.id, 'e_mere_road_cutthroats');
      expect(world.describeEncounter(road.ambush!),
          contains('They knew you would'));
      expect(_fightItOut(world), contains('won_e_mere_road_cutthroats_wave_1'));

      expect(world.move('north').to, 'MH_004_Temple');
      // Nothing is waiting on a third trip.
      expect(world.move('south').ambush, isNull);
    });

    test('the mill does not come back; only the road home does', () {
      final mill = _campaign.bestiary.encounterById('e_drowned_mill')!;
      expect(mill.rearmOn, isEmpty);
      expect(
          mill.isAvailable(
              {'cleared_drowned_mill', 'deception_revealed_mere_road'}),
          isFalse);
    });
  });

  group('Wendel afterwards', () {
    test('is waiting for the party with the cord in their hand', () {
      final world = _world(
        room: 'MH_003_Tavern',
        flags: {'met_wendel', 'deception_revealed_mere_road'},
      );
      expect(world.beginConversation('wendel')!.talk.currentScene.id,
          'wendel_caught');
    });

    test('can be confronted without going, if the lie was caught', () {
      final world = _world(
        room: 'MH_003_Tavern',
        flags: {'met_wendel', 'heard_of_the_mere_road', 'caught_wendel_lying'},
      );
      final talk = world.beginConversation('wendel')!.talk..choose('bar');
      expect(talk.availableOptions().map((o) => o.id), contains('confront'));
    });

    test("the Brother's doubt is a second opinion worth having", () {
      final world = _world(
        room: 'MH_003_Tavern',
        flags: {
          'met_wendel',
          'heard_of_the_mere_road',
          'believed_wendel',
          'aldus_doubted_the_mere'
        },
      );
      final talk = world.beginConversation('wendel')!.talk
        ..choose('bar')
        ..choose('doubt');
      expect(talk.flags, contains('caught_wendel_lying'));
    });

    test('a confession gets him arrested, and the tavern shut', () {
      final flags = {
        'met_thorne',
        'met_wendel',
        'deception_revealed_mere_road',
        'wendel_confessed',
      };
      final hall = _world(room: 'MH_002_GuardHall', flags: flags);
      final talk = hall.beginConversation('thorne')!.talk;
      expect(talk.currentScene.id, 'thorne_mere_road');
      talk.choose('name_confessed');
      hall.concludeConversation(talk);
      expect(hall.flags, contains('wendel_arrested'));

      final tavern = _world(room: 'MH_003_Tavern', flags: hall.flags);
      final after = tavern.beginConversation('wendel')!.talk;
      expect(after.currentScene.id, 'wendel_arrested');
      expect(after.isFinished, isTrue);
    });
  });

  group('the Under-Archive', () {
    test('is shut until the archivist opens it', () {
      final world = _world(room: 'VC_003_GrandLibrary');
      expect(() => world.move('down'), throwsA(isA<InvalidMoveException>()));

      final talk = world.beginConversation('hale')!.talk
        ..choose('ask_seals')
        ..choose('take_key');
      world.concludeConversation(talk);
      expect(world.move('down').ambush?.id, 'e_sealed_stacks_warden');
    });

    test('the Queen can be the one who sends the party to him', () {
      final world = _world(
        room: 'VC_003_GrandLibrary',
        flags: {'liora_sent_you_to_hale'},
      );
      final talk = world.beginConversation('hale')!.talk;
      expect(talk.availableOptions().map((o) => o.id), contains('queen_sent'));
    });

    test('the letter brings the stair back to life behind the party', () {
      // Fought down by a party of the right level; what is under test is what
      // happens after the letter, not a level 6 character's chances.
      final world = _world(
        room: 'UA_003_FalseSeal',
        cameFrom: 'UA_002_OssuaryStair',
        flags: {
          'heard_of_the_under_archive',
          'cleared_sealed_stacks',
          'cleared_ossuary_stair',
          'cleared_false_seal',
        },
      );
      final reveal = world.take('letter');
      expect(reveal.flagsSet,
          ['deception_revealed_under_archive', 'hale_lie_uncovered']);
      expect(reveal.said, contains('Hale has done well'));

      final back = world.move('up');
      expect(back.ambush?.id, 'e_ossuary_readers');
      expect(world.describeEncounter(back.ambush!),
          contains('not empty any more'));
      expect(() => world.move('up'), throwsA(isA<InvalidMoveException>()));

      final warden =
          _campaign.bestiary.encounterById('e_sealed_stacks_warden')!;
      expect(warden.isAvailable(world.flags), isTrue);
    });

    test('Hale and the Queen both know when the party has read it', () {
      final flags = {
        'met_hale',
        'met_liora',
        'deception_revealed_under_archive',
      };
      expect(
        _world(room: 'VC_003_GrandLibrary', flags: flags)
            .beginConversation('hale')!
            .talk
            .currentScene
            .id,
        'hale_caught',
      );
      expect(
        _world(room: 'VC_002_ThroneRoom', flags: flags)
            .beginConversation('liora')!
            .talk
            .currentScene
            .id,
        'liora_exposed',
      );
    });
  });

  group('stories that move on', () {
    test('people remember having met you', () {
      final world = _world(room: 'RF_001_Farm');
      final talk = world.beginConversation('marta')!.talk..choose('blunt');
      world.concludeConversation(talk);
      expect(world.beginConversation('marta')!.talk.currentScene.id,
          'marta_again');
    });

    test('bringing the doll back changes what Marta says', () {
      final world = _world(
        room: 'RF_001_Farm',
        flags: {'met_marta', 'item_acquired_elaras_doll'},
      );
      expect(
          world.beginConversation('marta')!.talk.currentScene.id, 'marta_doll');
    });

    test('once the Avatar is dead, Millhaven says so', () {
      final flags = {'boss_defeated_hollow_avatar'};
      for (final (room, npc, scene) in [
        ('MH_002_GuardHall', 'thorne', 'thorne_after'),
        ('RF_001_Farm', 'marta', 'marta_home'),
        ('MH_004_Temple', 'aldus', 'aldus_after'),
        ('MH_005_Forge', 'harrow', 'harrow_after'),
      ]) {
        expect(
          _world(room: room, flags: flags)
              .beginConversation(npc)!
              .talk
              .currentScene
              .id,
          scene,
        );
      }
    });

    test('the reward is what was haggled for', () {
      final world = _world(
        room: 'MH_002_GuardHall',
        flags: {'boss_defeated_hollow_avatar', 'thorne_reward_raised'},
      );
      final ids = world
          .beginConversation('thorne')!
          .talk
          .availableOptions()
          .map((o) => o.id);
      expect(ids, contains('paid_raised'));
      expect(ids, isNot(contains('paid_base')));
      expect(ids, isNot(contains('paid_double')));
    });
  });
}
