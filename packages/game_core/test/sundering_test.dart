import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;

const _tier2Done = {
  'NPC_King_Aldric_cured',
  'Faction_Covenant_shattered',
  'Trigger_Sundering_Earthquake_Event',
  'boss_defeated_malachai_vex',
};

WorldSession _world(String room, {Set<String> flags = const {}}) =>
    WorldSession(
      campaign: _campaign,
      actors: [SessionActor(id: 'korash', character: loadKorash())],
      roller: DiceRoller(3),
      roomId: room,
      flags: flags,
    );

int _xp(Encounter e, int party) => e.creatureIds
    .map((id) => _campaign.bestiary.creatureById(id)!.level)
    .fold(0, (sum, l) => sum + creatureXp(l - party));

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  test('every party level from 14 to 20 has a fight worth having', () {
    for (var level = 14; level <= 20; level++) {
      final fits = _campaign.bestiary.encounters.where((e) {
        final xp = _xp(e, level);
        return xp >= Threat.low.budget && xp <= Threat.extreme.budget;
      });
      expect(fits, isNotEmpty, reason: 'level $level');
    }
    expect(_campaign.survey().levelsWithoutAFight, isEmpty);
  });

  test('the finale is a severe threat for four at level 20', () {
    final cradle = _campaign.bestiary.encounters
        .firstWhere((e) => e.id == 'e_vessels_cradle');
    expect(_xp(cradle, 20), Threat.severe.budget);
  });

  test('the rift stays shut until Blood and Thrones is finished', () {
    expect(() => _world('VC_001_Plaza').move('down'),
        throwsA(isA<InvalidMoveException>()));
    final world = _world('VC_001_Plaza', flags: _tier2Done)..move('down');
    expect(world.currentRoom.id, 'SD_001_Rift');
  });

  test('finishing tier 2 starts the Quiet Kingdom', () {
    final tier2 = _campaign.arcs.byId('tier_2_kingdom_threat')!;
    expect(tier2.maxLevel, 13);
    expect(
        tier2.worldStateChanges, isNot(contains('End_of_Level_20_Campaign')));
    final tier3 = _campaign.arcs.byId('tier_3_quiet_kingdom')!;
    expect(tier3.startTrigger, 'Trigger_Sundering_Earthquake_Event');
    expect(tier3.worldStateChanges, contains('End_of_Level_20_Campaign'));
  });

  test('the Queen leaves the throne room and the King takes it back', () {
    final before = _world('VC_002_ThroneRoom').look().npcs.map((n) => n.name);
    expect(before, ['Queen Liora']);
    final after = _world('VC_002_ThroneRoom', flags: _tier2Done)
        .look()
        .npcs
        .map((n) => n.name);
    expect(after, ['King Aldric']);
  });

  test('the King sends the party down, and asks after his patrol', () {
    final world = _world('VC_002_ThroneRoom', flags: _tier2Done);
    final talk = world.beginConversation('aldric')!.talk
      ..choose('ask_queen')
      ..choose('ask_patrol');
    world.concludeConversation(talk);
    expect(world.flags,
        containsAll(['aldric_sent_you_down', 'aldric_asked_after_the_patrol']));
    expect(world.activeArcs().map((a) => a.id),
        containsAll(['tier_3_quiet_kingdom', 'side_kings_last_patrol']));
  });

  test('the Fifth Name runs from the causeway to Hale to Aldus', () {
    final hale = _world('VC_003_GrandLibrary', flags: {
      ..._tier2Done,
      'item_acquired_causeway_rubbing',
    });
    final a = hale.beginConversation('hale')!.talk..choose('show_rubbing');
    hale.concludeConversation(a);
    expect(hale.flags, contains('hale_read_the_rubbing'));

    final aldus = _world('MH_004_Temple', flags: {
      'boss_defeated_hollow_avatar',
      'hale_read_the_rubbing',
    });
    final b = aldus.beginConversation('aldus')!.talk..choose('take_back_name');
    aldus.concludeConversation(b);
    expect(aldus.flags, contains('aldus_took_back_the_name'));
  });

  test('an NPC waits for the story to bring them in', () {
    const npc = Npc(
      id: 'n',
      name: 'N',
      location: 'A',
      appearance: '',
      greeting: '',
      appearsAfter: ['in'],
      leavesAfter: ['out'],
    );
    expect(npc.isPresent({}), isFalse);
    expect(npc.isPresent({'in'}), isTrue);
    expect(npc.isPresent({'in', 'out'}), isFalse);
  });
}
