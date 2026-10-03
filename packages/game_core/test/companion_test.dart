import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;
late SpellBook _spells;

const _bren = 'npc_013_bren';
const _tamsin = 'npc_014_tamsin';
const _wren = 'npc_015_wren';

WorldSession _world(
  String room, {
  List<SessionActor>? actors,
  bool scale = false,
}) =>
    WorldSession(
      campaign: _campaign,
      actors: actors ?? [SessionActor(id: 'mira', character: loadMira())],
      roller: DiceRoller(3),
      roomId: room,
      spells: _spells,
      scaleFights: scale,
    );

/// [npc], standing in [room], taken on by Mira: walked over to rather
/// than found there, since some of them are a long road from the start.
WorldSession _withCompanion(String npc, {String room = 'WW_002_Deep'}) {
  final home = _campaign.npcs.byId(npc)!.location;
  final world = _world(home);
  world.recruit(npc);
  return WorldSession.restore(
    campaign: _campaign,
    actors: [world.primary],
    snapshot: {...world.snapshot(), 'roomId': room},
    spells: _spells,
  );
}

DerivedStats _sheet(String className, int level, {String ancestry = 'Human'}) {
  final result = const PathbuilderImporter().importMap(companionSheet(
    name: 'Test',
    recruit: Recruit(className: className, ancestry: ancestry),
    level: level,
  ));
  expect(result.report.warnings, isEmpty, reason: '$className $level');
  return DerivedStats(result.character);
}

