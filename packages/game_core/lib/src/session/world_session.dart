import 'package:pf2e_core/pf2e_core.dart';

import '../campaign/arc.dart';
import '../campaign/campaign.dart';
import '../campaign/locations.dart';
import '../campaign/npc.dart';
import '../campaign/creature.dart';
import '../campaign/gear.dart';
import '../campaign/world.dart';
import '../campaign/world_item.dart';
import 'encounter_session.dart';
import 'session_actor.dart';

/// Thrown when the party is asked to do something they cannot do here.
class InvalidMoveException implements Exception {
  InvalidMoveException(this.message);

  final String message;

  @override
  String toString() => 'InvalidMoveException: $message';
}

/// Everything a client needs to render one room.
class RoomView {
  const RoomView({
    required this.room,
    required this.openDirections,
    required this.barredDirections,
    required this.npcs,
    this.items = const [],
    this.encounters = const [],
    this.town,
    this.region,
    this.weather,
    this.isNight = false,
  });

  final Room room;

  /// Directions the party can take now.
  final List<String> openDirections;

  /// Directions that exist but are currently shut, with why.
  final List<({String direction, String? reason})> barredDirections;

  final List<Npc> npcs;

  /// Objects lying here that the party can still do something with.
  final List<WorldItem> items;

  /// Fights waiting here that have not been resolved.
  final List<Encounter> encounters;

  final Town? town;
  final Region? region;

  /// The line describing the current weather, if the region has any.
  final String? weather;
  final bool isNight;

  @override
  String toString() => '${room.title} (${openDirections.join(', ')})';
}

/// The result of walking in a direction.
class MoveResult {
  const MoveResult({
    required this.from,
    required this.to,
    required this.direction,
    this.flagsSet = const [],
    this.changedRegion = false,
  });

  final String from;
  final String to;
  final String direction;

  /// Flags entering the new room set, which arcs may be watching.
  final List<String> flagsSet;

  /// True when the party crossed into a different region, which a client may
  /// want to mark with fresh weather or an establishing line.
  final bool changedRegion;
}

/// The result of raising a topic with someone.
class TalkResult {
  const TalkResult({
    required this.npc,
    required this.said,
    this.topic,
    this.isGreeting = false,
    this.flagsSet = const [],
    this.exhaustedTopics = false,
  });

  final Npc npc;

  /// What they said.
  final String said;

  /// The topic raised, or null for a greeting.
  final String? topic;
  final bool isGreeting;
  final List<String> flagsSet;

  /// True when this exchange was the last unraised topic they had.
  final bool exhaustedTopics;
}

/// A party moving through a campaign world.
///
/// The counterpart to `GameSession`: that one runs an authored scene graph,
/// this one runs the map. They share the flag set deliberately, so a scene
/// outcome can open a road and walking into a room can advance an arc,
/// without either knowing about the other.
class WorldSession {
  WorldSession({
    required this.campaign,
    required List<SessionActor> actors,
    required DiceRoller roller,
    String? roomId,
    Set<String>? flags,
    int hour = 8,
  })  : _actors = List.of(actors),
        _roller = roller,
        _roomId = roomId ?? _firstRoomOf(campaign),
        // Copied rather than kept: callers pass an unmodifiable view or a
        // set another session owns, and a session must not mutate either.
        _flags = {...?flags},
        _hour = hour {
    if (_actors.isEmpty) {
      throw ArgumentError.value(actors, 'actors', 'a session needs an actor');
    }
    if (campaign.locations.roomById(_roomId) == null) {
      throw ArgumentError.value(_roomId, 'roomId', 'no such room');
    }
    _enter(_roomId);
  }

  final Campaign campaign;
  final List<SessionActor> _actors;
  final DiceRoller _roller;
  String _roomId;
  final Set<String> _flags;
  int _hour;

  /// Topics already raised, keyed by npc id, so a conversation does not
  /// re-award a flag every time the same question is asked.
  final Map<String, Set<String>> _topicsRaised = {};

  /// Weather per region, rolled once on arrival and kept until the party
  /// leaves. Weather that changed every step would be noise, not atmosphere.
  final Map<String, String> _weatherByRegion = {};

  static String _firstRoomOf(Campaign campaign) {
    final rooms = campaign.locations.rooms.keys.toList()..sort();
    if (rooms.isEmpty) {
      throw ArgumentError.value(campaign, 'campaign', 'has no rooms');
    }
    return rooms.first;
  }

