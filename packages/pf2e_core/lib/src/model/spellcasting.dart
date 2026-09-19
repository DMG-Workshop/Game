import 'ability.dart';
import 'proficiency.dart';

/// One of the four PF2e magical traditions.
enum MagicTradition {
  arcane('arcane', 'Arcane'),
  divine('divine', 'Divine'),
  occult('occult', 'Occult'),
  primal('primal', 'Primal');

  const MagicTradition(this.key, this.displayName);

  final String key;
  final String displayName;

  static MagicTradition? tryParse(String raw) {
    final needle = raw.trim().toLowerCase();
    for (final t in MagicTradition.values) {
      if (t.key == needle) return t;
    }
    return null;
  }
}

/// A list of spells at one rank.
///
/// The payload calls this `spellLevel`, retaining the pre-Remaster term for
/// what the current rules call a spell *rank*.
class SpellRankList {
  const SpellRankList(this.rank, this.spells);

  /// 0 for cantrips, 1-10 otherwise.
  final int rank;

  /// Spell names. In a prepared list this is a slot list rather than a set, so
  /// the same spell may legitimately appear more than once.
  final List<String> spells;

  @override
  String toString() =>
      '${rank == 0 ? 'Cantrips' : 'Rank $rank'}: ${spells.join(', ')}';
}

/// One spellcasting entry. A dual-class character has one per class.
class SpellcastingEntry {
  const SpellcastingEntry({
    required this.name,
    required this.tradition,
    required this.castingType,
    required this.ability,
    required this.proficiency,
    required this.isInnate,
    required this.slotsPerDay,
    required this.known,
    required this.prepared,
    required this.blendedSpells,
  });

  /// Usually the granting class, e.g. `Magus`.
  final String name;
  final MagicTradition? tradition;

  /// `prepared`, `spontaneous`, or similar.
  final String castingType;
  final Ability ability;
  final Proficiency proficiency;
  final bool isInnate;

  /// Slots per rank, indexed by rank. Index 0 is the cantrip count.
  final List<int> slotsPerDay;

  /// Spells known, or in the spellbook. Not necessarily prepared.
  final List<SpellRankList> known;

  /// Today's prepared loadout. May contain duplicates.
  final List<SpellRankList> prepared;

  final List<String> blendedSpells;

  int get cantripCount => slotsPerDay.isEmpty ? 0 : slotsPerDay[0];

  /// Highest rank with at least one slot, ignoring cantrips.
  int get highestRank {
    for (var rank = slotsPerDay.length - 1; rank >= 1; rank--) {
      if (slotsPerDay[rank] > 0) return rank;
    }
    return 0;
  }

  /// Slot count at [rank], or 0 when the rank is not available.
  int slotsAt(int rank) =>
      rank >= 0 && rank < slotsPerDay.length ? slotsPerDay[rank] : 0;

  SpellRankList? knownAt(int rank) =>
      known.where((l) => l.rank == rank).firstOrNull;

  SpellRankList? preparedAt(int rank) =>
      prepared.where((l) => l.rank == rank).firstOrNull;

  @override
  String toString() => '$name (${tradition?.displayName ?? '?'}, $castingType)';
}

/// Focus spells for one tradition/ability pairing.
class FocusEntry {
  const FocusEntry({
    required this.tradition,
    required this.ability,
    required this.abilityBonus,
    required this.proficiency,
    required this.itemBonus,
    required this.cantrips,
    required this.spells,
  });

  final MagicTradition? tradition;
  final Ability ability;
  final int abilityBonus;
  final Proficiency proficiency;
  final int itemBonus;
  final List<String> cantrips;
  final List<String> spells;

  @override
  String toString() => '${tradition?.displayName ?? '?'}: ${[
        ...cantrips,
        ...spells
      ].join(', ')}';
}

extension<T> on Iterable<T> {
  T? get firstOrNull => iterator.moveNext() ? first : null;
}
