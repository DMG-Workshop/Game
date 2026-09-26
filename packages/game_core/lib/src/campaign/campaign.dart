import 'arc.dart';
import 'conversation.dart';
import 'creature.dart';
import 'gear.dart';
import 'locations.dart';
import 'npc.dart';
import 'world.dart';
import 'world_item.dart';

/// A whole campaign: its world, map, cast, loot and arcs.
class Campaign {
  Campaign({
    required this.id,
    required this.title,
    required this.world,
    required this.locations,
    required this.npcs,
    required this.gear,
    required this.arcs,
    Bestiary? bestiary,
    ItemPlacements? items,
    Conversations? conversations,
  })  : bestiary = bestiary ?? Bestiary(),
        items = items ?? ItemPlacements(const []),
        conversations = conversations ?? Conversations(const []);

  final String id;
  final String title;
  final WorldConfig world;
  final Locations locations;
  final NpcDirectory npcs;
  final GearTable gear;
  final ArcTrack arcs;

  /// Creatures and the fights they appear in.
  final Bestiary bestiary;

  /// Objects lying in rooms, as opposed to equipment.
  final ItemPlacements items;

  /// What the cast says when properly talked to.
  final Conversations conversations;

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
        misplacedEncounters: bestiary.misplacedIn(locations.rooms.keys.toSet()),
        misplacedItems: items.misplacedIn(locations.rooms.keys.toSet()),
        encountersMissingCreatures: bestiary.missingCreatures,
        danglingDrops: gear.danglingDrops(
            {for (final creature in bestiary.creatures) creature.id}),
        unobtainableGear: gear.unobtainableRarities,
        orphanedConversations:
            conversations.orphanedFrom({for (final n in npcs.all) n.id}),
      );

  /// Arc conditions nothing in the campaign could ever set.
  ///
  /// A condition nothing can produce is a quest step that can never be ticked
  /// off, which strands a player. Working out what *can* produce one means
  /// knowing what the engine does as well as what the data declares, so every
  /// source is accounted for:
  ///
  /// - flags a completed arc awards;
  /// - flags a won fight awards, and flags an item awards when taken or
  ///   destroyed;
  /// - flags a line of conversation sets;
  /// - `enter_<room>`, set by walking in — matched as a prefix, since the
  ///   triggers abbreviate and `enter_MH_001` means `MH_001_Square`;
  /// - `keyword_<topic>_unlocked`, set by raising a topic somebody answers;
  /// - `dialogue_complete_<npc>`, set by raising every topic an NPC has.
  ///
  /// Leaving the last three out made this report cry wolf on conditions that
  /// ordinary play already reaches.
  List<String> _unreachableArcConditions() {
    final produced = <String>{
      for (final arc in arcs.all) ...arc.worldStateChanges,
      ...bestiary.victoryFlags,
      ...items.producibleFlags,
      ...conversations.producibleFlags,
    };

    final knownRooms = <String>{
      ...locations.rooms.keys,
      ...locations.unwrittenRoomIds,
    };
    final keywordFlags = <String>{
      for (final npc in npcs.all)
        for (final topic in npc.keywords.keys) 'keyword_${topic}_unlocked',
    };
    final dialogueFlags = <String>{
      for (final npc in npcs.all) 'dialogue_complete_${npc.slug}',
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

    return needed
        .difference(produced)
        .difference(keywordFlags)
        .difference(dialogueFlags)
        .where((c) => !isMovement(c))
        .toList()
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
    this.misplacedEncounters = const [],
    this.misplacedItems = const [],
    this.encountersMissingCreatures = const [],
    this.danglingDrops = const [],
    this.unobtainableGear = const [],
    this.orphanedConversations = const [],
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

  /// Fights placed in rooms that do not exist.
  final List<Encounter> misplacedEncounters;

  /// Objects lying in rooms that do not exist.
  final List<WorldItem> misplacedItems;

  /// Fights naming a creature the bestiary does not have.
  final List<({Encounter encounter, String creatureId})>
      encountersMissingCreatures;

  /// Loot tables naming a creature the bestiary does not have.
  final List<({GearItem item, String creatureId})> danglingDrops;

  /// Rare items nothing in the campaign drops.
  final List<GearItem> unobtainableGear;

  /// Conversations written for an NPC the campaign does not have.
  final List<Conversation> orphanedConversations;

  bool get isClean =>
      unwrittenRooms.isEmpty &&
      danglingExits.isEmpty &&
      oneWayExits.isEmpty &&
      misplacedNpcs.isEmpty &&
      gearLevelGaps.isEmpty &&
      unreachableArcConditions.isEmpty &&
      misplacedEncounters.isEmpty &&
      misplacedItems.isEmpty &&
      encountersMissingCreatures.isEmpty &&
      danglingDrops.isEmpty &&
      unobtainableGear.isEmpty &&
      orphanedConversations.isEmpty;

  /// Problems that would strand a player right now, as opposed to content
  /// that is merely unfinished.
  bool get isPlayable =>
      danglingExits.isEmpty &&
      misplacedNpcs.isEmpty &&
      misplacedEncounters.isEmpty &&
      misplacedItems.isEmpty &&
      encountersMissingCreatures.isEmpty;

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
    section(
      'Fights in rooms that do not exist',
      misplacedEncounters.map((e) => '${e.name} in ${e.location}'),
    );
    section(
      'Objects in rooms that do not exist',
      misplacedItems.map((i) => '${i.name} in ${i.location}'),
    );
    section(
      'Fights naming a creature that does not exist',
      encountersMissingCreatures
          .map((e) => '${e.encounter.name} wants "${e.creatureId}"'),
    );
    section(
      'Loot naming a creature that does not exist',
      danglingDrops.map((d) => '${d.item.name} drops from "${d.creatureId}"'),
    );
    section(
      'Conversations for somebody who does not exist',
      orphanedConversations.map((c) => c.npcId),
    );
    section(
      'Rare items nothing drops',
      unobtainableGear
          .map((i) => '${i.name} (level ${i.level} ${i.rarity.name})'),
    );
    section('Arc conditions nothing sets', unreachableArcConditions);
    return b.toString().trimRight();
  }

  @override
  String toString() => render();
}
