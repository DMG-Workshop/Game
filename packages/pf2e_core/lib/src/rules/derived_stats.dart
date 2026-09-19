import '../model/ability.dart';
import '../model/character.dart';
import '../model/proficiency.dart';
import '../model/skill.dart';
import '../model/spellcasting.dart';

/// One fully resolved check bonus.
class CheckValue {
  const CheckValue({
    required this.label,
    required this.proficiency,
    required this.ability,
    required this.abilityModifier,
    required this.itemBonus,
    required this.total,
  });

  final String label;
  final Proficiency proficiency;
  final Ability ability;
  final int abilityModifier;
  final int itemBonus;
  final int total;

  /// The DC a creature rolls against for this statistic.
  int get dc => 10 + total;

  String get formatted => total >= 0 ? '+$total' : '$total';

  @override
  String toString() => '$label $formatted (${proficiency.letter})';
}

/// Spell attack and DC for one spellcasting entry.
class SpellcastingValue {
  const SpellcastingValue({
    required this.entry,
    required this.attackBonus,
    required this.dc,
  });

  final SpellcastingEntry entry;
  final int attackBonus;
  final int dc;

  @override
  String toString() => '${entry.name}: spell attack +$attackBonus, DC $dc';
}

/// Every number on a Pathfinder 2e character sheet, derived from an import.
///
/// The one rule that governs all of it: a check is the ability modifier plus
/// the proficiency term, where the proficiency term is the rank bonus *plus
/// the character's level* — unless untrained, which contributes nothing at
/// all. Getting that exception wrong inflates every untrained skill by the
/// character's level.
class DerivedStats {
  DerivedStats(this.character);

  final ImportedCharacter character;

  int get level => character.level;

  int _mod(Ability a) => character.abilities.modifier(a);

  /// Ability modifier plus proficiency term, plus any flat bonuses.
  int checkBonus({
    required Proficiency proficiency,
    required Ability ability,
    int itemBonus = 0,
    int miscBonus = 0,
  }) =>
      _mod(ability) +
      proficiency.totalBonusAtLevel(level) +
      itemBonus +
      miscBonus;

  CheckValue _check(
    String label,
    Proficiency proficiency,
    Ability ability, {
    int itemBonus = 0,
  }) =>
      CheckValue(
        label: label,
        proficiency: proficiency,
        ability: ability,
        abilityModifier: _mod(ability),
        itemBonus: itemBonus,
        total: checkBonus(
          proficiency: proficiency,
          ability: ability,
          itemBonus: itemBonus,
        ),
      );

  /// Ancestry HP, plus (class HP + Constitution modifier) at every level.
  int get maxHp {
    final perLevel = character.classHp +
        _mod(Ability.constitution) +
        character.bonusHpPerLevel;
    return character.ancestryHp + perLevel * level + character.bonusHp;
  }

  /// Base speed adjusted by armour and other modifiers.
  int get speed => character.baseSpeed + character.speedModifier;

  /// Armour class, recomputed from the exported components.
  int get armorClass => character.reportedAc.recomputedTotal;

  /// True when our recomputation disagrees with the exported total.
  bool get armorClassMatchesExport => armorClass == character.reportedAc.total;

  CheckValue get perception => _check(
        'Perception',
        character.proficiencyFor('perception'),
        Ability.wisdom,
      );

  CheckValue get fortitude => _check(
        'Fortitude',
        character.proficiencyFor('fortitude'),
        Ability.constitution,
      );

  CheckValue get reflex => _check(
        'Reflex',
        character.proficiencyFor('reflex'),
        Ability.dexterity,
      );

  CheckValue get will =>
      _check('Will', character.proficiencyFor('will'), Ability.wisdom);

  List<CheckValue> get saves => [fortitude, reflex, will];

  /// Class DC: 10 + level + proficiency + key ability modifier.
  int get classDc =>
      10 +
      checkBonus(
        proficiency: character.proficiencyFor('classDC'),
        ability: character.keyAbility,
      );

