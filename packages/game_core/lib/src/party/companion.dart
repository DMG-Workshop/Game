import 'package:pf2e_core/pf2e_core.dart';

/// Somebody in the world who would join the party, and on what terms.
///
/// The campaign says who they are: a class, an ancestry, a fee. What they
/// can do comes from their class, built the way Pathbuilder would build it
/// at whatever level the party has reached, so a companion fights on the
/// same numbers and by the same rules as an imported character.
class Recruit {
  const Recruit({
    required this.className,
    required this.ancestry,
    this.heritage = '',
    this.background = '',
    this.fee = 0,
  });

  /// One of [CompanionKit.classes].
  final String className;
  final String ancestry;
  final String heritage;
  final String background;

  /// What they want before they come along, in copper. Paid once.
  final int fee;

  CompanionKit get kit => CompanionKit.forClass(className)!;
}

/// What a character of one class is good at, from level 1 to 20: the
/// scores they start with and boost, the proficiencies they gain and when,
/// the kit they carry, and the spells they prepare.
///
/// The proficiencies follow the class tables in the Player Core, as
/// `level: rank` pairs in Pathbuilder's numbering (2 trained, 4 expert, 6
/// master, 8 legendary). Feats are left out: the engine runs Strikes, spells
/// and saves, and a feat it cannot run would only be a word on the sheet.
class CompanionKit {
  const CompanionKit({
    required this.className,
    required this.classHp,
    required this.keyAbility,
    required this.scores,
    required this.boosts,
    required this.proficiencies,
    required this.skills,
    required this.weapon,
    this.armor,
    this.casting,
    this.specializationLevel = 7,
    this.extraSkillIncreases = false,
    this.rage = false,
    this.thief = false,
    this.specials = const [],
  });

  final String className;
  final int classHp;
  final String keyAbility;

  /// Ability scores at level 1.
  final Map<String, int> scores;

  /// The four abilities boosted at levels 5, 10, 15 and 20.
  final List<String> boosts;

  /// Pathbuilder proficiency key to `{level: rank}`.
  final Map<String, Map<int, int>> proficiencies;

  /// Trained at level 1; the first few are raised as the levels come.
  final List<String> skills;

  final CompanionWeapon weapon;
  final CompanionArmor? armor;
  final CompanionCasting? casting;

  /// When weapon specialization arrives: 7 for martial classes, 13 for
  /// casters. Greater specialization follows at 15 for the martial ones.
  final int specializationLevel;

  /// A rogue raises a skill every level, not every other.
  final bool extraSkillIncreases;

  /// A barbarian fights raging: more damage, a point less AC.
  final bool rage;

  /// A thief's finesse Strikes add Dexterity to damage, not Strength.
  final bool thief;

  final List<String> specials;

  static CompanionKit? forClass(String name) {
    final needle = name.trim().toLowerCase();
    for (final kit in classes) {
      if (kit.className.toLowerCase() == needle) return kit;
    }
    return null;
  }

  static const List<CompanionKit> classes = [
    fighter,
    ranger,
    rogue,
    barbarian,
    wizard,
    cleric,
  ];

  static const fighter = CompanionKit(
    className: 'Fighter',
    classHp: 10,
    keyAbility: 'str',
    scores: {'str': 18, 'dex': 14, 'con': 16, 'int': 10, 'wis': 12, 'cha': 10},
    boosts: ['str', 'con', 'dex', 'wis'],
    proficiencies: {
      'perception': {1: 4, 7: 6},
      'fortitude': {1: 4, 9: 6},
      'reflex': {1: 4, 15: 6},
      'will': {1: 2, 3: 4},
      'unarmored': {1: 2, 11: 4, 17: 6},
      'light': {1: 2, 11: 4, 17: 6},
      'medium': {1: 2, 11: 4, 17: 6},
      'heavy': {1: 2, 11: 4, 17: 6},
      'simple': {1: 4, 5: 6, 13: 8},
      'martial': {1: 4, 5: 6, 13: 8},
      'unarmed': {1: 4, 5: 6, 13: 8},
      'advanced': {1: 2, 5: 4, 13: 6},
      'classDC': {1: 2, 11: 4, 19: 6},
    },
    skills: ['athletics', 'intimidation', 'survival'],
    weapon: CompanionWeapon('Greatsword', 'martial', 'd12', 'S'),
    armor: CompanionArmor('Full Plate', 'heavy', ac: 6, dexCap: 0),
    specials: ['Attack of Opportunity', 'Bravery', 'Weapon Mastery'],
  );

