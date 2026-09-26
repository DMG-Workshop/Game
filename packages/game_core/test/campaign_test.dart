import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
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
      bestiaryJson: _read('bestiary.json'),
      itemsJson: _read('world_items.json'),
      conversationsJson: _read('conversations.json'),
      economyJson: _read('economy.json'),
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
      // Town, wood, farm, and the Mere Road nobody should take.
      expect(millhaven.zones, hasLength(4));
      expect(millhaven.roomIds, hasLength(13));
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
      expect(campaign.npcs.length, 10);
      expect(campaign.npcs.byId('npc_001_thorne')!.name,
          'Captain Thorne Ironhelm');
      expect(
          campaign.npcs.inRoom('VC_002_ThroneRoom').single.name, 'Queen Liora');
      expect(campaign.npcs.inRoom('MH_001_Square').single.name, 'Jory Tallow');
      expect(campaign.npcs.inRoom('WW_002_Deep'), isEmpty);
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
      expect(campaign.gear.ofType('armor'), hasLength(7));
      expect(campaign.gear.ofType('weapon'), hasLength(19));
      // Every item lands in exactly one category, so nothing is invisible to
      // a table that asks by type.
      final byType = {
        for (final type in {for (final i in campaign.gear.all) i.type})
          type: campaign.gear.ofType(type).length,
      };
      expect(byType.values.reduce((a, b) => a + b), campaign.gear.length);
    });

    test('a character of any level has something to find', () {
      // Loot pacing: twenty levels, twenty items, no dead stretch where the
      // tables have nothing to offer.
      expect(
          campaign.gear.levelGaps(campaign.world.metadata.levelCap), isEmpty);
      expect(campaign.gear.length, 32);
      for (var level = 1; level <= 20; level++) {
        expect(campaign.gear.forLevel(level), isNotEmpty,
            reason: 'nothing within two levels of $level');
      }
    });

    test('every item is identified once and described', () {
      final ids = campaign.gear.all.map((i) => i.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final item in campaign.gear.all) {
        expect(item.name.trim(), isNotEmpty);
        expect(item.description.trim(), isNotEmpty, reason: item.name);
        expect(item.traits, isNotEmpty, reason: item.name);
        expect(item.level, inInclusiveRange(1, 20), reason: item.name);
      }
    });

    test('every magical item says what the magic does', () {
      for (final item in campaign.gear.all.where((i) => i.isMagical)) {
        expect(item.special?.trim(), isNotEmpty, reason: item.name);
      }
      // The only mundane item is the militia sword a first-level character
      // starts with.
      expect(campaign.gear.all.where((i) => !i.isMagical).map((i) => i.id),
          ['w_001_guard_sword']);
    });

    test('every weapon rolls damage the engine can read', () {
      for (final weapon in campaign.gear.ofType('weapon')) {
        expect(weapon.damage, isNotNull, reason: weapon.name);
        expect(DamageExpression.tryParse(weapon.damage!), isNotNull,
            reason: '${weapon.name}: ${weapon.damage}');
      }
    });

    test('armour class climbs with level', () {
      final armour = campaign.gear.ofType('armor');
      var previous = 0;
      for (final piece in armour) {
        final ac = piece.armorClass;
        expect(ac, isNotNull, reason: piece.name);
        expect(ac, greaterThan(previous),
            reason: '${piece.name} is no better than the level below it');
        previous = ac!;
      }
    });

    test('every suit of armour says what it is worth', () {
      // The engine builds AC from the armour's own bonus and its Dexterity
      // cap, so a suit that declares neither is worth only its rune.
      for (final piece in campaign.gear.ofType('armor')) {
        expect(piece.acBonus, isNotNull, reason: piece.name);
        expect(piece.dexCap, isNotNull, reason: piece.name);
        expect(piece.acBonus, inInclusiveRange(1, 6), reason: piece.name);
        expect(piece.dexCap, inInclusiveRange(0, 5), reason: piece.name);
        expect(
          piece.traits.map((t) => t.toLowerCase()),
          anyElement(isIn(EquippedStats.armorDefaults.keys)),
          reason: '${piece.name} does not say if it is light, medium '
              'or heavy',
        );
      }
    });

    test('striking follows the same schedule potency does', () {
      // Striking at 4, greater at 12, major at 19. A magical weapon without
      // it would be strictly worse than a level 4 one.
      for (final weapon in campaign.gear.ofType('weapon')) {
        final expected = switch (weapon.level) {
          _ when !weapon.isMagical => StrikingRune.none,
          >= 19 => StrikingRune.majorStriking,
          >= 12 => StrikingRune.greaterStriking,
          >= 4 => StrikingRune.striking,
          _ => StrikingRune.none,
        };
        expect(weapon.striking, expected,
            reason: '${weapon.name} at level ${weapon.level}');
      }
    });

    test('no item carries a rune earlier than the rules allow', () {
      // Potency is the one number on these items the engine will eventually
      // add to a roll, so it follows Pathfinder's own pacing: weapons at 2,
      // 10 and 16; armour at 5, 11 and 18. An item ahead of that schedule is
      // a balance bug written in JSON.
      const weaponUnlocks = {1: 2, 2: 10, 3: 16};
      const armourUnlocks = {1: 5, 2: 11, 3: 18};
      for (final item in campaign.gear.all) {
        final unlocks = switch (item.type) {
          'weapon' => weaponUnlocks,
          'armor' => armourUnlocks,
          _ => null,
        };
        if (unlocks == null || item.bonus == 0) continue;
        expect(item.bonus, inInclusiveRange(1, 3), reason: item.name);
        expect(item.level, greaterThanOrEqualTo(unlocks[item.bonus]!),
            reason: '${item.name} is +${item.bonus} at level ${item.level}');
      }
    });
  });

  group('rare drops', () {
    test('nothing rare is impossible to find', () {
      // A rare item is one that cannot be bought, so if nothing drops it the
      // item does not exist as far as a player is concerned.
      final report = campaign.survey();
      expect(report.unobtainableGear, isEmpty,
          reason: report.unobtainableGear.map((i) => i.name).join(', '));
      expect(report.danglingDrops, isEmpty,
          reason: report.danglingDrops
              .map((d) => '${d.item.name} <- ${d.creatureId}')
              .join(', '));
    });

    test('every drop names a creature the bestiary has', () {
      final known = {for (final c in campaign.bestiary.creatures) c.id};
      for (final item in campaign.gear.all) {
        for (final drop in item.drops) {
          expect(known, contains(drop.creatureId), reason: item.name);
        }
      }
    });

    test('every chance is a percentage', () {
      for (final item in campaign.gear.all) {
        for (final drop in item.drops) {
          expect(drop.chance, inInclusiveRange(1, 100), reason: item.name);
        }
      }
    });

    test('nothing ordinary is locked behind a drop table', () {
      // The other way round from the first test: an item that can only be
      // found should say it is rare, or a shop will eventually sell it.
      for (final item in campaign.gear.all.where((i) => i.isDrop)) {
        expect(item.rarity, isNot(ItemRarity.common), reason: item.name);
      }
    });

    test('rarity defaults to common, as most magic items are', () {
      // Pathfinder rarity is about availability, not power: a level 18 sword
      // is ordinarily common, and the table says otherwise only when the
      // campaign means it.
      expect(
          campaign.gear.byId('w_001_guard_sword')!.rarity, ItemRarity.common);
      expect(
          campaign.gear.byId('w_018_shadow_ripper')!.rarity, ItemRarity.common);
      expect(ItemRarity.tryParse('RARE '), ItemRarity.rare);
      expect(ItemRarity.tryParse('legendary'), isNull);
    });

    test('both bosses are carrying their own weapon', () {
      // A boss fought once must not gate its signature item behind a roll
      // the party cannot repeat.
      final spike = campaign.gear.byId('w_024_crown_spike')!;
      expect(spike.rarity, ItemRarity.unique);
      expect(spike.dropFrom('c_hollow_avatar')!.isGuaranteed, isTrue);

      final rod = campaign.gear.byId('w_027_ascension_rod')!;
      expect(rod.dropFrom('c_malachai_vex')!.isGuaranteed, isTrue);
      expect(rod.dropFrom('c_hollow_thrall'), isNull);
    });

    test('the long shots stay long shots', () {
      final nail = campaign.gear.byId('w_021_thralls_nail')!;
      expect(nail.dropFrom('c_hollow_thrall')!.chance, lessThan(20));
      expect(nail.dropFrom('c_hollow_thrall')!.isGuaranteed, isFalse);
    });

    test('a creature drop table is listed likeliest first', () {
      final table = campaign.gear.droppedBy('c_hollow_thrall');
      expect(table, isNotEmpty);
      final chances = [
        for (final item in table) item.dropFrom('c_hollow_thrall')!.chance,
      ];
      expect(chances, orderedEquals(chances.toList()..sort((a, b) => b - a)));
    });

    test('a drop lands at a level the party could be when they fight it', () {
      // The acolytes are only met in the ritual chamber, so their gear is
      // written for the level that fight happens at rather than for the
      // creature's own level.
      for (final item in campaign.gear.all.where((i) => i.isDrop)) {
        for (final drop in item.drops) {
          final creature = campaign.bestiary.creatureById(drop.creatureId)!;
          expect(item.level, greaterThanOrEqualTo(creature.level),
              reason: '${item.name} is below ${creature.name}');
        }
      }
    });

    test('refuses a drop chance that is not a percentage', () {
      expect(
        () => const CampaignLoader().readGear('''
{"gear":[{"item_id":"i","name":"I","level":1,
 "drops":[{"from":"c_x","chance":0}]}]}'''),
        throwsA(isA<CampaignFormatException>()),
      );
    });

    test('refuses a rarity that is not one', () {
      expect(
        () => const CampaignLoader()
            .readGear('{"gear":[{"item_id":"i","name":"I","rarity":"epic"}]}'),
        throwsA(isA<CampaignFormatException>()),
      );
    });
  });

  group('system vocabulary', () {
    // Pathfinder and D&D 5e name several skills differently, and 5e wording
    // slips into notes written from memory. An item promising a bonus to a
    // skill that does not exist is a rule nothing can ever apply, so the
    // mechanical text is checked rather than trusted.
    const fiveEditionOnly = {
      'persuasion': 'Diplomacy',
      'animal handling': 'Nature',
      'sleight of hand': 'Thievery',
      'investigation': 'Perception, or Recall Knowledge',
      'insight': 'Perception',
    };

    test('gear rules text uses Pathfinder skill names', () {
      final offences = <String>[];
      for (final item in campaign.gear.all) {
        final text =
            '${item.special ?? ''} ${item.traits.join(' ')}'.toLowerCase();
        for (final entry in fiveEditionOnly.entries) {
          if (text.contains(entry.key)) {
            offences.add('${item.name}: "${entry.key}" should be '
                '${entry.value}');
          }
        }
      }
      expect(offences, isEmpty, reason: offences.join('; '));
    });

    test("the Monarch's Vestment grants a typed Diplomacy bonus", () {
      // Bonuses in Pathfinder are typed, and an untyped one would stack where
      // it should not, so the item says which kind it is.
      final vestment = campaign.gear.byId('a_011_monarchs_vestment')!;
      expect(vestment.special, contains('Diplomacy'));
      expect(vestment.special, contains('item bonus'));
      expect(vestment.special, isNot(contains('Persuasion')));
    });

    test('every modifier an item grants is typed', () {
      // Pathfinder stacks one bonus of each type and no more. An untyped "+2
      // to Diplomacy" would either stack with everything or with nothing,
      // depending on who implemented it, so the text always says which kind.
      final signed = RegExp(r'[+-]\d+');
      final typed = RegExp(r'^[+-]\d+ \w+ (bonus|penalty)\b');
      final untyped = <String>[];
      for (final item in campaign.gear.all) {
        final text = item.special ?? '';
        for (final match in signed.allMatches(text)) {
          if (!typed.hasMatch(text.substring(match.start))) {
            untyped.add('${item.name}: "${match[0]}"');
          }
        }
      }
      expect(untyped, isEmpty, reason: untyped.join('; '));
    });

    test('every skill an item names is one the engine can resolve', () {
      // Korash stands in as any imported character: the skill list is the
      // same for all of them.
      final stats = DerivedStats(const PathbuilderImporter()
          .importJson(
              File('../pf2e_core/test/fixtures/korash.json').readAsStringSync())
          .character);
      for (final item in campaign.gear.all) {
        for (final skill in CoreSkill.values) {
          if ((item.special ?? '').contains(skill.displayName)) {
            expect(stats.statByKey(skill.key), isNotNull,
                reason: '${item.name} names ${skill.displayName}');
          }
        }
      }
    });
  });

  group('arcs', () {
    test('reads both tiers', () {
      // Two tiers of main story, and the side quests alongside them.
      expect(campaign.arcs.all.where((a) => !a.isSide), hasLength(2));
      expect(campaign.arcs.all.where((a) => a.isSide), hasLength(3));
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

    test('every quest step can actually be completed', () {
      // The regression this locks in: no objective waits on a flag nothing
      // can set. Adding an objective without something that produces its
      // condition breaks this, and a player would only find out by getting
      // stranded on it.
      expect(campaign.survey().unreachableArcConditions, isEmpty);
    });

    test('has nothing outstanding left to report', () {
      // The survey is the campaign's own to-do list. It is empty, and a
      // future room, arc or item that arrives half-written will make it
      // speak up again rather than sliding in unnoticed.
      final report = campaign.survey();
      expect(report.gearLevelGaps, isEmpty);
      expect(report.isClean, isTrue, reason: report.render());
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
    Campaign broken(String locationsJson,
            {String? npcsJson, String? gearJson}) =>
        const CampaignLoader().load(
          id: 'broken',
          title: 'Broken',
          worldConfigJson: _read('world_config.json'),
          locationsJson: locationsJson,
          npcsJson: npcsJson ?? '{"npcs":[]}',
          gearJson: gearJson,
        );

    const oneRoom =
        '{"towns":{},"rooms":[{"room_id":"A","title":"A","description":"a"}]}';

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

    test('reports a rare item nothing drops', () {
      final c = broken(
        oneRoom,
        gearJson: '''
{"gear":[{"item_id":"i_ghost","name":"Ghost Blade","level":5,
 "rarity":"rare"}]}''',
      );
      expect(c.survey().unobtainableGear.single.name, 'Ghost Blade');
      expect(c.survey().render(), contains('Rare items nothing drops'));
    });

    test('reports loot carried by a creature nobody wrote', () {
      final c = broken(
        oneRoom,
        gearJson: '''
{"gear":[{"item_id":"i_ghost","name":"Ghost Blade","level":5,"rarity":"rare",
 "drops":[{"from":"c_nobody","chance":50}]}]}''',
      );
      final dangling = c.survey().danglingDrops.single;
      expect(dangling.item.name, 'Ghost Blade');
      expect(dangling.creatureId, 'c_nobody');
      // It names a source, so it is not also reported as having none.
      expect(c.survey().unobtainableGear, isEmpty);
    });

    test('says so when there is nothing outstanding', () {
      const clean = CampaignReport();
      expect(clean.isClean, isTrue);
      expect(clean.render(), 'Campaign data is complete.');
    });
  });
}
