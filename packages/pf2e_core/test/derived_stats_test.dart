import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'fixture_loader.dart';

void main() {
  late ImportedCharacter mira;
  late DerivedStats stats;

  setUp(() {
    mira = loadMira().character;
    stats = DerivedStats(mira);
  });

  group('ability modifiers', () {
    test('match the sheet', () {
      expect(mira.abilities.modifier(Ability.strength), 0);
      expect(mira.abilities.modifier(Ability.dexterity), 3);
      expect(mira.abilities.modifier(Ability.constitution), 2);
      expect(mira.abilities.modifier(Ability.intelligence), 4); // 19
      expect(mira.abilities.modifier(Ability.wisdom), 1);
      expect(mira.abilities.modifier(Ability.charisma), 1);
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
      // 8 + 6 x (6 + 2) = 56
      expect(stats.maxHp, 56);
    });

    test('speed applies the modifier the export carries', () {
      // Human base 25, Fleet +5.
      expect(mira.baseSpeed, 25);
      expect(mira.speedModifier, 5);
      expect(stats.speed, 30);
    });

    test('armour class recomputes to the exported total', () {
      // 10 + trained 8 + Dexterity 3 + a +1 rune 1 = 22
      expect(stats.armorClass, 22);
      expect(stats.armorClassMatchesExport, isTrue);
    });

    test('class DC is 10 + level + proficiency + key ability', () {
      // 10 + 6 + 2 + 4 = 22
      expect(mira.keyAbility, Ability.intelligence);
      expect(stats.classDc, 22);
    });

    test('perception and saves', () {
      expect(stats.perception.total, 9);
      expect(stats.fortitude.total, 10);
      expect(stats.reflex.total, 13);
      expect(stats.will.total, 11);
      expect(stats.reflex.proficiency, Proficiency.expert);
      expect(stats.fortitude.proficiency, Proficiency.trained);
    });
  });

  group('skills', () {
    test('trained skills add level plus rank', () {
      expect(stats.skill(CoreSkill.crafting)!.total, 12);
      expect(stats.skill(CoreSkill.society)!.total, 12);
      expect(stats.skill(CoreSkill.medicine)!.total, 9);
      expect(stats.skill(CoreSkill.nature)!.total, 9);
    });

    test('expert skills add level plus four', () {
      expect(stats.skill(CoreSkill.arcana)!.total, 14);
      expect(stats.skill(CoreSkill.occultism)!.total, 14);
      expect(stats.skill(CoreSkill.diplomacy)!.total, 11);
    });

    test('untrained skills add the ability modifier only, never the level', () {
      // The single easiest rule to lose: untrained contributes nothing, so
      // these are bare modifiers rather than level + modifier.
      expect(stats.skill(CoreSkill.acrobatics)!.total, 3); // Dex only
      expect(stats.skill(CoreSkill.stealth)!.total, 3); // Dex only
      expect(stats.skill(CoreSkill.thievery)!.total, 3); // Dex only
      expect(stats.skill(CoreSkill.performance)!.total, 1); // Cha only
      expect(stats.skill(CoreSkill.survival)!.total, 1); // Wis only
      expect(stats.skill(CoreSkill.athletics)!.total, 0);
    });

    test('every core skill matches the sheet', () {
      const expected = {
        CoreSkill.acrobatics: 3,
        CoreSkill.arcana: 14,
        CoreSkill.athletics: 0,
        CoreSkill.crafting: 12,
        CoreSkill.deception: 1,
        CoreSkill.diplomacy: 11,
        CoreSkill.intimidation: 1,
        CoreSkill.medicine: 9,
        CoreSkill.nature: 9,
        CoreSkill.occultism: 14,
        CoreSkill.performance: 1,
        CoreSkill.religion: 1,
        CoreSkill.society: 12,
        CoreSkill.stealth: 3,
        CoreSkill.survival: 1,
        CoreSkill.thievery: 3,
      };
      for (final entry in expected.entries) {
        expect(stats.skill(entry.key)!.total, entry.value,
            reason: '${entry.key.displayName} should be ${entry.value}');
      }
    });

    test('lores key off Intelligence', () {
      expect(stats.lore('Undead')!.total, 14); // expert
      expect(stats.lore('Religion')!.total, 12);
      expect(stats.lore('Academia')!.total, 12);
      expect(stats.lore('Local Undead')!.total, 12);
      expect(stats.lore('Herbalism')!.total, 4); // untrained, Int only
      expect(stats.lore('Legal')!.total, 4);
    });

    test('Religion the skill and Lore: Religion are independent', () {
      // Untrained in Religion at +1 while Lore: Religion is +12 — the kind of
      // asymmetry that defines a character and must survive the import.
      expect(stats.skill(CoreSkill.religion)!.total, 1);
      expect(stats.lore('Religion')!.total, 12);
    });

    test('allSkills covers the core sixteen plus every lore', () {
      expect(stats.allSkills.length, CoreSkill.values.length + 6);
    });
  });

  group('spellcasting', () {
    test('spell attack and DC per entry', () {
      final wizard =
          stats.spellcasting.firstWhere((s) => s.entry.name == 'Wizard');
      // 6 + 2 + 4 = 12, DC 22.
      expect(wizard.attackBonus, 12);
      expect(wizard.dc, 22);

      final witch =
          stats.spellcasting.firstWhere((s) => s.entry.name == 'Witch');
      expect(witch.attackBonus, 12);
      expect(witch.dc, 22);
    });
  });

  test('renderSheet produces a readable text sheet', () {
    final sheet = stats.renderSheet();
    expect(sheet, contains('Mira Quell'));
    expect(sheet, contains('AC 22'));
    expect(sheet, contains('HP 56'));
    expect(sheet, contains('Speed 30ft'));
    expect(sheet, contains('Lore: Undead'));
  });

  group('statByKey', () {
    test('resolves core skills, lores, saves and perception', () {
      expect(stats.statByKey('diplomacy')!.total, 11);
      expect(stats.statByKey('Arcana')!.total, 14);
      expect(stats.statByKey('  occultism  ')!.total, 14);
      expect(stats.statByKey('lore:undead')!.total, 14);
      expect(stats.statByKey('Lore: Local Undead')!.total, 12);
      expect(stats.statByKey('perception')!.total, 9);
      expect(stats.statByKey('fortitude')!.total, 10);
      expect(stats.statByKey('will')!.total, 11);
    });

    test('distinguishes a skill from a same-named lore', () {
      expect(stats.statByKey('religion')!.total, 1);
      expect(stats.statByKey('lore:religion')!.total, 12);
    });

    test('returns null for an unknown key rather than guessing', () {
      expect(stats.statByKey('basketweaving'), isNull);
      expect(stats.statByKey('lore:nonexistent'), isNull);
      expect(stats.statByKey(''), isNull);
    });
  });
}
