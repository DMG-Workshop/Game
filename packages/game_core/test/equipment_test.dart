import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

const _fixture = '../pf2e_core/test/fixtures/korash.json';

ImportedCharacter _korash() => const PathbuilderImporter()
    .importJson(File(_fixture).readAsStringSync())
    .character;

/// Korash with a different Dexterity, for the rules that only show up on a
/// character built the other way round. Our one fixture has Dex 10, and a cap
/// that never binds proves nothing.
ImportedCharacter _korashWithDex(int score) {
  final raw = jsonDecode(File(_fixture).readAsStringSync()) as Map;
  ((raw['build'] as Map)['abilities'] as Map)['dex'] = score;
  return const PathbuilderImporter().importJson(jsonEncode(raw)).character;
}

DerivedStats _stats([ImportedCharacter? character]) =>
    DerivedStats(character ?? _korash());

GearItem _weapon({
  String id = 'w_test',
  String damage = '1d10',
  int bonus = 0,
  Object? striking,
  List<String> traits = const ['martial'],
}) =>
    GearItem(
      id: id,
      name: 'Test Weapon',
      level: 1,
      type: 'weapon',
      description: 'x',
      traits: traits,
      stats: {
        'damage': damage,
        'bonus': bonus,
        'magic': true,
        if (striking != null) 'striking': striking,
      },
    );

GearItem _armor({
  int bonus = 0,
  int? acBonus,
  int? dexCap,
  List<String> traits = const ['heavy'],
}) =>
    GearItem(
      id: 'a_test',
      name: 'Test Armour',
      level: 1,
      type: 'armor',
      description: 'x',
      traits: traits,
      stats: {
        'bonus': bonus,
        'magic': true,
        if (acBonus != null) 'ac_bonus': acBonus,
        if (dexCap != null) 'dex_cap': dexCap,
      },
    );

GearTable _table(List<GearItem> items) => GearTable(items);

