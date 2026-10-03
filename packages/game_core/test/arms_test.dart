import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;
late SpellBook _spells;

const _fire = 'b_201_alchemists_fire_lesser';
const _fireballScroll = 'sc_246_scroll_fireball_3';
const _healWand = 'wd_261_wand_of_heal_1';
const _fireballWand = 'wd_265_wand_of_fireball_3';
const _fireStaff = 'st_282_greater_staff_of_fire';

WorldSession _world({
  String room = 'WW_002_Deep',
  List<String> carrying = const [],
  Set<String>? flags,
  List<SessionActor>? actors,
}) {
  final world = WorldSession(
    campaign: _campaign,
    actors: actors ?? [SessionActor(id: 'mira', character: loadMira())],
    roller: DiceRoller(3),
    roomId: room,
    spells: _spells,
    flags: flags,
    scaleFights: false,
  );
  carrying.forEach(world.inventory.add);
  return world;
}

/// The first party turn of the fight in [world].
EncounterSession _fight(WorldSession world) {
  final fight = world.beginEncounter();
  for (var i = 0; i < 10 && !fight.isPartyTurn; i++) {
    fight.endTurn();
  }
  return fight;
}

void main() {
  setUpAll(() {
    _campaign = loadShatteredSeals();
    _spells = const CampaignLoader().readSpells(
        File('../../content/pf2e_remaster/spells.json').readAsStringSync());
  });

  group('the arms and alchemy', () {
    test('fifty weapons, fifty things to use up, and wands and staffs', () {
      final ids = [for (final i in _campaign.gear.all) i.id];
      expect(
          ids.where((id) => RegExp(r'^w_1\d\d_').hasMatch(id)), hasLength(50));
      final used = [
        for (final i in _campaign.gear.all)
          if (const {'bomb', 'elixir', 'scroll'}.contains(i.type)) i,
      ];
      expect(used, hasLength(50));
      expect(used.every((i) => i.isConsumable), isTrue);
      expect(_campaign.gear.ofType('wand'), hasLength(17));
      expect(_campaign.gear.ofType('staff'), hasLength(10));
    });

    test('every spell an item holds is one the spell table has', () {
      for (final item in _campaign.gear.all) {
        for (final held in item.use?.spells ?? const <HeldSpell>[]) {
          final spell = _spells.byName(held.name);
          expect(spell, isNotNull, reason: '${item.name}: ${held.name}');
          expect(held.rank == 0 || held.rank >= spell!.rank, isTrue,
              reason: '${item.name} casts ${held.name} below its rank');
        }
      }
    });

    test('a bow from the rack is a bow: Dexterity, and the whole field', () {
      final bow = _campaign.gear.byId('w_125_longbow')!;
      expect(bow.hasTrait('ranged'), isTrue);
      expect(bow.level, 0);
      expect(bow.price, 600);
      final stats =
          EquippedStats(DerivedStats(loadMira()), Loadout(weapon: bow));
      expect(stats.isRanged, isTrue);
      expect(stats.attackAbility, Ability.dexterity);
    });

    test('the best of them are only found, on the bosses of the end', () {
      for (final id in [
        'w_149_quietus',
        'w_150_hammer_of_the_first_seal',
        'st_290_staff_of_the_unmaking',
      ]) {
        final item = _campaign.gear.byId(id)!;
        expect(item.rarity.mustBeFound, isTrue, reason: id);
        expect(item.isDrop, isTrue, reason: id);
      }
    });
  });

  group('shops', () {
    test('Harrow sells every plain weapon, the fletcher\'s bows among them',
        () {
      final wares = _world(room: 'MH_005_Forge').wares();
      final ids = wares.map((w) => w.item.id).toSet();
      for (var n = 101; n <= 130; n++) {
        expect(ids.any((id) => id.startsWith('w_${n}_')), isTrue,
            reason: 'w_$n');
      }
      expect(wares.first.item.level, 0);
    });

    test('the Watch sells bombs, the greater ones once the road opens', () {
      final early = _world(room: 'MH_002_GuardHall').wares();
      expect(early.map((w) => w.item.type).toSet(), {'bomb'});
      expect(early.map((w) => w.item.level).toSet(), {1, 3});
      final later = _world(room: 'MH_002_GuardHall', flags: {
        'Unlock_Travel_to_Valorheim',
        'Trigger_Sundering_Earthquake_Event',
      }).wares();
      expect(later, hasLength(24));
    });

    test('the temple shares elixirs, healing scrolls, wands and staffs', () {
      final wares = _world(room: 'MH_004_Temple').wares();
      expect(wares.map((w) => w.item.type).toSet(),
          {'elixir', 'scroll', 'wand', 'staff'});
      for (final w in wares.where((w) => w.item.type != 'elixir')) {
        expect(w.item.name, contains('Heal'), reason: w.item.name);
      }
    });

    test('two shops in one room: the traveller first, then whoever is asked',
        () {
      for (var seed = 1; seed <= 80; seed++) {
        final probe = WorldSession(
          campaign: _campaign,
          actors: [SessionActor(id: 'mira', character: loadMira())],
          roller: DiceRoller(seed),
        );
        if (probe.whereIs('npc_010_sal') != 'MH_004_Temple') continue;
        final world = WorldSession(
          campaign: _campaign,
          actors: [SessionActor(id: 'mira', character: loadMira())],
          roller: DiceRoller(seed),
          roomId: 'MH_004_Temple',
        );
        expect(world.shopsHere.map((s) => s.name),
            ["Sal Mercy's Mule", 'The Temple Alms-Table']);
        expect(world.shopHere!.name, "Sal Mercy's Mule");
        world.tradeWith('aldus');
        expect(world.shopHere!.name, 'The Temple Alms-Table');
        world.move('north');
        world.move('south');
        expect(world.shopHere!.keeperId, isNot('npc_003_aldus'),
            reason: 'walking off steps away from the counter');
        return;
      }
      fail('Sal never stopped at the temple');
    });
  });

  group('in a fight', () {
    test('a bomb is thrown, used up, and splashes even on a miss', () {
      var hits = 0;
      var misses = 0;
      for (var seed = 1; seed <= 30; seed++) {
        final world = WorldSession(
          campaign: _campaign,
          actors: [SessionActor(id: 'mira', character: loadMira())],
          roller: DiceRoller(seed),
          roomId: 'WW_002_Deep',
          spells: _spells,
          scaleFights: false,
        )..inventory.add(_fire);
        final fight = _fight(world);
        if (fight.throwTargets().isEmpty) continue;
        final before = fight.actionsLeft;
        final r = fight.throwBomb('alchemist\'s fire');
        expect(world.inventory.countOf(_fire), 0);
        expect(fight.actionsLeft, before - 1);
        expect(r.check.label, contains('thrown'));
        switch (r.check.degree) {
          case DegreeOfSuccess.criticalFailure:
            expect(r.damage, 0);
          case DegreeOfSuccess.failure:
            misses++;
            expect(r.damage, 1, reason: 'the splash');
          case _:
            hits++;
            expect(r.damage, r.damageRoll!.total + 1);
        }
      }
      expect(hits, greaterThan(0));
      expect(misses, greaterThan(0));
    });

    test('a scroll casts once and is gone', () {
      final world = _world(carrying: [_fireballScroll]);
      final fight = _fight(world);
      final option =
          fight.castOptions().firstWhere((o) => o.item?.id == _fireballScroll);
      expect(option.rank, 3);
      expect(option.left, 1);
      final result = fight.cast('Fireball', source: 'item:$_fireballScroll');
      expect(result.option.item?.id, _fireballScroll);
      expect(world.inventory.countOf(_fireballScroll), 0);
    });

    test('a wand casts once a day, and is ready again after rest', () {
      final world = _world(carrying: [_fireballWand]);
      var fight = _fight(world);
      fight.cast('Fireball', source: 'item:$_fireballWand');
      expect(world.inventory.countOf(_fireballWand), 1, reason: 'not used up');
      expect(world.itemUsesOf(_fireballWand), 1);
      expect(
          fight
              .castOptions()
              .firstWhere((o) => o.item?.id == _fireballWand)
              .isAvailable,
          isFalse);

      // Saved and loaded, the wand is still spent.
      final back = WorldSession.restore(
        campaign: _campaign,
        actors: world.actors,
        snapshot: world.snapshot(),
        spells: _spells,
      );
      expect(back.itemUsesOf(_fireballWand), 1);
    });

    test('a staff spends charges by rank, and a cantrip costs nothing', () {
      final world = _world(carrying: [_fireStaff]);
      final fight = _fight(world);
      final fromStaff = [
        for (final o in fight.castOptions())
          if (o.item?.id == _fireStaff) o,
      ];
      expect(fromStaff.map((o) => '${o.spell.name} ${o.rank}'),
          containsAll(['Ignition 3', 'Breathe Fire 2', 'Fireball 3']));
      expect(fromStaff.firstWhere((o) => o.spell.name == 'Ignition').cost,
          CastCost.cantrip);
      fight.cast('Fireball', source: 'item:$_fireStaff');
      expect(world.itemUsesOf(_fireStaff), 3, reason: '4 charges, 3 spent');
      final left = fight
          .castOptions()
          .where((o) => o.item?.id == _fireStaff && o.spell.name != 'Ignition');
      expect(left.every((o) => !o.isAvailable || o.rank <= 1), isTrue);
    });

    test('somebody with no magic of their own casts at the item\'s DC', () {
      final home = _campaign.npcs.byId('npc_013_bren')!.location;
      final hiring = _world(room: home);
      hiring.recruit('bren');
      final bren = hiring.companions.single;
      final pack = PartyInventory(gear: _campaign.gear)..add(_fireballWand);
      final options = itemCastOptions(bren, pack, {}, _spells);
      expect(options.single.dc, levelDc(7), reason: 'a level 7 wand');
      expect(options.single.attackBonus, levelDc(7) - 10);
    });
  });

  group('between fights', () {
    test('a wand of Heal mends somebody, once a day', () {
      final world = _world(room: 'MH_004_Temple', carrying: [_healWand]);
      world.vitalsOf('mira').hp = 20;
      final c = world.castHealing('heal', from: 'wand of heal');
      expect(c.option.item?.id, _healWand);
      expect(c.healed, greaterThan(0));
      expect(
          () => world.castHealing('heal', from: 'wand of heal'),
          throwsA(isA<InvalidMoveException>()
              .having((e) => e.message, 'message', contains('none of it'))));
      world.rest();
      expect(world.itemUsesOf(_healWand), 0);
    });

    test('a bomb is for a fight, and so is a scroll of Fireball', () {
      final world = _world(carrying: [_fire, _fireballScroll]);
      expect(
          () => world.use('alchemist\'s fire'),
          throwsA(isA<InvalidMoveException>()
              .having((e) => e.message, 'message', contains('in a fight'))));
      expect(
          () => world.use('scroll of fireball'),
          throwsA(isA<InvalidMoveException>()
              .having((e) => e.message, 'message', contains('for a fight'))));
    });
  });
}
