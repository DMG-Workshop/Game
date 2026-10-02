import '../campaign/gear.dart';
import '../campaign/spell.dart';
import '../party/equipment.dart';
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

  /// Something carried: a scroll used up, a wand's cast for the day, or a
  /// staff's charges.
  item,
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
    this.item,
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

  /// The scroll, wand or staff it is cast from, when it is.
  final GearItem? item;

  bool get isAvailable => cost == CastCost.cantrip || left > 0;

  /// How a prepared spell is counted in [ActorVitals.expended].
  String get key => '$source|$rank|${spell.name}';

  @override
  String toString() => '${spell.name} (${spell.isCantrip ? 'cantrip, ' : ''}'
      'rank $rank, ${cost == CastCost.cantrip ? 'at will' : '$left left'}'
      '${item == null ? '' : ', from ${item!.name}'})';
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
    case CastCost.item:
      // Spent from the item, by [spendItemCast].
      return;
  }
}

/// Pathfinder's DC for a challenge of [level], which is also what a magic
/// item of that level casts at for somebody with no magic of their own.
int levelDc(int level) => const [
      14, 15, 16, 18, 19, 20, 22, 23, 24, 26, //
      27, 28, 30, 31, 32, 34, 35, 36, 38, 39, 40,
    ][level.clamp(0, 20)];

/// What [actor] could cast from what the party carries: every spell on a
/// scroll, a wand or a staff that [book] has numbers for.
///
/// Anyone can use them. Pathfinder asks for the spell on your own list, or a
/// check to fake it; here a caster casts with their own spell attack and DC
/// and anybody else with the item's, from its level, whichever is better.
/// [used] is what each wand and staff has given today.
List<CastOption> itemCastOptions(
  SessionActor actor,
  PartyInventory inventory,
  Map<String, int> used,
  SpellBook book,
) {
  var attack = -100;
  var dc = 0;
  for (final value in actor.stats.spellcasting) {
    if (value.attackBonus > attack) attack = value.attackBonus;
    if (value.dc > dc) dc = value.dc;
  }
  final out = <CastOption>[];
  for (final item in inventory.carried) {
    final use = item.use;
    if (use == null || !use.castsSpells) continue;
    final itemDc = levelDc(item.level);
    final copies = inventory.countOf(item.id);
    final spent = used[item.id] ?? 0;
    for (final held in use.spells) {
      final spell = book.byName(held.name);
      if (spell == null) continue;
      final cantrip = held.rank == 0 || spell.isCantrip;
      final left = use.isStaff
          ? (cantrip ? 0 : (use.charges - spent) ~/ held.rank)
          : use.isWand
              ? copies * use.perDay - spent
              : copies;
      out.add(CastOption(
        actor: actor,
        spell: spell,
        rank: cantrip ? cantripRank(actor.character.level) : held.rank,
        source: 'item:${item.id}',
        attackBonus: attack > itemDc - 10 ? attack : itemDc - 10,
        dc: dc > itemDc ? dc : itemDc,
        cost: cantrip && use.isStaff ? CastCost.cantrip : CastCost.item,
        left: left < 0 ? 0 : left,
        item: item,
      ));
    }
  }
  return out;
}

/// Uses up what casting [option] from an item costs: the scroll itself, the
/// wand's cast for the day, or as many of the staff's charges as the
/// spell's rank.
void spendItemCast(
  CastOption option,
  PartyInventory inventory,
  Map<String, int> used,
) {
  final item = option.item;
  final use = item?.use;
  if (item == null || use == null || option.cost == CastCost.cantrip) return;
  if (use.isStaff) {
    used.update(item.id, (n) => n + option.rank, ifAbsent: () => option.rank);
  } else if (use.isWand) {
    used.update(item.id, (n) => n + 1, ifAbsent: () => 1);
  } else {
    inventory.remove(item.id);
  }
}
