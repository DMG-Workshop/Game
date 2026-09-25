import 'package:pf2e_core/pf2e_core.dart';

import '../campaign/gear.dart';

/// Thrown when a character cannot equip what they were asked to equip.
class EquipException implements Exception {
  EquipException(this.message);

  final String message;

  @override
  String toString() => 'EquipException: $message';
}

/// Where a piece of gear sits on a character.
///
/// Two slots, because two are all the engine can honestly run: a weapon
/// changes a Strike and armour changes AC. A talisman whose rule is a
/// sentence of English is carried, not worn, until something can read it.
enum EquipSlot {
  weapon,
  armor;

  /// The slot an item of [type] belongs in, or null when it is only carried.
  static EquipSlot? forType(String type) => switch (type.trim().toLowerCase()) {
        'weapon' => EquipSlot.weapon,
        'armor' || 'armour' => EquipSlot.armor,
        _ => null,
      };

  static EquipSlot? tryParse(String source) {
    final needle = source.trim().toLowerCase();
    for (final slot in values) {
      if (slot.name == needle) return slot;
    }
    return needle == 'armour' ? EquipSlot.armor : null;
  }

  String get label => this == EquipSlot.weapon ? 'weapon' : 'armour';
}

/// What one character is wielding and wearing.
class Loadout {
  const Loadout({this.weapon, this.armor});

  final GearItem? weapon;
  final GearItem? armor;

  bool get isEmpty => weapon == null && armor == null;

  GearItem? inSlot(EquipSlot slot) => slot == EquipSlot.weapon ? weapon : armor;

  Loadout replacing(EquipSlot slot, GearItem? item) => Loadout(
        weapon: slot == EquipSlot.weapon ? item : weapon,
        armor: slot == EquipSlot.armor ? item : armor,
      );

  @override
  String toString() => isEmpty
      ? 'nothing equipped'
      : [
          if (weapon != null) 'wielding ${weapon!.name}',
          if (armor != null) 'wearing ${armor!.name}',
        ].join(', ');
}

/// A character's fighting numbers with their equipment applied.
///
/// The arithmetic is Pathfinder's, and it is checked against the sheet it came
/// from: a level 6 expert with Strength 19 holding a +1 striking scythe is +15
/// for 2d10+4, and computing that same weapon as a campaign item has to
/// produce the same three numbers. Equipping nothing falls back to the
/// imported kit, so a character who has looted nothing fights exactly as
/// Pathbuilder says they do.
class EquippedStats {
  const EquippedStats(this.base, [this.loadout = const Loadout()]);

  final DerivedStats base;
  final Loadout loadout;

  /// What a suit of armour is worth when the data does not say.
  ///
  /// Campaign armour normally declares `ac_bonus` and `dex_cap`; these are the
  /// ordinary values for each category, so armour written before those fields
  /// existed still means something instead of silently being worth nothing.
  static const Map<String, ({int ac, int dexCap})> armorDefaults = {
    'unarmored': (ac: 0, dexCap: 5),
    'light': (ac: 2, dexCap: 3),
    'medium': (ac: 4, dexCap: 1),
    'heavy': (ac: 6, dexCap: 0),
  };

  static const Set<String> _weaponCategories = {
    'simple',
    'martial',
    'advanced',
    'unarmed',
  };

  ImportedCharacter get _character => base.character;

  int _mod(Ability ability) => _character.abilities.modifier(ability);

  // --- armour --------------------------------------------------------------

  /// Armour class, from the worn suit or from the imported sheet.
  int get armorClass {
    final armor = loadout.armor;
    if (armor == null) return base.armorClass;

    final defaults = armorDefaults[armorCategory] ?? armorDefaults['light']!;
    final proficiency = _character.proficiencyFor(armorCategory);
    return 10 +
        proficiency.totalBonusAtLevel(base.level) +
        dexterityToAc +
        (armor.acBonus ?? defaults.ac) +
        armor.bonus;
  }

  /// `light`, `medium`, `heavy` or `unarmored`, read off the item's traits.
  ///
  /// Light when the data does not say: it is the category a character is
  /// likeliest to be trained in, and guessing heavy at a character who is not
  /// would quietly cost them their level in AC.
  String get armorCategory {
    final armor = loadout.armor;
    if (armor == null) return 'unarmored';
    for (final trait in armor.traits) {
      final needle = trait.trim().toLowerCase();
      if (armorDefaults.containsKey(needle)) return needle;
    }
    return 'light';
  }

  /// The most Dexterity this armour lets through.
  int get dexterityCap {
    final armor = loadout.armor;
    if (armor == null) return armorDefaults['unarmored']!.dexCap;
    return armor.dexCap ??
        (armorDefaults[armorCategory] ?? armorDefaults['light']!).dexCap;
  }

