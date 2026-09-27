import '../campaign/atlas.dart';
import '../campaign/locations.dart';

/// A sheet of a town's map as lines of text, drawn from what the party
/// knows.
///
/// A room they know is drawn by its label, and the room they are in is
/// drawn [bracketed]. A room they know nothing of but have seen a way to
/// is a `?`; anything further off is not drawn at all. Paths are `--` and
/// `|`; a way up or down is `::` and `:`. Columns are as wide as the widest
/// label drawn in them, so a map the party has barely begun stays small.
///
/// Empty when nothing on the sheet is known.
List<String> drawSheet({
  required MapSheet sheet,
  required TownMap map,
  required bool Function(String roomId) knows,
  required Iterable<Exit> Function(String roomId) exitsOf,
  required String here,
}) {
  // What goes in each square: a label, a bracketed one, or a question.
  final drawn = <MapPlace, String>{};
  final links = <(MapPlace, MapPlace), bool>{};
  for (final entry in sheet.places.entries) {
    if (!knows(entry.key)) continue;
    drawn[entry.value] = entry.key == here
        ? '[${map.labelOf(entry.key)}]'
        : map.labelOf(entry.key);
  }
  if (drawn.isEmpty) return const [];
  for (final entry in sheet.places.entries) {
    if (!knows(entry.key)) continue;
    for (final exit in exitsOf(entry.key)) {
      final there = sheet.places[exit.to];
      if (there == null || !entry.value.isBeside(there)) continue;
      drawn.putIfAbsent(there, () => '?');
      final stairs = exit.direction == 'up' || exit.direction == 'down';
      final key = _ordered(entry.value, there);
      links[key] = (links[key] ?? false) || stairs;
    }
  }

  final columns = {for (final p in drawn.keys) p.x}.toList()..sort();
  final rows = {for (final p in drawn.keys) p.y}.toList()..sort();
  final width = {
    for (final x in columns)
      x: drawn.entries
          .where((e) => e.key.x == x)
          .fold(0, (w, e) => e.value.length > w ? e.value.length : w),
  };

  // A path runs right up to the label, through whatever padding centres it.
  String? linkBetween(MapPlace a, MapPlace b) =>
      switch (links[_ordered(a, b)]) {
        null => null,
        false => '-',
        true => ':',
      };

  final lines = <String>[];
  for (var r = 0; r < rows.length; r++) {
    final y = rows[r];
    final line = StringBuffer();
    for (var c = 0; c < columns.length; c++) {
      final x = columns[c];
      final here = MapPlace(x, y);
      final label = drawn[here] ?? '';
      final left = (width[x]! - label.length) ~/ 2;
      final right = width[x]! - label.length - left;
      final before = c > 0 && columns[c - 1] == x - 1
          ? linkBetween(MapPlace(x - 1, y), here)
          : null;
      final after = c < columns.length - 1 && columns[c + 1] == x + 1
          ? linkBetween(here, MapPlace(x + 1, y))
          : null;
      line
        ..write((label.isEmpty ? ' ' : before ?? ' ') * left)
        ..write(label)
        ..write((label.isEmpty ? ' ' : after ?? ' ') * right);
      if (c < columns.length - 1) line.write((after ?? ' ') * 2);
    }
    lines.add(line.toString().trimRight());

    if (r == rows.length - 1) break;
    if (rows[r + 1] != y + 1) {
      lines.add('');
      continue;
    }
    final under = StringBuffer();
    for (var c = 0; c < columns.length; c++) {
      final x = columns[c];
      final w = width[x]!;
      final stairs = links[_ordered(MapPlace(x, y), MapPlace(x, y + 1))];
      final mid = (w - 1) ~/ 2;
      under
        ..write(' ' * mid)
        ..write(switch (stairs) { null => ' ', false => '|', true => ':' })
        ..write(' ' * (w - mid - 1));
      if (c < columns.length - 1) under.write('  ');
    }
    lines.add(under.toString().trimRight());
  }
  return lines;
}

(MapPlace, MapPlace) _ordered(MapPlace a, MapPlace b) =>
    (a.y < b.y || (a.y == b.y && a.x < b.x)) ? (a, b) : (b, a);