void main() {
  setUpAll(() {
    _campaign = loadShatteredSeals();
    _spells = const CampaignLoader().readSpells(
        File('../../content/pf2e_remaster/spells.json').readAsStringSync());
  });

  group('a companion is built', () {
    test('on the numbers Pathbuilder would give a level 1 fighter', () {
      final s = _sheet('Fighter', 1);
      expect(s.maxHp, 21, reason: '8 human + 10 fighter + 3 Constitution');
      expect(s.armorClass, 19, reason: '10 + trained 3 + full plate 6');
      final sword = s.character.weapons.single;
      expect(sword.attackBonus, 9, reason: 'expert 5 + Strength 4');
      expect(sword.damageFormula, '1d12+4');
      expect(s.perception.total, 6, reason: 'expert 5 + Wisdom 1');
    });

    test('and keeps pace: runes, boosts and mastery by level 6', () {
      final s = _sheet('Fighter', 6);
      expect(s.maxHp, 92);
      expect(s.armorClass, 25, reason: 'a +1 suit from level 5');
      final sword = s.character.weapons.single;
      expect(sword.display, '+1 Striking Greatsword');
      expect(sword.attackBonus, 17, reason: 'master 10 + Strength 4 + 1');
      expect(sword.damageFormula, '2d12+4');
    });

    test('with weapon specialization from 7, and greater from 15', () {
      expect(_sheet('Fighter', 7).character.weapons.single.damageBonus, 7,
          reason: 'Strength 4 and master 3');
      expect(_sheet('Fighter', 15).character.weapons.single.damageBonus, 13,
          reason: 'Strength 5 and legendary 4, doubled');
    });

    test('a bow adds half Strength, and a thief adds Dexterity', () {
      expect(
          _sheet('Ranger', 1).character.weapons.single.damageFormula, '1d8+1');
      expect(
          _sheet('Rogue', 1).character.weapons.single.damageFormula, '1d6+4');
    });

    test('a barbarian fights raging: more damage, a point less AC', () {
      final s = _sheet('Barbarian', 1, ancestry: 'Dwarf');
      expect(s.maxHp, 25);
      expect(s.character.weapons.single.damageFormula, '1d12+6');
      expect(s.armorClass, 16, reason: '10 + 3 + Dex 1 + hide 3, less 1');
    });

    test('a wizard prepares a slot more than other casters', () {
      final s = _sheet('Wizard', 6);
      final casting = s.spellcasting.single;
      expect(casting.attackBonus, 12);
      expect(casting.dc, 22);
      expect(casting.entry.slotsPerDay.sublist(1, 4), [4, 4, 4]);
      final third = casting.entry.prepared.firstWhere((l) => l.rank == 3);
      expect(third.spells.toSet(), {'Fireball', 'Lightning Bolt'});
    });

    test('a cleric has Heal from every slot, and more from the font', () {
      final s = _sheet('Cleric', 6);
      final lists = s.spellcasting.single.entry.prepared;
      expect(lists.firstWhere((l) => l.rank == 3).spells, everyElement('Heal'));
      expect(lists.firstWhere((l) => l.rank == 3).spells, hasLength(8),
          reason: '3 slots and a font of 5');
    });

    test('for every recruit in the campaign, at every level', () {
      final recruits = [
        for (final npc in _campaign.npcs.all)
          if (npc.recruit != null) npc,
      ];
      expect(recruits.map((n) => n.recruit!.className).toSet(),
          {'Fighter', 'Ranger', 'Rogue', 'Barbarian', 'Wizard', 'Cleric'});
      for (final npc in recruits) {
        for (var level = 1; level <= 20; level++) {
          final result = const PathbuilderImporter().importMap(companionSheet(
              name: npc.name, recruit: npc.recruit!, level: level));
          expect(result.report.warnings, isEmpty,
              reason: '${npc.name} at $level');
          expect(result.character.level, level);
        }
      }
    });
  });

  group('recruiting', () {
    test('pays the fee, and they walk with the party from then on', () {
      final world = _world('MH_003_Tavern');
      final coin = world.inventory.coin;
      expect(world.recruitsHere.map((n) => n.id), [_bren]);
      final bren = world.recruit('bren');
      expect(bren.name, 'Bren Cask');
      expect(bren.character.level, 6, reason: 'the party\'s level');
      expect(world.actors.map((a) => a.id), ['mira', _bren]);
      expect(world.isCompanion(_bren), isTrue);
      expect(world.inventory.coin, coin - 2000);
      expect(world.vitalsOf(_bren).hp, world.vitalsOf(_bren).maxHp);
      expect(world.look().npcs.map((n) => n.id), isNot(contains(_bren)),
          reason: 'she is with you, not on the bench');
    });

    test('a companion parted with goes home, and comes back for free', () {
      final world = _world('MH_003_Tavern');
      world.recruit('bren');
      final coin = world.inventory.coin;
      world.dismiss('bren');
      expect(world.actors, hasLength(1));
      expect(world.look().npcs.map((n) => n.id), contains(_bren));
      final bren = _campaign.npcs.byId(_bren)!;
      expect(world.feeFor(bren), 0);
      world.recruit('bren');
      expect(world.inventory.coin, coin);
    });

    test('an imported character is not somebody to part with', () {
      final world = _world('MH_003_Tavern');
      expect(() => world.dismiss('mira'), throwsA(isA<InvalidMoveException>()));
    });

    test('nobody joins a party of four, or for coin the party has not got', () {
      final four = _world('MH_003_Tavern', actors: [
        for (var i = 0; i < 4; i++)
          SessionActor(id: 'pc$i', character: loadMira()),
      ]);
      expect(
          () => four.recruit('bren'),
          throwsA(isA<InvalidMoveException>().having(
              (e) => e.message, 'message', contains('4 of you already'))));

      final broke = _world('MH_003_Tavern');
      broke.inventory.spend(broke.inventory.coin);
      expect(
          () => broke.recruit('bren'),
          throwsA(isA<InvalidMoveException>()
              .having((e) => e.message, 'message', contains('wants 20 gp'))));
      expect(broke.actors, hasLength(1));
    });

    test('survives a save, rebuilt at the party\'s level as it is now', () {
      final world = _world('MH_003_Tavern');
      world.recruit('bren');
      world.vitalsOf(_bren).hp = 50;
      final snapshot = world.snapshot();

      final back = WorldSession.restore(
        campaign: _campaign,
        actors: [world.primary],
        snapshot: snapshot,
        spells: _spells,
      );
      expect(back.actors.map((a) => a.id), ['mira', _bren]);
      expect(back.isCompanion(_bren), isTrue);
      expect(back.vitalsOf(_bren).hp, 50);

      // Mira levelled up in Pathbuilder and was re-imported.
      final seven = const PathbuilderImporter()
          .importJson(loadMiraPayload()
              .replaceFirst(RegExp(r'"level":\s*6'), '"level": 7'))
          .character;
      final levelled = WorldSession.restore(
        campaign: _campaign,
        actors: [SessionActor(id: 'mira', character: seven)],
        snapshot: snapshot,
        spells: _spells,
      );
      expect(levelled.companions.single.character.level, 7);
      expect(levelled.feeFor(_campaign.npcs.byId(_bren)!), 0,
          reason: 'already paid');
    });

    test('a companion counts toward the party fights are scaled for', () {
      final world = _withCompanion(_bren);
      world.scaleFights = true;
      final fight = world.beginEncounter();
      expect(fight.enemies.map((e) => e.name), ['Hollow Thrall'],
          reason: 'one of two thralls for two, and not weakened');
      expect(fight.party.map((c) => c.id).toSet(), {'mira', _bren});
    });
  });

  group('in a fight', () {
    Combatant advanceTo(EncounterSession fight, String id) {
      for (var i = 0; i < 20 && fight.current.id != id; i++) {
        fight.endTurn();
      }
      expect(fight.current.id, id);
      return fight.current;
    }

    test('a bow reaches across the field; a scythe does not', () {
      final fight = _withCompanion(_tamsin).beginEncounter();
      final tamsin = advanceTo(fight, _tamsin);
      expect(tamsin.reachZones, fight.zones.length - 1);
      expect(fight.combatantById('mira')!.reachZones, 0);
      expect(fight.targetsInReach(), isNotEmpty,
          reason: 'the thralls come on from near, in bowshot');
    });

    test('Heal brings a fallen ally back to their feet', () {
      final fight = _withCompanion(_wren).beginEncounter();
      advanceTo(fight, _wren);
      final mira = fight.combatantById('mira')!;
      mira.takeDamage(mira.hp);
      expect(mira.isDown, isTrue);

      final heal = fight.castOptions().firstWhere((o) => o.spell.heals);
      expect(fight.aimsFor(heal).first.target.id, 'mira',
          reason: 'the worst hurt first');
      final result = fight.cast('Heal', targetId: 'mira');
      final mended = result.mended.single;
      expect(mended.target.id, 'mira');
      expect(mended.healed, greaterThan(0));
      expect(mended.revived, isTrue);
      expect(mira.isDown, isFalse);
      expect(result.hits, isEmpty, reason: 'nobody was struck');
    });
  });

  group('healing between fights', () {
    test('the cleric casts Heal on whoever is worst hurt', () {
      final world = _withCompanion(_wren, room: 'MH_004_Temple');
      world.vitalsOf('mira').hp = 10;
      final before = world
          .castOptions(_wren)
          .where((o) => o.spell.heals)
          .fold(0, (n, o) => n + o.left);

      final cast = world.castHealing('heal');
      expect(cast.caster.id, _wren);
      expect(cast.patient.id, 'mira');
      expect(cast.option.rank, 3, reason: 'the highest rank left');
      expect(cast.healed, greaterThan(0));
      expect(world.vitalsOf('mira').hp, 10 + cast.healed);
      final after = world
          .castOptions(_wren)
          .where((o) => o.spell.heals)
          .fold(0, (n, o) => n + o.left);
      expect(after, before - 1);
    });

    test('says so when nobody is hurt, or nobody can cast it', () {
      final world = _withCompanion(_wren, room: 'MH_004_Temple');
      expect(() => world.castHealing('heal', who: 'mira'),
          throwsA(isA<InvalidMoveException>()));
      expect(
          () => _world('MH_004_Temple').castHealing('heal'),
          throwsA(isA<InvalidMoveException>().having(
              (e) => e.message, 'message', contains('Nobody in the party'))));
    });
  });
}