  List<SessionActor> get actors => List.unmodifiable(_actors);
  SessionActor get primary => _actors.first;

  Set<String> get flags => Set.unmodifiable(_flags);

  String get roomId => _roomId;
  Room get currentRoom => campaign.locations.roomById(_roomId)!;

  int get hour => _hour;
  bool get isNight => campaign.world.time.isNight(_hour);

  Town? get currentTown => campaign.locations.townForRoom(_roomId);

  Region? get currentRegion {
    final town = currentTown;
    return town == null ? null : campaign.world.regionForTown(town.name);
  }

  /// The circumstance modifier the time of day applies to [statKey].
  int timeModifierFor(String statKey) =>
      campaign.world.time.modifierFor(statKey, hour: _hour);

  /// Everything needed to render the room the party is standing in.
  RoomView look() {
    final room = currentRoom;
    final barred = <({String direction, String? reason})>[];
    for (final entry in room.exits.entries) {
      if (!entry.value.isOpen(_flags)) {
        barred.add((
          direction: entry.key,
          reason: entry.value.blockedMessage,
        ));
      }
    }
    barred.sort((a, b) => a.direction.compareTo(b.direction));

    return RoomView(
      room: room,
      openDirections: room.openDirections(_flags),
      barredDirections: barred,
      npcs: campaign.npcs.inRoom(_roomId),
      items: campaign.items.visibleIn(_roomId, _flags),
      encounters: campaign.bestiary.availableIn(_roomId, _flags),
      town: currentTown,
      region: currentRegion,
      weather: currentWeather,
      isNight: isNight,
    );
  }

  /// The weather line for where the party is, rolled once per region visit.
  String? get currentWeather {
    final region = currentRegion;
    if (region == null || !region.hasWeather) return null;
    final chosen = _weatherByRegion[region.id];
    if (chosen != null) return region.weatherStates[chosen];
    final keys = region.weatherStates.keys.toList()..sort();
    final key = keys[_roller.rollDie(keys.length) - 1];
    _weatherByRegion[region.id] = key;
    return region.weatherStates[key];
  }

  /// A random ambiance line for the current region, or null if it has none.
  ///
  /// Returned rather than emitted on a timer: how often atmosphere intrudes
  /// is a presentation decision, and a phone and a terminal will not agree.
  String? ambianceEcho() {
    final echoes = currentRegion?.ambianceEchoes ?? const [];
    if (echoes.isEmpty) return null;
    return echoes[_roller.rollDie(echoes.length) - 1];
  }

  /// Walks [direction], returning what changed.
  MoveResult move(String direction) {
    final room = currentRoom;
    final exit = room.exit(direction);
    if (exit == null) {
      throw InvalidMoveException('There is no way $direction from here.');
    }
    if (!exit.isOpen(_flags)) {
      throw InvalidMoveException(
          exit.blockedMessage ?? 'The way $direction is shut.');
    }
    if (campaign.locations.roomById(exit.to) == null) {
      throw InvalidMoveException(
          'The way $direction leads to "${exit.to}", which does not exist.');
    }

    final fromRegion = currentRegion?.id;
    final from = _roomId;
    _roomId = exit.to;
    final set = _enter(exit.to);

    return MoveResult(
      from: from,
      to: exit.to,
      direction: exit.direction,
      flagsSet: set,
      changedRegion: currentRegion?.id != fromRegion,
    );
  }

  /// Marks a room as visited, returning the flags that were newly set.
  ///
  /// Both the full id and its short form are recorded, because the arcs
  /// abbreviate: `enter_MH_001` means `MH_001_Square`. Writing both means an
  /// arc can use either and neither convention has to win.
  List<String> _enter(String roomId) {
    final set = <String>[];
    for (final flag in {'enter_$roomId', 'enter_${_shortId(roomId)}'}) {
      if (_flags.add(flag)) set.add(flag);
    }
    return set..sort();
  }

  /// `MH_001_Square` becomes `MH_001`.
  static String _shortId(String roomId) {
    final parts = roomId.split('_');
    return parts.length < 2 ? roomId : '${parts[0]}_${parts[1]}';
  }