  /// Core skills in display order.
  List<CheckValue> get skills {
    final out = <CheckValue>[];
    for (final skill in CoreSkill.values) {
      final prof = character.skills[skill] ?? Proficiency.untrained;
      out.add(_check(skill.displayName, prof, skill.ability));
    }
    return out;
  }

  /// Lore subskills, always keyed off Intelligence.
  List<CheckValue> get lores => [
        for (final lore in character.lores)
          _check(lore.displayName, lore.proficiency, Ability.intelligence),
      ];

  /// Core skills and Lores together, sorted by display name the way the
  /// Pathbuilder sheet shows them.
  List<CheckValue> get allSkills =>
      [...skills, ...lores]..sort((a, b) => a.label.compareTo(b.label));

  CheckValue? skill(CoreSkill s) {
    final prof = character.skills[s] ?? Proficiency.untrained;
    return _check(s.displayName, prof, s.ability);
  }

  CheckValue? lore(String subject) {
    final needle = subject.trim().toLowerCase();
    for (final l in character.lores) {
      if (l.subject.toLowerCase() == needle) {
        return _check(l.displayName, l.proficiency, Ability.intelligence);
      }
    }
    return null;
  }

  /// Resolves a statistic from a string key, for data-driven content.
  ///
  /// Accepts a core skill (`deception`), a Lore subskill (`lore:undead`), a
  /// save (`fortitude`), or `perception`. Matching ignores case and
  /// surrounding whitespace. Returns null when nothing matches, so callers can
  /// report a bad key in their content rather than silently rolling the wrong
  /// statistic.
  CheckValue? statByKey(String key) {
    final needle = key.trim().toLowerCase();
    if (needle.isEmpty) return null;

    if (needle.startsWith('lore:')) {
      return lore(needle.substring(5));
    }

    switch (needle) {
      case 'perception':
        return perception;
      case 'fortitude':
      case 'fort':
        return fortitude;
      case 'reflex':
      case 'ref':
        return reflex;
      case 'will':
        return will;
    }

    if (CoreSkill.tryParse(needle) case final coreSkill?) {
      return skill(coreSkill);
    }
    return null;
  }

  /// Spell attack bonus and DC per spellcasting entry.
  List<SpellcastingValue> get spellcasting => [
        for (final entry in character.spellcasting)
          SpellcastingValue(
            entry: entry,
            attackBonus: checkBonus(
              proficiency: entry.proficiency,
              ability: entry.ability,
            ),
            dc: 10 +
                checkBonus(
                  proficiency: entry.proficiency,
                  ability: entry.ability,
                ),
          ),
      ];

  /// A compact plain-text sheet, useful for a text-first client and for
  /// eyeballing an import against Pathbuilder's own display.
  String renderSheet() {
    final b = StringBuffer()
      ..writeln(character.toString())
      ..writeln('${character.ancestry} ${character.heritage} '
          '| ${character.background} | ${character.sizeName}')
      ..writeln(character.abilities.toString())
      ..writeln('AC $armorClass  HP $maxHp  Speed ${speed}ft'
          '  Class DC $classDc')
      ..writeln(saves.map((s) => s.toString()).join('  '))
      ..writeln(perception.toString())
      ..writeln('--- Skills ---');
    for (final s in allSkills) {
      b.writeln(
          '  ${s.formatted.padLeft(3)} ${s.label} (${s.proficiency.letter})');
    }
    if (spellcasting.isNotEmpty) {
      b.writeln('--- Spellcasting ---');
      for (final sc in spellcasting) {
        b.writeln('  $sc');
      }
      b.writeln('  Focus points: ${character.focusPoints}');
    }
    if (character.weapons.isNotEmpty) {
      b.writeln('--- Weapons ---');
      for (final w in character.weapons) {
        b.writeln('  $w');
      }
    }
    return b.toString();
  }
}