  static const ranger = CompanionKit(
    className: 'Ranger',
    classHp: 10,
    keyAbility: 'dex',
    scores: {'str': 14, 'dex': 18, 'con': 14, 'int': 10, 'wis': 14, 'cha': 10},
    boosts: ['dex', 'con', 'wis', 'str'],
    proficiencies: {
      'perception': {1: 4, 7: 6, 15: 8},
      'fortitude': {1: 4, 11: 6},
      'reflex': {1: 4, 7: 6, 15: 8},
      'will': {1: 2, 3: 4},
      'unarmored': {1: 2, 11: 4, 19: 6},
      'light': {1: 2, 11: 4, 19: 6},
      'medium': {1: 2, 11: 4, 19: 6},
      'simple': {1: 2, 5: 4, 13: 6},
      'martial': {1: 2, 5: 4, 13: 6},
      'unarmed': {1: 2, 5: 4, 13: 6},
      'classDC': {1: 2, 9: 4, 17: 6},
    },
    skills: ['survival', 'nature', 'stealth', 'athletics'],
    weapon: CompanionWeapon('Longbow', 'martial', 'd8', 'P',
        ranged: true, propulsive: true),
    armor: CompanionArmor('Studded Leather', 'light', ac: 2, dexCap: 3),
    specials: ['Hunt Prey', 'Hunter\'s Edge', 'Evasion'],
  );

  static const rogue = CompanionKit(
    className: 'Rogue',
    classHp: 8,
    keyAbility: 'dex',
    scores: {'str': 10, 'dex': 18, 'con': 14, 'int': 12, 'wis': 12, 'cha': 14},
    boosts: ['dex', 'con', 'cha', 'wis'],
    proficiencies: {
      'perception': {1: 4, 7: 6, 13: 8},
      'fortitude': {1: 2, 9: 4},
      'reflex': {1: 4, 7: 6, 13: 8},
      'will': {1: 4, 17: 6},
      'unarmored': {1: 2, 13: 4, 19: 6},
      'light': {1: 2, 13: 4, 19: 6},
      'simple': {1: 2, 5: 4, 13: 6},
      // Trained in the rogue's martial weapons — rapier, shortsword,
      // shortbow — which is all of them a rogue picks up here.
      'martial': {1: 2, 5: 4, 13: 6},
      'unarmed': {1: 2, 5: 4, 13: 6},
      'classDC': {1: 2, 11: 4, 19: 6},
    },
    skills: ['thievery', 'stealth', 'acrobatics', 'deception', 'society'],
    weapon: CompanionWeapon('Rapier', 'martial', 'd6', 'P', finesse: true),
    armor: CompanionArmor('Leather Armor', 'light', ac: 1, dexCap: 4),
    extraSkillIncreases: true,
    thief: true,
    specials: ['Thief Racket', 'Sneak Attack', 'Surprise Attack'],
  );

  static const barbarian = CompanionKit(
    className: 'Barbarian',
    classHp: 12,
    keyAbility: 'str',
    scores: {'str': 18, 'dex': 12, 'con': 16, 'int': 10, 'wis': 14, 'cha': 8},
    boosts: ['str', 'con', 'dex', 'wis'],
    proficiencies: {
      'perception': {1: 4, 17: 6},
      'fortitude': {1: 4, 7: 6, 13: 8},
      'reflex': {1: 2, 9: 4},
      'will': {1: 4, 15: 6},
      'unarmored': {1: 2, 13: 4, 19: 6},
      'light': {1: 2, 13: 4, 19: 6},
      'medium': {1: 2, 13: 4, 19: 6},
      'simple': {1: 2, 5: 4, 13: 6},
      'martial': {1: 2, 5: 4, 13: 6},
      'unarmed': {1: 2, 5: 4, 13: 6},
      'classDC': {1: 2, 11: 4, 19: 6},
    },
    skills: ['athletics', 'intimidation', 'survival'],
    weapon: CompanionWeapon('Greataxe', 'martial', 'd12', 'S'),
    armor: CompanionArmor('Hide Armor', 'medium', ac: 3, dexCap: 2),
    rage: true,
    specials: ['Rage', 'Fury Instinct', 'Juggernaut'],
  );

