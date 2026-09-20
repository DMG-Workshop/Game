import 'dart:convert';

import 'arc.dart';
import 'campaign.dart';
import 'gear.dart';
import 'locations.dart';
import 'npc.dart';
import 'world.dart';

/// Thrown when campaign data cannot be read at all.
class CampaignFormatException implements Exception {
  CampaignFormatException(this.message);

  final String message;

  @override
  String toString() => 'CampaignFormatException: $message';
}

/// Reads a campaign from its five data files.
///
/// Takes the file contents rather than paths: the package does no I/O, so the
/// same loader serves the terminal build, a bundled asset on a phone, and a
/// fetch in the browser.
class CampaignLoader {
  const CampaignLoader();

  Campaign load({
    required String id,
    required String title,
    required String worldConfigJson,
    required String locationsJson,
    required String npcsJson,
    String? gearJson,
    String? arcsJson,
  }) =>
      Campaign(
        id: id,
        title: title,
        world: readWorld(worldConfigJson),
        locations: readLocations(locationsJson),
        npcs: readNpcs(npcsJson),
        gear: gearJson == null ? GearTable(const []) : readGear(gearJson),
        arcs: arcsJson == null ? ArcTrack(const []) : readArcs(arcsJson),
      );

  // --- world ---------------------------------------------------------------

  WorldConfig readWorld(String json) {
    final root = _object(json, 'world config');
    final meta = _map(root['world_metadata']);
    final time = _map(root['time_system']);
    final penalty = _map(time['night_penalty']);

    return WorldConfig(
      metadata: WorldMetadata(
        name: _string(meta['name'], 'world_metadata.name'),
        theme: _optional(meta['theme']) ?? 'Fantasy',
        levelCap: _int(meta['level_cap'], fallback: 20),
        backgroundLore: _optional(meta['background_lore']) ?? '',
      ),
      regions: [
        for (final entry in _list(root['regions']))
          if (entry is Map) _readRegion(entry.cast<String, Object?>()),
      ],
      time: TimeSystem(
        dayCycleHours: _int(time['day_cycle'], fallback: 24),
        nightStealthBonus: _int(penalty['stealth_bonus']),
        nightPerceptionPenalty: _int(penalty['perception_penalty']),
        dawnEcho: _optional(time['global_echo_dawn']),
        duskEcho: _optional(time['global_echo_dusk']),
      ),
    );
  }

  Region _readRegion(Map<String, Object?> raw) => Region(
        id: _string(raw['region_id'], 'region_id'),
        towns: _strings(raw['towns']),
        ambianceEchoes: _strings(raw['ambiance_echoes']),
        weatherStates: {
          for (final e in _map(raw['weather_states']).entries)
            e.key: e.value.toString(),
        },
      );

  // --- locations -----------------------------------------------------------

