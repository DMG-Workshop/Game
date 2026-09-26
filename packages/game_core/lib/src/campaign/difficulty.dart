/// The DC for a task of a given level, from Pathfinder's level-based DC table.
///
/// What a GM reaches for when a check has no DC of its own — making shelter
/// in a storm, or saving against one — so that the same storm is as hard for
/// a level 15 party as a level 1 one would find a level 1 storm.
int dcForLevel(int level) {
  const table = [
    14, 15, 16, 18, 19, 20, 22, 23, 24, 26, 27, 28, 30, //
    31, 32, 34, 35, 36, 38, 39, 40, 42, 44, 46, 48, 50,
  ];
  final index = level.clamp(0, table.length - 1);
  return table[index];
}