  static const wizard = CompanionKit(
    className: 'Wizard',
    classHp: 6,
    keyAbility: 'int',
    scores: {'str': 10, 'dex': 14, 'con': 14, 'int': 18, 'wis': 12, 'cha': 10},
    boosts: ['int', 'dex', 'con', 'wis'],
    proficiencies: {
      'perception': {1: 2, 11: 4},
      'fortitude': {1: 2, 9: 4},
      'reflex': {1: 2, 5: 4},
      'will': {1: 4, 17: 6},
      'unarmored': {1: 2, 13: 4},
      'simple': {1: 2, 11: 4},
      'unarmed': {1: 2, 11: 4},
      'classDC': {1: 2, 7: 4, 15: 6, 19: 8},
      'castingArcane': {1: 2, 7: 4, 15: 6, 19: 8},
    },
    skills: ['arcana', 'occultism', 'society', 'crafting'],
    weapon: CompanionWeapon('Staff', 'simple', 'd4', 'B'),
    casting: CompanionCasting(
      tradition: 'arcane',
      ability: 'int',
      proficiencyKey: 'castingArcane',
      cantrips: [
        'Electric Arc',
        'Telekinetic Projectile',
        'Ignition',
        'Needle Darts',
        'Daze',
      ],
      byRank: {
        1: ['Breathe Fire'],
        3: ['Fireball', 'Lightning Bolt'],
      },
      extraSlot: true,
    ),
    specializationLevel: 13,
    specials: ['Arcane Bond', 'Arcane School', 'Spellbook'],
  );

  static const cleric = CompanionKit(
    className: 'Cleric',
    classHp: 8,
    keyAbility: 'wis',
    scores: {'str': 8, 'dex': 14, 'con': 14, 'int': 10, 'wis': 18, 'cha': 12},
    boosts: ['wis', 'con', 'dex', 'cha'],
    proficiencies: {
      'perception': {1: 2, 5: 4},
      'fortitude': {1: 2, 3: 4},
      'reflex': {1: 2, 11: 4},
      'will': {1: 4, 9: 6},
      'unarmored': {1: 2, 13: 4},
      'simple': {1: 2, 11: 4},
      'unarmed': {1: 2, 11: 4},
      'classDC': {1: 2, 7: 4, 15: 6, 19: 8},
      'castingDivine': {1: 2, 7: 4, 15: 6, 19: 8},
    },
    skills: ['medicine', 'religion', 'diplomacy', 'nature'],
    weapon: CompanionWeapon('Mace', 'simple', 'd6', 'B'),
    casting: CompanionCasting(
      tradition: 'divine',
      ability: 'wis',
      proficiencyKey: 'castingDivine',
      cantrips: ['Void Warp', 'Daze', 'Guidance', 'Light', 'Stabilize'],
      byRank: {
        1: ['Heal'],
      },
      font: 'Heal',
    ),
    specializationLevel: 13,
    specials: ['Cloistered Cleric', 'Divine Font', 'Deity'],
  );
}

/// A weapon as Pathbuilder lists it, before runes.
class CompanionWeapon {
  const CompanionWeapon(
    this.name,
    this.category,
    this.die,
    this.damageType, {
    this.ranged = false,
    this.propulsive = false,
    this.finesse = false,
  });

  final String name;

  /// `simple`, `martial`, `advanced` or `unarmed`.
  final String category;
  final String die;
  final String damageType;
  final bool ranged;
  final bool propulsive;
  final bool finesse;
}

/// A suit of armour as Pathbuilder lists it, before runes.
class CompanionArmor {
  const CompanionArmor(
    this.name,
    this.category, {
    required this.ac,
    required this.dexCap,
  });

  final String name;
  final String category;
  final int ac;
  final int dexCap;
}

/// What a prepared caster prepares.
class CompanionCasting {
  const CompanionCasting({
    required this.tradition,
    required this.ability,
    required this.proficiencyKey,
    required this.cantrips,
    required this.byRank,
    this.extraSlot = false,
    this.font,
  });

  final String tradition;
  final String ability;
  final String proficiencyKey;
  final List<String> cantrips;

  /// The spells worth preparing, by the rank they are first had at: a slot
  /// is filled with the best of them that fits, heightened to the slot.
  final Map<int, List<String>> byRank;

  /// A wizard's curriculum gives one more slot at every rank.
  final bool extraSlot;

  /// A cleric's divine font: this spell, several more times, at the
  /// highest rank.
  final String? font;
}

const Map<String, int> _ancestryHp = {
  'human': 8,
  'elf': 6,
  'dwarf': 10,
  'halfling': 6,
  'gnome': 8,
  'goblin': 6,
  'orc': 10,
};

const Map<String, int> _ancestrySpeed = {
  'elf': 30,
  'dwarf': 20,
};

