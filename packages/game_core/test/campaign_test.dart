import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

const _dir = '../../campaigns/shattered_seals';

String _read(String name) => File('$_dir/$name').readAsStringSync();

Campaign loadShatteredSeals() => const CampaignLoader().load(
      id: 'campaign_i_shattered_seals',
      title: 'Campaign I: Shattered Seals',
      worldConfigJson: _read('world_config.json'),
      locationsJson: _read('locations.json'),
      npcsJson: _read('npcs_and_dialogue.json'),
      gearJson: _read('gear.json'),
      arcsJson: _read('campaign_arcs.json'),
    );

void main() {
  late Campaign campaign;

  setUpAll(() => campaign = loadShatteredSeals());

  group('world', () {
    test('reads metadata and regions', () {
      expect(campaign.world.metadata.name, 'Valorheim');
      expect(campaign.world.metadata.theme, 'Dark Fantasy');
      expect(campaign.world.metadata.levelCap, 20);
      expect(campaign.world.regions, hasLength(2));
      expect(
          campaign.world.metadata.backgroundLore, contains('Crimson Covenant'));
    });

    test('finds the region a town belongs to', () {
      expect(campaign.world.regionForTown('Millhaven')!.id,
          'r_001_millhaven_valley');
      expect(campaign.world.regionForTown('  thornhaven  ')!.id,
          'r_002_valorheim_heartlands');
      expect(campaign.world.regionForTown('Nowhere'), isNull);
    });

    test('reads weather and ambiance', () {
      final valley = campaign.world.regionById('r_001_millhaven_valley')!;
      expect(valley.weatherStates.keys, containsAll(['clear', 'rain', 'fog']));
      expect(valley.ambianceEchoes, hasLength(3));
      expect(valley.hasWeather, isTrue);
    });
  });

  group('time', () {
    test('turns to night at the halfway point of the cycle', () {
      final time = campaign.world.time;
      expect(time.dayCycleHours, 24);
      expect(time.nightfallHour, 12);
      expect(time.isNight(11), isFalse);
      expect(time.isNight(12), isTrue);
    });

    test('applies night modifiers only at night, and only where written', () {
      final time = campaign.world.time;
      expect(time.modifierFor('stealth', hour: 9), 0);
      expect(time.modifierFor('stealth', hour: 20), 2);
      expect(time.modifierFor('perception', hour: 20), -2);
      // Everything else is unaffected; darkness is not a general penalty.
      expect(time.modifierFor('athletics', hour: 20), 0);
    });
  });

  group('locations', () {
    test('reads towns, zones and their level bands', () {
      final millhaven = campaign.locations.townById('town_01_millhaven')!;
      expect(millhaven.name, 'Millhaven');
      expect(millhaven.tier, 1);
      expect(millhaven.minLevel, 1);
      expect(millhaven.maxLevel, 10);
      expect(millhaven.suitsLevel(6), isTrue);
      expect(millhaven.suitsLevel(14), isFalse);
      expect(millhaven.zones, hasLength(3));
      expect(millhaven.roomIds, hasLength(10));
    });

    test('maps a room back to its town and zone', () {
      expect(
          campaign.locations.townForRoom('MH_001_Square')!.name, 'Millhaven');
      final millhaven = campaign.locations.townById('town_01_millhaven')!;
      expect(millhaven.zoneForRoom('WW_002_Deep')!.id, 'z_02_whisperwood');
    });

    test('resolves exits, including MUD shorthands', () {
      final square = campaign.locations.roomById('MH_001_Square')!;
      expect(
          square.directions, ['east', 'north', 'northeast', 'south', 'west']);
      expect(square.exitTo('north'), 'MH_002_GuardHall');
      expect(square.exitTo('n'), 'MH_002_GuardHall');
      expect(square.exitTo('NORTH'), 'MH_002_GuardHall');
      expect(square.exitTo('in'), isNull);
    });

    test('reads a gated exit and keeps it shut until its flag is set', () {
      final road = campaign.locations.roomById('MH_001_Square')!.exit('ne')!;
      expect(road.to, 'VC_001_Plaza');
      expect(road.isGated, isTrue);
      expect(road.requiredFlags, ['Unlock_Travel_to_Valorheim']);
      expect(road.blockedMessage, contains('tollgate'));
      expect(road.isOpen(const {}), isFalse);
      expect(road.isOpen({'Unlock_Travel_to_Valorheim'}), isTrue);
    });
  });

  group('npcs', () {
    test('reads the cast and places them', () {
      expect(campaign.npcs.length, 3);
      expect(campaign.npcs.byId('npc_001_thorne')!.name,
          'Captain Thorne Ironhelm');
      expect(
          campaign.npcs.inRoom('VC_002_ThroneRoom').single.name, 'Queen Liora');
      expect(campaign.npcs.inRoom('MH_001_Square'), isEmpty);
    });

    test('finds an NPC by any word of their name', () {
      final thorne = campaign.npcs.findInRoom('MH_002_GuardHall', 'thorne');
      expect(thorne?.name, 'Captain Thorne Ironhelm');
      expect(
          campaign.npcs.findInRoom('MH_002_GuardHall', 'ironhelm'), isNotNull);
      expect(campaign.npcs.findInRoom('MH_002_GuardHall', 'liora'), isNull);
    });

    test('answers keywords, exactly or by mention', () {
      final thorne = campaign.npcs.byId('npc_001_thorne')!;
      expect(thorne.replyTo('elara'), contains('Fifty gold'));
      expect(thorne.replyTo('ELARA'), contains('Fifty gold'));
      // A player types a sentence, not a keyword.
      expect(thorne.replyTo('ask him about elara'), contains('Fifty gold'));
      expect(thorne.replyTo('the weather'), isNull);
      expect(thorne.knows('quest'), isTrue);
    });

    test('lists what an NPC will talk about', () {
      expect(campaign.npcs.byId('npc_006_malachai')!.topics,
          ['ascension', 'shadow', 'vision']);
    });
  });

  group('gear', () {
    test('reads items with their traits and stats', () {
      final dagger = campaign.gear.byId('w_006_shadowbane_dagger')!;
      expect(dagger.level, 5);
      expect(dagger.damage, '1d4');
      expect(dagger.bonus, 1);
      expect(dagger.isMagical, isTrue);
      expect(dagger.hasTrait('finesse'), isTrue);
      expect(dagger.hasTrait('heavy'), isFalse);
      expect(dagger.special, contains('Shadow entities'));
    });

    test('reads armour class where an item has one', () {
      final vestment = campaign.gear.byId('a_011_monarchs_vestment')!;
      expect(vestment.armorClass, 20);
      expect(vestment.damage, isNull);
    });

    test('selects items near a character level', () {
      expect(campaign.gear.forLevel(5).map((i) => i.id),
          contains('w_006_shadowbane_dagger'));
      expect(campaign.gear.forLevel(5).map((i) => i.id),
          isNot(contains('w_018_shadow_ripper')));
    });

    test('filters by type', () {
      expect(campaign.gear.ofType('armor'), hasLength(1));
      expect(campaign.gear.ofType('weapon'), hasLength(3));
    });
  });

  group('arcs', () {
    test('reads both tiers', () {
      expect(campaign.arcs.length, 2);
      final tier1 = campaign.arcs.byId('tier_1_local_threat')!;
      expect(tier1.name, 'Shadows Over Millhaven');
      expect(tier1.minLevel, 1);
      expect(tier1.maxLevel, 10);
      expect(tier1.objectives, hasLength(3));
    });

    test('tracks progress against a flag set', () {
      final tier1 = campaign.arcs.byId('tier_1_local_threat')!;
      var flags = <String>{};

      expect(tier1.hasStarted(flags), isFalse);
      flags = {'enter_MH_001'};
      expect(tier1.hasStarted(flags), isTrue);
      expect(tier1.nextObjective(flags)!.task, 'Speak to Captain Thorne');
      expect(tier1.progress(flags), (done: 0, total: 3));

      flags.add('keyword_quest_unlocked');
      expect(tier1.nextObjective(flags)!.task, 'Investigate Old Oak Grove');
      expect(tier1.progress(flags), (done: 1, total: 3));

      flags
          .addAll(['item_acquired_elaras_doll', 'boss_defeated_hollow_avatar']);
      expect(tier1.isComplete(flags), isTrue);
      expect(tier1.nextObjective(flags), isNull);
    });

    test('reports world state changes owed once an arc completes', () {
      final flags = {
        'enter_MH_001',
        'keyword_quest_unlocked',
        'item_acquired_elaras_doll',
        'boss_defeated_hollow_avatar',
      };
      expect(campaign.arcs.pendingWorldStateChanges(flags),
          containsAll(['NPC_Elara_freed', 'Unlock_Travel_to_Valorheim']));
      expect(campaign.arcs.active(flags), isEmpty);
    });
  });

  group('looking around', () {
    test('gathers room, town, region and cast together', () {
      final view = campaign.look('VC_002_ThroneRoom')!;
      expect(view.room.title, 'The Royal Throne Room');
      expect(view.town!.name, 'Valorheim Capital');
      expect(view.region!.id, 'r_002_valorheim_heartlands');
      expect(view.npcs.single.name, 'Queen Liora');
    });

    test('returns nothing for a room id nobody has written', () {
      expect(campaign.look('MH_099_Nowhere'), isNull);
    });
  });

  group('survey of the real campaign', () {
    test('Valorheim is walkable and stays that way', () {
      // The regression this locks in: every room the zones name is written,
      // every exit leads somewhere real, and nobody stands in a room that
      // does not exist. Adding a zone entry without a room breaks this.
      final report = campaign.survey();
      expect(report.unwrittenRooms, isEmpty);
      expect(report.danglingExits, isEmpty);
      expect(report.misplacedNpcs, isEmpty);
      expect(report.isPlayable, isTrue);
    });

    test('every exit has a way back', () {
      expect(campaign.survey().oneWayExits, isEmpty);
    });

    test('still reports the content genuinely outstanding', () {
      // Not clean: gear and the encounters that would set the arc conditions
      // are still unwritten, and the survey should keep saying so.
      final report = campaign.survey();
      expect(report.isClean, isFalse);
      expect(report.gearLevelGaps, contains(2));
      expect(report.unreachableArcConditions,
          contains('boss_defeated_hollow_avatar'));
    });

    test('does not flag conditions that walking into a room would set', () {
      // enter_MH_001 abbreviates MH_001_Square, and no data file declares it
      // because movement does.
      final unreachable = campaign.survey().unreachableArcConditions;
      expect(unreachable, isNot(contains('enter_MH_001')));
      expect(unreachable, isNot(contains('enter_VC_001')));
    });
  });

  group('survey of deliberately broken data', () {
    // Detection is tested against data built to be wrong, rather than by
    // relying on the shipping campaign happening to be incomplete.
    Campaign broken(String locationsJson, {String? npcsJson}) =>
        const CampaignLoader().load(
          id: 'broken',
          title: 'Broken',
          worldConfigJson: _read('world_config.json'),
          locationsJson: locationsJson,
          npcsJson: npcsJson ?? '{"npcs":[]}',
        );

    test('reports a room a zone names but nobody wrote', () {
      final c = broken('''
{"towns":{"t":{"name":"T","tier":1,"level_range":[1,2],"zones":{"z":["A","B"]}}},
 "rooms":[{"room_id":"A","title":"A","description":"a"}]}''');
      expect(c.survey().unwrittenRooms, ['B']);
    });

    test('reports an exit leading nowhere', () {
      final c = broken('''
{"towns":{},"rooms":[{"room_id":"A","title":"A","description":"a",
 "exits":{"north":"B"}}]}''');
      final dangling = c.survey().danglingExits;
      expect(dangling.single.from, 'A');
      expect(dangling.single.direction, 'north');
      expect(dangling.single.to, 'B');
      expect(c.survey().isPlayable, isFalse);
    });

    test('reports an exit with no way back', () {
      final c = broken('''
{"towns":{},"rooms":[
 {"room_id":"A","title":"A","description":"a","exits":{"north":"B"}},
 {"room_id":"B","title":"B","description":"b"}]}''');
      expect(c.survey().oneWayExits.single.from, 'A');
    });

    test('reports an NPC standing nowhere', () {
      final c = broken(
        '{"towns":{},"rooms":[{"room_id":"A","title":"A","description":"a"}]}',
        npcsJson: '''
{"npcs":[{"npc_id":"npc_001_ghost","name":"A Ghost","location":"Z",
 "appearance":"x","greeting":"y"}]}''',
      );
      expect(c.survey().misplacedNpcs.single.name, 'A Ghost');
      expect(c.survey().isPlayable, isFalse);
    });

    test('renders every section it found', () {
      final c = broken('''
{"towns":{"t":{"name":"T","tier":1,"level_range":[1,2],"zones":{"z":["A","B"]}}},
 "rooms":[{"room_id":"A","title":"A","description":"a","exits":{"north":"B"}}]}''');
      final rendered = c.survey().render();
      expect(rendered, contains('Rooms named but not written'));
      expect(rendered, contains('Exits leading nowhere'));
    });

    test('says so when there is nothing outstanding', () {
      const clean = CampaignReport();
      expect(clean.isClean, isTrue);
      expect(clean.render(), 'Campaign data is complete.');
    });
  });
}
