import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;

const _minor = 'g_033_hearth_water_minor';
const _lesser = 'g_034_hearth_water_lesser';

WorldSession _world({
  String room = 'MH_001_Square',
  bool withSela = false,
  int seed = 3,
  List<String> carrying = const [],
}) {
  final world = WorldSession(
    campaign: _campaign,
    actors: [
      SessionActor(id: 'korash', character: loadKorash()),
      if (withSela) SessionActor(id: 'sela', character: loadSela()),
    ],
    roller: DiceRoller(seed),
    roomId: room,
  );
  carrying.forEach(world.inventory.add);
  return world;
}

/// Ends turns until it is [id]'s, so a test can act as them.
void _turnOf(EncounterSession fight, String id) {
  var guard = 0;
  while (!fight.isOver && fight.current.id != id && guard++ < 20) {
    fight.endTurn();
  }
  expect(fight.current.id, id);
}

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  group('out of a fight', () {
    test('heals whoever is worst hurt, and the draught is gone', () {
      final world = _world(withSela: true, carrying: [_lesser]);
      world.vitalsOf('korash').hp = 60; // 60/70 is the lesser hurt
      world.vitalsOf('sela').hp = 5;
      final result = world.use('lesser hearth-water');
      expect(result.target, contains('Sela'));
      expect(result.onSelf, isTrue);
      expect(result.roll.expression.toString(), '2d8+5');
      expect(result.healed, result.roll.total);
      expect(world.vitalsOf('sela').hp, 5 + result.healed);
      expect(world.inventory.countOf(_lesser), 0);
    });

    test('goes to whoever it is given to', () {
      final world = _world(withSela: true, carrying: [_minor]);
      world.vitalsOf('korash').hp = 10;
      world.vitalsOf('sela').hp = world.vitalsOf('sela').maxHp - 1;
      final result = world.use('minor hearth-water', who: 'sela');
      expect(result.target, contains('Sela'));
      expect(result.healed, 1, reason: 'no further than full');
      expect(world.vitalsOf('korash').hp, 10);
    });

    test('is not wasted on somebody whole', () {
      final world = _world(carrying: [_minor]);
      // Nobody hurt at all, and nobody hurt by name.
      expect(() => world.use('hearth-water'),
          throwsA(isA<InvalidMoveException>()));
      expect(
          () => world.use('hearth-water', who: 'korash'),
          throwsA(isA<InvalidMoveException>()
              .having((e) => e.message, 'message', contains('not hurt'))));
      expect(world.inventory.countOf(_minor), 1, reason: 'still in the pack');
    });

    test('says why something cannot be used by hand', () {
      final world = _world(carrying: [
        'g_003_charm_of_iron_nails',
        'w_001_guard_sword',
        'g_007_last_shift_lamp',
      ]);
      world.vitalsOf('korash').hp = 10;
      String refusal(String what) {
        try {
          world.use(what);
        } on InvalidMoveException catch (e) {
          return e.message;
        }
        fail('"$what" was used');
      }

      // A consumable the engine cannot trigger says what its terms are.
      expect(refusal('charm'), contains('not used by hand'));
      expect(refusal('charm'), contains('fail a save against a shadow'));
      expect(refusal('guard sword'), contains('Wield it'));
      expect(refusal('lamp'), contains('while it is carried'));
      expect(world.inventory.countOf('g_003_charm_of_iron_nails'), 1);
    });

    test('rolls on the world dice, so a seed replays it', () {
      int heal() {
        final world = _world(seed: 11, carrying: [_lesser]);
        world.vitalsOf('korash').hp = 1;
        return world.use('lesser hearth-water').healed;
      }

      expect(heal(), heal());
    });
  });

  group('in a fight', () {
    test('drinking is one action, and what is drunk is gone afterwards', () {
      final world = _world(room: 'WW_002_Deep', carrying: [_lesser]);
      world.vitalsOf('korash').hp = 20;
      final fight = world.beginEncounter();
      _turnOf(fight, 'korash');
      final before = fight.current.hp;
      final actions = fight.actionsLeft;
      final result = fight.use('lesser hearth-water');
      expect(fight.actionsLeft, actions - 1);
      expect(fight.current.hp, before + result.healed);
      expect(world.inventory.countOf(_lesser), 0);
    });

    test('gets a fallen ally back on their feet', () {
      final world =
          _world(room: 'WW_002_Deep', withSela: true, carrying: [_lesser]);
      final fight = world.beginEncounter();
      final sela = fight.combatantById('sela')!..hp = 0;
      _turnOf(fight, 'korash');
      expect(sela.isDown, isTrue);

      final result = fight.use('lesser hearth-water', targetId: 'sela');
      expect(result.onSelf, isFalse);
      expect(result.revived, isTrue);
      expect(sela.isDown, isFalse);
      expect(sela.hp, result.healed);
    });

    test('an ally has to be within reach', () {
      final world =
          _world(room: 'WW_002_Deep', withSela: true, carrying: [_lesser]);
      final fight = world.beginEncounter();
      final sela = fight.combatantById('sela')!..hp = 1;
      _turnOf(fight, 'korash');
      sela.zoneIndex = fight.current.zoneIndex + 1;
      expect(
          () => fight.use('hearth-water', targetId: 'sela'),
          throwsA(isA<InvalidActionException>()
              .having((e) => e.message, 'message', contains('out of reach'))));
      expect(world.inventory.countOf(_lesser), 1);
    });

    test('takes an action to spare', () {
      final world = _world(
          room: 'WW_002_Deep', carrying: [_minor, _minor, _minor, _minor]);
      world.vitalsOf('korash').hp = 5;
      final fight = world.beginEncounter();
      _turnOf(fight, 'korash');
      fight.current.hp = 5;
      for (var i = 0; i < EncounterSession.actionsPerTurn; i++) {
        fight.use('hearth-water');
      }
      expect(() => fight.use('hearth-water'),
          throwsA(isA<InvalidActionException>()));
      expect(world.inventory.countOf(_minor), 1);
    });
  });

  group('the data', () {
    test('Hearth-Water heals as a healing potion of its level does', () {
      final grades = {
        _minor: (level: 1, gp: 4, heal: '1d8'),
        _lesser: (level: 3, gp: 12, heal: '2d8+5'),
        'g_035_hearth_water_moderate': (level: 6, gp: 50, heal: '3d8+10'),
        'g_036_hearth_water_greater': (level: 12, gp: 400, heal: '6d8+20'),
        'g_037_hearth_water_major': (level: 18, gp: 5000, heal: '8d8+30'),
      };
      for (final MapEntry(key: id, value: grade) in grades.entries) {
        final item = _campaign.gear.byId(id)!;
        expect(item.level, grade.level, reason: id);
        expect(item.price, grade.gp * 100, reason: id);
        expect(item.use!.heal.toString(), grade.heal, reason: id);
        expect(item.use!.actions, 1, reason: id);
      }
    });

    test('Jory sells it, the dearer grades once the road is open', () {
      final cart = _campaign.economy.shopKeptBy('npc_009_jory')!;
      expect(cart.onSaleFor(const {}),
          containsAll([_minor, _lesser, 'g_035_hearth_water_moderate']));
      expect(cart.onSaleFor(const {}),
          isNot(contains('g_036_hearth_water_greater')));
      expect(cart.onSaleFor({'Unlock_Travel_to_Valorheim'}),
          contains('g_036_hearth_water_greater'));
      expect(cart.onSaleFor({'boss_defeated_malachai_vex'}),
          contains('g_037_hearth_water_major'));
    });

    test('every consumable either can be used, or says when it is spent', () {
      for (final item in _campaign.gear.all) {
        if (!item.isConsumable) continue;
        expect(item.use != null || item.special != null, isTrue,
            reason: item.name);
      }
    });

    group('the loader refuses', () {
      GearTable read(String item) => const CampaignLoader()
          .readGear('{"gear": [{"item_id": "x", "name": "X", $item}]}');

      test('a use on something that is not used up', () {
        expect(() => read('"use": {"heal": "1d8"}'),
            throwsA(isA<CampaignFormatException>()));
      });

      test('a heal it cannot roll', () {
        expect(() => read('"traits": ["consumable"], "use": {"heal": "lots"}'),
            throwsA(isA<CampaignFormatException>()));
      });

      test('more actions than a turn has', () {
        expect(
            () => read('"traits": ["consumable"], '
                '"use": {"heal": "1d8", "actions": 4}'),
            throwsA(isA<CampaignFormatException>()));
      });
    });
  });
}