/// [name], a [recruit] built at [level].
ImportedCharacter buildCompanion({
  required String name,
  required Recruit recruit,
  required int level,
}) =>
    const PathbuilderImporter()
        .importMap(companionSheet(name: name, recruit: recruit, level: level))
        .character;

/// [recruit] at [level] as a Pathbuilder 2e export, which is what the
/// importer reads and what the rest of the engine has been checked against.
///
/// Runes follow the levels Pathfinder's automatic bonus progression gives
/// them at, which is also roughly when a party can afford them: a +1 weapon
/// at 2, striking at 4, +1 armour at 5, and so on.
Map<String, Object?> companionSheet({
  required String name,
  required Recruit recruit,
  required int level,
}) {
  final kit = recruit.kit;
  level = level.clamp(1, 20);

  final scores = Map.of(kit.scores);
  for (final at in const [5, 10, 15, 20]) {
    if (level < at) break;
    for (final ability in kit.boosts) {
      scores[ability] = scores[ability]! + (scores[ability]! >= 18 ? 1 : 2);
    }
  }
  int mod(String ability) => (scores[ability]! - 10) ~/ 2;

  final profs = <String, int>{
    for (final e in kit.proficiencies.entries) e.key: _rankAt(e.value, level),
  };
  for (final skill in _skillRanks(kit, level).entries) {
    profs[skill.key] = skill.value;
  }
  int bonus(String key) {
    final rank = profs[key] ?? 0;
    return rank == 0 ? 0 : rank + level;
  }

  // --- the weapon ----------------------------------------------------------
  final weapon = kit.weapon;
  final potency = level >= 16
      ? 3
      : level >= 10
          ? 2
          : level >= 2
              ? 1
              : 0;
  final striking = level >= 19
      ? 'majorStriking'
      : level >= 12
          ? 'greaterStriking'
          : level >= 4
              ? 'striking'
              : '';
  final attackAbility =
      weapon.ranged || (weapon.finesse && mod('dex') > mod('str'))
          ? 'dex'
          : 'str';
  final weaponRank = profs[weapon.category] ?? 0;
  var specialization = 0;
  if (level >= kit.specializationLevel && weaponRank >= 4) {
    specialization = weaponRank ~/ 2; // expert 2, master 3, legendary 4
    if (kit.specializationLevel <= 7 && level >= 15) specialization *= 2;
  }
  final abilityDamage = weapon.propulsive
      ? (mod('str') > 0 ? mod('str') ~/ 2 : mod('str'))
      : weapon.ranged
          ? 0
          : kit.thief && weapon.finesse
              ? mod('dex')
              : mod('str');
  // Fury: 2 more damage raging, 6 from weapon specialization, 12 from
  // greater, as the instinct's specialization ability has it.
  final rage = !kit.rage
      ? 0
      : level >= 15
          ? 12
          : level >= 7
              ? 6
              : 2;
  final display = [
    if (potency > 0) '+$potency',
    if (striking.isNotEmpty)
      switch (striking) {
        'greaterStriking' => 'Greater Striking',
        'majorStriking' => 'Major Striking',
        _ => 'Striking',
      },
    weapon.name,
  ].join(' ');

  // --- the armour ----------------------------------------------------------
  final armor = kit.armor;
  final armorPotency = level >= 18
      ? 3
      : level >= 11
          ? 2
          : level >= 5
              ? 1
              : 0;
  final resilient = level >= 20
      ? 'majorResilient'
      : level >= 14
          ? 'greaterResilient'
          : level >= 8
              ? 'resilient'
              : '';
  final armorCategory = armor?.category ?? 'unarmored';
  final dexToAc = armor == null
      ? mod('dex')
      : (mod('dex') < armor.dexCap ? mod('dex') : armor.dexCap);
  final acItem =
      (armor == null ? 0 : armor.ac + armorPotency) - (kit.rage ? 1 : 0);
  final acProf = bonus(armorCategory);

  // --- the spells ----------------------------------------------------------
  final casting = kit.casting;
  final spellCasters = <Map<String, Object?>>[];
  if (casting != null) {
    final top = ((level + 1) ~/ 2).clamp(1, 9);
    final perDay = List.filled(11, 0)..[0] = casting.cantrips.length;
    final prepared = <Map<String, Object?>>[
      {'spellLevel': 0, 'list': casting.cantrips},
    ];
    for (var rank = 1; rank <= top; rank++) {
      var slots = (level >= rank * 2 ? 3 : 2) + (casting.extraSlot ? 1 : 0);
      // The best that fits: the spells first had at the highest rank that
      // is not above this slot, taken in turn.
      final best = (casting.byRank.keys.where((r) => r <= rank).toList()
            ..sort())
          .lastOrNull;
      final pool = best == null ? const <String>[] : casting.byRank[best]!;
      final list = [
        if (pool.isNotEmpty)
          for (var i = 0; i < slots; i++) pool[i % pool.length],
      ];
      if (casting.font case final font? when rank == top) {
        final extra = level >= 15
            ? 6
            : level >= 5
                ? 5
                : 4;
        list.addAll(List.filled(extra, font));
        slots += extra;
      }
      perDay[rank] = slots;
      prepared.add({'spellLevel': rank, 'list': list});
    }
    spellCasters.add({
      'name': kit.className,
      'magicTradition': casting.tradition,
      'spellcastingType': 'prepared',
      'ability': casting.ability,
      'proficiency': profs[casting.proficiencyKey] ?? 2,
      'focusPoints': 0,
      'innate': false,
      'perDay': perDay,
      'spells': prepared,
      'prepared': prepared,
    });
  }

  final ancestry = recruit.ancestry.trim().toLowerCase();
  return {
    'success': true,
    'build': {
      'name': name,
      'class': kit.className,
      'dualClass': null,
      'level': level,
      'xp': 0,
      'ancestry': recruit.ancestry,
      'heritage': recruit.heritage,
      'background': recruit.background,
      'sizeName':
          ancestry == 'halfling' || ancestry == 'gnome' || ancestry == 'goblin'
              ? 'Small'
              : 'Medium',
      'keyability': kit.keyAbility,
      'languages': ['Common'],
      'abilities': scores,
      'attributes': {
        'ancestryhp': _ancestryHp[ancestry] ?? 8,
        'classhp': kit.classHp,
        'bonushp': 0,
        'bonushpPerLevel': 0,
        'speed': _ancestrySpeed[ancestry] ?? 25,
        'speedBonus': 0,
      },
      'proficiencies': profs,
      'feats': const [],
      'specials': kit.specials,
      'lores': const [],
      'weapons': [
        {
          'name': weapon.name,
          'qty': 1,
          'prof': weapon.category,
          'die': weapon.die,
          'pot': potency,
          'str': striking,
          'mat': null,
          'display': display,
          'runes': const [],
          'damageType': weapon.damageType,
          'attack': mod(attackAbility) + bonus(weapon.category) + potency,
          'damageBonus': abilityDamage + specialization + rage,
        },
      ],
      'armor': [
        if (armor != null)
          {
            'name': armor.name,
            'qty': 1,
            'prof': armor.category,
            'pot': armorPotency,
            'res': resilient,
            'mat': null,
            'display': [
              if (armorPotency > 0) '+$armorPotency',
              armor.name,
            ].join(' '),
            'worn': true,
            'runes': const [],
          },
      ],
      'money': {'cp': 0, 'sp': 0, 'gp': 0, 'pp': 0},
      'spellCasters': spellCasters,
      'focusPoints': 0,
      'focus': const {},
      'acTotal': {
        'acProfBonus': acProf,
        'acAbilityBonus': dexToAc,
        'acItemBonus': acItem,
        'acTotal': 10 + acProf + dexToAc + acItem,
        'shieldBonus': null,
      },
      'equipment': const [],
    },
  };
}

int _rankAt(Map<int, int> steps, int level) {
  var rank = 0;
  for (final e in steps.entries) {
    if (e.key <= level && e.value > rank) rank = e.value;
  }
  return rank;
}

/// Every skill trained at 1, and the skill increases since spent on the
/// first of them, each as far as the level allows: expert from 3 (2 for a
/// rogue), master from 7, legendary from 15.
Map<String, int> _skillRanks(CompanionKit kit, int level) {
  final ranks = {for (final s in kit.skills) s: 2};
  final focus = kit.skills.take(3).toList();
  final increases = [
    for (var at = kit.extraSkillIncreases ? 2 : 3; at <= level; at++)
      if (kit.extraSkillIncreases || at.isOdd) at,
  ];
  for (final at in increases) {
    final cap = at >= 15
        ? 8
        : at >= 7
            ? 6
            : 4;
    for (final skill in focus) {
      if (ranks[skill]! < cap) {
        ranks[skill] = ranks[skill]! + 2;
        break;
      }
    }
  }
  return ranks;
}
