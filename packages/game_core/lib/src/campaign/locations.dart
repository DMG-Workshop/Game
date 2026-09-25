/// A way out of a room, possibly barred until something has happened.
///
/// Gating lives on the exit rather than the room because a road can open
/// mid-campaign: the arcs award `Unlock_Travel_to_Valorheim`, and that is
/// exactly what should turn a wall into a way out.
class Exit {
  const Exit({
    required this.direction,
    required this.to,
    this.requiredFlags = const [],
    this.blockedMessage,
  });

  final String direction;

  /// Room id this leads to.
  final String to;

  /// Flags that must all be set before this exit opens.
  final List<String> requiredFlags;

  /// What the player is told when it is barred. A closed road should say why,
  /// not pretend it was never there.
  final String? blockedMessage;

  bool get isGated => requiredFlags.isNotEmpty;

  bool isOpen(Set<String> flags) =>
      requiredFlags.every((flag) => flags.contains(flag));

  @override
  String toString() =>
      isGated ? '$direction -> $to (gated)' : '$direction -> $to';
}

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

  /// Direction to the exit leading that way.
  final Map<String, Exit> exits;

  /// Every direction out, gated or not.
  List<String> get directions => exits.keys.toList()..sort();

  /// Directions the party can actually take right now.
  List<String> openDirections(Set<String> flags) => [
        for (final e in exits.entries)
          if (e.value.isOpen(flags)) e.key
      ]..sort();

  Exit? exit(String direction) => exits[_normalise(direction)];

  /// The room a direction leads to, ignoring whether it is currently open.
  String? exitTo(String direction) => exit(direction)?.to;

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
      referenced.addAll(room.exits.values.map((e) => e.to));
    }
    return referenced.where((id) => !rooms.containsKey(id)).toList()..sort();
  }

  /// Exits that lead somewhere unwritten, as `roomId -> direction -> target`.
  List<({String from, String direction, String to})> get danglingExits {
    final out = <({String from, String direction, String to})>[];
    for (final room in rooms.values) {
      for (final entry in room.exits.entries) {
        if (!rooms.containsKey(entry.value.to)) {
          out.add((from: room.id, direction: entry.key, to: entry.value.to));
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
        final target = rooms[entry.value.to];
        if (target == null) continue; // already reported as dangling
        final back = opposites[entry.key];
        if (back == null) continue;
        if (target.exits[back]?.to != room.id) {
          out.add((from: room.id, direction: entry.key, to: entry.value.to));
        }
      }
    }
    out.sort((a, b) => a.from.compareTo(b.from));
    return out;
  }

  @override
  String toString() => '${towns.length} towns, ${rooms.length} rooms written';
}
