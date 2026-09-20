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
