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

/// What the party is carrying, who is wearing what, and what is in the purse.
///
/// Party-wide rather than per-character: a marching order shares a pack, and
/// loot belongs to the party rather than to whoever happened to swing last.
/// The pack holds copies, because a party of four may well want four swords;
/// each copy can be on one person at a time.
class PartyInventory {
  PartyInventory({
    required GearTable gear,
    Iterable<String> carried = const [],
    Map<String, Map<EquipSlot, String>> equipped = const {},
    int coin = 0,
  })  : _gear = gear,
        _coin = coin < 0 ? 0 : coin {
    for (final id in carried) {
      if (_gear.byId(id) == null) continue;
      _counts.update(id, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final entry in equipped.entries) {
      for (final slot in entry.value.entries) {
        if (_spareCopies(slot.value, forActor: entry.key) > 0) {
          _equipped.putIfAbsent(entry.key, () => {})[slot.key] = slot.value;
        }
      }
    }
  }

  final GearTable _gear;
  final Map<String, int> _counts = {};
  final Map<String, Map<EquipSlot, String>> _equipped = {};

  /// Coin in copper, which is exact where gold pieces would not be.
  int _coin;

  bool get isEmpty => _counts.isEmpty;

  /// Distinct items carried.
  int get length => _counts.length;

  /// One of each item the party has, lowest level first.
  List<GearItem> get carried => [
        for (final id in _counts.keys)
          if (_gear.byId(id) case final item?) item,
      ]..sort((a, b) {
          final byLevel = a.level.compareTo(b.level);
          return byLevel != 0 ? byLevel : a.name.compareTo(b.name);
        });

  bool isCarrying(String itemId) => _counts.containsKey(itemId);

  /// How many copies of [itemId] the party has, worn or not.
  int countOf(String itemId) => _counts[itemId] ?? 0;

  /// Puts a copy in the pack, returning how many there are now.
  int add(String itemId) {
    if (_gear.byId(itemId) == null) {
      throw ArgumentError.value(itemId, 'itemId', 'no such item in this gear');
    }
    return _counts.update(itemId, (n) => n + 1, ifAbsent: () => 1);
  }

  /// Takes a copy out of the pack, as selling does.
  ///
  /// Refuses to take one somebody is wearing: selling the armour off a
  /// character's back should be a decision they make by taking it off first.
  GearItem remove(String itemId) {
    final item = _gear.byId(itemId);
    if (item == null || !isCarrying(itemId)) {
      throw EquipException('You are not carrying that.');
    }
    if (_spareCopies(itemId) < 1) {
      throw EquipException('${holdersOf(itemId).join(' and ')} '
          '${holdersOf(itemId).length == 1 ? 'is' : 'are'} using '
          '${item.name}. Take it off first.');
    }
    final left = _counts[itemId]! - 1;
    if (left == 0) {
      _counts.remove(itemId);
    } else {
      _counts[itemId] = left;
    }
    return item;
  }

  // --- the purse -----------------------------------------------------------

  /// What the party has to spend, in copper.
  int get coin => _coin;

  void earn(int copper) {
    if (copper < 0) {
      throw ArgumentError.value(copper, 'copper', 'must not be negative');
    }
    _coin += copper;
  }

  /// Spends [copper], or refuses without spending anything.
  void spend(int copper) {
    if (copper < 0) {
      throw ArgumentError.value(copper, 'copper', 'must not be negative');
    }
    if (copper > _coin) {
      throw EquipException('That is ${formatCoin(copper)}, and the party has '
          '${formatCoin(_coin)}.');
    }
    _coin -= copper;
  }

  // --- wearing things ------------------------------------------------------

  /// Finds a carried item by id, or by any word of its name.
  ///
  /// A player types "equip nail", not an item id, and being told there is no
  /// such thing when it is in the pack is the worst answer available.
  GearItem? find(String query) => findIn(carried, query);

  /// Finds an item in [candidates] by id, exact name, or part of a name.
  static GearItem? findIn(Iterable<GearItem> candidates, String query) {
    final needle = _plain(query);
    if (needle.isEmpty) return null;

    for (final item in candidates) {
      if (item.id.toLowerCase() == query.trim().toLowerCase()) return item;
    }
    for (final item in candidates) {
      if (_plain(item.name) == needle) return item;
    }
    // Longest name first, so "nail" does not match "The Last Nail" ahead of
    // an exact-ish shorter one by accident of ordering.
    final byLength = candidates.toList()
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final item in byLength) {
      if (_plain(item.name).contains(needle)) return item;
    }
    return null;
  }

  /// A name as a player types it: no case, no apostrophes, and hyphens and
  /// other punctuation as spaces. "The Avatar's Crown-Spike" becomes
  /// "the avatars crown spike", so "crown spike" and "avatars" both find it.
  static String _plain(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r"['’]"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  /// Everyone wearing or wielding a copy of [itemId].
  List<String> holdersOf(String itemId) => [
        for (final entry in _equipped.entries)
          if (entry.value.values.contains(itemId)) entry.key,
      ];

  /// Who is carrying [itemId] on their person, if anyone.
  String? holderOf(String itemId) {
    final holders = holdersOf(itemId);
    return holders.isEmpty ? null : holders.first;
  }

  /// Copies nobody is using; [forActor]'s own copy counts as spare to them.
  int _spareCopies(String itemId, {String? forActor}) {
    final using = holdersOf(itemId).where((h) => h != forActor).length;
    return countOf(itemId) - using;
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
    if (item == null || !isCarrying(itemId)) {
      throw EquipException('You are not carrying that.');
    }

    final slot = EquipSlot.forType(item.type);
    if (slot == null) {
      throw EquipException('${item.name} is not something you can wield or '
          'wear. It stays in the pack.');
    }

    if (_spareCopies(itemId, forActor: actorId) < 1) {
      throw EquipException('${holdersOf(itemId).join(' and ')} already '
          '${holdersOf(itemId).length == 1 ? 'has' : 'have'} ${item.name}, '
          'and the party has no other.');
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

  /// Written as a list with one entry per copy, so a save from before copies
  /// existed — one entry per item — still reads correctly.
  Map<String, Object?> toJson() => {
        'carried': [
          for (final id in (_counts.keys.toList()..sort()))
            for (var i = 0; i < _counts[id]!; i++) id,
        ],
        'coin': _coin,
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
      coin: (root['coin'] as num?)?.toInt() ?? 0,
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
  String toString() => '${_counts.length} carried, '
      '${_equipped.length} equipped, ${formatCoin(_coin)}';
}

/// Copper as a player would say it: "12 gp 5 sp", or "nothing".
///
/// Platinum is left out on purpose. Pathfinder prices are quoted in gold
/// right up to the top of the level range, and "4 pp 5 gp" reads as a
/// puzzle where "45 gp" reads as a price.
String formatCoin(int copper) {
  if (copper <= 0) return 'nothing';
  final gp = copper ~/ 100;
  final sp = (copper % 100) ~/ 10;
  final cp = copper % 10;
  return [
    if (gp > 0) '$gp gp',
    if (sp > 0) '$sp sp',
    if (cp > 0) '$cp cp',
  ].join(' ');
}
