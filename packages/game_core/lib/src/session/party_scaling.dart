import '../campaign/creature.dart';
import '../party/experience.dart';

/// What a fight written for four became for a smaller party.
class PartyScaling {
  const PartyScaling({
    required this.partySize,
    required this.written,
    required this.fielded,
    required this.weakened,
  });

  final int partySize;

  /// The foes as the fight was written, for a party of four.
  final List<Creature> written;

  /// The foes who actually come.
  final List<Creature> fielded;

  /// Whether those who come were given Pathfinder's weak adjustment.
  final bool weakened;

  /// Whether anything changed at all.
  bool get changed => weakened || fielded.length != written.length;
}

/// The foes a fight sends against a party of [partySize] at [partyLevel].
///
/// Fights are written for four, as Pathfinder's encounters are, and
/// Pathfinder's budget is a quarter per character: a fight that is a
/// moderate threat to four is a moderate threat to one at a quarter of the
/// XP. So the foes' XP is brought down toward [partySize] quarters of what
/// was written. The lesser foes stay home first, never a boss, and never
/// the last one; if what is left is still more than the budget, it comes in
/// with the weak adjustment. A party of four or more meets the fight as
/// written.
PartyScaling scaleForParty(
  List<Creature> written, {
  required int partyLevel,
  required int partySize,
}) {
  if (partySize >= 4 || written.isEmpty) {
    return PartyScaling(
      partySize: partySize,
      written: written,
      fielded: written,
      weakened: false,
    );
  }
  int xp(Iterable<Creature> foes) =>
      foes.fold(0, (sum, c) => sum + creatureXp(c.level - partyLevel));
  final budget = xp(written) * partySize / 4;

  final fielded = List.of(written);
  while (fielded.length > 1 && xp(fielded) > budget) {
    // The least of those who are not a boss, the last of them first, so a
    // pack keeps its leader and the order it was written in.
    final spare = fielded.where((c) => !c.isBoss).toList();
    if (spare.isEmpty) break;
    final least = spare.reduce((a, b) => b.level <= a.level ? b : a);
    fielded.remove(least);
  }

  final weakened = xp(fielded) > budget;
  return PartyScaling(
    partySize: partySize,
    written: written,
    fielded: weakened ? [for (final c in fielded) c.weak()] : fielded,
    weakened: weakened,
  );
}
