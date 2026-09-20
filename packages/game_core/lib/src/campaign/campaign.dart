import 'arc.dart';
import 'gear.dart';
import 'locations.dart';
import 'npc.dart';
import 'world.dart';

/// A whole campaign: its world, map, cast, loot and arcs.
class Campaign {
  const Campaign({
    required this.id,
    required this.title,
    required this.world,
    required this.locations,
    required this.npcs,
    required this.gear,
    required this.arcs,
  });

  final String id;
  final String title;
  final WorldConfig world;
  final Locations locations;
  final NpcDirectory npcs;
  final GearTable gear;
  final ArcTrack arcs;

  /// Everything a player could see in a room: its text, exits, and who is
  /// standing there.
  ({Room room, Town? town, Region? region, List<Npc> npcs})? look(
      String roomId) {
    final room = locations.roomById(roomId);
    if (room == null) return null;
    final town = locations.townForRoom(roomId);
    final region = town == null ? null : world.regionForTown(town.name);
    return (room: room, town: town, region: region, npcs: npcs.inRoom(roomId));
  }

  /// A survey of what the content still owes, rather than a pass/fail.
  ///
  /// A campaign is written over months and is incomplete for most of that
  /// time, so this reports gaps instead of refusing to load. Refusing would
  /// make the tooling useless exactly when it is most needed.
  CampaignReport survey() => CampaignReport(
        unwrittenRooms: locations.unwrittenRoomIds,
        danglingExits: locations.danglingExits,
        oneWayExits: locations.oneWayExits,
        misplacedNpcs: npcs
            .misplacedIn(locations.rooms.keys.toSet())
            .map((n) => n)
            .toList(),
        gearLevelGaps: gear.levelGaps(world.metadata.levelCap),
        unreachableArcConditions: _unreachableArcConditions(),
      );

  /// Arc conditions no objective, world-state change, or movement could set.
  ///
  /// These are the quest steps that would strand a player: a condition
  /// nothing can produce is a step that can never be ticked off.
  ///
  /// Conditions of the form `enter_<room>` are excluded, because walking into
  /// a room is how they get set and no data file declares them. The room part
  /// is matched as a prefix, since triggers abbreviate ids — `enter_MH_001`
  /// means `MH_001_Square`.
  List<String> _unreachableArcConditions() {
    final produced = <String>{};
    for (final arc in arcs.all) {
      produced.addAll(arc.worldStateChanges);
    }

    final knownRooms = <String>{
      ...locations.rooms.keys,
      ...locations.unwrittenRoomIds,
    };
    bool isMovement(String condition) {
      if (!condition.startsWith('enter_')) return false;
      final prefix = condition.substring('enter_'.length);
      if (prefix.isEmpty) return false;
      return knownRooms.any((id) => id.startsWith(prefix));
    }

    final needed = <String>{};
    for (final arc in arcs.all) {
      needed.add(arc.startTrigger);
      for (final objective in arc.objectives) {
        needed.add(objective.condition);
      }
    }
    return needed.difference(produced).where((c) => !isMovement(c)).toList()
      ..sort();
  }

  @override
  String toString() => '$title — $world';
}

/// What a campaign's data is missing, gathered in one place.
class CampaignReport {
  const CampaignReport({
    this.unwrittenRooms = const [],
    this.danglingExits = const [],
    this.oneWayExits = const [],
    this.misplacedNpcs = const [],
    this.gearLevelGaps = const [],
    this.unreachableArcConditions = const [],
  });

  /// Rooms a zone or an exit names but nobody has written.
  final List<String> unwrittenRooms;

  /// Exits leading to a room that does not exist.
  final List<({String from, String direction, String to})> danglingExits;

  /// Exits with no way back, which usually means a missing reverse exit.
  final List<({String from, String direction, String to})> oneWayExits;

  /// NPCs standing in rooms that do not exist.
  final List<Npc> misplacedNpcs;

  /// Character levels with no gear written for them.
  final List<int> gearLevelGaps;

  /// Arc conditions nothing in the data can set.
  final List<String> unreachableArcConditions;

  bool get isClean =>
      unwrittenRooms.isEmpty &&
      danglingExits.isEmpty &&
      oneWayExits.isEmpty &&
      misplacedNpcs.isEmpty &&
      gearLevelGaps.isEmpty &&
      unreachableArcConditions.isEmpty;

  /// Problems that would strand a player right now, as opposed to content
  /// that is merely unfinished.
  bool get isPlayable => danglingExits.isEmpty && misplacedNpcs.isEmpty;

  String render() {
    if (isClean) return 'Campaign data is complete.';
    final b = StringBuffer();

    void section(String title, Iterable<String> lines) {
      final list = lines.toList();
      if (list.isEmpty) return;
      b.writeln('$title (${list.length}):');
      for (final line in list) {
        b.writeln('  $line');
      }
    }

    section('Rooms named but not written', unwrittenRooms);
    section(
      'Exits leading nowhere',
      danglingExits.map((e) => '${e.from} --${e.direction}--> ${e.to}'),
    );
    section(
      'Exits with no way back',
      oneWayExits.map((e) => '${e.from} --${e.direction}--> ${e.to}'),
    );
    section(
      'NPCs in rooms that do not exist',
      misplacedNpcs.map((n) => '${n.name} in ${n.location}'),
    );
    if (gearLevelGaps.isNotEmpty) {
      b
        ..writeln('Levels with no gear (${gearLevelGaps.length}):')
        ..writeln('  ${gearLevelGaps.join(', ')}');
    }
    section('Arc conditions nothing sets', unreachableArcConditions);
    return b.toString().trimRight();
  }

  @override
  String toString() => render();
}
