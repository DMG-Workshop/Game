import 'dart:convert';

import 'package:pf2e_core/pf2e_core.dart';

import '../scene/adventure_loader.dart';
import '../party/experience.dart';
import '../scene/scene.dart';
import 'arc.dart';
import 'campaign.dart';
import 'conversation.dart';
import 'creature.dart';
import 'economy.dart';
import 'fight_scene.dart';
import 'gear.dart';
import 'hunt.dart';
import 'locations.dart';
import 'npc.dart';
import 'spell.dart';
import 'weather.dart';
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
    String? conversationsJson,
    String? economyJson,
    String? huntJson,
    String? weatherJson,
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
        conversations: conversationsJson == null
            ? null
            : readConversations(conversationsJson),
        economy: economyJson == null ? null : readEconomy(economyJson),
        hunts: huntJson == null ? null : readHunts(huntJson),
        weather: weatherJson == null ? null : readWeather(weatherJson),
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
        shelter: raw['shelter'] == true,
        ambiance: _strings(raw['ambiance']),
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
        minutes: m['minutes'] == null ? null : _int(m['minutes']),
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
        route: _readRoute(raw['route'], id),
        barks: [
          for (final b in _list(raw['barks']))
            if (b is Map)
              NpcBark(
                line: b['line']?.toString().trim() ?? '',
                requiredFlags: _strings(b['requires']),
                forbiddenFlags: _strings(b['unless']),
              ),
        ],
      ));
    }
    return NpcDirectory(npcs);
  }

  NpcRoute? _readRoute(Object? raw, String npcId) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    final stops = _strings(m['stops']);
    if (stops.isEmpty) {
      throw CampaignFormatException(
          '"$npcId" travels but has nowhere to travel to.');
    }
    final every = _int(m['every'], fallback: 10);
    final away = _int(m['away_chance'], fallback: 25);
    if (every < 1 || away < 0 || away > 100) {
      throw CampaignFormatException('"$npcId" has a route that moves every '
          '$every steps with a $away% chance of being away.');
    }
    return NpcRoute(stops: stops, every: every, awayChance: away);
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
        listedPrice: _readPrice(raw['price'], 'item "$id"'),
        drops: [
          for (final d in _list(raw['drops']))
            if (d is Map) _readDrop(d.cast<String, Object?>(), id),
        ],
        checkBonuses: [
          for (final b in _list(raw['check_bonuses']))
            if (b is Map)
              CheckBonus(
                stat: _string(b['stat'], 'check bonus on "$id"').toLowerCase(),
                bonus: _int(b['bonus']),
                when: _optional(b['when']),
              ),
        ],
        use: _readUse(raw['use'], id, _strings(raw['traits'])),
      ));
    }
    return GearTable(items);
  }

  /// Reads what using an item up does.
  ///
  /// Only a consumable is used up, and a healing roll the engine cannot read
  /// is a typo worth hearing about now rather than the first time somebody
  /// is bleeding and reaches for it.
  ItemUse? _readUse(Object? raw, String itemId, List<String> traits) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw CampaignFormatException(
          'Item "$itemId" has a "use" that is not an object.');
    }
    if (!traits.any((t) => t.trim().toLowerCase() == 'consumable')) {
      throw CampaignFormatException('Item "$itemId" can be used up, but is not '
          'consumable.');
    }
    final heal = DamageExpression.tryParse(_optional(raw['heal']) ?? '');
    if (heal == null) {
      throw CampaignFormatException('Item "$itemId" heals "${raw['heal']}", '
          'which is not a roll the engine can read.');
    }
    // A turn is three actions, so nothing can take more.
    final actions = _int(raw['actions'], fallback: 1);
    if (actions < 1 || actions > 3) {
      throw CampaignFormatException('Item "$itemId" takes $actions actions to '
          'use, which is not 1 to 3.');
    }
    return ItemUse(heal: heal, actions: actions);
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
        voice: _readVoice(raw['voice']),
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
        rearmOn: _strings(raw['rearm_on']),
        rearmDescription: _optional(raw['rearm_description']),
        ambush: raw['ambush'] == true,
        coin: _readCoinDice(raw['coin'], 'Fight "$id"'),
        scene: _readScene(raw['scene'], 'fight "$id"'),
      ));
    }

    return Bestiary(creatures: creatures, encounters: encounters);
  }

  /// Reads what a creature says, or does, when a fight turns.
  CreatureVoice? _readVoice(Object? raw) {
    if (raw is! Map) return null;
    return CreatureVoice(
      speaks: raw['speaks'] != false,
      taunts: _strings(raw['taunts']),
      hurt: _strings(raw['hurt']),
      dying: _strings(raw['dying']),
    );
  }

  /// Reads the words around a fight.
  FightScene? _readScene(Object? raw, String what) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    List<SceneLine> lines(String key) => [
          for (final entry in _list(m[key]))
            if (entry is Map) _readLine(entry.cast<String, Object?>(), what),
        ];
    return FightScene(
      setting: _optional(m['setting']) ?? '',
      ambiance: _strings(m['ambiance']),
      opening: lines('opening'),
      bloodied: lines('bloodied'),
      firstDown: lines('first_down'),
      victory: lines('victory'),
      defeat: lines('defeat'),
      flee: lines('flee'),
    );
  }

  /// One line: `{"enemy": "..."}`, `{"pc": "..."}` or `{"text": "..."}`.
  SceneLine _readLine(Map<String, Object?> raw, String what) {
    if (raw.length != 1) {
      throw CampaignFormatException('A line in $what has ${raw.length} '
          'speakers; it should have one of enemy, pc or text.');
    }
    final entry = raw.entries.single;
    final speaker = Speaker.tryParse(entry.key);
    if (speaker == null) {
      throw CampaignFormatException('A line in $what is spoken by '
          '"${entry.key}", which is not enemy, pc or text.');
    }
    return SceneLine(speaker, entry.value.toString());
  }

  /// Reads a fight's coin as dice in gold, checked now rather than when the
  /// party is standing over the bodies.
  String? _readCoinDice(Object? raw, String what) {
    final dice = _optional(raw);
    if (dice == null) return null;
    final parsed = DamageExpression.tryParse(dice);
    if (parsed == null || parsed.minimum < 0) {
      throw CampaignFormatException(
          '$what pays "$dice", which is not dice of gold.');
    }
    return dice;
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
        sayOnTake: _optional(raw['say_on_take']),
        sayOnDestroy: _optional(raw['say_on_destroy']),
      ));
    }
    return ItemPlacements(items);
  }

  // --- shops and rewards ----------------------------------------------------

  /// Reads the campaign's shops and the coin it pays for things done.
  ///
  /// Prices and rewards are written in gold, as a Pathfinder player would
  /// write them, and held in copper so a price like 1 gp 5 sp is exact.
  Economy readEconomy(String json) {
    final root = _object(json, 'economy');
    final shops = <Shop>[];
    final seen = <String>{};
    for (final entry in _list(root['shops'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final id = _string(raw['shop_id'], 'shop_id');
      if (!seen.add(id)) {
        throw CampaignFormatException('Duplicate shop id "$id".');
      }
      shops.add(Shop(
        id: id,
        name: _string(raw['name'], 'shop name'),
        keeperId: _string(raw['keeper'], 'shop keeper on "$id"'),
        location: _optional(raw['location']),
        carries: raw['carries'] == null ? null : _int(raw['carries']),
        lines: ShopLines(
          greet: _strings(_map(raw['lines'])['greet']),
          buy: _strings(_map(raw['lines'])['buy']),
          sell: _strings(_map(raw['lines'])['sell']),
          broke: _strings(_map(raw['lines'])['broke']),
        ),
        stock: [
          for (final line in _list(raw['stock']))
            if (line is Map)
              StockLine(
                itemId: _string(line.cast<String, Object?>()['item'],
                    'stock item on "$id"'),
                requiredFlags: _strings(line['requires']),
              ),
        ],
        modifiers: [
          for (final m in _list(raw['price_modifiers']))
            if (m is Map)
              PriceModifier(
                flag: _string(
                    m.cast<String, Object?>()['flag'], 'modifier on "$id"'),
                percent: _int(m['percent']),
              ),
        ],
      ));
    }

    final rewards = <Reward>[];
    for (final entry in _list(root['rewards'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final flag = _string(raw['flag'], 'reward flag');
      final payout = _readPayout(raw, 'the reward for "$flag"');
      if (payout.isEmpty) {
        throw CampaignFormatException('The reward for "$flag" pays nothing.');
      }
      rewards.add(Reward(
        flag: flag,
        payout: payout,
        from: _optional(raw['from']),
      ));
    }
    return Economy(shops: shops, rewards: rewards);
  }

  /// Reads `gp` and `xp` from a reward. XP may be a number or the size of the
  /// accomplishment — `minor`, `moderate`, `major` — which is how Pathfinder
  /// asks a GM to think about it.
  Payout _readPayout(Map<String, Object?> raw, String what) {
    final rawXp = raw['xp'];
    final int xp;
    if (rawXp == null) {
      xp = 0;
    } else if (rawXp is String && Accomplishment.tryParse(rawXp) != null) {
      xp = Accomplishment.tryParse(rawXp)!.xp;
    } else {
      final n = _int(rawXp, fallback: -1);
      if (n < 0) {
        throw CampaignFormatException('The XP of $what is "$rawXp", which is '
            'neither a number nor minor, moderate or major.');
      }
      xp = n;
    }
    return Payout(copper: _readPrice(raw['gp'], what) ?? 0, xp: xp);
  }

  /// Reads an amount written in gold pieces as copper, or null if absent.
  int? _readPrice(Object? raw, String what) {
    if (raw == null) return null;
    final gp = switch (raw) {
      final num v => v,
      final String v => num.tryParse(v.trim()),
      _ => null,
    };
    if (gp == null || gp < 0) {
      throw CampaignFormatException('The price of $what is "$raw", which is '
          'not an amount of gold.');
    }
    return (gp * 100).round();
  }

  // --- the hunt ------------------------------------------------------------

  /// Reads who comes after a party that has got rich.
  ///
  /// Chances and percentages are checked here, and every hunter's coin: a
  /// hunter that paid nothing would make getting richer a pure loss.
  HuntTable readHunts(String json) {
    final root = _object(json, 'hunt');
    final tiers = <NotorietyTier>[];
    for (final entry in _list(root['notoriety'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final name = _string(raw['name'], 'notoriety tier name');
      final threatName = _optional(raw['threat']);
      final threat = threatName == null ? null : Threat.tryParse(threatName);
      if (threatName != null && threat == null) {
        throw CampaignFormatException('Notoriety "$name" has threat '
            '"$threatName", which is not one of: '
            '${Threat.values.map((t) => t.name).join(', ')}.');
      }
      final chance = _int(raw['chance']);
      if (chance < 0 || chance > 100) {
        throw CampaignFormatException('Notoriety "$name" has a $chance% '
            'chance, which is not a percentage.');
      }
      tiers.add(NotorietyTier(
        name: name,
        fromPercent: _int(raw['from_percent']),
        threat: threat,
        chance: chance,
        description: _optional(raw['description']) ?? '',
      ));
    }

    final hunters = <Hunter>[];
    final seen = <String>{};
    for (final entry in _list(root['hunters'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final id = _string(raw['creature'], 'hunter creature');
      if (!seen.add(id)) {
        throw CampaignFormatException('"$id" is on the hunt twice.');
      }
      hunters.add(Hunter(
        creatureId: id,
        coin: _readCoinDice(raw['coin'], 'Hunter "$id"') ??
            (throw CampaignFormatException('Hunter "$id" carries no coin.')),
        arrival: _optional(raw['arrival']) ?? '',
        scene: _readScene(raw['scene'], 'hunter "$id"'),
      ));
    }

    final rob = _int(root['rob_percent']);
    if (rob < 0 || rob > 100) {
      throw CampaignFormatException(
          'A hunter takes $rob% of the purse, which is not a percentage.');
    }
    return HuntTable(
      tiers: tiers,
      hunters: hunters,
      restSteps: _int(root['rest_steps'], fallback: 6),
      robPercent: rob,
    );
  }

  // --- spells --------------------------------------------------------------

  /// Reads a spell table from a content package.
  ///
  /// Spells are rules content rather than campaign content, so they are read
  /// on their own and handed to the session, not folded into a campaign.
  SpellBook readSpells(String json) {
    final root = _object(json, 'spells');
    final spells = <Spell>[];
    final seen = <String>{};
    for (final entry in _list(root['spells'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final name = _string(raw['name'], 'spell name');
      if (!seen.add(name.toLowerCase())) {
        throw CampaignFormatException('"$name" is in the spell table twice.');
      }
      final defenseName = _string(raw['defense'], 'defense of "$name"');
      final defense = SpellDefense.tryParse(defenseName);
      if (defense == null) {
        throw CampaignFormatException('"$name" is rolled against '
            '"$defenseName", which is not ac, fortitude, reflex or will.');
      }
      final damage = DamageExpression.tryParse(
          _string(raw['damage'], 'damage of "$name"'));
      if (damage == null) {
        throw CampaignFormatException('"$name" has damage "${raw['damage']}", '
            'which is not dice.');
      }
      final heighten = _map(raw['heighten']);
      final extraRaw = _optional(heighten['damage']);
      final extra =
          extraRaw == null ? null : DamageExpression.tryParse(extraRaw);
      if (extraRaw != null &&
          (extra == null || extra.dieSize != damage.dieSize)) {
        throw CampaignFormatException('"$name" heightens by "$extraRaw", '
            'which is not more of its own dice.');
      }
      final range = _optional(raw['range']) ?? 'far';
      if (!const {'engaged', 'near', 'far'}.contains(range)) {
        throw CampaignFormatException('"$name" reaches "$range", which is not '
            'engaged, near or far.');
      }
      spells.add(Spell(
        name: name,
        rank: _int(raw['rank']),
        defense: defense,
        damage: damage,
        actions: _int(raw['actions'], fallback: 2),
        range: range,
        area: raw['area'] == true,
        heightenEvery: _int(heighten['every'], fallback: 1).clamp(1, 10),
        heightenDamage: extra,
      ));
    }
    return SpellBook(spells);
  }

  // --- the calendar and the weather ------------------------------------------

  /// Reads the calendar, the road, and each region's weather by season.
  WeatherBook readWeather(String json) {
    final root = _object(json, 'weather');
    final cal = _map(root['calendar']);
    final seasons = [
      for (final s in _list(cal['seasons']))
        if (s is Map)
          Season(
            id: _string(s['id'], 'season id'),
            name: _string(s['name'], 'season name'),
            days: _int(s['days'], fallback: 30),
          ),
    ];
    if (seasons.isEmpty) {
      throw CampaignFormatException('The calendar has no seasons.');
    }
    final start = _map(cal['start']);
    final startId = _optional(start['season']) ?? seasons.first.id;
    final startIndex = seasons.indexWhere((s) => s.id == startId);
    if (startIndex < 0) {
      throw CampaignFormatException(
          'The calendar starts in "$startId", which is not a season.');
    }

    final road = _map(root['travel']);
    const defaults = TravelTimes();
    final travel = TravelTimes(
      sameZoneMinutes:
          _int(road['same_zone_minutes'], fallback: defaults.sameZoneMinutes),
      newZoneMinutes:
          _int(road['new_zone_minutes'], fallback: defaults.newZoneMinutes),
      newTownMinutes:
          _int(road['new_town_minutes'], fallback: defaults.newTownMinutes),
      fatiguedAfterHours: _int(road['fatigued_after_hours'],
          fallback: defaults.fatiguedAfterHours),
      exhaustedAfterHours: _int(road['exhausted_after_hours'],
          fallback: defaults.exhaustedAfterHours),
      awakeHours: _int(road['awake_hours'], fallback: defaults.awakeHours),
    );

    final types = <WeatherType>[];
    for (final w in _list(root['weather'])) {
      if (w is! Map) continue;
      final raw = w.cast<String, Object?>();
      final id = _string(raw['id'], 'weather id');
      final severityName = _optional(raw['severity']) ?? 'fair';
      final severity = WeatherSeverity.tryParse(severityName);
      if (severity == null) {
        throw CampaignFormatException('Weather "$id" is "$severityName", '
            'which is not fair, foul or severe.');
      }
      final travelRaw = raw['travel'];
      types.add(WeatherType(
        id: id,
        name: _optional(raw['name']) ?? id,
        severity: severity,
        travel: travelRaw is num ? travelRaw.toDouble() : 1.0,
        rangedPenalty: _int(raw['ranged_penalty']),
        text: _optional(raw['text']) ?? '',
        exposure: _optional(raw['exposure']),
        after: _optional(raw['after']),
        remark: _optional(raw['remark']),
      ));
    }

    final tables = <String, Map<String, List<WeatherBand>>>{};
    for (final region in _map(root['regions']).entries) {
      tables[region.key] = {
        for (final season in _map(region.value).entries)
          season.key: [
            for (final band in _list(season.value))
              if (band is List && band.length == 2)
                WeatherBand(
                    upTo: _int(band[0]), weather: band[1].toString().trim()),
          ],
      };
    }

    return WeatherBook(
      calendar: Calendar(
        seasons: seasons,
        startSeason: startIndex,
        startDayOfSeason: _int(start['day'], fallback: 1),
      ),
      travel: travel,
      types: types,
      tables: tables,
      restLines: RestLines(
        indoors: _strings(_map(root['rest'])['indoors']),
        outdoors: _strings(_map(root['rest'])['outdoors']),
        pc: _strings(_map(root['rest'])['pc']),
        wake: _strings(_map(root['rest'])['wake']),
      ),
    );
  }

  // --- conversations -------------------------------------------------------

  /// Reads the campaign's conversations.
  ///
  /// Each one's scenes go through the adventure loader, so a line that leads
  /// nowhere or a choice with no outcome is refused here exactly as it would
  /// be in an adventure, and named by the NPC it belongs to.
  Conversations readConversations(String json) {
    final root = _object(json, 'conversations');
    final conversations = <Conversation>[];
    final seen = <String>{};

    for (final entry in _list(root['conversations'])) {
      if (entry is! Map) continue;
      final raw = entry.cast<String, Object?>();
      final npcId = _string(raw['npc'], 'conversation npc');
      if (!seen.add(npcId)) {
        throw CampaignFormatException('Two conversations for "$npcId".');
      }

      final entries = [
        for (final e in _list(raw['entries']))
          if (e is Map)
            ConversationEntry(
              sceneId: _string(
                  e.cast<String, Object?>()['scene'], 'entry scene on $npcId'),
              requiredFlags: _strings(e['requires']),
              forbiddenFlags: _strings(e['unless']),
            ),
      ];
      if (entries.isEmpty) {
        throw CampaignFormatException(
            'The conversation with "$npcId" has no way in.');
      }

      final Adventure adventure;
      try {
        adventure = const AdventureLoader().fromMap({
          'id': 'conversation_$npcId',
          'title': npcId,
          'startScene': entries.last.sceneId,
          'scenes': raw['scenes'],
        });
      } on AdventureFormatException catch (e) {
        throw CampaignFormatException(
            'The conversation with "$npcId": ${e.message}');
      }

      for (final e in entries) {
        if (adventure.sceneById(e.sceneId) == null) {
          throw CampaignFormatException('The conversation with "$npcId" '
              'opens on "${e.sceneId}", which it does not have.');
        }
      }

      conversations.add(Conversation(
        npcId: npcId,
        entries: entries,
        adventure: adventure,
      ));
    }
    return Conversations(conversations);
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
        isSide: _optional(raw['kind'])?.toLowerCase() == 'side',
        zone: _optional(raw['zone']),
        reward: raw['reward'] is Map
            ? _readPayout((raw['reward'] as Map).cast<String, Object?>(),
                'the reward for "$id"')
            : null,
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