  /// Dexterity actually reaching AC, which heavy armour holds at zero.
  int get dexterityToAc {
    final dex = _mod(Ability.dexterity);
    final cap = dexterityCap;
    return dex < cap ? dex : cap;
  }

  // --- weapon --------------------------------------------------------------

  /// Attack bonus for a Strike with whatever is in hand.
  int get attackBonus {
    final weapon = loadout.weapon;
    if (weapon == null) return _importedAttackBonus;
    return _character.proficiencyFor(weaponCategory).totalBonusAtLevel(
              base.level,
            ) +
        _mod(attackAbility) +
        weapon.bonus;
  }

  /// `simple`, `martial`, `advanced` or `unarmed`.
  ///
  /// Martial when the data does not say, which is where most weapons sit and
  /// what a campaign author writing "sword" means.
  String get weaponCategory {
    final weapon = loadout.weapon;
    if (weapon == null) return 'martial';
    for (final trait in weapon.traits) {
      final needle = trait.trim().toLowerCase();
      if (_weaponCategories.contains(needle)) return needle;
    }
    return 'martial';
  }

  /// The ability a Strike rolls with.
  ///
  /// Ranged attacks use Dexterity; a finesse weapon uses whichever of the two
  /// is better, which is the whole point of the trait.
  Ability get attackAbility {
    final weapon = loadout.weapon;
    if (weapon == null) return Ability.strength;
    if (_isRanged(weapon)) return Ability.dexterity;
    if (weapon.hasTrait('finesse') &&
        _mod(Ability.dexterity) > _mod(Ability.strength)) {
      return Ability.dexterity;
    }
    return Ability.strength;
  }

  /// Damage for a Strike, with the striking rune setting the number of dice.
  DamageExpression get damage {
    final weapon = loadout.weapon;
    if (weapon == null) return _importedDamage;

    final written = DamageExpression.tryParse(weapon.damage ?? '');
    final dieSize =
        written == null || written.dieSize == 0 ? 4 : written.dieSize;
    return DamageExpression(
      diceCount: weapon.striking.diceCount,
      dieSize: dieSize,
      flatBonus: damageAbilityBonus,
    );
  }

  /// Strength added to damage: all of it in melee, half from a propulsive
  /// bow, none from anything else thrown or shot.
  int get damageAbilityBonus {
    final weapon = loadout.weapon;
    if (weapon == null) return 0;
    final strength = _mod(Ability.strength);
    if (weapon.hasTrait('propulsive')) {
      return strength > 0 ? strength ~/ 2 : strength;
    }
    if (_isRanged(weapon)) return 0;
    return strength;
  }

  /// Agile weapons take a smaller multiple attack penalty.
  bool get isAgile {
    final weapon = loadout.weapon;
    if (weapon != null) return weapon.hasTrait('agile');
    return _importedWeapon?.runes.any((r) => r.toLowerCase() == 'agile') ??
        false;
  }

  String get weaponLabel =>
      loadout.weapon?.name ?? _importedWeapon?.display ?? 'bare hands';

  String get armorLabel =>
      loadout.armor?.name ?? _character.wornArmor?.display ?? 'no armour';

  bool _isRanged(GearItem weapon) =>
      weapon.hasTrait('ranged') || weapon.hasTrait('propulsive');

  // --- the kit they arrived in ---------------------------------------------

  ImportedWeapon? get _importedWeapon =>
      _character.weapons.isEmpty ? null : _character.weapons.first;

  int get _importedAttackBonus =>
      _importedWeapon?.attackBonus ?? base.perception.total;

  DamageExpression get _importedDamage {
    final weapon = _importedWeapon;
    if (weapon == null) return DamageExpression.parse('1d4');
    return DamageExpression.tryParse(weapon.damageFormula) ??
        DamageExpression.parse('1d4');
  }

  /// A few lines a client can print without knowing the rules.
  List<String> describe() => [
        'AC $armorClass  ($armorLabel)',
        'Strike ${attackBonus >= 0 ? '+' : ''}$attackBonus '
            '$damage  ($weaponLabel)',
      ];
}

/// What the party is carrying, and who is wearing what.
///
/// Party-wide rather than per-character: a marching order shares a pack, and
/// loot belongs to the party rather than to whoever happened to swing last.
/// Equipping is per character, and one item can only be on one of them.
class PartyInventory {
  PartyInventory({
    required GearTable gear,
    Iterable<String> carried = const [],
    Map<String, Map<EquipSlot, String>> equipped = const {},
  }) : _gear = gear {
    for (final id in carried) {
      if (_gear.byId(id) != null) _carried.add(id);
    }
    for (final entry in equipped.entries) {
      for (final slot in entry.value.entries) {
        if (_carried.contains(slot.value)) {
          _equipped.putIfAbsent(entry.key, () => {})[slot.key] = slot.value;
        }
      }
    }
  }

