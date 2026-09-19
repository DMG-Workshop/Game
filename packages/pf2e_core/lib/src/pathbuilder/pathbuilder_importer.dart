import 'dart:convert';

import '../model/ability.dart';
import '../model/character.dart';
import '../model/feat.dart';
import '../model/gear.dart';
import '../model/proficiency.dart';
import '../model/skill.dart';
import '../model/spellcasting.dart';
import '../model/variant_rules.dart';
import 'import_report.dart';
import 'json_util.dart';

/// A parsed character plus everything the importer noticed on the way.
class ImportResult {
  const ImportResult(this.character, this.report);

  final ImportedCharacter character;
  final ImportReport report;
}

/// Reads a Pathbuilder 2e export into [ImportedCharacter].
///
/// Accepts either the envelope returned by the JSON endpoint
/// (`{"success": true, "build": {...}}`) or a bare build object, since the
/// in-app "export to file" and the web endpoint do not agree on shape.
class PathbuilderImporter {
  const PathbuilderImporter();

  ImportResult importJson(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw PathbuilderImportException(
          'Payload is not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw PathbuilderImportException(
          'Expected a JSON object at the top level, got ${decoded.runtimeType}.');
    }
    return importMap(decoded.cast<String, Object?>());
  }

  ImportResult importMap(Map<String, Object?> root) {
    final report = ImportReport();

    // The endpoint wraps the build; the file export may not.
    final Map<String, Object?> build;
    if (root.containsKey('build')) {
      if (root.containsKey('success') && !readBool(root['success'])) {
        throw PathbuilderImportException(
            'Export reports success=false. The build code may have expired.',
            report);
      }
      build = readMap(root['build']);
    } else {
      report.info('bare_build',
          'Payload had no "build" wrapper; treating the root object as the build.');
      build = root;
    }

    if (build.isEmpty) {
      throw PathbuilderImportException(
          'Export contained no build data.', report);
    }

    final level = readInt(build['level'], fallback: 1);
    final abilities = _readAbilities(build, report);
    final proficiencies = _readProficiencies(build, report);
    final feats = _readFeats(build, report);
    final variantRules = _detectVariantRules(build, feats, report);

    final character = ImportedCharacter(
      name: readString(build['name'], fallback: 'Unnamed'),
      className: readString(build['class'], fallback: 'Unknown'),
      dualClassName: readOptionalString(build['dualClass']),
      level: level,
      xp: readInt(build['xp']),
      ancestry: readString(build['ancestry']),
      heritage: readString(build['heritage']),
      background: readString(build['background']),
      alignment: readOptionalString(build['alignment']),
      gender: readOptionalString(build['gender']),
      age: readOptionalString(build['age']),
      deity: readOptionalString(build['deity']),
      sizeName: readString(build['sizeName'], fallback: 'Medium'),
      keyAbility: _readKeyAbility(build, report),
      languages: readStringList(build['languages']),
      languagesRaw: readStringList(build['languages']),
      abilities: abilities,
      ancestryHp: readInt(readMap(build['attributes'])['ancestryhp']),
      classHp: readInt(readMap(build['attributes'])['classhp']),
      bonusHp: readInt(readMap(build['attributes'])['bonushp']),
      bonusHpPerLevel: readInt(readMap(build['attributes'])['bonushpPerLevel']),
      baseSpeed: readInt(readMap(build['attributes'])['speed'], fallback: 25),
      speedModifier: readInt(readMap(build['attributes'])['speedBonus']),
      defenceProficiencies: proficiencies.defences,
      skills: proficiencies.skills,
      lores: _readLores(build, report),
      feats: feats,
      classFeatures: _readClassFeatures(build, feats, report),
      weapons: _readWeapons(build, report),
      armor: _readArmor(build, report),
      equipment: _readEquipment(build, report),
      money: _readMoney(build),
      spellcasting: _readSpellcasting(build, report),
      focusPoints: readInt(build['focusPoints']),
      focus: _readFocus(build, report),
      reportedAc: _readAc(build, report),
      variantRules: variantRules,
      pets: _readNamedList(build['pets']),
      familiars: _readNamedList(build['familiars']),
    );

    _reportBuildHealth(character, report);
    return ImportResult(character, report);
  }

  // --- abilities -----------------------------------------------------------

  AbilityScores _readAbilities(
      Map<String, Object?> build, ImportReport report) {
    final raw = readMap(build['abilities']);
    final scores = <Ability, int>{};
    for (final ability in Ability.values) {
      final value = readOptionalInt(raw[ability.key]);
      if (value == null) {
        report.warn('missing_ability',
            'No score for ${ability.displayName}; defaulting to 10.');
        scores[ability] = 10;
      } else {
        scores[ability] = value;
      }
    }
    return AbilityScores(scores);
  }

  Ability _readKeyAbility(Map<String, Object?> build, ImportReport report) {
    final raw = readOptionalString(build['keyability']);
    final parsed = raw == null ? null : Ability.tryParse(raw);
    if (parsed == null) {
      report.warn('unknown_key_ability',
          'Key ability "${raw ?? ''}" not recognised; assuming Strength.');
      return Ability.strength;
    }
    return parsed;
  }

  // --- proficiencies -------------------------------------------------------

  _Proficiencies _readProficiencies(
      Map<String, Object?> build, ImportReport report) {
    final raw = readMap(build['proficiencies']);
    final defences = <String, Proficiency>{};
    final skills = <CoreSkill, Proficiency>{};

    for (final entry in raw.entries) {
      final value = readOptionalInt(entry.value);
      if (value == null) continue;
      final prof = _safeProficiency(value, entry.key, report);

      if (nonSkillProficiencyKeys.contains(entry.key)) {
        defences[entry.key] = prof;
        continue;
      }
      if (CoreSkill.tryParse(entry.key) case final skill?) {
        skills[skill] = prof;
        continue;
      }
      if (foreignSystemSkillKeys.contains(entry.key)) {
        if (prof != Proficiency.untrained) {
          report.warn(
              'foreign_system_skill',
              'Skill "${entry.key}" belongs to Starfinder 2e but has rank '
                  '${prof.displayName}. It was ignored.');
        }
        continue;
      }
      report.warn('unknown_proficiency',
          'Unrecognised proficiency key "${entry.key}" was ignored.');
    }

    for (final skill in CoreSkill.values) {
      skills.putIfAbsent(skill, () => Proficiency.untrained);
    }
    return _Proficiencies(defences, skills);
  }

  Proficiency _safeProficiency(int value, String key, ImportReport report) {
    try {
      return Proficiency.fromPathbuilder(value);
    } on ArgumentError {
      report.warn('bad_proficiency_value',
          'Proficiency "$key" had unexpected value $value; treated as untrained.');
      return Proficiency.untrained;
    }
  }

  List<LoreSkill> _readLores(Map<String, Object?> build, ImportReport report) {
    final out = <LoreSkill>[];
    for (final entry in readList(build['lores'])) {
      if (entry is! List || entry.isEmpty) {
        report.warn('bad_lore', 'Skipped a malformed lore entry.');
        continue;
      }
      final subject = readOptionalString(tupleAt(entry, 0));
      if (subject == null) continue;
      final rank = readInt(tupleAt(entry, 1));
      out.add(
          LoreSkill(subject, _safeProficiency(rank, 'Lore: $subject', report)));
    }
    return out;
  }

  // --- feats and features --------------------------------------------------

  List<ImportedFeat> _readFeats(
      Map<String, Object?> build, ImportReport report) {
    final out = <ImportedFeat>[];
    for (final entry in readList(build['feats'])) {
      if (entry is! List || entry.isEmpty) {
        report.warn('bad_feat', 'Skipped a malformed feat entry.');
        continue;
      }
      final name = readOptionalString(tupleAt(entry, 0));
      if (name == null) continue;
      out.add(ImportedFeat(
        name: name,
        choice: readOptionalString(tupleAt(entry, 1)),
        type: readString(tupleAt(entry, 2), fallback: 'Feat'),
        level: readInt(tupleAt(entry, 3), fallback: 1),
        source: readOptionalString(tupleAt(entry, 4)),
        choiceKind: readOptionalString(tupleAt(entry, 5)),
        parentKey: readOptionalString(tupleAt(entry, 6)),
      ));
    }
    return out;
  }

  /// `specials` and `feats` overlap — a feat such as Reactive Strike appears in
  /// both — so entries that duplicate a feat name are dropped here.
  List<String> _readClassFeatures(Map<String, Object?> build,
      List<ImportedFeat> feats, ImportReport report) {
    final featNames = {for (final f in feats) f.name.toLowerCase()};
    final out = <String>[];
    final duplicates = <String>[];
    for (final special in readStringList(build['specials'])) {
      if (featNames.contains(special.toLowerCase())) {
        duplicates.add(special);
        continue;
      }
      out.add(special);
    }
    if (duplicates.isNotEmpty) {
      report.info(
          'feature_feat_overlap',
          '${duplicates.length} class feature(s) also appear as feats and were '
              'de-duplicated: ${duplicates.join(', ')}.');
    }
    return out;
  }

  VariantRules _detectVariantRules(
    Map<String, Object?> build,
    List<ImportedFeat> feats,
    ImportReport report,
  ) {
    final dualClass = readOptionalString(build['dualClass']) != null;
    var freeArchetype = false;
    var ancestryParagon = false;
    for (final feat in feats) {
      final source = feat.source?.toLowerCase() ?? '';
      if (source.contains('free archetype')) freeArchetype = true;
      if (source.contains('ancestry paragon')) ancestryParagon = true;
    }
    final rules = VariantRules(
      dualClass: dualClass,
      freeArchetype: freeArchetype,
      ancestryParagon: ancestryParagon,
    );
    if (rules.any) {
      report.info('variant_rules', 'Variant rules detected: $rules.');
    }
    if (freeArchetype || ancestryParagon) {
      report.info(
          'variant_rules_inferred',
          'Free Archetype and Ancestry Paragon have no dedicated field and were '
              'inferred from feat source labels.');
    }
    return rules;
  }

  // --- gear ----------------------------------------------------------------

  List<ImportedWeapon> _readWeapons(
      Map<String, Object?> build, ImportReport report) {
    final out = <ImportedWeapon>[];
    for (final entry in readList(build['weapons'])) {
      final w = readMap(entry);
      if (w.isEmpty) continue;
      final name = readString(w['name'], fallback: 'Weapon');
      out.add(ImportedWeapon(
        name: name,
        display: readString(w['display'], fallback: name),
        quantity: readInt(w['qty'], fallback: 1),
        proficiencyCategory: readString(w['prof'], fallback: 'simple'),
        damageDie: readString(w['die'], fallback: 'd4'),
        potencyRune: readInt(w['pot']),
        // `str` here is the striking rune, not Strength.
        strikingRune: StrikingRune.parse(w['str']),
        material: readOptionalString(w['mat']),
        damageType: readString(w['damageType'], fallback: 'B'),
        attackBonus: readInt(w['attack']),
        damageBonus: readInt(w['damageBonus']),
        runes: readStringList(w['runes']),
      ));
    }
    return out;
  }

  List<ImportedArmor> _readArmor(
      Map<String, Object?> build, ImportReport report) {
    final out = <ImportedArmor>[];
    for (final entry in readList(build['armor'])) {
      final a = readMap(entry);
      if (a.isEmpty) continue;
      final name = readString(a['name'], fallback: 'Armor');
      out.add(ImportedArmor(
        name: name,
        display: readString(a['display'], fallback: name),
        quantity: readInt(a['qty'], fallback: 1),
        proficiencyCategory: readString(a['prof'], fallback: 'unarmored'),
        potencyRune: readInt(a['pot']),
        resilientRune: readOptionalString(a['res']),
        material: readOptionalString(a['mat']),
        worn: readBool(a['worn']),
        runes: readStringList(a['runes']),
      ));
    }
    final wornCount = out.where((a) => a.worn).length;
    if (wornCount > 1) {
      report.warn('multiple_worn_armor',
          '$wornCount suits of armour are flagged as worn.');
    }
    return out;
  }

  List<ImportedItem> _readEquipment(
      Map<String, Object?> build, ImportReport report) {
    final out = <ImportedItem>[];
    for (final entry in readList(build['equipment'])) {
      if (entry is List && entry.isNotEmpty) {
        final name = readOptionalString(tupleAt(entry, 0));
        if (name == null) continue;
        out.add(ImportedItem(name, readInt(tupleAt(entry, 1), fallback: 1)));
      } else if (entry is Map) {
        final m = entry.cast<String, Object?>();
        final name = readOptionalString(m['name']);
        if (name == null) continue;
        out.add(ImportedItem(name, readInt(m['qty'], fallback: 1)));
      }
    }
    return out;
  }

  Money _readMoney(Map<String, Object?> build) {
    final m = readMap(build['money']);
    return Money(
      cp: readInt(m['cp']),
      sp: readInt(m['sp']),
      gp: readInt(m['gp']),
      pp: readInt(m['pp']),
    );
  }

  ReportedArmorClass _readAc(Map<String, Object?> build, ImportReport report) {
    final ac = readMap(build['acTotal']);
    final reported = ReportedArmorClass(
      proficiencyBonus: readInt(ac['acProfBonus']),
      abilityBonus: readInt(ac['acAbilityBonus']),
      itemBonus: readInt(ac['acItemBonus']),
      total: readInt(ac['acTotal'], fallback: 10),
      shieldBonus: readOptionalInt(ac['shieldBonus']),
    );
    if (!reported.isSelfConsistent) {
      report.warn(
          'ac_mismatch',
          'Exported AC ${reported.total} does not match its own components '
              '(10 + ${reported.proficiencyBonus} + ${reported.abilityBonus} + '
              '${reported.itemBonus} = ${reported.recomputedTotal}).');
    }
    return reported;
  }

  // --- spellcasting --------------------------------------------------------

  List<SpellcastingEntry> _readSpellcasting(
      Map<String, Object?> build, ImportReport report) {
    final out = <SpellcastingEntry>[];
    for (final entry in readList(build['spellCasters'])) {
      final c = readMap(entry);
      if (c.isEmpty) continue;
      final name = readString(c['name'], fallback: 'Spellcasting');

      final traditionRaw = readString(c['magicTradition']);
      final tradition = MagicTradition.tryParse(traditionRaw);
      if (tradition == null && traditionRaw.isNotEmpty) {
        report.warn('unknown_tradition',
            'Unrecognised magic tradition "$traditionRaw" on $name.');
      }

      final abilityRaw = readString(c['ability'], fallback: 'int');
      final ability = Ability.tryParse(abilityRaw) ?? Ability.intelligence;

      out.add(SpellcastingEntry(
        name: name,
        tradition: tradition,
        castingType: readString(c['spellcastingType'], fallback: 'prepared'),
        ability: ability,
        proficiency: _safeProficiency(
            readInt(c['proficiency']), '$name casting', report),
        isInnate: readBool(c['innate']),
        slotsPerDay: [for (final s in readList(c['perDay'])) readInt(s)],
        known: _readSpellLists(c['spells'], report, name),
        prepared: _readSpellLists(c['prepared'], report, name),
        blendedSpells: readStringList(c['blendedSpells']),
      ));
    }

    if (out.length > 1) {
      final signatures = out.map((e) => e.slotsPerDay.join(',')).toSet();
      if (signatures.length == 1) {
        report.warn(
            'identical_slot_arrays',
            '${out.length} spellcasting entries report identical slots per day. '
                'Dual-class slot progressions are worth verifying by hand.');
      }
    }
    return out;
  }

  /// Reads `spells` / `prepared`, which are ordered arbitrarily — the reference
  /// payload lists ranks 0, 3, 2, 1 — so the rank must come from `spellLevel`
  /// and never from the array index.
  List<SpellRankList> _readSpellLists(
      Object? raw, ImportReport report, String casterName) {
    final out = <SpellRankList>[];
    for (final entry in readList(raw)) {
      final m = readMap(entry);
      if (m.isEmpty) continue;
      final rank = readOptionalInt(m['spellLevel']);
      if (rank == null) {
        report.warn('missing_spell_rank',
            'A spell list on $casterName had no spellLevel and was skipped.');
        continue;
      }
      out.add(SpellRankList(rank, readStringList(m['list'])));
    }
    out.sort((a, b) => a.rank.compareTo(b.rank));
    return out;
  }

  /// `focus` is nested tradition -> ability -> entry.
  List<FocusEntry> _readFocus(Map<String, Object?> build, ImportReport report) {
    final out = <FocusEntry>[];
    final focus = readMap(build['focus']);
    for (final traditionEntry in focus.entries) {
      final tradition = MagicTradition.tryParse(traditionEntry.key);
      if (tradition == null) {
        report.warn('unknown_focus_tradition',
            'Unrecognised focus tradition "${traditionEntry.key}".');
      }
      for (final abilityEntry in readMap(traditionEntry.value).entries) {
        final ability = Ability.tryParse(abilityEntry.key);
        if (ability == null) {
          report.warn('unknown_focus_ability',
              'Unrecognised focus ability "${abilityEntry.key}".');
          continue;
        }
        final data = readMap(abilityEntry.value);
        out.add(FocusEntry(
          tradition: tradition,
          ability: ability,
          abilityBonus: readInt(data['abilityBonus']),
          proficiency: _safeProficiency(readInt(data['proficiency']),
              'focus ${traditionEntry.key}', report),
          itemBonus: readInt(data['itemBonus']),
          cantrips: readStringList(data['focusCantrips']),
          spells: readStringList(data['focusSpells']),
        ));
      }
    }
    return out;
  }

  List<String> _readNamedList(Object? raw) {
    final out = <String>[];
    for (final entry in readList(raw)) {
      if (entry is Map) {
        final name = readOptionalString(entry.cast<String, Object?>()['name']);
        if (name != null) out.add(name);
      } else if (readOptionalString(entry) case final s?) {
        out.add(s);
      }
    }
    return out;
  }

  // --- post-import checks --------------------------------------------------

  void _reportBuildHealth(ImportedCharacter c, ImportReport report) {
    for (final unresolved in c.unresolvedChoices) {
      report.warn(
          'unresolved_choice',
          '"${unresolved.name}" (${unresolved.source}) grants a choice that has '
              'not been made yet.');
    }
    if (c.alignment != null) {
      report.info('legacy_alignment',
          'Payload carries a pre-Remaster alignment ("${c.alignment}"); ignored.');
    }

    // Composite parent keys are built by concatenation with no delimiter, so a
    // collision would silently re-parent a feat.
    final sources = <String, int>{};
    for (final feat in c.feats) {
      final key = feat.source;
      if (key == null) continue;
      sources[key] = (sources[key] ?? 0) + 1;
    }
    for (final entry in sources.entries) {
      if (entry.value > 1) {
        report.warn(
            'duplicate_feat_source',
            'Feat slot key "${entry.key}" appears ${entry.value} times; '
                'parent/child links using it are ambiguous.');
      }
    }
  }
}

class _Proficiencies {
  const _Proficiencies(this.defences, this.skills);

  final Map<String, Proficiency> defences;
  final Map<CoreSkill, Proficiency> skills;
}
