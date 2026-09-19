import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'fixture_loader.dart';

void main() {
  late ImportedCharacter korash;
  late ImportReport report;

  setUp(() {
    final result = loadKorash();
    korash = result.character;
    report = result.report;
  });

  group('identity and sentinels', () {
    test('strips the leading whitespace Pathbuilder exports in names', () {
      expect(korash.name, 'Korash Blackearth');
    });

    test('maps the "Not set" sentinel to null', () {
      expect(korash.gender, isNull);
      expect(korash.age, isNull);
      expect(korash.deity, isNull);
    });

    test('keeps legacy alignment but flags it', () {
      expect(korash.alignment, 'N');
      expect(report.hasCode('legacy_alignment'), isTrue);
    });

    test('reads class, dual class and ancestry', () {
      expect(korash.className, 'Magus');
      expect(korash.dualClassName, 'Necromancer');
      expect(korash.ancestry, 'Orc');
      expect(korash.heritage, 'Dragonblood');
      expect(korash.background, 'Undertaker');
      expect(korash.level, 6);
    });
  });

  group('variant rules', () {
    test('detects dual class from its dedicated field', () {
      expect(korash.variantRules.dualClass, isTrue);
    });

    test('infers Free Archetype and Ancestry Paragon from feat source labels',
        () {
      // Neither has a field of its own; both exist only as free text such as
      // "Free Archetype 4" and "Ancestry Paragon 3".
      expect(korash.variantRules.freeArchetype, isTrue);
      expect(korash.variantRules.ancestryParagon, isTrue);
      expect(report.hasCode('variant_rules_inferred'), isTrue);
    });
  });

  group('feats', () {
    test('reads all entries including short tuples', () {
      expect(korash.feats.length, 21);
      // Background-granted feats carry four elements rather than seven.
      final awarded =
          korash.feats.firstWhere((f) => f.name == 'Forensic Acumen');
      expect(awarded.type, 'Awarded Feat');
      expect(awarded.level, 1);
      expect(awarded.source, isNull);
      expect(awarded.choiceKind, isNull);
    });

    test('captures a feat’s own selected option', () {
      final assurance = korash.feats.firstWhere((f) => f.name == 'Assurance');
      expect(assurance.choice, 'Medicine');
    });

    test('links granted feats to their parent through the composite key', () {
      final reincarnation =
          korash.feats.firstWhere((f) => f.name == 'Reincarnation Feat');
      expect(reincarnation.isParent, isTrue);

      final children = korash.childrenOf(reincarnation);
      expect(children.map((f) => f.name), contains('Weight of Experience'));

      // The chain nests: Reincarnation Feat -> Weight of Experience ->
      // Assurance, with each parent key built by bare concatenation.
      final weight =
          korash.feats.firstWhere((f) => f.name == 'Weight of Experience');
      expect(
          korash.childrenOf(weight).map((f) => f.name), contains('Assurance'));
    });

    test('flags a parent choice that was never resolved', () {
      final unresolved = korash.unresolvedChoices.map((f) => f.name);
      expect(unresolved, contains('Basic Maneuver'));
      expect(report.hasCode('unresolved_choice'), isTrue);
    });
  });

  group('class features', () {
    test('de-duplicates features that also appear as feats', () {
      // Reactive Strike is in both `feats` and `specials`.
      expect(korash.feats.map((f) => f.name), contains('Reactive Strike'));
      expect(korash.classFeatures, isNot(contains('Reactive Strike')));
      expect(report.hasCode('feature_feat_overlap'), isTrue);
    });

    test('keeps genuine features', () {
      expect(korash.classFeatures, contains('Spellstrike'));
      expect(korash.classFeatures, contains('Arcane Cascade'));
      expect(korash.classFeatures, contains('Inexorable Iron'));
      expect(korash.classFeatures, contains('Puppeteer'));
    });
  });

  group('proficiencies', () {
    test('separates defences from skills', () {
      expect(korash.proficiencyFor('fortitude'), Proficiency.expert);
      expect(korash.proficiencyFor('martial'), Proficiency.expert);
      expect(korash.proficiencyFor('heavy'), Proficiency.trained);
      expect(korash.proficiencyFor('advanced'), Proficiency.untrained);
      expect(korash.skills[CoreSkill.deception], Proficiency.expert);
    });

    test('ignores Starfinder skills that leak into the schema', () {
      // `piloting` and `computers` are Starfinder 2e and must not be surfaced
      // as Pathfinder skills, nor reported as unknown keys.
      expect(report.hasCode('unknown_proficiency'), isFalse);
      expect(report.hasCode('foreign_system_skill'), isFalse); // both rank 0
    });

    test('every core skill is present even when absent from the payload', () {
      expect(korash.skills.length, CoreSkill.values.length);
    });
  });

  group('gear', () {
    test('reads the striking rune from the field named "str"', () {
      // `weapons[].str` is the striking rune; `abilities.str` is Strength.
      final scythe = korash.weapons.single;
      expect(scythe.strikingRune, StrikingRune.striking);
      expect(scythe.strikingRune.diceCount, 2);
      expect(scythe.damageFormula, '2d10+4');
      expect(scythe.attackBonus, 15);
      expect(scythe.potencyRune, 1);
      expect(scythe.display, '+1 Striking Scythe');
    });

    test('reads worn armour', () {
      expect(korash.wornArmor?.name, 'Full Plate');
      expect(korash.wornArmor?.proficiencyCategory, 'heavy');
      expect(korash.wornArmor?.potencyRune, 1);
    });

    test('reads money', () {
      expect(korash.money.gp, 270);
      expect(korash.money.totalInCopper, 27000);
    });
  });

  group('spellcasting', () {
    test('reads one entry per class', () {
      expect(korash.spellcasting.length, 2);
      final magus = korash.spellcasting.first;
      expect(magus.name, 'Magus');
      expect(magus.tradition, MagicTradition.arcane);
      expect(magus.castingType, 'prepared');
      expect(magus.ability, Ability.intelligence);
    });

    test('sorts spell lists by rank despite arbitrary payload order', () {
      // The Magus `spells` array arrives ordered 0, 3, 2, 1.
      final magus = korash.spellcasting.first;
      expect(magus.known.map((l) => l.rank), [0, 1, 2, 3]);
      expect(magus.knownAt(3)!.spells, ['Fireball']);
    });

    test('distinguishes known spells from the prepared loadout', () {
      final magus = korash.spellcasting.first;
      // Stupefy is in the spellbook but was not prepared today.
      expect(magus.knownAt(2)!.spells, contains('Stupefy'));
      expect(magus.preparedAt(2)!.spells, isNot(contains('Stupefy')));
    });

    test('keeps duplicates in a prepared list', () {
      // Prepared is a slot list, not a set: both rank-1 slots hold Sure Strike.
      final necro = korash.spellcasting[1];
      expect(necro.preparedAt(1)!.spells, ['Sure Strike', 'Sure Strike']);
    });

    test('reads slots per day with cantrips at index zero', () {
      final magus = korash.spellcasting.first;
      expect(magus.slotsPerDay, [5, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0]);
      expect(magus.cantripCount, 5);
      expect(magus.highestRank, 3);
      expect(magus.slotsAt(3), 2);
      expect(magus.slotsAt(4), 0);
      expect(magus.slotsAt(99), 0);
    });

    test('warns when dual-class entries report identical slot arrays', () {
      expect(report.hasCode('identical_slot_arrays'), isTrue);
    });
  });

  group('focus', () {
    test('uses the top-level pool, not the per-caster field', () {
      // Each spellCasters entry reports focusPoints 0; the real pool is 3.
      expect(korash.focusPoints, 3);
      for (final entry in korash.spellcasting) {
        expect(entry.name, isNotEmpty);
      }
    });

    test('flattens the tradition/ability nesting', () {
      expect(korash.focus.length, 2);
      final occult =
          korash.focus.firstWhere((f) => f.tradition == MagicTradition.occult);
      expect(occult.ability, Ability.intelligence);
      expect(occult.cantrips, ['Create Thrall', 'Thrall Charge']);
      expect(occult.spells, ['Life Tap', 'Necrotic Bomb']);

      final arcane =
          korash.focus.firstWhere((f) => f.tradition == MagicTradition.arcane);
      expect(arcane.cantrips, isEmpty);
      expect(arcane.spells, ['Thunderous Strike']);
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

  test('a clean import of a real build raises no errors', () {
    expect(report.hasErrors, isFalse);
  });
}
