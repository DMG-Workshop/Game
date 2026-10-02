import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;

WorldSession _world(String room, Set<String> flags) => WorldSession(
      campaign: _campaign,
      actors: [SessionActor(id: 'korash', character: loadKorash())],
      roller: DiceRoller(3),
      roomId: room,
      flags: flags,
    );

List<CampaignArc> get _quests => [
      for (final arc in _campaign.arcs.all)
        if (arc.id.startsWith('side_sq_')) arc,
    ];

/// Talks to [who], choosing the first option whose id starts with each of
/// [path] in turn: enough to walk a conversation to a hub and pick there.
/// Returns the ids on offer at the end.
List<String> _talk(WorldSession world, String who, List<String> path) {
  final talk = world.beginConversation(who)!.talk;
  for (final step in path) {
    final option =
        talk.availableOptions().where((o) => o.id.startsWith(step)).firstOrNull;
    expect(option, isNotNull,
        reason: 'no "$step" in ${talk.availableOptions().map((o) => o.id)}');
    talk.choose(option!.id);
  }
  final offered = [for (final o in talk.availableOptions()) o.id];
  world.concludeConversation(talk);
  return offered;
}

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  group('thirty side quests', () {
    test('none of them part of the story, all of them paid', () {
      expect(_quests, hasLength(30));
      for (final arc in _quests) {
        expect(arc.isSide, isTrue, reason: arc.id);
        expect(arc.reward, isNotNull, reason: arc.id);
        expect(arc.objectives.length, greaterThanOrEqualTo(2),
            reason: 'something to do, and somebody to go back to');
        expect(arc.objectives.last.task, startsWith('Go back to'));
      }
    });

    test('in every part of the map, the valley and the capital both', () {
      final zones = {for (final arc in _quests) arc.zone};
      expect(
          zones,
          containsAll([
            'z_01_proper',
            'z_02_whisperwood',
            'z_03_ravencrest',
            'z_07_mere_road',
            'z_04_palace_district',
            'z_05_bloodstone_mines',
            'z_06_thornhaven',
            'z_08_under_archive',
            'z_09_the_sundering',
            'z_10_quiet_court'
          ]));
    });

    test('what is to be found is not there until somebody asks for it', () {
      final quested = [
        for (final item in _campaign.items.all)
          if (item.id.startsWith('i_sq_')) item,
      ];
      expect(quested, isNotEmpty);
      for (final item in quested) {
        expect(item.hiddenUntilFlags.single, endsWith('_taken'),
            reason: item.id);
        expect(_campaign.locations.roomById(item.location), isNotNull,
            reason: item.id);
      }
    });
  });

  group('a quest to find something', () {
    test('Jory\'s crate: asked, found on the Mere Road, handed back, paid', () {
      final square =
          _world('MH_001_Square', {'met_jory', 'heard_of_the_mere_road'});
      expect(_talk(square, 'jory', ['talk']), contains('sq_jorys_crate'));
      _talk(square, 'jory', ['talk', 'sq_jorys_crate']);
      expect(square.flags, contains('sq_jorys_crate_taken'));
      expect(square.activeArcs().map((a) => a.id),
          contains('side_sq_jorys_crate'));

      // The crate is on the causeway now, and was not before.
      final before = _world('MR_001_MereRoad', {});
      expect(before.look().items.map((i) => i.name),
          isNot(contains('A Crate Stamped TALLOW')));
      final road = _world('MR_001_MereRoad', square.flags);
      expect(road.look().items.map((i) => i.name),
          contains('A Crate Stamped TALLOW'));
      road.take('crate');

      final back = _world('MH_001_Square', road.flags);
      final start = back.inventory.coin;
      _talk(back, 'jory', ['talk', 'sq_jorys_crate_back']);
      final settled = back.settleArcs();
      expect(
          settled.completed.map((a) => a.id), contains('side_sq_jorys_crate'));
      expect(back.inventory.coin, start + 1500);
    });

    test('nobody offers a quest before its time', () {
      final early = _world('MH_001_Square', {'met_jory'});
      expect(_talk(early, 'jory', ['talk']), isNot(contains('sq_jorys_crate')),
          reason: 'nobody has mentioned the Mere Road yet');
    });
  });

  group('a quest for a word', () {
    test('the Watch roster: Rook asks, Thorne signs, Rook is told', () {
      final hall = _world('MH_002_GuardHall', {'met_rook', 'met_thorne'});
      _talk(hall, 'rook', ['talk', 'sq_roster']);
      expect(_talk(hall, 'thorne', ['talk']), contains('sq_roster_word'));
      _talk(hall, 'thorne', ['talk', 'sq_roster_word']);
      _talk(hall, 'rook', ['talk', 'sq_roster_back']);
      expect(hall.settleArcs().completed.map((a) => a.id),
          contains('side_sq_roster'));
    });
  });

  group('a quest for a fight', () {
    test('the drovers\' road is done once the deep wood is clear', () {
      final farm = _world('RF_001_Farm', {'met_marta'});
      _talk(farm, 'marta', ['ask', 'sq_drovers_road']);
      expect(_talk(farm, 'marta', ['ask']),
          isNot(contains('sq_drovers_road_back')),
          reason: 'the thralls are still in the wood');

      final cleared =
          _world('RF_001_Farm', {...farm.flags, 'cleared_whisperwood_thralls'});
      _talk(cleared, 'marta', ['ask', 'sq_drovers_road_back']);
      expect(cleared.settleArcs().completed.map((a) => a.id),
          contains('side_sq_drovers_road'));
    });
  });
}
