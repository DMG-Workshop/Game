import 'gear.dart';
import 'locations.dart';

/// Where a room is drawn on a sheet: columns run east, rows run south.
class MapPlace {
  const MapPlace(this.x, this.y);

  final int x;
  final int y;

  /// Whether [other] is the next square along a row or down a column,
  /// which is the only way two places can be joined by a drawn line.
  bool isBeside(MapPlace other) =>
      (x == other.x && (y - other.y).abs() == 1) ||
      (y == other.y && (x - other.x).abs() == 1);

  @override
  bool operator ==(Object other) =>
      other is MapPlace && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// One drawing on a map: a level of a town, or a place below it.
///
/// A town that goes underground cannot be drawn flat, since north of a
/// room is somewhere else again once you have gone down a stair. Each
/// level is its own sheet, and the ways between them are written beneath
/// rather than drawn.
class MapSheet {
  const MapSheet({
    required this.title,
    required this.places,
    this.under,
    this.charted = true,
  });

  final String title;

  /// Whether the town's map shows this sheet. Somewhere no surveyor went,
  /// or nobody will admit to, is only known by walking it.
  final bool charted;

  /// Where the sheet hangs from, when it is not the top of the town: "below
  /// the Royal Plaza".
  final String? under;

  final Map<String, MapPlace> places;
}

/// A town's map, as the party will see it once they have walked it, or
/// bought it.
class TownMap {
  const TownMap({
    required this.townId,
    required this.title,
    required this.sheets,
    required this.labels,
    this.itemId,
    this.hint,
  });

  final String townId;
  final String title;
  final List<MapSheet> sheets;

  /// A few letters for each room, short enough to draw on a phone.
  final Map<String, String> labels;

  /// The map itself, as gear: carrying it shows the whole town.
  final String? itemId;

  /// Where a copy might be had, for a party still walking it blind.
  final String? hint;

  Iterable<String> get roomIds sync* {
    for (final sheet in sheets) {
      yield* sheet.places.keys;
    }
  }

  /// Whether carrying the map shows [roomId].
  bool charts(String roomId) => sheetOf(roomId)?.charted ?? false;

  MapSheet? sheetOf(String roomId) {
    for (final sheet in sheets) {
      if (sheet.places.containsKey(roomId)) return sheet;
    }
    return null;
  }

  String labelOf(String roomId) => labels[roomId] ?? roomId;
}

/// Every town's map.
class Atlas {
  Atlas([List<TownMap> maps = const []]) : _maps = List.of(maps);

  final List<TownMap> _maps;

  List<TownMap> get maps => List.unmodifiable(_maps);

  bool get isEmpty => _maps.isEmpty;

  TownMap? forTown(String townId) {
    for (final map in _maps) {
      if (map.townId == townId) return map;
    }
    return null;
  }

  TownMap? forRoom(String roomId) {
    for (final map in _maps) {
      if (map.sheetOf(roomId) != null) return map;
    }
    return null;
  }

  /// What is wrong with the maps, in words an author can act on: rooms left
  /// off or drawn twice, two rooms in one square, a label a phone cannot
  /// fit, and a way between two rooms on one sheet that cannot be drawn.
  List<String> problems({
    required Locations locations,
    required GearTable gear,
    int longestLabel = 7,
  }) {
    final out = <String>[];
    for (final map in _maps) {
      final town = locations.townById(map.townId);
      if (town == null) {
        out.add('${map.title} is a map of "${map.townId}", which does not '
            'exist');
        continue;
      }
      final item = map.itemId;
      if (item != null && gear.byId(item) == null) {
        out.add('${map.title} is sold as "$item", which does not exist');
      }

      final drawn = <String, int>{};
      for (final sheet in map.sheets) {
        final taken = <MapPlace, String>{};
        for (final entry in sheet.places.entries) {
          drawn.update(entry.key, (n) => n + 1, ifAbsent: () => 1);
          final other = taken[entry.value];
          if (other != null) {
            out.add('${sheet.title} puts ${entry.key} and $other both at '
                '${entry.value}');
          }
          taken[entry.value] = entry.key;
        }
      }
      for (final roomId in town.roomIds) {
        final times = drawn[roomId] ?? 0;
        if (times == 0) out.add('${map.title} leaves out $roomId');
        if (times > 1) out.add('${map.title} draws $roomId $times times');
      }
      for (final roomId in drawn.keys) {
        if (locations.townForRoom(roomId)?.id != map.townId) {
          out.add('${map.title} draws $roomId, which is not in ${town.name}');
        }
        final label = map.labels[roomId];
        if (label == null || label.isEmpty) {
          out.add('${map.title} has no label for $roomId');
        } else if (label.contains(RegExp(r'[\[\]?:|\-]'))) {
          out.add('${map.title} labels $roomId "$label", with a letter the '
              'map draws with');
        } else if (label.length > longestLabel) {
          out.add('${map.title} labels $roomId "$label", longer than '
              '$longestLabel letters');
        }
      }

      for (final sheet in map.sheets) {
        for (final entry in sheet.places.entries) {
          final room = locations.roomById(entry.key);
          if (room == null) continue;
          for (final exit in room.exits.values) {
            final there = sheet.places[exit.to];
            if (there != null && !entry.value.isBeside(there)) {
              out.add('${sheet.title}: ${entry.key} goes ${exit.direction} to '
                  '${exit.to}, but they are not drawn side by side');
            }
          }
        }
      }
    }
    return out;
  }
}