void main() {
  group('the kit they arrived in', () {
    test('matches the imported sheet exactly', () {
      final equipped = EquippedStats(_stats());
      expect(equipped.armorClass, 25);
      expect(equipped.attackBonus, 15);
      expect(equipped.damage.toString(), '2d10+4');
      expect(equipped.weaponLabel, '+1 Striking Scythe');
      expect(equipped.armorLabel, '+1 Full Plate');
    });
  });

  group('a weapon in hand', () {
    test('computes the same numbers Pathbuilder did for the same weapon', () {
      // The scythe as a campaign item: martial, d10, +1 potency, striking.
      // Pathbuilder says +15 for 2d10+4, and so must we — level 6, expert in
      // martial weapons (4+6), Strength +4, potency +1.
      final scythe = _weapon(
        damage: '1d10',
        bonus: 1,
        striking: 'striking',
        traits: const ['martial'],
      );
      final equipped = EquippedStats(_stats(), Loadout(weapon: scythe));
      expect(equipped.attackBonus, 15);
      expect(equipped.damage.toString(), '2d10+4');
    });

    test('a striking rune sets the number of dice', () {
      final base = EquippedStats(_stats(), Loadout(weapon: _weapon()));
      expect(base.damage.diceCount, 1);
      expect(
        EquippedStats(_stats(), Loadout(weapon: _weapon(striking: 'striking')))
            .damage
            .diceCount,
        2,
      );
      expect(
        EquippedStats(
                _stats(), Loadout(weapon: _weapon(striking: 'greaterStriking')))
            .damage
            .diceCount,
        3,
      );
      expect(
        EquippedStats(
                _stats(), Loadout(weapon: _weapon(striking: 'majorStriking')))
            .damage
            .diceCount,
        4,
      );
    });

    test('potency adds to the attack, not the damage', () {
      final plain = EquippedStats(_stats(), Loadout(weapon: _weapon()));
      final potent =
          EquippedStats(_stats(), Loadout(weapon: _weapon(bonus: 3)));
      expect(potent.attackBonus - plain.attackBonus, 3);
      expect(potent.damage.flatBonus, plain.damage.flatBonus);
    });

    test('proficiency comes from the weapon category', () {
      // Korash is an expert with martial weapons and untrained with advanced
      // ones, and untrained gives up the level entirely.
      final martial =
          EquippedStats(_stats(), Loadout(weapon: _weapon(traits: ['martial'])))
              .attackBonus;
      final advanced = EquippedStats(
          _stats(), Loadout(weapon: _weapon(traits: ['advanced']))).attackBonus;
      expect(martial, 14); // 6 level + 4 expert + 4 Strength
      expect(advanced, 4); // Strength alone
    });

    test('an uncategorised weapon is treated as martial', () {
      final vague = EquippedStats(
          _stats(), Loadout(weapon: _weapon(traits: ['finesse', 'magical'])));
      expect(vague.weaponCategory, 'martial');
    });

    test('Strength swings it, and finesse only changes the attack', () {
      final finesse = EquippedStats(
        _stats(_korashWithDex(20)),
        Loadout(weapon: _weapon(traits: ['martial', 'finesse'])),
      );
      // Dexterity +5 beats Strength +4, so the attack uses it.
      expect(finesse.attackAbility, Ability.dexterity);
      expect(finesse.attackBonus, 15);
      // Damage is still Strength: finesse does not change what a blow weighs.
      expect(finesse.damage.flatBonus, 4);
    });

    test('finesse stays with Strength when Strength is better', () {
      final finesse = EquippedStats(
        _stats(),
        Loadout(weapon: _weapon(traits: ['martial', 'finesse'])),
      );
      expect(finesse.attackAbility, Ability.strength);
    });

    test('a bow shoots with Dexterity and adds half Strength', () {
      final bow = EquippedStats(
        _stats(),
        Loadout(weapon: _weapon(traits: ['martial', 'propulsive'])),
      );
      expect(bow.attackAbility, Ability.dexterity);
      expect(bow.attackBonus, 10); // 6 + 4 + Dexterity 0
      expect(bow.damage.flatBonus, 2); // half of Strength +4
    });

    test('anything else thrown or shot adds no Strength at all', () {
      final thrown = EquippedStats(
        _stats(),
        Loadout(weapon: _weapon(traits: ['martial', 'ranged'])),
      );
      expect(thrown.damage.flatBonus, 0);
    });

    test('agile is read off the equipped weapon', () {
      expect(
        EquippedStats(_stats(), Loadout(weapon: _weapon(traits: ['agile'])))
            .isAgile,
        isTrue,
      );
      expect(
          EquippedStats(_stats(), Loadout(weapon: _weapon())).isAgile, isFalse);
    });
  });

  group('armour on', () {
    test('AC is rebuilt from the suit rather than the sheet', () {
      // 10 + (trained 2 + level 6) + Dexterity 0 (capped at 0) + 6 plate + 2
      // potency = 26, one better than the +1 full plate he came in.
      final equipped = EquippedStats(
        _stats(),
        Loadout(armor: _armor(bonus: 2, acBonus: 6, dexCap: 0)),
      );
      expect(equipped.armorClass, 26);
      expect(equipped.armorCategory, 'heavy');
    });

    test('the Dexterity cap actually binds', () {
      final nimble = _stats(_korashWithDex(18)); // +4
      final plate = EquippedStats(
        nimble,
        Loadout(armor: _armor(acBonus: 6, dexCap: 0, traits: ['heavy'])),
      );
      final leather = EquippedStats(
        nimble,
        Loadout(armor: _armor(acBonus: 2, dexCap: 3, traits: ['light'])),
      );
      expect(plate.dexterityToAc, 0);
      expect(leather.dexterityToAc, 3); // capped below the character's +4
      expect(leather.armorClass, plate.armorClass - 1);
    });

    test('proficiency comes from the armour category', () {
      // Korash is trained in every category, so the categories differ only by
      // what the suits themselves are worth.
      expect(
        EquippedStats(_stats(), Loadout(armor: _armor(traits: ['light'])))
            .armorCategory,
        'light',
      );
    });

    test('armour with nothing declared falls back to its category', () {
      final bare = EquippedStats(
        _stats(),
        Loadout(armor: _armor(traits: ['medium'])),
      );
      // Medium default: +4 AC, Dexterity capped at 1.
      expect(bare.armorClass, 10 + 8 + 0 + 4);
      expect(bare.dexterityCap, 1);
    });

    test('an uncategorised suit is treated as light', () {
      // Guessing heavy at a character who is not trained in it would cost
      // them their level in AC, which is a worse failure than guessing small.
      expect(
        EquippedStats(_stats(), Loadout(armor: _armor(traits: ['magical'])))
            .armorCategory,
        'light',
      );
    });
  });

  group('the pack', () {
    late GearTable table;
    late PartyInventory pack;

    setUp(() {
      table = _table([
        _weapon(id: 'w_axe'),
        _weapon(id: 'w_spear'),
        _armor(),
        const GearItem(
          id: 'g_charm',
          name: 'Lucky Charm',
          level: 1,
          type: 'talisman',
          description: 'x',
        ),
      ]);
      pack = PartyInventory(gear: table);
    });

    test('starts empty and takes what it is given', () {
      expect(pack.isEmpty, isTrue);
      expect(pack.add('w_axe'), isTrue);
      expect(pack.add('w_axe'), isFalse, reason: 'already in the pack');
      expect(pack.carried.single.id, 'w_axe');
    });

    test('refuses an item the campaign does not have', () {
      expect(() => pack.add('w_nothing'), throwsArgumentError);
    });

    test('finds what a player would type', () {
      pack.add('w_axe');
      expect(pack.find('w_axe')?.id, 'w_axe');
      expect(pack.find('test weapon')?.id, 'w_axe');
      expect(pack.find('WEAPON')?.id, 'w_axe');
      expect(pack.find('sandwich'), isNull);
    });

    test('equipping puts it in the slot its type belongs to', () {
      pack
        ..add('w_axe')
        ..add('a_test');
      expect(pack.equip('korash', 'w_axe').slot, EquipSlot.weapon);
      expect(pack.equip('korash', 'a_test').slot, EquipSlot.armor);
      final loadout = pack.loadoutFor('korash');
      expect(loadout.weapon?.id, 'w_axe');
      expect(loadout.armor?.id, 'a_test');
    });

    test('equipping over something returns what it displaced', () {
      pack
        ..add('w_axe')
        ..add('w_spear');
      pack.equip('korash', 'w_axe');
      final swap = pack.equip('korash', 'w_spear');
      expect(swap.replaced?.id, 'w_axe');
      // The old one is still in the pack; it was put away, not dropped.
      expect(pack.isCarrying('w_axe'), isTrue);
    });

    test('refuses something nobody is carrying', () {
      expect(
          () => pack.equip('korash', 'w_axe'), throwsA(isA<EquipException>()));
    });

    test('refuses something that is not worn or wielded', () {
      pack.add('g_charm');
      expect(
        () => pack.equip('korash', 'g_charm'),
        throwsA(isA<EquipException>().having(
            (e) => e.message, 'message', contains('stays in the pack'))),
      );
    });

    test('one item cannot be on two people at once', () {
      pack.add('w_axe');
      pack.equip('korash', 'w_axe');
      expect(
        () => pack.equip('elara', 'w_axe'),
        throwsA(isA<EquipException>()
            .having((e) => e.message, 'message', contains('korash'))),
      );
      expect(pack.holderOf('w_axe'), 'korash');
    });

    test('unequipping gives it back and leaves it carried', () {
      pack.add('w_axe');
      pack.equip('korash', 'w_axe');
      expect(pack.unequip('korash', EquipSlot.weapon)?.id, 'w_axe');
      expect(pack.loadoutFor('korash').weapon, isNull);
      expect(pack.isCarrying('w_axe'), isTrue);
      expect(pack.holderOf('w_axe'), isNull);
    });

    test('unequipping an empty slot is not an error', () {
      expect(pack.unequip('korash', EquipSlot.armor), isNull);
    });

    test('survives being written out and read back', () {
      pack
        ..add('w_axe')
        ..add('a_test');
      pack.equip('korash', 'w_axe');

      final restored =
          PartyInventory.fromJson(table, jsonDecode(jsonEncode(pack.toJson())));
      expect(restored.carried.map((i) => i.id), pack.carried.map((i) => i.id));
      expect(restored.loadoutFor('korash').weapon?.id, 'w_axe');
    });

    test('drops what the campaign no longer has rather than throwing', () {
      // A save written before an item was renamed should still load.
      final restored = PartyInventory.fromJson(table, {
        'carried': ['w_axe', 'w_deleted'],
        'equipped': {
          'korash': {'weapon': 'w_deleted'}
        },
      });
      expect(restored.carried.map((i) => i.id), ['w_axe']);
      expect(restored.loadoutFor('korash').weapon, isNull);
    });
  });
}
