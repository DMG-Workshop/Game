import 'dart:convert';

import 'package:pf2e_core/pf2e_core.dart';

import 'arc.dart';
import 'campaign.dart';
import 'creature.dart';
import 'gear.dart';
import 'locations.dart';
import 'npc.dart';
import 'world.dart';
import 'world_item.dart';

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
    String? bestiaryJson,
    String? itemsJson,
  }) =>
      Campaign(
        id: id,
        title: title,
        world: readWorld(worldConfigJson),
        locations: readLocations(locationsJson),
        npcs: readNpcs(npcsJson),
        gear: gearJson == null ? GearTable(const []) : readGear(gearJson),
        arcs: arcsJson == null ? ArcTrack(const []) : readArcs(arcsJson),
        bestiary: bestiaryJson == null ? null : readBestiary(bestiaryJson),
        items: itemsJson == null ? null : readItems(itemsJson),
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
            e.key.trim().toLowerCase():
                _readExit(e.key.trim().toLowerCase(), e.value, id),
        },
      );
    }

    return Locations(towns: towns, rooms: rooms);
  }

  /// Reads an exit, which may be a bare room id or an object that gates it.
  ///
  /// The plain string form stays valid, because most exits are not gated and
  /// making every author write an object for the common case would be noise.
  Exit _readExit(String direction, Object? raw, String roomId) {
    if (raw is Map) {
      final m = raw.cast<String, Object?>();
      return Exit(
        direction: direction,
        to: _string(m['to'], 'exit target in "$roomId"'),
        requiredFlags: _strings(m['requires']),
        blockedMessage: _optional(m['blocked']),
      );
    }
    final to = _optional(raw);
    if (to == null) {
      throw CampaignFormatException(
          'Room "$roomId" has an empty "$direction" exit.');
    }
    return Exit(direction: direction, to: to);
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
        rarity: _readRarity(_optional(raw['rarity']), id),
        drops: [
          for (final d in _list(raw['drops']))
            if (d is Map) _readDrop(d.cast<String, Object?>(), id),
        ],
      ));
    }
    return GearTable(items);
  }

  /// Reads an item's rarity, defaulting to common where it says nothing.
  ///
  /// Most magic gear in Pathfinder is common, so the default is the honest
  /// one; a value that is not a rarity at all is a typo, and a typo that
  /// silently made a rare item ordinary would never be noticed.
  ItemRarity _readRarity(String? raw, String itemId) {
    if (raw == null) return ItemRarity.common;
    final rarity = ItemRarity.tryParse(raw);
    if (rarity == null) {
      throw CampaignFormatException('Item "$itemId" has rarity "$raw", which '
          'is not one of: ${ItemRarity.values.map((r) => r.name).join(', ')}.');
    }
    return rarity;
  }

  /// Reads one entry of an item's drop table.
  ///
  /// A chance outside 1–100 is rejected rather than clamped: 0 would be an
  /// item nobody can ever find and 1000 is a typo, and both are the sort of
  /// thing a content author wants told to them now rather than after a
  /// hundred fights that dropped nothing.
  DropSource _readDrop(Map<String, Object?> raw, String itemId) {
    final chance = _int(raw['chance'], fallback: 100);
    if (chance < 1 || chance > 100) {
      throw CampaignFormatException(
          'Item "$itemId" has a drop chance of $chance, which is not a '
          'percentage between 1 and 100.');
    }
    return DropSource(
      creatureId: _string(raw['from'], 'drop source on "$itemId"'),
      chance: chance,
    );
  }

  // --- creatures and encounters --------------------------------------------

  Bestiary readBestiary(String json) {
    final root = _object(json, 'bestiary');

    final creatures = <Creature>[];
    final seenCreatures = <String>{};
    for (final entry in _list(root['creatures'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final id = _string(raw['creature_id'], 'creature_id');
      if (!seenCreatures.add(id)) {
        throw CampaignFormatException('Duplicate creature id "$id".');
      }
      creatures.add(Creature(
        id: id,
        name: _string(raw['name'], 'creature name'),
        level: _int(raw['level'], fallback: 1),
        description: _optional(raw['description']) ?? '',
        armorClass: _int(raw['ac'], fallback: 10),
        maxHp: _int(raw['hp'], fallback: 1),
        perception: _int(raw['perception']),
        fortitude: _int(raw['fortitude']),
        reflex: _int(raw['reflex']),
        will: _int(raw['will']),
        traits: _strings(raw['traits']),
        speed: _int(raw['speed'], fallback: 25),
        specials: _strings(raw['specials']),
        isBoss: raw['boss'] == true,
        attacks: [
          for (final a in _list(raw['attacks']))
            if (a is Map) _readAttack(a.cast<String, Object?>(), id),
        ],
      ));
    }

    final encounters = <Encounter>[];
    final seenEncounters = <String>{};
    for (final entry in _list(root['encounters'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final id = _string(raw['encounter_id'], 'encounter_id');
      if (!seenEncounters.add(id)) {
        throw CampaignFormatException('Duplicate encounter id "$id".');
      }
      final zones = _strings(raw['zones']);
      encounters.add(Encounter(
        id: id,
        location: _string(raw['location'], 'encounter location'),
        name: _string(raw['name'], 'encounter name'),
        description: _optional(raw['description']) ?? '',
        creatureIds: _strings(raw['creatures']),
        zones: zones.isEmpty ? const ['engaged', 'near', 'far'] : zones,
        startZone: _optional(raw['start_zone']) ?? 'near',
        victoryFlags: _strings(raw['victory_flags']),
        requiredFlags: _strings(raw['requires']),
        repeatable: raw['repeatable'] == true,
      ));
    }

    return Bestiary(creatures: creatures, encounters: encounters);
  }

  CreatureAttack _readAttack(Map<String, Object?> raw, String creatureId) {
    final damage = _string(raw['damage'], 'attack damage on "$creatureId"');
    // Validated here so a malformed statblock fails when the campaign loads
    // rather than in the middle of a fight.
    if (DamageExpression.tryParse(damage) == null) {
      throw CampaignFormatException(
          'Creature "$creatureId" has an unreadable damage expression '
          '"$damage".');
    }
    return CreatureAttack(
      name: _string(raw['name'], 'attack name on "$creatureId"'),
      attackBonus: _int(raw['bonus']),
      damage: damage,
      damageType: _optional(raw['damage_type']) ?? 'B',
      traits: _strings(raw['traits']),
      reach: _optional(raw['reach']) ?? 'engaged',
      onCritical: _optional(raw['on_critical']),
    );
  }

  // --- world items ---------------------------------------------------------

  ItemPlacements readItems(String json) {
    final root = _object(json, 'items');
    final items = <WorldItem>[];
    final seen = <String>{};
    for (final entry in _list(root['items'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final id = _string(raw['item_id'], 'item_id');
      if (!seen.add(id)) {
        throw CampaignFormatException('Duplicate world item id "$id".');
      }
      items.add(WorldItem(
        id: id,
        name: _string(raw['name'], 'item name'),
        location: _string(raw['location'], 'item location'),
        description: _optional(raw['description']) ?? '',
        inRoomText: _optional(raw['in_room']),
        takeable: raw['takeable'] != false,
        destroyable: raw['destroyable'] == true,
        acquireFlags: _strings(raw['acquire_flags']),
        destroyFlags: _strings(raw['destroy_flags']),
        requiredFlags: _strings(raw['requires']),
        hiddenUntilFlags: _strings(raw['hidden_until']),
        onTake: _optional(raw['on_take']),
        onDestroy: _optional(raw['on_destroy']),
      ));
    }
    return ItemPlacements(items);
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
