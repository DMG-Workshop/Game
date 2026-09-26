import 'arc.dart';
import 'conversation.dart';
import 'creature.dart';
import 'economy.dart';
import 'gear.dart';
import 'hunt.dart';
import 'locations.dart';
import 'npc.dart';
import 'weather.dart';
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
    Economy? economy,
    HuntTable? hunts,
    WeatherBook? weather,
  })  : bestiary = bestiary ?? Bestiary(),
        items = items ?? ItemPlacements(const []),
        conversations = conversations ?? Conversations(const []),
        economy = economy ?? Economy(),
        hunts = hunts ?? HuntTable(),
        weather = weather ?? WeatherBook();

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

  /// Where gear is bought and sold, and the coin paid for deeds.
  final Economy economy;

  /// What comes after a party that gets rich.
  final HuntTable hunts;

  /// The calendar, the road, and the sky.
  final WeatherBook weather;

  /// What setting [flag] pays: a reward the economy lists, or the reward for
  /// the quest [flag] marks as finished.
  Payout? payoutFor(String flag) =>
      economy.rewardFor(flag) ?? arcs.completedBy(flag)?.reward;

  /// Who or what paid for setting [flag], as the party's ledger reads.
  String payerFor(String flag) =>
      economy.payerFor(flag) ?? arcs.completedBy(flag)?.name ?? flag;

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
        unobtainableGear: _unobtainableGear(),
        orphanedConversations:
            conversations.orphanedFrom({for (final n in npcs.all) n.id}),
        unpaidEncounters: [
          for (final e in bestiary.encounters)
            if (e.coin == null) e,
        ],
        unrewardedArcs: [
          for (final arc in arcs.all)
            if ((arc.reward?.copper ?? 0) <= 0 || (arc.reward?.xp ?? 0) <= 0)
              arc,
        ],
        shopProblems: economy.problems(
          gear: gear,
          npcs: npcs,
          roomIds: locations.rooms.keys.toSet(),
        ),
        sideQuestGaps: _sideQuestGaps(),
        weatherProblems:
            weather.problems(regionIds: [for (final r in world.regions) r.id]),
        dialogueGaps: _dialogueGaps(),
        gearBonusProblems: _gearBonusProblems(),
        huntProblems: hunts.problems(
          bestiary,
          levels: [for (var l = 1; l <= world.metadata.levelCap; l++) l],
        ),
      );

  /// Items no amount of playing would turn up: nothing drops them, no shop
  /// stocks them, and nobody hands them over.
  ///
  /// Rarity says where an item may come from, not whether it comes from
  /// anywhere, so every item is checked. A gift is a line of conversation
  /// setting `loot_<item>`, which is how somebody gives the party a thing.
  List<GearItem> _unobtainableGear() {
    final sold = {
      for (final shop in economy.shops)
        for (final line in shop.stock) line.itemId,
    };
    final given = {
      for (final flag in conversations.producibleFlags)
        if (flag.startsWith('loot_')) flag.substring('loot_'.length),
    };
    return [
      for (final item in gear.all)
        if (!item.isDrop && !sold.contains(item.id) && !given.contains(item.id))
          item,
    ]..sort((a, b) => a.level.compareTo(b.level));
  }

  /// Item bonuses that could never apply: a condition naming a region or a
  /// part of the map that does not exist, or one the engine does not know.
  List<String> _gearBonusProblems() {
    final regions = {for (final r in world.regions) r.id};
    final zones = {
      for (final town in locations.towns)
        for (final zone in town.zones) zone.id,
    };
    final out = <String>[];
    for (final item in gear.all) {
      for (final b in item.checkBonuses) {
        final when = b.when;
        final ok = when == null ||
            when == 'exposure' ||
            (when.startsWith('region:') &&
                regions.contains(when.substring('region:'.length))) ||
            (when.startsWith('zone:') &&
                zones.contains(when.substring('zone:'.length)));
        if (!ok) {
          out.add('${item.name} gives $b, which can never apply');
        }
        if (b.bonus <= 0) out.add('${item.name} gives a bonus of ${b.bonus}');
      }
    }
    return out;
  }

  /// Everywhere something happens with nothing said about it.
  ///
  /// Every fight and every hunter needs a scene: where it is, what it feels
  /// like, and words at its start and at each way it can end. Every creature
  /// needs a voice for the turns of a fight, even if its voice is only what
  /// it does. Every room needs something going on in it, every object
  /// something said on picking it up or breaking it, every shopkeeper
  /// something to say across the counter, and the weather and the night
  /// their lines too.
  List<String> _dialogueGaps() {
    final out = <String>[];
    for (final e in bestiary.encounters) {
      final scene = e.scene;
      if (scene == null) {
        out.add('${e.name} (${e.id}) has no scene');
      } else {
        for (final gap in scene.gaps()) {
          out.add('${e.name} (${e.id}): $gap');
        }
      }
    }
    for (final h in hunts.hunters) {
      final scene = h.scene;
      if (scene == null) {
        out.add('Hunter ${h.creatureId} has no scene');
      } else {
        for (final gap in scene.gaps()) {
          out.add('Hunter ${h.creatureId}: $gap');
        }
      }
    }
    for (final c in bestiary.creatures) {
      final voice = c.voice;
      if (voice == null) {
        out.add('${c.name} (${c.id}) has no voice');
      } else {
        for (final gap in voice.gaps()) {
          out.add('${c.name} (${c.id}): $gap');
        }
      }
    }
    for (final room in locations.rooms.values) {
      if (room.ambiance.length < 2) {
        out.add('${room.title} (${room.id}) has fewer than two lines of '
            'ambiance');
      }
    }
    for (final item in items.all) {
      if (item.takeable && item.sayOnTake == null) {
        out.add('${item.name} (${item.id}): nothing said taking it');
      }
      if (item.destroyable && item.sayOnDestroy == null) {
        out.add('${item.name} (${item.id}): nothing said breaking it');
      }
    }
    for (final shop in economy.shops) {
      for (final gap in shop.lines.gaps()) {
        out.add('${shop.name}: $gap');
      }
    }
    if (!weather.isEmpty) {
      for (final type in weather.types) {
        if (type.remark == null) out.add('${type.name}: no remark');
      }
      for (final gap in weather.restLines.gaps()) {
        out.add('Resting: $gap');
      }
    }
    return out;
  }

  /// Parts of the map with no side quest set in them, and side quests set
  /// somewhere the map does not have.
  ///
  /// Every region should have something to do besides the main road, or the
  /// map has places that are only ever walked through.
  List<String> _sideQuestGaps() {
    final zones = {
      for (final town in locations.towns)
        for (final zone in town.zones) zone.id,
    };
    final covered = {
      for (final arc in arcs.all)
        if (arc.isSide && arc.zone != null) arc.zone!,
    };
    return [
      for (final zone in zones.difference(covered).toList()..sort())
        'No side quest in $zone',
      for (final arc in arcs.all)
        if (arc.zone != null && !zones.contains(arc.zone))
          '${arc.name} is set in "${arc.zone}", which is not on the map',
    ];
  }

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
  /// - `dialogue_complete_<npc>`, set by raising every topic an NPC has;
  /// - `hunted_first` and `hunt_survived_<n>`, set by being hunted, when the
  ///   campaign has anything to hunt the party with.
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
        .where((c) => !isMovement(c) && !hunts.producesFlag(c))
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
    this.shopProblems = const [],
    this.unpaidEncounters = const [],
    this.unrewardedArcs = const [],
    this.huntProblems = const [],
    this.sideQuestGaps = const [],
    this.weatherProblems = const [],
    this.dialogueGaps = const [],
    this.gearBonusProblems = const [],
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

  /// Items nothing in the campaign drops, sells or gives.
  final List<GearItem> unobtainableGear;

  /// Conversations written for an NPC the campaign does not have.
  final List<Conversation> orphanedConversations;

  /// Shops selling what they should not, or kept by nobody.
  final List<String> shopProblems;

  /// Fights that pay no coin. Every fight should: somebody was carrying
  /// something.
  final List<Encounter> unpaidEncounters;

  /// Quests, main or side, that pay no coin or no XP.
  final List<CampaignArc> unrewardedArcs;

  /// Hunters that cannot be sent, and levels nothing can be sent at.
  final List<String> huntProblems;

  /// Regions with nothing to do off the main road.
  final List<String> sideQuestGaps;

  /// Seasons with no weather, and weather that does not add up.
  final List<String> weatherProblems;

  /// Fights, creatures, rooms and the rest with nothing said about them.
  final List<String> dialogueGaps;

  /// Item bonuses that could never apply.
  final List<String> gearBonusProblems;

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
      orphanedConversations.isEmpty &&
      shopProblems.isEmpty &&
      unpaidEncounters.isEmpty &&
      unrewardedArcs.isEmpty &&
      huntProblems.isEmpty &&
      sideQuestGaps.isEmpty &&
      weatherProblems.isEmpty &&
      dialogueGaps.isEmpty &&
      gearBonusProblems.isEmpty;

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
    section('Shops that need attention', shopProblems);
    section('Fights that pay no coin',
        unpaidEncounters.map((e) => '${e.name} (${e.id})'));
    section('Quests that pay no coin or no XP',
        unrewardedArcs.map((a) => '${a.name} (${a.id})'));
    section('The hunt', huntProblems);
    section('Side quests', sideQuestGaps);
    section('Weather', weatherProblems);
    section('Scenes and dialogue', dialogueGaps);
    section('Item bonuses', gearBonusProblems);
    section(
      'Conversations for somebody who does not exist',
      orphanedConversations.map((c) => c.npcId),
    );
    section(
      'Items nothing drops, sells or gives',
      unobtainableGear
          .map((i) => '${i.name} (level ${i.level} ${i.rarity.name})'),
    );
    section('Arc conditions nothing sets', unreachableArcConditions);
    return b.toString().trimRight();
  }

  @override
  String toString() => render();
}
