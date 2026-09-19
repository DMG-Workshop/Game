import 'ability.dart';
import 'feat.dart';
import 'gear.dart';
import 'proficiency.dart';
import 'skill.dart';
import 'spellcasting.dart';
import 'variant_rules.dart';

/// AC as Pathbuilder reported it, kept alongside our own recomputation so the
/// two can be cross-checked on import.
class ReportedArmorClass {
  const ReportedArmorClass({
    required this.proficiencyBonus,
    required this.abilityBonus,
    required this.itemBonus,
    required this.total,
    required this.shieldBonus,
  });

  /// Already includes the character's level.
  final int proficiencyBonus;
  final int abilityBonus;
  final int itemBonus;
  final int total;
  final int? shieldBonus;

  /// 10 + proficiency + ability + item.
  int get recomputedTotal => 10 + proficiencyBonus + abilityBonus + itemBonus;

  bool get isSelfConsistent => recomputedTotal == total;
}

/// A character imported from a Pathbuilder 2e export, before any game rules
/// are applied. Values here are as-exported; see `DerivedStats` for the math.
class ImportedCharacter {
  const ImportedCharacter({
    required this.name,
    required this.className,
    required this.dualClassName,
    required this.level,
    required this.xp,
    required this.ancestry,
    required this.heritage,
    required this.background,
    required this.alignment,
    required this.gender,
    required this.age,
    required this.deity,
    required this.sizeName,
    required this.keyAbility,
    required this.languages,
    required this.abilities,
    required this.ancestryHp,
    required this.classHp,
    required this.bonusHp,
    required this.bonusHpPerLevel,
    required this.baseSpeed,
    required this.speedModifier,
    required this.defenceProficiencies,
    required this.skills,
    required this.lores,
    required this.feats,
    required this.classFeatures,
    required this.weapons,
    required this.armor,
    required this.equipment,
    required this.money,
    required this.spellcasting,
    required this.focusPoints,
    required this.focus,
    required this.reportedAc,
    required this.variantRules,
    required this.pets,
    required this.familiars,
    required this.languagesRaw,
  });

  final String name;
  final String className;

  /// Set only when the Dual Class variant is in use.
  final String? dualClassName;
  final int level;
  final int xp;
  final String ancestry;
  final String heritage;
  final String background;

  /// Legacy pre-Remaster field. Still present in every export even though
  /// alignment was removed from the rules.
  final String? alignment;

  /// Null when the export carried Pathbuilder's `"Not set"` sentinel.
  final String? gender;
  final String? age;
  final String? deity;

  final String sizeName;
  final Ability keyAbility;
  final List<String> languages;
  final List<String> languagesRaw;
  final AbilityScores abilities;

  final int ancestryHp;
  final int classHp;
  final int bonusHp;
  final int bonusHpPerLevel;

  /// Unarmoured base speed in feet.
  final int baseSpeed;

  /// Named `speedBonus` in the payload but normally a penalty, e.g. -5 for
  /// heavy armour.
  final int speedModifier;

  /// Perception, saves, class DC, armour and weapon categories, and the four
  /// casting traditions, keyed by their Pathbuilder names.
  final Map<String, Proficiency> defenceProficiencies;

  final Map<CoreSkill, Proficiency> skills;
  final List<LoreSkill> lores;
  final List<ImportedFeat> feats;

  /// Flat list of class features from `specials`, with entries that duplicate
  /// a feat already removed.
  final List<String> classFeatures;

  final List<ImportedWeapon> weapons;
  final List<ImportedArmor> armor;
  final List<ImportedItem> equipment;
  final Money money;

  final List<SpellcastingEntry> spellcasting;

  /// Authoritative focus pool size. The per-entry `focusPoints` fields inside
  /// `spellCasters` are unreliable and are not used.
  final int focusPoints;
  final List<FocusEntry> focus;

  final ReportedArmorClass reportedAc;
  final VariantRules variantRules;
  final List<String> pets;
  final List<String> familiars;

  Proficiency proficiencyFor(String key) =>
      defenceProficiencies[key] ?? Proficiency.untrained;

  /// The worn suit of armour, if any.
  ImportedArmor? get wornArmor =>
      armor.where((a) => a.worn).cast<ImportedArmor?>().firstWhere(
            (_) => true,
            orElse: () => null,
          );

  /// Feats granted by [parent], matched on the parent's `source` key.
  List<ImportedFeat> childrenOf(ImportedFeat parent) {
    final key = parent.source;
    if (key == null) return const [];
    return feats.where((f) => f.parentKey == key).toList();
  }

  /// Parent feats whose granted choice was never made — an unfinished build.
  List<ImportedFeat> get unresolvedChoices =>
      feats.where((f) => f.isParent && childrenOf(f).isEmpty).toList();

  @override
  String toString() => dualClassName == null
      ? '$name - $className $level'
      : '$name - $className/$dualClassName $level';
}