  /// Greets [who], or raises [topic] with them.
  ///
  /// Raising a topic sets `keyword_<topic>_unlocked`, and raising the last
  /// one an NPC has sets `dialogue_complete_<name>`. Both conventions are
  /// read off this campaign's own arc conditions rather than invented: its
  /// first objective waits on `keyword_quest_unlocked`, and its second tier
  /// on `dialogue_complete_queen_liora`.
  TalkResult talk(String who, {String? topic}) {
    final npc = campaign.npcs.findInRoom(_roomId, who);
    if (npc == null) {
      throw InvalidMoveException('There is nobody called "$who" here.');
    }

    if (topic == null || topic.trim().isEmpty) {
      return TalkResult(npc: npc, said: npc.greeting, isGreeting: true);
    }

    final reply = npc.replyTo(topic);
    if (reply == null) {
      return TalkResult(
        npc: npc,
        said: '${npc.name} has nothing to say about that.',
        topic: topic,
      );
    }

    final matched = _matchedKeyword(npc, topic)!;
    final raised = _topicsRaised.putIfAbsent(npc.id, () => <String>{});
    final isNew = raised.add(matched);

    final set = <String>[];
    if (isNew) {
      final keywordFlag = 'keyword_${matched}_unlocked';
      if (_flags.add(keywordFlag)) set.add(keywordFlag);
    }

    final exhausted = raised.length == npc.keywords.length;
    if (exhausted) {
      final completeFlag = 'dialogue_complete_${npc.slug}';
      if (_flags.add(completeFlag)) set.add(completeFlag);
    }

    return TalkResult(
      npc: npc,
      said: reply,
      topic: matched,
      flagsSet: set..sort(),
      exhaustedTopics: exhausted,
    );
  }