  final GearTable _gear;
  final Set<String> _carried = {};
  final Map<String, Map<EquipSlot, String>> _equipped = {};

  bool get isEmpty => _carried.isEmpty;
  int get length => _carried.length;

  /// Everything the party has, lowest level first.
  List<GearItem> get carried => [
        for (final id in _carried)
          if (_gear.byId(id) case final item?) item,
      ]..sort((a, b) {
          final byLevel = a.level.compareTo(b.level);
          return byLevel != 0 ? byLevel : a.name.compareTo(b.name);
        });

  bool isCarrying(String itemId) => _carried.contains(itemId);

  /// Puts an item in the pack. Returns false when it was already there.
  bool add(String itemId) {
    if (_gear.byId(itemId) == null) {
      throw ArgumentError.value(itemId, 'itemId', 'no such item in this gear');
    }
    return _carried.add(itemId);
  }

  /// Finds a carried item by id, or by any word of its name.
  ///
  /// A player types "equip nail", not an item id, and being told there is no
  /// such thing when it is in the pack is the worst answer available.
  GearItem? find(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return null;

    final candidates = carried;
    for (final item in candidates) {
      if (item.id.toLowerCase() == needle) return item;
    }
    for (final item in candidates) {
      if (item.name.toLowerCase() == needle) return item;
    }
    // Longest name first, so "nail" does not match "The Last Nail" ahead of
    // an exact-ish shorter one by accident of ordering.
    final byLength = candidates.toList()
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final item in byLength) {
      if (item.name.toLowerCase().contains(needle)) return item;
    }
    return null;
  }

  /// Who is carrying [itemId] on their person, if anyone.
  String? holderOf(String itemId) {
    for (final entry in _equipped.entries) {
      if (entry.value.values.contains(itemId)) return entry.key;
    }
    return null;
  }

  Loadout loadoutFor(String actorId) {
    final slots = _equipped[actorId] ?? const {};
    return Loadout(
      weapon: _gear.byId(slots[EquipSlot.weapon] ?? ''),
      armor: _gear.byId(slots[EquipSlot.armor] ?? ''),
    );
  }

  Map<String, Loadout> loadouts() => {
        for (final actorId in _equipped.keys) actorId: loadoutFor(actorId),
      };

  /// Equips [itemId] on [actorId], returning what it displaced.
  ({GearItem item, EquipSlot slot, GearItem? replaced}) equip(
    String actorId,
    String itemId,
  ) {
    final item = _gear.byId(itemId);
    if (item == null || !_carried.contains(itemId)) {
      throw EquipException('You are not carrying that.');
    }

    final slot = EquipSlot.forType(item.type);
    if (slot == null) {
      throw EquipException('${item.name} is not something you can wield or '
          'wear. It stays in the pack.');
    }

    final holder = holderOf(itemId);
    if (holder != null && holder != actorId) {
      throw EquipException('$holder already has ${item.name}.');
    }

    final slots = _equipped.putIfAbsent(actorId, () => {});
    final replaced = _gear.byId(slots[slot] ?? '');
    slots[slot] = itemId;
    return (item: item, slot: slot, replaced: replaced);
  }

  /// Takes whatever is in [slot] off [actorId], returning it.
  GearItem? unequip(String actorId, EquipSlot slot) {
    final removed = _equipped[actorId]?.remove(slot);
    if (_equipped[actorId]?.isEmpty ?? false) _equipped.remove(actorId);
    return _gear.byId(removed ?? '');
  }

  Map<String, Object?> toJson() => {
        'carried': _carried.toList()..sort(),
        'equipped': {
          for (final entry in _equipped.entries)
            entry.key: {
              for (final slot in entry.value.entries) slot.key.name: slot.value,
            },
        },
      };

  /// Rebuilds an inventory from [json].
  ///
  /// Anything the campaign no longer has is dropped rather than throwing: a
  /// save from before an item was renamed should still load, minus the item.
  static PartyInventory fromJson(GearTable gear, Object? json) {
    final root = json is Map ? json.cast<String, Object?>() : const {};
    return PartyInventory(
      gear: gear,
      carried: [
        for (final id in (root['carried'] as List? ?? const [])) id.toString(),
      ],
      equipped: {
        for (final entry in (root['equipped'] as Map? ?? const {}).entries)
          entry.key.toString(): {
            for (final slot in ((entry.value as Map?) ?? const {})
                .cast<Object?, Object?>()
                .entries)
              if (EquipSlot.tryParse(slot.key.toString()) case final parsed?)
                parsed: slot.value.toString(),
          },
      },
    );
  }

  @override
  String toString() => '${_carried.length} carried, '
      '${_equipped.length} equipped';
}
