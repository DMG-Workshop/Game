import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'fixture_loader.dart';

void main() {
  late ImportedCharacter korash;
  late DerivedStats stats;

  setUp(() {
    korash = loadKorash().character;
    stats = DerivedStats(korash);
  });

  group('ability modifiers', () {
    test('match the sheet', () {
      expect(korash.abilities.modifier(Ability.strength), 4);
      expect(korash.abilities.modifier(Ability.dexterity), 0);
      expect(korash.abilities.modifier(Ability.constitution), 2);
      expect(korash.abilities.modifier(Ability.intelligence), 4);
      expect(korash.abilities.modifier(Ability.wisdom), 0);
      expect(korash.abilities.modifier(Ability.charisma), 3);
    });

    test('floor rather than truncate below 10', () {
      // Truncating division would give 0 for a score of 9 and -1 for 7.
      const low = AbilityScores({
        Ability.strength: 9,
        Ability.dexterity: 8,
        Ability.constitution: 7,
        Ability.intelligence: 1,
      });
      expect(low.modifier(Ability.strength), -1);
      expect(low.modifier(Ability.dexterity), -1);
      expect(low.modifier(Ability.constitution), -2);
      expect(low.modifier(Ability.intelligence), -5);
    });
  });

  group('core statistics', () {
    test('hit points: ancestry + level x (class + Con)', () {
      // 10 + 6 x (8 + 2) = 70
      expect(stats.maxHp, 70);
    });

    test('speed applies the armour penalty', () {
      // Orc base 25, Full Plate -5.
      expect(korash.baseSpeed, 25);
      expect(korash.speedModifier, -5);
      expect(stats.speed, 20);
    });

    test('armour class recomputes to the exported total', () {
      expect(stats.armorClass, 25);
      expect(stats.armorClassMatchesExport, isTrue);
    });

    test('class DC is 10 + level + proficiency + key ability', () {
      // 10 + 6 + 2 + 4 = 22
      expect(korash.keyAbility, Ability.strength);
      expect(stats.classDc, 22);
    });

    test('perception and saves', () {
      expect(stats.perception.total, 8);
      expect(stats.fortitude.total, 12);
      expect(stats.reflex.total, 10);
      expect(stats.will.total, 10);
      expect(stats.fortitude.proficiency, Proficiency.expert);
      expect(stats.perception.proficiency, Proficiency.trained);
    });
  });

  group('skills', () {
    test('trained skills add level plus rank', () {
      expect(stats.skill(CoreSkill.arcana)!.total, 12);
      expect(stats.skill(CoreSkill.athletics)!.total, 12);
      expect(stats.skill(CoreSkill.occultism)!.total, 12);
      expect(stats.skill(CoreSkill.intimidation)!.total, 11);
      expect(stats.skill(CoreSkill.medicine)!.total, 8);
    });

    test('expert skills add level plus four', () {
      expect(stats.skill(CoreSkill.deception)!.total, 13);
      expect(stats.skill(CoreSkill.diplomacy)!.total, 13);
    });

    test('untrained skills add the ability modifier only, never the level', () {
      // The single easiest rule to lose: untrained contributes nothing, so
      // these are bare modifiers rather than level + modifier.
      expect(stats.skill(CoreSkill.crafting)!.total, 4); // Int only
      expect(stats.skill(CoreSkill.society)!.total, 4); // Int only
      expect(stats.skill(CoreSkill.performance)!.total, 3); // Cha only
      expect(stats.skill(CoreSkill.acrobatics)!.total, 0);
      expect(stats.skill(CoreSkill.nature)!.total, 0);
      expect(stats.skill(CoreSkill.stealth)!.total, 0);
      expect(stats.skill(CoreSkill.survival)!.total, 0);
      expect(stats.skill(CoreSkill.thievery)!.total, 0);
    });

    test('every core skill matches the sheet', () {
      const expected = {
        CoreSkill.acrobatics: 0,
        CoreSkill.arcana: 12,
        CoreSkill.athletics: 12,
        CoreSkill.crafting: 4,
        CoreSkill.deception: 13,
        CoreSkill.diplomacy: 13,
        CoreSkill.intimidation: 11,
        CoreSkill.medicine: 8,
        CoreSkill.nature: 0,
        CoreSkill.occultism: 12,
        CoreSkill.performance: 3,
        CoreSkill.religion: 0,
        CoreSkill.society: 4,
        CoreSkill.stealth: 0,
        CoreSkill.survival: 0,
        CoreSkill.thievery: 0,
      };
      for (final entry in expected.entries) {
        expect(stats.skill(entry.key)!.total, entry.value,
            reason: '${entry.key.displayName} should be ${entry.value}');
      }
    });

    test('lores key off Intelligence and match the sheet', () {
      expect(stats.lore('Undead')!.total, 14); // expert
      expect(stats.lore('Religion')!.total, 12);
      expect(stats.lore('First World')!.total, 12);
      expect(stats.lore('Local Undead')!.total, 12);
      expect(stats.lore('Herbalism')!.total, 4); // untrained, Int only
      expect(stats.lore('Legal')!.total, 4);
    });

    test('Religion the skill and Lore: Religion are independent', () {
      // Untrained in Religion at +0 while Lore: Religion is +12 — the kind of
      // asymmetry that defines a character and must survive the import.
      expect(stats.skill(CoreSkill.religion)!.total, 0);
      expect(stats.lore('Religion')!.total, 12);
    });

    test('allSkills covers the core sixteen plus every lore', () {
      expect(stats.allSkills.length, CoreSkill.values.length + 6);
    });
  });

  group('spellcasting', () {
    test('spell attack and DC per entry', () {
      final magus =
          stats.spellcasting.firstWhere((s) => s.entry.name == 'Magus');
      // 6 + 2 + 4 = 12, DC 22.
      expect(magus.attackBonus, 12);
      expect(magus.dc, 22);

      final necro =
          stats.spellcasting.firstWhere((s) => s.entry.name == 'Necromancer');
      expect(necro.attackBonus, 12);
      expect(necro.dc, 22);
    });
  });

  test('renderSheet produces a readable text sheet', () {
    final sheet = stats.renderSheet();
    expect(sheet, contains('Korash Blackearth'));
    expect(sheet, contains('AC 25'));
    expect(sheet, contains('HP 70'));
    expect(sheet, contains('Speed 20ft'));
    expect(sheet, contains('Lore: Undead'));
  });

  group('statByKey', () {
    test('resolves core skills, lores, saves and perception', () {
      expect(stats.statByKey('deception')!.total, 13);
      expect(stats.statByKey('Athletics')!.total, 12);
      expect(stats.statByKey('  occultism  ')!.total, 12);
      expect(stats.statByKey('lore:undead')!.total, 14);
      expect(stats.statByKey('Lore: Local Undead')!.total, 12);
      expect(stats.statByKey('perception')!.total, 8);
      expect(stats.statByKey('fortitude')!.total, 12);
      expect(stats.statByKey('will')!.total, 10);
    });

    test('distinguishes a skill from a same-named lore', () {
      expect(stats.statByKey('religion')!.total, 0);
      expect(stats.statByKey('lore:religion')!.total, 12);
    });

    test('returns null for an unknown key rather than guessing', () {
      expect(stats.statByKey('basketweaving'), isNull);
      expect(stats.statByKey('lore:nonexistent'), isNull);
      expect(stats.statByKey(''), isNull);
    });
  });
}