  Locations readLocations(String json) {
    final root = _object(json, 'locations');

    final towns = <Town>[];
    for (final entry in _map(root['towns']).entries) {
      final raw = _map(entry.value);
      towns.add(Town(
        id: entry.key,
        name: _string(raw['name'], 'town name'),
        tier: _int(raw['tier'], fallback: 1),
        levelRange: [for (final v in _list(raw['level_range'])) _int(v)],
        description: _optional(raw['description']) ?? '',
        zones: [
          for (final zone in _map(raw['zones']).entries)
            Zone(id: zone.key, roomIds: _strings(zone.value)),
        ],
      ));
    }

    final rooms = <String, Room>{};
    for (final entry in _list(root['rooms'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final id = _string(raw['room_id'], 'room_id');
      if (rooms.containsKey(id)) {
        throw CampaignFormatException('Duplicate room id "$id".');
      }
      rooms[id] = Room(
        id: id,
        title: _optional(raw['title']) ?? id,
        description: _optional(raw['description']) ?? '',
        exits: {
          for (final e in _map(raw['exits']).entries)
            e.key.trim().toLowerCase(): e.value.toString(),
        },
      );
    }

    return Locations(towns: towns, rooms: rooms);
  }

  // --- npcs ----------------------------------------------------------------

  NpcDirectory readNpcs(String json) {
    final root = _object(json, 'npcs');
    final npcs = <Npc>[];
    final seen = <String>{};
    for (final entry in _list(root['npcs'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final id = _string(raw['npc_id'], 'npc_id');
      if (!seen.add(id)) {
        throw CampaignFormatException('Duplicate npc id "$id".');
      }
      npcs.add(Npc(
        id: id,
        name: _string(raw['name'], 'npc name'),
        location: _string(raw['location'], 'npc location'),
        tier: _int(raw['tier'], fallback: 1),
        appearance: _optional(raw['appearance']) ?? '',
        greeting: _optional(raw['greeting']) ?? '',
        keywords: {
          for (final e in _map(raw['keywords']).entries)
            e.key.trim().toLowerCase(): e.value.toString(),
        },
      ));
    }
    return NpcDirectory(npcs);
  }

  // --- gear ----------------------------------------------------------------

  GearTable readGear(String json) {
    final root = _object(json, 'gear');
    final items = <GearItem>[];
    final seen = <String>{};
    for (final entry in _list(root['gear'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final id = _string(raw['item_id'], 'item_id');
      if (!seen.add(id)) {
        throw CampaignFormatException('Duplicate item id "$id".');
      }
      items.add(GearItem(
        id: id,
        name: _string(raw['name'], 'item name'),
        level: _int(raw['level'], fallback: 1),
        type: _optional(raw['type']) ?? 'item',
        description: _optional(raw['description']) ?? '',
        traits: _strings(raw['traits']),
        stats: _map(raw['stats']),
        special: _optional(raw['special']),
      ));
    }
    return GearTable(items);
  }

  // --- arcs ----------------------------------------------------------------

  ArcTrack readArcs(String json) {
    final root = _object(json, 'campaign arcs');
    final arcs = <CampaignArc>[];
    final seen = <String>{};
    for (final entry in _list(root['arcs'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final id = _string(raw['arc_id'], 'arc_id');
      if (!seen.add(id)) {
        throw CampaignFormatException('Duplicate arc id "$id".');
      }
      arcs.add(CampaignArc(
        id: id,
        name: _string(raw['name'], 'arc name'),
        levels: [for (final v in _list(raw['levels'])) _int(v)],
        startTrigger: _string(raw['start_trigger'], 'start_trigger'),
        objectives: [
          for (final o in _list(raw['objectives']))
            if (o is Map)
              ArcObjective(
                id: _int((o.cast<String, Object?>())['id'], fallback: 1),
                task: _string(
                    (o.cast<String, Object?>())['task'], 'objective task'),
                condition: _string((o.cast<String, Object?>())['condition'],
                    'objective condition'),
              ),
        ],
        worldStateChanges: _strings(raw['world_state_changes_on_completion']),
      ));
    }
    return ArcTrack(arcs);
  }

  // --- helpers -------------------------------------------------------------

  Map<String, Object?> _object(String json, String what) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw CampaignFormatException(
          'The $what is not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw CampaignFormatException(
          'The $what must be a JSON object at the top level.');
    }
    return decoded.cast<String, Object?>();
  }

  static Map<String, Object?> _map(Object? raw) =>
      raw is Map ? raw.cast<String, Object?>() : const {};

  static List<Object?> _list(Object? raw) => raw is List ? raw : const [];

  static List<String> _strings(Object? raw) => [
        for (final v in _list(raw))
          if (v != null && v.toString().trim().isNotEmpty) v.toString().trim(),
      ];

  static String? _optional(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String _string(Object? raw, String field) {
    final value = _optional(raw);
    if (value == null) {
      throw CampaignFormatException('Missing required field "$field".');
    }
    return value;
  }

  static int _int(Object? raw, {int fallback = 0}) => switch (raw) {
        final int v => v,
        final num v => v.round(),
        final String v => int.tryParse(v.trim()) ?? fallback,
        _ => fallback,
      };
}
