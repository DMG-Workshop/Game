import 'ability.dart';
import 'proficiency.dart';

/// The Pathfinder 2e core skills and the ability each keys off.
enum CoreSkill {
  acrobatics('acrobatics', 'Acrobatics', Ability.dexterity),
  arcana('arcana', 'Arcana', Ability.intelligence),
  athletics('athletics', 'Athletics', Ability.strength),
  crafting('crafting', 'Crafting', Ability.intelligence),
  deception('deception', 'Deception', Ability.charisma),
  diplomacy('diplomacy', 'Diplomacy', Ability.charisma),
  intimidation('intimidation', 'Intimidation', Ability.charisma),
  medicine('medicine', 'Medicine', Ability.wisdom),
  nature('nature', 'Nature', Ability.wisdom),
  occultism('occultism', 'Occultism', Ability.intelligence),
  performance('performance', 'Performance', Ability.charisma),
  religion('religion', 'Religion', Ability.wisdom),
  society('society', 'Society', Ability.intelligence),
  stealth('stealth', 'Stealth', Ability.dexterity),
  survival('survival', 'Survival', Ability.wisdom),
  thievery('thievery', 'Thievery', Ability.dexterity);

  const CoreSkill(this.key, this.displayName, this.ability);

  final String key;
  final String displayName;
  final Ability ability;

  static CoreSkill? tryParse(String raw) {
    final needle = raw.trim().toLowerCase();
    for (final s in CoreSkill.values) {
      if (s.key == needle) return s;
    }
    return null;
  }
}

/// Keys inside `proficiencies` that are not skills.
///
/// Defences, perception, class DC, armour and weapon categories, and the four
/// spellcasting traditions all share that one flat map.
const nonSkillProficiencyKeys = <String>{
  'classDC',
  'perception',
  'fortitude',
  'reflex',
  'will',
  'heavy',
  'medium',
  'light',
  'unarmored',
  'advanced',
  'martial',
  'simple',
  'unarmed',
  'castingArcane',
  'castingDivine',
  'castingOccult',
  'castingPrimal',
};

/// Skill keys belonging to Starfinder 2e that leak into the Pathfinder
/// payload because Pathbuilder shares a schema across both systems.
///
/// They are ignored rather than treated as unknown, but a non-zero rank is
/// reported so a genuinely Starfinder build is not silently mangled.
const foreignSystemSkillKeys = <String>{'piloting', 'computers'};

/// A Lore subskill. Lore always keys off Intelligence.
class LoreSkill {
  const LoreSkill(this.subject, this.proficiency);

  final String subject;
  final Proficiency proficiency;

  String get displayName => 'Lore: $subject';

  @override
  String toString() => '$displayName (${proficiency.letter})';
}