  /// Which of [npc]'s keywords answered [topic].
  String? _matchedKeyword(Npc npc, String topic) {
    final asked = topic.trim().toLowerCase();
    for (final key in npc.keywords.keys) {
      if (key.toLowerCase() == asked) return key;
    }
    final byLength = npc.keywords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in byLength) {
      if (asked.contains(key.toLowerCase())) return key;
    }
    return null;
  }

  /// Topics this NPC will answer that the party has not yet raised.
  List<String> unraisedTopicsFor(Npc npc) {
    final raised = _topicsRaised[npc.id] ?? const <String>{};
    return [
      for (final t in npc.topics)
        if (!raised.contains(t)) t
    ];
  }

  // --- objects -------------------------------------------------------------

  /// Takes an object from the room.
  ///
  /// Returns the narration and any flags set. Refuses rather than silently
  /// no-ops, because "nothing happened" is the worst possible answer to a
  /// player who typed a specific verb at a specific noun.
  ({WorldItem item, String said, List<String> flagsSet}) take(String query) {
    final item = _requireItem(query);
    if (!item.takeable) {
      throw InvalidMoveException('${item.name} is not something you can take.');
    }
    final set = <String>[];
    for (final flag in item.acquireFlags) {
      if (_flags.add(flag)) set.add(flag);
    }
    return (
      item: item,
      said: item.onTake ?? 'You take ${item.name}.',
      flagsSet: set..sort(),
    );
  }

  /// Destroys an object in the room.
  ({WorldItem item, String said, List<String> flagsSet}) destroy(String query) {
    final item = _requireItem(query);
    if (!item.destroyable) {
      throw InvalidMoveException(
          '${item.name} is not something you can destroy.');
    }
    final set = <String>[];
    for (final flag in item.destroyFlags) {
      if (_flags.add(flag)) set.add(flag);
    }
    return (
      item: item,
      said: item.onDestroy ?? 'You destroy ${item.name}.',
      flagsSet: set..sort(),
    );
  }

  WorldItem _requireItem(String query) {
    final item = campaign.items.findInRoom(_roomId, query);
    if (item == null) {
      throw InvalidMoveException('There is no "$query" here.');
    }
    if (!item.isVisible(_flags)) {
      throw InvalidMoveException('There is no "$query" here.');
    }
    if (item.isResolved(_flags)) {
      throw InvalidMoveException('You have already dealt with ${item.name}.');
    }
    if (!item.isReachable(_flags)) {
      throw InvalidMoveException('You cannot get at ${item.name} yet.');
    }
    return item;
  }

  // --- fights --------------------------------------------------------------

  /// Fights waiting in this room that have not been resolved.
  List<Encounter> availableEncounters() =>
      campaign.bestiary.availableIn(_roomId, _flags);

  /// Starts a fight, by id or by the first one waiting here.
  ///
  /// The returned session is separate state: a fight is its own mode, and
  /// folding initiative and actions into the walking session would make both
  /// harder to reason about.
  EncounterSession beginEncounter({String? encounterId}) {
    final available = availableEncounters();
    if (available.isEmpty) {
      throw InvalidMoveException('There is nothing to fight here.');
    }
    final encounter = encounterId == null
        ? available.first
        : available.where((e) => e.id == encounterId).firstOrNull;
    if (encounter == null) {
      throw InvalidMoveException('There is no fight called "$encounterId" '
          'waiting here.');
    }
    return EncounterSession(
      encounter: encounter,
      bestiary: campaign.bestiary,
      actors: _actors,
      roller: _roller,
      gear: campaign.gear,
    );
  }

  /// Records the result of a fight, returning the flags it set.
  ///
  /// Called by the client once the fight is over, rather than by the fight
  /// itself, so that losing and fleeing are the caller's to narrate. Loot is
  /// recorded here too: a drop the party never went back for is not theirs.
  List<String> concludeEncounter(EncounterSession fight) {
    final set = <String>[];
    for (final flag in [...fight.victoryFlags, ...fight.lootFlags]) {
      if (_flags.add(flag)) set.add(flag);
    }
    return set..sort();
  }

  /// Gear the party has taken off something it killed.
  ///
  /// Held as flags rather than as an inventory, because there is no inventory
  /// yet: this records what has been found, not what anyone is wearing.
  List<GearItem> get recoveredGear => [
        for (final item in campaign.gear.all)
          if (_flags.contains('loot_${item.id}')) item,
      ];

  /// Moves the clock on, wrapping at the end of the day.
  void advanceTime(int hours) {
    if (hours < 0) {
      throw ArgumentError.value(hours, 'hours', 'must not be negative');
    }
    final cycle = campaign.world.time.dayCycleHours;
    _hour = cycle <= 0 ? _hour : (_hour + hours) % cycle;
  }

  /// Arcs that have started and are not yet finished.
  List<CampaignArc> activeArcs() => campaign.arcs.active(_flags);

  /// Applies any world-state changes owed by completed arcs, returning them.
  ///
  /// Owed rather than applied automatically at the moment they become due,
  /// because an arc finishing is something a client will want to announce
  /// before the world quietly changes underneath the player.
  List<String> applyPendingWorldState() {
    final pending = campaign.arcs.pendingWorldStateChanges(_flags);
    _flags.addAll(pending);
    return pending;
  }

  /// Captures enough state to resume exactly where this left off.
  Map<String, Object?> snapshot() => {
        'campaignId': campaign.id,
        'roomId': _roomId,
        'hour': _hour,
        'flags': (_flags.toList()..sort()),
        'rollerState': _roller.state,
        'weather': Map<String, String>.from(_weatherByRegion),
        'topicsRaised': {
          for (final e in _topicsRaised.entries)
            e.key: (e.value.toList()..sort()),
        },
      };

  /// Rebuilds a session from a [snapshot].
  static WorldSession restore({
    required Campaign campaign,
    required List<SessionActor> actors,
    required Map<String, Object?> snapshot,
  }) {
    final id = snapshot['campaignId']?.toString();
    if (id != null && id != campaign.id) {
      throw ArgumentError('Snapshot belongs to campaign "$id", not '
          '"${campaign.id}".');
    }
    final session = WorldSession(
      campaign: campaign,
      actors: actors,
      roller: DiceRoller.fromState((snapshot['rollerState'] as num).toInt()),
      roomId: snapshot['roomId']!.toString(),
      flags: {
        for (final f in (snapshot['flags'] as List? ?? const [])) f.toString(),
      },
      hour: (snapshot['hour'] as num?)?.toInt() ?? 8,
    );
    for (final e in (snapshot['weather'] as Map? ?? const {}).entries) {
      session._weatherByRegion[e.key.toString()] = e.value.toString();
    }
    for (final e in (snapshot['topicsRaised'] as Map? ?? const {}).entries) {
      session._topicsRaised[e.key.toString()] = {
        for (final t in (e.value as List? ?? const [])) t.toString(),
      };
    }
    return session;
  }
}
