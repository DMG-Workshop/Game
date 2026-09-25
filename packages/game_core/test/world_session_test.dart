import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;

ImportedCharacter _korash() => const PathbuilderImporter()
    .importJson(
        File('../pf2e_core/test/fixtures/korash.json').readAsStringSync())
    .character;

WorldSession newWorld({
  int seed = 1,
  String room = 'MH_001_Square',
  Set<String>? flags,
  int hour = 8,
  Campaign? campaign,
}) =>
    WorldSession(
      campaign: campaign ?? loadShatteredSeals(),
      actors: [SessionActor(id: 'korash', character: _korash())],
      roller: DiceRoller(seed),
      roomId: room,
      flags: flags,
      hour: hour,
    );

void main() {
  group('starting out', () {
    test('needs at least one actor', () {
      expect(
        () => WorldSession(
          campaign: loadShatteredSeals(),
          actors: const [],
          roller: DiceRoller(1),
        ),
        throwsArgumentError,
      );
    });

    test('refuses a room that does not exist', () {
      expect(() => newWorld(room: 'nowhere'), throwsArgumentError);
    });

    test('copies the flags it is given rather than holding onto them', () {
      // Passing one session's flags to another is the natural way to carry
      // progress forward, and session.flags is an unmodifiable view. Keeping
      // the caller's set meant the next room entered threw, and would also
      // have let two sessions quietly write to each other's state.
      final first = newWorld();
      final second = newWorld(room: 'MH_002_GuardHall', flags: first.flags);
      expect(second.flags, contains('enter_MH_002_GuardHall'));
      expect(first.flags, isNot(contains('enter_MH_002_GuardHall')));
    });

    test('marks the starting room as entered, in both id forms', () {
      // The arcs abbreviate — enter_MH_001 means MH_001_Square — so both are
      // recorded and neither convention has to win.
      final world = newWorld();
      expect(world.flags, contains('enter_MH_001_Square'));
      expect(world.flags, contains('enter_MH_001'));
    });
  });

  group('looking', () {
    test('gathers room, town, region and who is present', () {
      final view = newWorld(room: 'MH_002_GuardHall').look();
      expect(view.room.title, 'The Guard Hall');
      expect(view.town!.name, 'Millhaven');
      expect(view.region!.id, 'r_001_millhaven_valley');
      expect(view.npcs.single.name, 'Captain Thorne Ironhelm');
    });

    test('separates open exits from barred ones', () {
      final view = newWorld().look();
      expect(view.openDirections, ['east', 'north', 'south', 'west']);
      expect(view.barredDirections.map((b) => b.direction), ['northeast']);
      expect(view.barredDirections.single.reason, contains('tollgate'));
    });

    test('a barred exit opens once its flag is set', () {
      final view = newWorld(flags: {'Unlock_Travel_to_Valorheim'}).look();
      expect(view.openDirections, contains('northeast'));
      expect(view.barredDirections, isEmpty);
    });
  });

  group('walking', () {
    test('moves and records the new room', () {
      final world = newWorld();
      final result = world.move('north');
      expect(result.from, 'MH_001_Square');
      expect(result.to, 'MH_002_GuardHall');
      expect(world.roomId, 'MH_002_GuardHall');
      expect(result.flagsSet, contains('enter_MH_002_GuardHall'));
    });

    test('accepts MUD shorthand', () {
      final world = newWorld();
      expect(world.move('n').to, 'MH_002_GuardHall');
      expect(world.move('s').to, 'MH_001_Square');
    });

    test('refuses a direction that is not there', () {
      final world = newWorld(room: 'MH_002_GuardHall');
      expect(() => world.move('north'), throwsA(isA<InvalidMoveException>()));
    });

    test('refuses a barred exit, saying why', () {
      final world = newWorld();
      expect(
        () => world.move('northeast'),
        throwsA(isA<InvalidMoveException>()
            .having((e) => e.message, 'message', contains('tollgate'))),
      );
      expect(world.roomId, 'MH_001_Square', reason: 'should not have moved');
    });

    test('takes the barred exit once the arc has opened it', () {
      final world = newWorld(flags: {'Unlock_Travel_to_Valorheim'});
      final result = world.move('northeast');
      expect(result.to, 'VC_001_Plaza');
      expect(result.changedRegion, isTrue);
    });

    test('does not report a region change within one region', () {
      final world = newWorld();
      expect(world.move('west').changedRegion, isFalse);
    });

    test('the whole Millhaven loop is connected', () {
      // Square -> Forge -> Whisperwood -> Ravencrest and back again.
      final world = newWorld();
      for (final step in ['w', 'w', 'n', 'e', 'w', 's', 'e', 'e']) {
        world.move(step);
      }
      expect(world.roomId, 'MH_001_Square');
    });

    test('re-entering a room sets no new flags', () {
      final world = newWorld();
      world.move('north');
      world.move('south');
      expect(world.move('north').flagsSet, isEmpty);
    });
  });

  group('talking', () {
    WorldSession atThorne({int seed = 1}) =>
        newWorld(seed: seed, room: 'MH_002_GuardHall');

    test('greets without a topic', () {
      final result = atThorne().talk('thorne');
      expect(result.isGreeting, isTrue);
      expect(result.said, contains('Well met'));
      expect(result.flagsSet, isEmpty);
    });

    test('answers a topic and unlocks its keyword flag', () {
      // The campaign's first objective waits on keyword_quest_unlocked, which
      // is where this convention is read from rather than invented.
      final world = atThorne();
      final result = world.talk('thorne', topic: 'quest');
      expect(result.said, contains('Caravans vanish'));
      expect(result.flagsSet, contains('keyword_quest_unlocked'));
      expect(world.flags, contains('keyword_quest_unlocked'));
    });

    test('advances the arc it was gating', () {
      final world = atThorne();
      final arc = world.campaign.arcs.byId('tier_1_local_threat')!;
      expect(arc.progress(world.flags), (done: 0, total: 3));
      world.talk('thorne', topic: 'quest');
      expect(arc.progress(world.flags), (done: 1, total: 3));
    });

    test('does not re-award a flag for the same topic twice', () {
      final world = atThorne();
      world.talk('thorne', topic: 'quest');
      expect(world.talk('thorne', topic: 'quest').flagsSet, isEmpty);
    });

    test('matches a topic mentioned in a sentence', () {
      final result = atThorne().talk('thorne', topic: 'tell me about elara');
      expect(result.topic, 'elara');
      expect(result.said, contains('Fifty gold'));
    });

    test('says so when they have nothing on a topic', () {
      final result = atThorne().talk('thorne', topic: 'the weather');
      expect(result.said, contains('nothing to say'));
      expect(result.flagsSet, isEmpty);
    });

    test('marks the conversation complete when every topic is raised', () {
      final world = atThorne();
      for (final topic in ['quest', 'elara', 'creatures']) {
        world.talk('thorne', topic: topic);
      }
      expect(world.flags, contains('dialogue_complete_thorne'));
      expect(world.unraisedTopicsFor(world.look().npcs.single), isEmpty);
    });

    test('tracks which topics are still unraised', () {
      final world = atThorne();
      final thorne = world.look().npcs.single;
      expect(world.unraisedTopicsFor(thorne), ['creatures', 'elara', 'quest']);
      world.talk('thorne', topic: 'elara');
      expect(world.unraisedTopicsFor(thorne), ['creatures', 'quest']);
    });

    test('refuses someone who is not here', () {
      expect(() => newWorld().talk('thorne'),
          throwsA(isA<InvalidMoveException>()));
    });
  });

  group('objects', () {
    test('sees what is lying in the room', () {
      final world = newWorld(room: 'RF_002_OakGrove');
      expect(world.look().items.single.name, "Elara's Doll");
    });

    test('taking sets the flag its quest waits on', () {
      final world = newWorld(room: 'RF_002_OakGrove');
      final result = world.take('doll');
      expect(result.said, contains('dry'));
      expect(result.flagsSet, ['item_acquired_elaras_doll']);
      expect(world.flags, contains('item_acquired_elaras_doll'));
    });

    test('finds an object by any word of its name', () {
      final world = newWorld(room: 'RF_002_OakGrove');
      expect(world.take('elara').item.id, 'i_elaras_doll');
    });

    test('a taken object is gone from the room', () {
      final world = newWorld(room: 'RF_002_OakGrove')..take('doll');
      expect(world.look().items, isEmpty);
      expect(() => world.take('doll'), throwsA(isA<InvalidMoveException>()));
    });

    test('destroying sets its own flag', () {
      final world = newWorld(room: 'BM_002_DeepMine');
      final result = world.destroy('geode');
      expect(result.said, contains('grey'));
      expect(result.flagsSet, ['item_destroyed_bloodstone_geode']);
    });

    test('refuses to take something that is not takeable', () {
      // The geode is the size of a cart; it can be broken, not pocketed.
      final world = newWorld(room: 'BM_002_DeepMine');
      expect(
        () => world.take('geode'),
        throwsA(isA<InvalidMoveException>().having((e) => e.message, 'message',
            contains('not something you can take'))),
      );
    });

    test('refuses to destroy something that is not destroyable', () {
      final world = newWorld(room: 'RF_002_OakGrove');
      expect(() => world.destroy('doll'), throwsA(isA<InvalidMoveException>()));
    });

    test('refuses something that is not here', () {
      expect(
          () => newWorld().take('doll'), throwsA(isA<InvalidMoveException>()));
    });
  });

  group('fights', () {
    test('the Avatar is not waiting until the doll is found', () {
      expect(
          newWorld(room: 'WW_003_HollowGrove').availableEncounters(), isEmpty);
      expect(
          newWorld(
            room: 'WW_003_HollowGrove',
            flags: {'item_acquired_elaras_doll'},
          ).availableEncounters().single.id,
          'e_hollow_grove');
    });

    test('beginning a fight refuses when there is nothing to fight', () {
      expect(() => newWorld().beginEncounter(),
          throwsA(isA<InvalidMoveException>()));
    });

    test('a won fight sets the flag its arc waits on', () {
      final world = newWorld(
        room: 'WW_002_Deep',
        flags: {'item_acquired_elaras_doll'},
      );
      final f = world.beginEncounter();
      // Resolve it by fiat rather than rolling for twenty rounds; what is
      // under test is that the world records the win, not the dice.
      while (!f.isOver) {
        if (f.isPartyTurn) {
          final targets = f.targetsInReach();
          if (targets.isEmpty) {
            f.stride();
          } else {
            f.strike(targets.first.id);
          }
          if (f.actionsLeft == 0 && !f.isOver) f.endTurn();
        } else {
          f.endTurn();
        }
      }
      final set = world.concludeEncounter(f);
      if (f.outcome == EncounterOutcome.victory) {
        expect(set, contains('cleared_whisperwood_thralls'));
      } else {
        expect(set, isEmpty, reason: 'only a win earns the flag');
      }
    });

    test('what the thralls were carrying is recorded as the party takes it',
        () {
      // Drops are a roll, so this hunts for a seed where something turned up
      // rather than pretending a particular seed is meaningful. Finding none
      // at all would mean the loot table never fires.
      final campaign = loadShatteredSeals();
      for (var seed = 1; seed <= 60; seed++) {
        final world = newWorld(
          seed: seed,
          room: 'WW_002_Deep',
          campaign: campaign,
        );
        final f = world.beginEncounter();
        var guard = 0;
        while (!f.isOver && guard++ < 200) {
          if (f.isPartyTurn) {
            final targets = f.targetsInReach();
            if (targets.isEmpty) {
              f.stride();
            } else {
              f.strike(targets.first.id);
            }
            if (f.actionsLeft == 0 && !f.isOver) f.endTurn();
          } else {
            f.endTurn();
          }
        }
        if (f.outcome != EncounterOutcome.victory || f.loot.isEmpty) continue;

        final set = world.concludeEncounter(f);
        expect(set, containsAll(f.lootFlags));
        expect(world.recoveredGear.map((i) => i.id),
            containsAll(f.loot.map((i) => i.id)));
        // It survives a save, because it is a flag like any other.
        expect(world.snapshot()['flags'], containsAll(f.lootFlags));
        return;
      }
      fail('sixty fights with the thralls and nothing ever dropped');
    });

    test('nothing is recovered before anything has been killed', () {
      expect(newWorld().recoveredGear, isEmpty);
    });
  });

  group('equipment', () {
    late Campaign campaign;
    setUpAll(() => campaign = loadShatteredSeals());

    WorldSession withPack(List<String> itemIds) {
      final world = newWorld(campaign: campaign);
      for (final id in itemIds) {
        world.inventory.add(id);
      }
      return world;
    }

    test('a session started mid-campaign is carrying what it found', () {
      // Flags describe everything else about where a party has got to, and
      // the pack is no exception.
      final world = newWorld(
        campaign: campaign,
        flags: {'loot_w_024_crown_spike', 'loot_of_nothing'},
      );
      expect(world.inventory.carried.single.id, 'w_024_crown_spike');
    });

    test('what the party carries starts and stays theirs', () {
      final world = withPack(['w_006_shadowbane_dagger']);
      expect(world.inventory.carried.single.name, 'Shadowbane Dagger');
      expect(world.recoveredGear, world.inventory.carried);
    });

    test('wearing better armour is worth exactly what the rules say', () {
      final world = withPack(['a_011_monarchs_vestment']);
      expect(world.statsFor('korash').armorClass, 25);

      final result = world.equip('monarch');
      expect(result.slot, EquipSlot.armor);
      expect(result.actor.id, 'korash');
      // Full plate +6 and a +2 rune, against the +1 full plate he came in.
      expect(world.statsFor('korash').armorClass, 26);
    });

    test('a smaller weapon keeps the attack and costs the damage', () {
      // The dagger is +1 striking like his scythe, so it swings just as
      // often; it is the die that is smaller, and that is the trade.
      final world = withPack(['w_006_shadowbane_dagger']);
      expect(world.statsFor('korash').damage.toString(), '2d10+4');

      world.equip('shadowbane');
      final after = world.statsFor('korash');
      expect(after.attackBonus, 15);
      expect(after.damage.toString(), '2d4+4');
    });

    test('a fight is fought with what is actually held', () {
      final world = newWorld(
        campaign: campaign,
        room: 'WW_002_Deep',
      );
      world.inventory.add('w_019_the_last_nail');
      world.equip('last nail');

      final fight = world.beginEncounter();
      final korash = fight.party.single;
      // Major striking, 1d6 base: four dice and Strength, at +3 potency.
      expect(korash.damage.toString(), '4d6+4');
      expect(korash.attackBonus, 17);
    });

    test('taking it off puts the imported kit back', () {
      final world = withPack(['w_006_shadowbane_dagger']);
      world.equip('shadowbane');
      final removed = world.unequip('weapon');
      expect(removed.removed?.id, 'w_006_shadowbane_dagger');
      expect(world.statsFor('korash').damage.toString(), '2d10+4');
      expect(world.inventory.isCarrying('w_006_shadowbane_dagger'), isTrue);
    });

    test('refuses to equip what is not in the pack', () {
      expect(() => newWorld(campaign: campaign).equip('crown spike'),
          throwsA(isA<InvalidMoveException>()));
    });

    test('refuses a slot that does not exist', () {
      expect(() => newWorld(campaign: campaign).unequip('hat'),
          throwsA(isA<InvalidMoveException>()));
    });

    test('refuses somebody who is not in the party', () {
      expect(() => newWorld(campaign: campaign).statsFor('nobody'),
          throwsA(isA<InvalidMoveException>()));
      expect(newWorld(campaign: campaign).knowsActor('korash'), isTrue);
      expect(newWorld(campaign: campaign).knowsActor('liora'), isFalse);
    });

    test('a save remembers the pack and what is worn', () {
      final world = withPack([
        'w_006_shadowbane_dagger',
        'a_011_monarchs_vestment',
      ]);
      world
        ..equip('shadowbane')
        ..equip('monarch');

      final restored = WorldSession.restore(
        campaign: campaign,
        actors: [SessionActor(id: 'korash', character: _korash())],
        snapshot:
            jsonDecode(jsonEncode(world.snapshot())) as Map<String, Object?>,
      );
      expect(restored.inventory.carried.map((i) => i.id),
          world.inventory.carried.map((i) => i.id));
      expect(restored.statsFor('korash').armorClass, 26);
      expect(restored.statsFor('korash').damage.toString(), '2d4+4');
    });

    test('a save from before the pack existed keeps its loot', () {
      // Loot was recorded as flags first. Those saves still load, and the
      // gear comes back into the pack rather than vanishing.
      final restored = WorldSession.restore(
        campaign: campaign,
        actors: [SessionActor(id: 'korash', character: _korash())],
        snapshot: {
          'campaignId': campaign.id,
          'roomId': 'MH_001_Square',
          'hour': 8,
          'flags': ['loot_w_021_thralls_nail'],
          'rollerState': 1,
        },
      );
      expect(restored.inventory.carried.single.id, 'w_021_thralls_nail');
    });

    test('the whole tier one chain is reachable in order', () {
      // Thorne names the quest, the grove yields the doll, and the doll opens
      // the Avatar. Each step is a flag the next one waits on.
      final world = newWorld(room: 'MH_002_GuardHall');
      world.talk('thorne', topic: 'quest');
      expect(world.flags, contains('keyword_quest_unlocked'));

      final grove = newWorld(room: 'RF_002_OakGrove', flags: world.flags)
        ..take('doll');
      expect(grove.flags, contains('item_acquired_elaras_doll'));

      final hollow = newWorld(room: 'WW_003_HollowGrove', flags: grove.flags);
      expect(hollow.availableEncounters(), isNotEmpty);

      // With the Avatar down, tier one is complete and the road opens.
      final finished = newWorld(
        room: 'MH_001_Square',
        flags: {...hollow.flags, 'boss_defeated_hollow_avatar'},
      );
      expect(finished.applyPendingWorldState(),
          contains('Unlock_Travel_to_Valorheim'));
      expect(finished.look().openDirections, contains('northeast'));
    });
  });

  group('time', () {
    test('advances and wraps at the end of the day', () {
      final world = newWorld(hour: 22);
      world.advanceTime(4);
      expect(world.hour, 2);
    });

    test('knows night from day', () {
      expect(newWorld(hour: 9).isNight, isFalse);
      expect(newWorld(hour: 21).isNight, isTrue);
    });

    test('applies the campaign night modifiers', () {
      expect(newWorld(hour: 9).timeModifierFor('stealth'), 0);
      expect(newWorld(hour: 21).timeModifierFor('stealth'), 2);
      expect(newWorld(hour: 21).timeModifierFor('perception'), -2);
    });

    test('rejects going backwards', () {
      expect(() => newWorld().advanceTime(-1), throwsArgumentError);
    });
  });

  group('atmosphere', () {
    test('weather is rolled once per region and then holds', () {
      final world = newWorld();
      final first = world.currentWeather;
      expect(first, isNotNull);
      for (var i = 0; i < 5; i++) {
        expect(world.currentWeather, first, reason: 'weather should not churn');
      }
    });

    test('a different region gets its own weather', () {
      final world = newWorld(flags: {'Unlock_Travel_to_Valorheim'});
      final millhaven = world.currentWeather;
      world.move('northeast');
      final capital = world.currentWeather;
      expect(capital, isNotNull);
      expect(capital, isNot(millhaven));
    });

    test('ambiance comes from the region the party is in', () {
      final world = newWorld();
      final region = world.currentRegion!;
      expect(region.ambianceEchoes, contains(world.ambianceEcho()));
    });
  });

  group('arcs', () {
    test('an arc starts when the party walks into its trigger room', () {
      final world = newWorld();
      expect(
          world.activeArcs().map((a) => a.id), contains('tier_1_local_threat'));
    });

    test('world state changes are owed, not applied silently', () {
      final world = newWorld(flags: {
        'keyword_quest_unlocked',
        'item_acquired_elaras_doll',
        'boss_defeated_hollow_avatar',
      });
      expect(world.flags, isNot(contains('Unlock_Travel_to_Valorheim')));

      final applied = world.applyPendingWorldState();
      expect(applied, contains('Unlock_Travel_to_Valorheim'));
      expect(world.flags, contains('Town_Millhaven_Saved'));
      // And now the road out of Millhaven is open.
      expect(world.look().openDirections, contains('northeast'));
    });

    test('applying twice owes nothing the second time', () {
      final world = newWorld(flags: {
        'keyword_quest_unlocked',
        'item_acquired_elaras_doll',
        'boss_defeated_hollow_avatar',
      });
      world.applyPendingWorldState();
      expect(world.applyPendingWorldState(), isEmpty);
    });
  });

  group('resuming', () {
    test('a restored session stands where the original stood', () {
      final world = newWorld(seed: 9);
      world.move('north');
      world.talk('thorne', topic: 'quest');
      world.advanceTime(6);

      final resumed = WorldSession.restore(
        campaign: loadShatteredSeals(),
        actors: [SessionActor(id: 'korash', character: _korash())],
        snapshot: world.snapshot(),
      );

      expect(resumed.roomId, world.roomId);
      expect(resumed.hour, world.hour);
      expect(resumed.flags, world.flags);
      expect(resumed.currentWeather, world.currentWeather);
      // Topics already raised stay raised, so no flag is awarded twice.
      expect(resumed.talk('thorne', topic: 'quest').flagsSet, isEmpty);
    });

    test('refuses a snapshot from another campaign', () {
      final snapshot = newWorld().snapshot()..['campaignId'] = 'something_else';
      expect(
        () => WorldSession.restore(
          campaign: loadShatteredSeals(),
          actors: [SessionActor(id: 'korash', character: _korash())],
          snapshot: snapshot,
        ),
        throwsArgumentError,
      );
    });
  });
}
