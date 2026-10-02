import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;

WorldSession _world({
  String room = 'MH_001_Square',
  Set<String>? flags,
  List<String> carrying = const [],
  int seed = 1,
}) {
  final world = WorldSession(
    campaign: _campaign,
    actors: [SessionActor(id: 'korash', character: loadKorash())],
    roller: DiceRoller(seed),
    roomId: room,
    flags: flags,
  );
  for (final item in carrying) {
    world.inventory.add(item);
  }
  return world;
}

/// The sheet [roomId] is on, drawn as the party in [world] knows it.
List<String> _draw(WorldSession world, [String? roomId]) {
  final room = roomId ?? world.currentRoom.id;
  final map = _campaign.atlas.forRoom(room)!;
  return drawSheet(
    sheet: map.sheetOf(room)!,
    map: map,
    knows: world.knowsRoom,
    exitsOf: world.knownExits,
    here: world.currentRoom.id,
  );
}

const _valleyMap = 'g_038_map_of_the_valley';
const _cityPlan = 'g_039_plan_of_valorheim';

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  group('the atlas', () {
    test('draws every room, and the survey finds nothing wrong with it', () {
      expect(_campaign.survey().mapProblems, isEmpty);
      for (final roomId in _campaign.locations.rooms.keys) {
        expect(_campaign.atlas.forRoom(roomId), isNotNull, reason: roomId);
      }
    });

    test('reports a room left off, and a road that cannot be drawn', () {
      final atlas = Atlas([
        TownMap(
          townId: 'town_01_millhaven',
          title: 'Bad',
          labels: const {'MH_001_Square': 'Square', 'MH_003_Tavern': 'Inn'},
          sheets: const [
            MapSheet(title: 'Bad', places: {
              'MH_001_Square': MapPlace(0, 0),
              // East of the square, but drawn two squares away.
              'MH_003_Tavern': MapPlace(2, 0),
            }),
          ],
        ),
      ]);
      final problems =
          atlas.problems(locations: _campaign.locations, gear: _campaign.gear);
      expect(problems, contains('Bad leaves out MH_002_GuardHall'));
      expect(
          problems,
          contains('Bad: MH_001_Square goes east to MH_003_Tavern, but they '
              'are not drawn side by side'));
    });
  });

  group('fog of war', () {
    test('at the start, the party knows where it stands and no further', () {
      final world = _world();
      expect(world.knowsRoom('MH_001_Square'), isTrue);
      expect(world.knowsRoom('MH_005_Forge'), isFalse);
      // Every way out is a question mark: seen, not known.
      expect(_draw(world), [
        '      ?',
        '      |',
        '?--[Square]--?',
        '      |',
        '      ?',
      ]);
    });

    test('walking somewhere puts it on the map, and what lies past it', () {
      final world = _world()..move('west');
      expect(world.knowsRoom('MH_005_Forge'), isTrue);
      final drawn = _draw(world).join('\n');
      expect(drawn, contains('?--[Forge]--Square'));
      expect(drawn, isNot(contains('Wood')), reason: 'not been there yet');
    });

    test('the valley map shows all of it', () {
      final world = _world(carrying: [_valleyMap]);
      expect(_draw(world), [
        '              Farm--Oaks    Guards',
        '               |              |',
        'Hollow--Deep--Wood--Forge--[Square]--Sparrow',
        '                              |',
        '                            Temple',
        '                              |',
        '                           Mere Rd',
        '                              |',
        '                            Reeds',
        '                              |',
        '                             Mill',
      ]);
    });

    test('the plan of the city shows its streets, and nothing under them', () {
      final world = _world(room: 'VC_001_Plaza', carrying: [_cityPlan]);
      expect(_draw(world), [
        'Ritual  Throne',
        '  :        |',
        'Gates---[Plaza]--Library',
        '           |',
        '         Mine',
        '           :',
        '         Deeps',
      ]);
      for (final below in [
        'UA_001_SealedStacks',
        'SD_001_Rift',
        'QK_004_Cradle',
      ]) {
        expect(world.knowsRoom(below), isFalse, reason: below);
      }
    });

    test('a map does not show a door it has no way of explaining', () {
      // The stair under the Grand Library is shut, and nobody who has not
      // stood in the room knows it is there.
      final world = _world(room: 'VC_001_Plaza', carrying: [_cityPlan]);
      final library = world.knownExits('VC_003_GrandLibrary');
      expect(library.map((e) => e.direction), ['west']);
    });
  });

  group('routes', () {
    test('go the quickest known way, and only through known places', () {
      final world = _world()
        ..move('west')
        ..move('west')
        ..move('east')
        ..move('east');
      final routes = {for (final r in world.routes()) r.roomId: r};
      expect(routes.keys, unorderedEquals(['MH_005_Forge', 'WW_001_Edge']));
      expect(routes['WW_001_Edge']!.directions, ['west', 'west']);
      expect(routes['WW_001_Edge']!.minutes,
          greaterThan(routes['MH_005_Forge']!.minutes));
      expect(routes.containsKey('WW_002_Deep'), isFalse,
          reason: 'only glimpsed, never visited or mapped');
    });

    test('with a map, reach anywhere on it, nearest first', () {
      final routes = _world(carrying: [_valleyMap]).routes();
      final oaks = routes.firstWhere((r) => r.roomId == 'RF_002_OakGrove');
      expect(oaks.directions, ['west', 'west', 'north', 'east']);
      final times = [for (final r in routes) r.minutes];
      expect(times, [...times]..sort());
    });

    test('never along a road that is shut', () {
      // The Mere Road is barred until Wendel has pointed the way south.
      final routes = _world(carrying: [_valleyMap]).routes();
      expect(routes.map((r) => r.roomId), isNot(contains('MR_001_MereRoad')));
    });
  });

  group('selling maps', () {
    test('Sal Mercy has the valley map at every stop', () {
      final shop = _campaign.economy.shopKeptBy('npc_010_sal')!;
      expect(shop.alwaysFor(const {}), [_valleyMap]);
      var checked = 0;
      for (var seed = 1; seed < 40 && checked < 3; seed++) {
        final stop = _world(seed: seed).whereIs('npc_010_sal');
        if (stop == null) continue;
        final world = _world(room: stop, seed: seed);
        expect(world.whereIs('npc_010_sal'), stop);
        expect(world.wares().map((w) => w.item.id), contains(_valleyMap),
            reason: 'seed $seed at $stop');
        checked++;
      }
      expect(checked, 3, reason: 'Sal should be found somewhere');
    });

    test('the Grand Library sells the plan of the city', () {
      final world = _world(room: 'VC_003_GrandLibrary');
      expect(world.shopHere?.keeperId, 'npc_008_hale');
      final plan = world.wares().singleWhere((w) => w.item.id == _cityPlan);
      expect(plan.item.id, _cityPlan);
      expect(plan.price, 1200);
    });
  });
}
