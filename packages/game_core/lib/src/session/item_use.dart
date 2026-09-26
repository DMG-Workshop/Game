import 'package:pf2e_core/pf2e_core.dart';

import '../campaign/gear.dart';

/// Somebody using up an item: on whom, with what roll, and what it did.
class UseResult {
  const UseResult({
    required this.item,
    required this.user,
    required this.target,
    required this.roll,
    required this.healed,
    required this.hp,
    required this.maxHp,
    this.revived = false,
  });

  final GearItem item;

  /// Who used it, and who it was used on, by name.
  final String user;
  final String target;

  final DamageRoll roll;

  /// What it actually gave back, which a full roll can overshoot.
  final int healed;

  /// Where [target] stands afterwards.
  final int hp;
  final int maxHp;

  /// True when it got somebody who was down back on their feet.
  final bool revived;

  bool get onSelf => user == target;

  @override
  String toString() => onSelf
      ? '$user drinks ${item.name}: $roll, +$healed HP ($hp/$maxHp)'
      : '$user gets ${item.name} into $target: $roll, +$healed HP '
          '($hp/$maxHp)';
}

/// Why [item] cannot be used by hand, in words a player can act on.
///
/// A consumable with no use the engine knows is spent when something calls
/// for it, and says so in its own text. Nothing in the game calls for it
/// yet, and a player reaching for it should hear that rather than nothing.
String cannotUseByHand(GearItem item) {
  if (item.isConsumable) {
    final terms = item.special == null ? '' : ' Its terms: ${item.special}';
    return '${item.name} is not used by hand.$terms Nothing in the game '
        'calls for it yet.';
  }
  return switch (item.type.toLowerCase()) {
    'weapon' => '${item.name} is not used up. Wield it: "equip ${item.name}".',
    'armor' => '${item.name} is not used up. Wear it: "equip ${item.name}".',
    _ => '${item.name} is not used up. It does its work while it is carried.',
  };
}
