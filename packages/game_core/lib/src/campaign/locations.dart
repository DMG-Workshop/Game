/// A single place a party can stand in.
class Room {
  const Room({
    required this.id,
    required this.title,
    required this.description,
    this.exits = const {},
  });

  final String id;
  final String title;
  final String description;

  /// Direction to the room it leads to, e.g. `{"north": "MH_002_GuardHall"}`.
  final Map<String, String> exits;

  List<String> get directions => exits.keys.toList()..sort();

  String? exitTo(String direction) => exits[_normalise(direction)];

  /// Accepts the usual MUD shorthands, so `n` reaches north.
  static String _normalise(String direction) {
    final d = direction.trim().toLowerCase();
    return switch (d) {
      'n' => 'north',
      's' => 'south',
      'e' => 'east',
      'w' => 'west',
      'ne' => 'northeast',
      'nw' => 'northwest',
      'se' => 'southeast',
      'sw' => 'southwest',
      'u' => 'up',
      'd' => 'down',
      _ => d,
    };
  }

  @override
  String toString() => '$id: $title';
}

/// A named cluster of rooms within a town.
class Zone {
  const Zone({required this.id, required this.roomIds});

  final String id;
  final List<String> roomIds;

  @override
  String toString() => '$id (${roomIds.length} rooms)';
}

/// A settlement, its zones, and the levels it is pitched at.
class Town {
  const Town({
    required this.id,
    required this.name,
    required this.tier,
    required this.levelRange,
    required this.description,
    required this.zones,
  });

  final String id;
  final String name;
  final int tier;

  /// Inclusive `[min, max]` character levels this town is written for.
  final List<int> levelRange;
  final String description;
  final List<Zone> zones;

  int get minLevel => levelRange.isEmpty ? 1 : levelRange.first;
  int get maxLevel => levelRange.length < 2 ? minLevel : levelRange[1];

  bool suitsLevel(int level) => level >= minLevel && level <= maxLevel;

  /// Every room id this town claims, across all its zones.
  List<String> get roomIds => [
        for (final zone in zones) ...zone.roomIds,
      ];

  Zone? zoneForRoom(String roomId) {
    for (final zone in zones) {
      if (zone.roomIds.contains(roomId)) return zone;
    }
    return null;
  }

  @override
  String toString() => '$name (tier $tier, levels $minLevel-$maxLevel)';
}

/// The campaign's geography.
class Locations {
  const Locations({required this.towns, required this.rooms});

  final List<Town> towns;

  /// Rooms that have actually been written, by id.
  final Map<String, Room> rooms;

  Room? roomById(String id) => rooms[id];

  Town? townById(String id) {
    for (final town in towns) {
      if (town.id == id) return town;
    }
    return null;
  }

  Town? townForRoom(String roomId) {
    for (final town in towns) {
      if (town.roomIds.contains(roomId)) return town;
    }
    return null;
  }

  /// Room ids named by a zone or an exit but never written.
  ///
  /// A map is planned before it is built, so this is the difference between
  /// the two: the content still owed, in the order a player would hit it.
  List<String> get unwrittenRoomIds {
    final referenced = <String>{};
    for (final town in towns) {
      referenced.addAll(town.roomIds);
    }
    for (final room in rooms.values) {
      referenced.addAll(room.exits.values);
    }
    return referenced.where((id) => !rooms.containsKey(id)).toList()..sort();
  }

  /// Exits that lead somewhere unwritten, as `roomId -> direction -> target`.
  List<({String from, String direction, String to})> get danglingExits {
    final out = <({String from, String direction, String to})>[];
    for (final room in rooms.values) {
      for (final entry in room.exits.entries) {
        if (!rooms.containsKey(entry.value)) {
          out.add((from: room.id, direction: entry.key, to: entry.value));
        }
      }
    }
    out.sort((a, b) => a.from.compareTo(b.from));
    return out;
  }

  /// Exits with no matching exit back, which in a MUD reads as a bug unless
  /// it is meant to be one-way.
  List<({String from, String direction, String to})> get oneWayExits {
    const opposites = {
      'north': 'south',
      'south': 'north',
      'east': 'west',
      'west': 'east',
      'northeast': 'southwest',
      'southwest': 'northeast',
      'northwest': 'southeast',
      'southeast': 'northwest',
      'up': 'down',
      'down': 'up',
      'in': 'out',
      'out': 'in',
    };
    final out = <({String from, String direction, String to})>[];
    for (final room in rooms.values) {
      for (final entry in room.exits.entries) {
        final target = rooms[entry.value];
        if (target == null) continue; // already reported as dangling
        final back = opposites[entry.key];
        if (back == null) continue;
        if (target.exits[back] != room.id) {
          out.add((from: room.id, direction: entry.key, to: entry.value));
        }
      }
    }
    out.sort((a, b) => a.from.compareTo(b.from));
    return out;
  }

  @override
  String toString() => '${towns.length} towns, ${rooms.length} rooms written';
}
