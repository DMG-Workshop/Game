import '../campaign/spell.dart';
import '../party/vitals.dart';
import 'session_actor.dart';

/// What casting a spell uses up.
enum CastCost {
  /// Nothing: cantrips are free.
  cantrip,

  /// The prepared spell itself, which is gone once cast.
  prepared,

  /// A spell slot of its rank.
  slot,

  /// A focus point.
  focus,
}

/// One spell a character could cast, where from, and at what.
class CastOption {
  const CastOption({
    required this.actor,
    required this.spell,
    required this.rank,
    required this.source,
    required this.attackBonus,
    required this.dc,
    required this.cost,
    required this.left,
  });

  final SessionActor actor;
  final Spell spell;

  /// The rank it would be cast at.
  final int rank;

  /// The spellcasting entry it comes from, or `focus`.
  final String source;

  /// The caster's spell attack modifier and spell DC for [source].
  final int attackBonus;
  final int dc;

  final CastCost cost;

  /// Casts left today; ignored for a cantrip.
  final int left;

  bool get isAvailable => cost == CastCost.cantrip || left > 0;

  /// How a prepared spell is counted in [ActorVitals.expended].
  String get key => '$source|$rank|${spell.name}';

  @override
  String toString() => '${spell.name} (${spell.isCantrip ? 'cantrip, ' : ''}'
      'rank $rank, ${cost == CastCost.cantrip ? 'at will' : '$left left'})';
}

/// Every spell [actor] could cast that [book] has numbers for, and how many
/// times more today.
///
/// Read from the character's own Pathbuilder spellcasting: what a prepared
/// caster prepared, what a spontaneous one knows, and their focus spells.
/// Spell attack and DC come from the sheet, per entry. A spell the book does
/// not know is simply not offered — better missing than made up.
List<CastOption> castOptionsFor(
  SessionActor actor,
  ActorVitals vitals,
  SpellBook book,
) {
  final level = actor.character.level;
  final out = <CastOption>[];

  for (final value in actor.stats.spellcasting) {
    final entry = value.entry;
    final prepared =
        entry.castingType.toLowerCase() == 'prepared' || entry.isInnate;
    final lists =
        prepared && entry.prepared.isNotEmpty ? entry.prepared : entry.known;
    for (final list in lists) {
      final counts = <String, int>{};
      for (final name in list.spells) {
        counts.update(name, (n) => n + 1, ifAbsent: () => 1);
      }
      for (final e in counts.entries) {
        final spell = book.byName(e.key);
        if (spell == null) continue;
        if (list.rank == 0) {
          if (!spell.isCantrip) continue;
          out.add(CastOption(
            actor: actor,
            spell: spell,
            rank: cantripRank(level),
            source: entry.name,
            attackBonus: value.attackBonus,
            dc: value.dc,
            cost: CastCost.cantrip,
            left: 0,
          ));
          continue;
        }
        if (spell.isCantrip || spell.rank > list.rank) continue;
        final key = '${entry.name}|${list.rank}|${spell.name}';
        out.add(CastOption(
          actor: actor,
          spell: spell,
          rank: list.rank,
          source: entry.name,
          attackBonus: value.attackBonus,
          dc: value.dc,
          cost: prepared ? CastCost.prepared : CastCost.slot,
          left: prepared
              ? e.value - (vitals.expended[key] ?? 0)
              : vitals.slotsLeft[list.rank] ?? 0,
        ));
      }
    }
  }

  for (final focus in actor.character.focus) {
    final attack = focus.abilityBonus +
        focus.proficiency.totalBonusAtLevel(level) +
        focus.itemBonus;
    for (final name in {...focus.cantrips, ...focus.spells}) {
      final spell = book.byName(name);
      if (spell == null) continue;
      final isCantrip = focus.cantrips.contains(name);
      out.add(CastOption(
        actor: actor,
        spell: spell,
        rank: cantripRank(level),
        source: 'focus',
        attackBonus: attack,
        dc: 10 + attack,
        cost: isCantrip ? CastCost.cantrip : CastCost.focus,
        left: isCantrip ? 0 : vitals.focus,
      ));
    }
  }

  out.sort((a, b) {
    final byRank = b.rank.compareTo(a.rank);
    return byRank != 0 ? byRank : a.spell.name.compareTo(b.spell.name);
  });
  return out;
}

/// Uses up what [option] costs from [vitals].
void spendCast(CastOption option, ActorVitals vitals) {
  switch (option.cost) {
    case CastCost.cantrip:
      return;
    case CastCost.prepared:
      vitals.expended.update(option.key, (n) => n + 1, ifAbsent: () => 1);
      final left = vitals.slotsLeft[option.rank] ?? 0;
      if (left > 0) vitals.slotsLeft[option.rank] = left - 1;
    case CastCost.slot:
      final left = vitals.slotsLeft[option.rank] ?? 0;
      if (left > 0) vitals.slotsLeft[option.rank] = left - 1;
    case CastCost.focus:
      if (vitals.focus > 0) vitals.focus--;
  }
}
