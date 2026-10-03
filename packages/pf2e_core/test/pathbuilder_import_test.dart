import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'fixture_loader.dart';

void main() {
  late ImportedCharacter mira;
  late ImportReport report;

  setUp(() {
    final result = loadMira();
    mira = result.character;
    report = result.report;
  });

  group('identity and sentinels', () {
    test('strips the leading whitespace Pathbuilder exports in names', () {
      expect(mira.name, 'Mira Quell');
    });

    test('maps the "Not set" sentinel to null', () {
      expect(mira.gender, isNull);
      expect(mira.age, isNull);
      expect(mira.deity, isNull);
    });

    test('keeps legacy alignment but flags it', () {
      expect(mira.alignment, 'N');
      expect(report.hasCode('legacy_alignment'), isTrue);
    });

    test('reads class, dual class and ancestry', () {
      expect(mira.className, 'Wizard');
      expect(mira.dualClassName, 'Witch');
      expect(mira.ancestry, 'Human');
      expect(mira.heritage, 'Skilled Human');
      expect(mira.background, 'Hermit');
      expect(mira.level, 6);
    });
  });

  group('variant rules', () {
    test('detects dual class from its dedicated field', () {
      expect(mira.variantRules.dualClass, isTrue);
    });

    test('infers Free Archetype and Ancestry Paragon from feat source labels',
        () {
      // Neither has a field of its own; both exist only as free text such as
      // "Free Archetype 2" and "Ancestry Paragon 3".
      expect(mira.variantRules.freeArchetype, isTrue);
      expect(mira.variantRules.ancestryParagon, isTrue);
      expect(report.hasCode('variant_rules_inferred'), isTrue);
    });
  });

  group('feats', () {
    test('reads all entries including short tuples', () {
      expect(mira.feats.length, 23);
      // Background-granted feats carry four elements rather than seven.
      final awarded =
          mira.feats.firstWhere((f) => f.name == 'Dubious Knowledge');
      expect(awarded.type, 'Awarded Feat');
      expect(awarded.level, 1);
      expect(awarded.source, isNull);
      expect(awarded.choiceKind, isNull);
    });

    test('captures a feat’s own selected option', () {
      final assurance = mira.feats.firstWhere((f) => f.name == 'Assurance');
      expect(assurance.choice, 'Medicine');
    });

    test('links granted feats to their parent through the composite key', () {
      // Each child's source is its parent's name and source run together:
      // "Natural AmbitionHuman Feat 1".
      final ambition =
          mira.feats.firstWhere((f) => f.name == 'Natural Ambition');
      expect(ambition.isParent, isTrue);
      expect(mira.childrenOf(ambition).map((f) => f.name), ['Reach Spell']);

      final adopted =
          mira.feats.firstWhere((f) => f.name == 'Adopted Ancestry');
      expect(adopted.choice, 'Elf');
      expect(
          mira.childrenOf(adopted).map((f) => f.name), ['Otherworldly Magic']);
    });

    test('flags a parent choice that was never resolved', () {
      final unresolved = mira.unresolvedChoices.map((f) => f.name);
      expect(unresolved, contains('Skill Mastery'));
      expect(unresolved, isNot(contains('Natural Ambition')));
      expect(report.hasCode('unresolved_choice'), isTrue);
    });
  });

  group('class features', () {
    test('de-duplicates features that also appear as feats', () {
      // Reach Spell is in both `feats` and `specials`.
      expect(mira.feats.map((f) => f.name), contains('Reach Spell'));
      expect(mira.classFeatures, isNot(contains('Reach Spell')));
      expect(report.hasCode('feature_feat_overlap'), isTrue);
    });

    test('keeps genuine features', () {
      expect(mira.classFeatures, contains('Arcane Bond'));
      expect(mira.classFeatures, contains('Arcane School'));
      expect(mira.classFeatures, contains('Patron'));
      expect(mira.classFeatures, contains('Hexes'));
    });
  });

  group('proficiencies', () {
    test('separates defences from skills', () {
      expect(mira.proficiencyFor('reflex'), Proficiency.expert);
      expect(mira.proficiencyFor('simple'), Proficiency.trained);
      expect(mira.proficiencyFor('unarmored'), Proficiency.trained);
      expect(mira.proficiencyFor('martial'), Proficiency.untrained);
      expect(mira.skills[CoreSkill.arcana], Proficiency.expert);
    });

    test('ignores Starfinder skills that leak into the schema', () {
      // `piloting` and `computers` are Starfinder 2e and must not be surfaced
      // as Pathfinder skills, nor reported as unknown keys.
      expect(report.hasCode('unknown_proficiency'), isFalse);
      expect(report.hasCode('foreign_system_skill'), isFalse); // both rank 0
    });

    test('every core skill is present even when absent from the payload', () {
      expect(mira.skills.length, CoreSkill.values.length);
    });
  });

  group('gear', () {
    test('reads the striking rune from the field named "str"', () {
      // `weapons[].str` is the striking rune; `abilities.str` is Strength.
      final staff = mira.weapons.single;
      expect(staff.strikingRune, StrikingRune.striking);
      expect(staff.strikingRune.diceCount, 2);
      expect(staff.damageFormula, '2d4');
      expect(staff.attackBonus, 9);
      expect(staff.potencyRune, 1);
      expect(staff.display, '+1 Striking Staff');
    });

    test('reads worn armour', () {
      expect(mira.wornArmor?.name, "Explorer's Clothing");
      expect(mira.wornArmor?.proficiencyCategory, 'unarmored');
      expect(mira.wornArmor?.potencyRune, 1);
    });

    test('reads money', () {
      expect(mira.money.gp, 270);
      expect(mira.money.totalInCopper, 27000);
    });
  });

  group('spellcasting', () {
    test('reads one entry per class', () {
      expect(mira.spellcasting.length, 2);
      final wizard = mira.spellcasting.first;
      expect(wizard.name, 'Wizard');
      expect(wizard.tradition, MagicTradition.arcane);
      expect(wizard.castingType, 'prepared');
      expect(wizard.ability, Ability.intelligence);
      expect(mira.spellcasting.last.tradition, MagicTradition.occult);
    });

    test('sorts spell lists by rank despite arbitrary payload order', () {
      // The Wizard `spells` array arrives ordered 0, 3, 2, 1.
      final wizard = mira.spellcasting.first;
      expect(wizard.known.map((l) => l.rank), [0, 1, 2, 3]);
      expect(wizard.knownAt(3)!.spells, ['Fireball', 'Lightning Bolt']);
    });

    test('distinguishes known spells from the prepared loadout', () {
      final wizard = mira.spellcasting.first;
      // See the Unseen is in the spellbook but was not prepared today.
      expect(wizard.knownAt(2)!.spells, contains('See the Unseen'));
      expect(wizard.preparedAt(2)!.spells, isNot(contains('See the Unseen')));
    });

    test('keeps duplicates in a prepared list', () {
      // Prepared is a slot list, not a set: two rank-1 slots hold Sure Strike.
      final witch = mira.spellcasting[1];
      expect(
          witch.preparedAt(1)!.spells, ['Sure Strike', 'Sure Strike', 'Fear']);
    });

    test('reads slots per day with cantrips at index zero', () {
      final wizard = mira.spellcasting.first;
      expect(wizard.slotsPerDay, [5, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0]);
      expect(wizard.cantripCount, 5);
      expect(wizard.highestRank, 3);
      expect(wizard.slotsAt(3), 3);
      expect(wizard.slotsAt(4), 0);
      expect(wizard.slotsAt(99), 0);
    });

    test('warns when dual-class entries report identical slot arrays', () {
      expect(report.hasCode('identical_slot_arrays'), isTrue);
    });
  });

  group('focus', () {
    test('uses the top-level pool, not the per-caster field', () {
      // Each spellCasters entry reports focusPoints 0; the real pool is 2.
      expect(mira.focusPoints, 2);
      for (final entry in mira.spellcasting) {
        expect(entry.name, isNotEmpty);
      }
    });

    test('flattens the tradition/ability nesting', () {
      expect(mira.focus.length, 2);
      final occult =
          mira.focus.firstWhere((f) => f.tradition == MagicTradition.occult);
      expect(occult.ability, Ability.intelligence);
      expect(occult.cantrips, ['Evil Eye']);
      expect(occult.spells, ['Cackle']);

      final arcane =
          mira.focus.firstWhere((f) => f.tradition == MagicTradition.arcane);
      expect(arcane.cantrips, isEmpty);
      expect(arcane.spells, ['Force Bolt']);
    });
  });

  group('payload shapes', () {
    test('accepts a bare build object without the success envelope', () {
      const bare = '{"name":"Test","class":"Fighter","level":1,'
          '"abilities":{"str":16,"dex":12,"con":14,"int":10,"wis":10,"cha":10},'
          '"attributes":{"ancestryhp":8,"classhp":10,"bonushp":0,'
          '"bonushpPerLevel":0,"speed":25,"speedBonus":0},'
          '"proficiencies":{"fortitude":4},"acTotal":{"acProfBonus":3,'
          '"acAbilityBonus":1,"acItemBonus":2,"acTotal":16,"shieldBonus":null}}';
      final result = const PathbuilderImporter().importJson(bare);
      expect(result.report.hasCode('bare_build'), isTrue);
      expect(result.character.name, 'Test');
      expect(DerivedStats(result.character).maxHp, 20); // 8 + 1 x (10 + 2)
    });

    test('rejects an export that reports failure', () {
      expect(
        () => const PathbuilderImporter()
            .importJson('{"success":false,"build":{}}'),
        throwsA(isA<PathbuilderImportException>()),
      );
    });

    test('rejects malformed JSON', () {
      expect(
        () => const PathbuilderImporter().importJson('not json'),
        throwsA(isA<PathbuilderImportException>()),
      );
    });

    test('flags an AC whose components do not add up', () {
      const inconsistent = '{"name":"Test","class":"Fighter","level":1,'
          '"abilities":{"str":16,"dex":12,"con":14,"int":10,"wis":10,"cha":10},'
          '"attributes":{},"proficiencies":{},'
          '"acTotal":{"acProfBonus":3,"acAbilityBonus":1,"acItemBonus":2,'
          '"acTotal":99,"shieldBonus":null}}';
      final result = const PathbuilderImporter().importJson(inconsistent);
      expect(result.report.hasCode('ac_mismatch'), isTrue);
    });
  });

  test('a clean import of a full build raises no errors', () {
    expect(report.hasErrors, isFalse);
  });
}
