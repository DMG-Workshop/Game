import 'package:pf2e_core/pf2e_core.dart';

import '../campaign/arc.dart';
import '../campaign/campaign.dart';
import '../campaign/creature.dart';
import '../campaign/economy.dart';
import '../campaign/gear.dart';
import '../campaign/hunt.dart';
import '../campaign/locations.dart';
import '../campaign/npc.dart';
import '../campaign/world.dart';
import '../campaign/world_item.dart';
import '../party/equipment.dart';
import '../party/experience.dart';
import '../party/wealth.dart';
import 'encounter_session.dart';
import 'game_session.dart';
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
    this.ambush,
    this.hunt,
    this.huntRoll,
  });

  final String from;
  final String to;
  final String direction;

  /// A fight that springs on arrival, which a client should start rather
  /// than merely mention.
  final Encounter? ambush;

  /// Something that has tracked the party down and caught them up here. Like
  /// an ambush, a client should start it rather than mention it.
  final Encounter? hunt;

  /// The d100 against the chance of being found, when one was rolled.
  final ({int die, int chance})? huntRoll;

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
    PartyInventory? inventory,
    String? cameFrom,
    Experience? experience,
    LootLedger? ledger,
  })  : _actors = List.of(actors),
        _experience = experience ?? Experience(),
        _ledger = ledger ?? LootLedger(),
        // Salted off the world's own starting point, so a seed still fixes
        // everything, but a traveller's wandering never shifts a fight.
        _roadDice = DiceRoller(roller.state ^ 0x9E3779B9),
        // The hunt has dice of its own for the same reason: being rich must
        // not change the outcome of a fight the party would have had anyway.
        _huntDice = DiceRoller(roller.state ^ 0x5851F42D),
        _cameFrom = cameFrom,
        _roller = roller,
        _roomId = roomId ?? _firstRoomOf(campaign),
        // Copied rather than kept: callers pass an unmodifiable view or a
        // set another session owns, and a session must not mutate either.
        _flags = {...?flags},
        _hour = hour,
        _inventory = inventory ?? PartyInventory(gear: campaign.gear) {
    if (_actors.isEmpty) {
      throw ArgumentError.value(actors, 'actors', 'a session needs an actor');
    }
    if (campaign.locations.roomById(_roomId) == null) {
      throw ArgumentError.value(_roomId, 'roomId', 'no such room');
    }
    _experience.reconcile([
      for (final a in _actors)
        (id: a.id, level: a.character.level, sheetXp: a.character.xp),
    ]);

    // Without a pack of its own, a session works out what it is carrying from
    // the flags, which is how everything else here describes progress. It
    // also means a save written before the pack existed still has its loot.
    if (inventory == null) {
      for (final flag in _flags) {
        if (!flag.startsWith('loot_')) continue;
        final id = flag.substring('loot_'.length);
        if (campaign.gear.byId(id) != null) _inventory.add(id);
      }
      _inventory.earn(_startingCoin(_actors));
    }
    for (final npc in campaign.npcs.travellers) {
      _moveOn(npc);
    }
    _enter(_roomId);
  }

  final Campaign campaign;
  final List<SessionActor> _actors;
  final DiceRoller _roller;
  String _roomId;

  /// The room the party walked in from, which is the one way past an ambush.
  String? _cameFrom;
  final Set<String> _flags;
  int _hour;
  final PartyInventory _inventory;
  final Experience _experience;
  final LootLedger _ledger;

  /// Dice for whether anything finds the party, and what.
  DiceRoller _huntDice;

  /// Steps since something last found the party.
  int _sinceHunt = 0;

  /// Hunters the party has beaten.
  int _huntsSurvived = 0;

  /// Whatever has found the party and not yet been dealt with.
  Pursuer? _pursuer;

  /// Dice for who is where on the roads, kept apart from the world's dice.
  ///
  /// Travellers wander on these alone, so adding one to a campaign changes
  /// no fight, drop or weather roll in a game that was seeded before them.
  DiceRoller _roadDice;

  /// Steps the party has taken, which is what travellers keep time by.
  int _steps = 0;

  /// Where each traveller is; null while they are on the road between stops.
  final Map<String, String?> _whereabouts = {};

  /// What a travelling shop has on hand at its current stop.
  final Map<String, List<String>> _onHand = {};

  /// Topics already raised, keyed by npc id, so a conversation does not
  /// re-award a flag every time the same question is asked.
  final Map<String, Set<String>> _topicsRaised = {};

  /// Weather per region, rolled once on arrival and kept until the party
  /// leaves. Weather that changed every step would be noise, not atmosphere.
  final Map<String, String> _weatherByRegion = {};

  /// What the party's own sheets say they are carrying, pooled.
  ///
  /// The characters arrive with the coin Pathbuilder gave them, the same way
  /// they arrive with its weapons, because it is their money.
  static int _startingCoin(List<SessionActor> actors) =>
      actors.fold(0, (sum, actor) => sum + actor.character.money.totalInCopper);

  static String _firstRoomOf(Campaign campaign) {
    final rooms = campaign.locations.rooms.keys.toList()..sort();
    if (rooms.isEmpty) {
      throw ArgumentError.value(campaign, 'campaign', 'has no rooms');
    }
    return rooms.first;
  }

  List<SessionActor> get actors => List.unmodifiable(_actors);
  SessionActor get primary => _actors.first;

  /// What the party is carrying and who is wearing what.
  PartyInventory get inventory => _inventory;

  /// Who has earned how much experience.
  Experience get experience => _experience;

  /// Everything the party has come away with, and from where.
  LootLedger get ledger => _ledger;

  /// What the party is worth now, against what Pathfinder expects of it.
  Wealth get wealth => Wealth(
        coin: _inventory.coin,
        gear: _inventory.gearValue,
        expected: expectedWealth(level: _partyLevel, partySize: _actors.length),
      );

  int get _partyLevel =>
      partyLevel([for (final a in _actors) a.character.level]);

  /// How far word of the party's wealth has spread, and what it brings.
  Notoriety get notoriety {
    final worth = wealth;
    return Notoriety(
      wealth: worth,
      tier: campaign.hunts.tierFor(worth.percentOfExpected),
      partyLevel: _partyLevel,
      partySize: _actors.length,
    );
  }

  /// Whatever has tracked the party down and is waiting to be fought.
  Pursuer? get pursuer => _pursuer;

  /// How many hunters the party has beaten.
  int get huntsSurvived => _huntsSurvived;

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
      npcs: _npcsHere(),
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

    final hunter = _pursuer;
    if (hunter != null) {
      throw InvalidMoveException('${hunter.creature.name} has caught you up. '
          'Fight it, or flee.');
    }

    // Only the way back is open past an ambush. With no known way in — a
    // session started in the room — every way counts as back.
    final waiting = campaign.bestiary.ambushIn(_roomId, _flags);
    if (waiting != null && _cameFrom != null && exit.to != _cameFrom) {
      throw InvalidMoveException('${waiting.name} is between you and the way '
          'on. Fight, or go back the way you came.');
    }

    final fromRegion = currentRegion?.id;
    final from = _roomId;
    _roomId = exit.to;
    _cameFrom = from;
    final set = _enter(exit.to);

    _steps++;
    for (final npc in campaign.npcs.travellers) {
      if (_steps % npc.route!.every == 0) _moveOn(npc);
    }

    final ambush = campaign.bestiary.ambushIn(_roomId, _flags);
    final huntRoll = ambush == null ? _rollHunt() : null;
    final caught = _pursuer;
    if (caught != null && _set('hunted_first')) set.add('hunted_first');

    return MoveResult(
      from: from,
      to: exit.to,
      direction: exit.direction,
      flagsSet: set..sort(),
      changedRegion: currentRegion?.id != fromRegion,
      ambush: ambush,
      hunt: caught?.encounterIn(_roomId),
      huntRoll: huntRoll,
    );
  }

  /// Rolls whether anything finds the party this step, and sends it if so.
  ///
  /// Never while a fight is already waiting here, and never within a few
  /// steps of the last one: a hunt is a threat on the road, not a treadmill.
  /// Returns the roll, or null when there was nothing to roll for.
  ({int die, int chance})? _rollHunt() {
    final hunts = campaign.hunts;
    if (hunts.isEmpty) return null;
    _sinceHunt++;
    if (_sinceHunt <= hunts.restSteps) return null;

    final standing = notoriety;
    final level = standing.hunterLevel;
    if (!standing.tier.isHunted || level == null) return null;

    final roll = (die: _huntDice.rollDie(100), chance: standing.tier.chance);
    if (roll.die > roll.chance) return roll;

    _pursuer = hunts.choose(level, campaign.bestiary, _huntDice);
    if (_pursuer != null) _sinceHunt = 0;
    return roll;
  }

  /// The room the party came in from, if the session knows it.
  String? get cameFrom => _cameFrom;

  /// How a fight looks from here, which is different the second time.
  String describeEncounter(Encounter encounter) =>
      encounter.descriptionFor(_flags);

  /// Marks a room as visited, returning the flags that were newly set.
  ///
  /// Both the full id and its short form are recorded, because the arcs
  /// abbreviate: `enter_MH_001` means `MH_001_Square`. Writing both means an
  /// arc can use either and neither convention has to win.
  List<String> _enter(String roomId) {
    final set = <String>[];
    for (final flag in {'enter_$roomId', 'enter_${_shortId(roomId)}'}) {
      if (_set(flag)) set.add(flag);
    }
    return set..sort();
  }

  /// Sets [flag], paying out any coin it carries. True when it was new.
  ///
  /// Every flag the world sets comes through here, so a reward keyed to one
  /// pays out once whichever way it was reached: a conversation, a fight,
  /// an object, or an arc finishing.
  bool _set(String flag) {
    if (!_flags.add(flag)) return false;
    _payReward(flag);
    return true;
  }

  void _payReward(String flag) {
    final payout = campaign.payoutFor(flag);
    if (payout == null) return;
    if (payout.copper > 0) {
      _inventory.earn(payout.copper);
      _ledger.recordCoin(campaign.payerFor(flag), payout.copper);
    }
    _experience.award(_actors.map((a) => a.id), payout.xp);
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
    final npc = _findNpcHere(who);
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
      if (_set(keywordFlag)) set.add(keywordFlag);
    }

    final exhausted = raised.length == npc.keywords.length;
    if (exhausted) {
      final completeFlag = 'dialogue_complete_${npc.slug}';
      if (_set(completeFlag)) set.add(completeFlag);
    }

    return TalkResult(
      npc: npc,
      said: reply,
      topic: matched,
      flagsSet: set..sort(),
      exhaustedTopics: exhausted,
    );
  }

  /// Starts a proper conversation with [who].
  ///
  /// Returns null when they have nothing to say beyond a greeting, which a
  /// client can fall back to with [talk]. The conversation runs on the world's
  /// own dice and starts from a copy of its flags; nothing it does reaches the
  /// world until [concludeConversation], so a conversation abandoned halfway
  /// still counts for whatever was said before it was.
  ({Npc npc, GameSession talk})? beginConversation(String who) {
    final npc = _findNpcHere(who);
    if (npc == null) {
      throw InvalidMoveException('There is nobody called "$who" here.');
    }
    final conversation = campaign.conversations.forNpc(npc.id);
    final opening = conversation?.openingFor(_flags);
    if (conversation == null || opening == null) return null;

    return (
      npc: npc,
      talk: GameSession(
        adventure: conversation.adventure,
        actors: _actors,
        roller: _roller,
        sceneId: opening,
        flags: _flags,
      ),
    );
  }

  /// Takes what a conversation changed back into the world, returning the
  /// flags it newly set.
  List<String> concludeConversation(GameSession conversation) {
    final before = Set.of(_flags);
    _flags
      ..clear()
      ..addAll(conversation.flags);
    final set = _flags.difference(before).toList()..sort();
    set.forEach(_payReward);

    // Somebody handing the party something is recorded the way a drop is,
    // so a gift and a kill end up in the same pack and the same ledger.
    final npcId = conversation.adventure.id.replaceFirst('conversation_', '');
    final giver = campaign.npcs.byId(npcId)?.name ?? npcId;
    for (final flag in set) {
      if (!flag.startsWith('loot_')) continue;
      final item = campaign.gear.byId(flag.substring('loot_'.length));
      if (item == null) continue;
      _inventory.add(item.id);
      _ledger.recordItem(giver, item);
    }
    return set;
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
      if (_set(flag)) set.add(flag);
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
      if (_set(flag)) set.add(flag);
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

  /// Fights waiting in this room that have not been resolved, a hunter that
  /// has caught the party up first of all.
  List<Encounter> availableEncounters() => [
        if (_pursuer case final hunter?) hunter.encounterIn(_roomId),
        ...campaign.bestiary.availableIn(_roomId, _flags),
      ];

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
    final hunter = _pursuer;
    return EncounterSession(
      encounter: encounter,
      bestiary: campaign.bestiary,
      actors: _actors,
      roller: _roller,
      gear: campaign.gear,
      loadouts: _inventory.loadouts(),
      // A hunter comes at the level it was sent at, which is not the level
      // the bestiary writes it at.
      foes: hunter != null && _isHunt(encounter, hunter)
          ? [hunter.creature]
          : null,
    );
  }

  bool _isHunt(Encounter encounter, Pursuer hunter) =>
      encounter.id == hunter.encounterIn(_roomId).id;

  /// Records the result of a fight, returning the flags it set.
  ///
  /// Called by the client once the fight is over, rather than by the fight
  /// itself, so that losing and fleeing are the caller's to narrate. Loot is
  /// recorded here too: a drop the party never went back for is not theirs.
  List<String> concludeEncounter(EncounterSession fight) {
    final hunter = _pursuer;
    if (hunter != null && _isHunt(fight.encounter, hunter)) {
      return _concludeHunt(fight, hunter);
    }
    final set = <String>[];
    // Which wave was beaten is worked out before anything else changes, so
    // a victory flag that happened to rearm something could not skip a wave.
    final won = fight.outcome == EncounterOutcome.victory
        ? [fight.encounter.wonFlag(fight.encounter.waveFor(_flags))]
        : const <String>[];
    for (final flag in [...won, ...fight.victoryFlags, ...fight.lootFlags]) {
      if (_set(flag)) set.add(flag);
    }
    _collect(fight);
    return set..sort();
  }

  /// Takes a won fight's coin, loot and XP, and writes them in the ledger.
  void _collect(EncounterSession fight) {
    final source = fight.encounter.name;
    for (final item in fight.loot) {
      _inventory.add(item.id);
      _ledger.recordItem(source, item);
    }
    _inventory.earn(fight.coinEarned);
    _ledger.recordCoin(source, fight.coinEarned);
    _experience.award(_actors.map((a) => a.id), fight.xpEarned);
  }

  /// Settles a fight with a hunter, however it went.
  ///
  /// Won, it pays like any fight and counts toward `hunt_survived_<n>`. Lost,
  /// the hunter takes its share of the purse, which is what it came for. Fled,
  /// it loses the trail. Either way it is gone, and the next one is a few
  /// steps off at least.
  List<String> _concludeHunt(EncounterSession fight, Pursuer hunter) {
    final set = <String>[];
    switch (fight.outcome) {
      case EncounterOutcome.victory:
        _huntsSurvived++;
        for (final flag in [
          'hunt_survived_$_huntsSurvived',
          ...fight.lootFlags,
        ]) {
          if (_set(flag)) set.add(flag);
        }
        _collect(fight);
      case EncounterOutcome.defeat:
        final taken = _inventory.coin * campaign.hunts.robPercent ~/ 100;
        if (taken > 0) _inventory.spend(taken);
      case EncounterOutcome.fled || null:
        break;
    }
    _pursuer = null;
    _sinceHunt = 0;
    return set..sort();
  }

  /// Gear the party is carrying.
  ///
  /// The flags record that a thing was *found*, which arcs can watch; the
  /// pack records that it is still had. They are set together and only the
  /// pack is authoritative.
  List<GearItem> get recoveredGear => _inventory.carried;

  // --- equipment -----------------------------------------------------------

  /// Puts a carried item on an actor, returning what it displaced.
  ///
  /// [who] may be an actor id or any word of their name, and [what] an item
  /// id or any word of its name, because that is what a player types.
  ({SessionActor actor, GearItem item, EquipSlot slot, GearItem? replaced})
      equip(String what, {String? who}) {
    final actor = actorFor(who);
    final item = _inventory.find(what);
    if (item == null) {
      throw InvalidMoveException('You are not carrying a "$what".');
    }
    final others =
        _inventory.holdersOf(item.id).where((h) => h != actor.id).toList();
    if (others.length >= _inventory.countOf(item.id)) {
      throw InvalidMoveException('${_namesOf(others)} already '
          '${others.length == 1 ? 'has' : 'have'} ${item.name}, and the '
          'party has no other.');
    }
    final result = _inventory.equip(actor.id, item.id);
    return (
      actor: actor,
      item: result.item,
      slot: result.slot,
      replaced: result.replaced,
    );
  }

  /// Takes whatever is in [slot] off an actor, returning it.
  ({SessionActor actor, GearItem? removed}) unequip(
    String slot, {
    String? who,
  }) {
    final actor = actorFor(who);
    final parsed = EquipSlot.tryParse(slot);
    if (parsed == null) {
      throw InvalidMoveException('There is no "$slot" to take off. Try '
          '${EquipSlot.values.map((s) => s.label).join(' or ')}.');
    }
    return (actor: actor, removed: _inventory.unequip(actor.id, parsed));
  }

  /// An actor's numbers with what they are wearing and wielding applied.
  EquippedStats statsFor(String actorId) => EquippedStats(
        actorFor(actorId).stats,
        _inventory.loadoutFor(actorFor(actorId).id),
      );

  // --- trade ---------------------------------------------------------------

  /// The shop kept in this room, if there is one.
  Shop? get shopHere {
    final fixed = campaign.economy.shopIn(_roomId);
    if (fixed != null) return fixed;
    for (final npc in _npcsHere()) {
      final shop = campaign.economy.shopKeptBy(npc.id);
      if (shop != null && shop.travels) return shop;
    }
    return null;
  }

  // --- travellers ----------------------------------------------------------

  /// Everyone in this room: those who stay put, and any traveller whose
  /// road has brought them here.
  List<Npc> _npcsHere() => [
        ...campaign.npcs.inRoom(_roomId),
        for (final npc in campaign.npcs.travellers)
          if (_whereabouts[npc.id] == _roomId) npc,
      ];

  Npc? _findNpcHere(String who) => NpcDirectory.findAmong(_npcsHere(), who);

  /// Where a traveller is now, or null while they are on the road.
  String? whereIs(String npcId) => _whereabouts[npcId];

  /// What a travelling shop has on hand at its current stop.
  List<String> onHandAt(String shopId) =>
      List.unmodifiable(_onHand[shopId] ?? const []);

  /// Sends [npc] to their next stop, or out onto the road, and packs their
  /// shop afresh: a different few things each time they are found.
  void _moveOn(Npc npc) {
    final route = npc.route!;
    final away = _roadDice.rollDie(100) <= route.awayChance;
    _whereabouts[npc.id] =
        away ? null : route.stops[_roadDice.rollDie(route.stops.length) - 1];

    final shop = campaign.economy.shopKeptBy(npc.id);
    if (shop == null || !shop.travels) return;
    final pool = shop.onSaleFor(_flags);
    final count = (shop.carries ?? pool.length).clamp(0, pool.length);
    // A partial shuffle on the road's dice: the first [count] are the pick.
    for (var i = 0; i < count; i++) {
      final j = i + _roadDice.rollDie(pool.length - i) - 1;
      final held = pool[i];
      pool[i] = pool[j];
      pool[j] = held;
    }
    _onHand[shop.id] = pool.take(count).toList();
  }

  /// What is on the shelf here, cheapest first, at what the party would pay.
  List<({GearItem item, int price})> wares() {
    final shop = _requireShop();
    final rows = [
      for (final id in shop.travels
          ? (_onHand[shop.id] ?? const <String>[])
          : shop.onSaleFor(_flags))
        if (campaign.gear.byId(id) case final item?)
          (item: item, price: shop.priceFor(item, _flags)),
    ];
    return rows..sort((a, b) => a.price.compareTo(b.price));
  }

  /// Buys one of something on the shelf.
  ({GearItem item, int price}) buy(String what) {
    final shop = _requireShop();
    final onSale = [
      for (final row in wares()) row.item,
    ];
    final item = PartyInventory.findIn(onSale, what);
    if (item == null) {
      throw InvalidMoveException('${_keeperName(shop)} has nothing called '
          '"$what" for sale.');
    }
    final price = shop.priceFor(item, _flags);
    try {
      _inventory.spend(price);
    } on EquipException catch (e) {
      throw InvalidMoveException(e.message);
    }
    _inventory.add(item.id);
    return (item: item, price: price);
  }

  /// What the keeper here would pay for something the party carries.
  ({GearItem item, int price}) valueOf(String what) {
    _requireShop();
    final item = _inventory.find(what);
    if (item == null) {
      throw InvalidMoveException('You are not carrying a "$what".');
    }
    return (item: item, price: item.resalePrice);
  }

  /// Sells one of something the party carries, for half its price.
  ///
  /// Anything can be sold, rare things included; selling the only one of a
  /// boss's weapon is a choice a player is allowed to regret.
  ({GearItem item, int price}) sell(String what) {
    final quote = valueOf(what);
    final holders = _inventory.holdersOf(quote.item.id);
    if (holders.length >= _inventory.countOf(quote.item.id)) {
      throw InvalidMoveException('${_namesOf(holders)} '
          '${holders.length == 1 ? 'is' : 'are'} using ${quote.item.name}. '
          'Take it off first.');
    }
    try {
      _inventory.remove(quote.item.id);
    } on EquipException catch (e) {
      throw InvalidMoveException(e.message);
    }
    _inventory.earn(quote.price);
    return quote;
  }

  Shop _requireShop() {
    final shop = shopHere;
    if (shop == null) {
      throw InvalidMoveException('There is nobody here to trade with.');
    }
    return shop;
  }

  /// Actor ids as a player would read them: "Korash Blackearth and Sela".
  String _namesOf(List<String> actorIds) => actorIds
      .map((id) => _actors.where((a) => a.id == id).firstOrNull?.name ?? id)
      .join(' and ');

  String _keeperName(Shop shop) =>
      campaign.npcs.byId(shop.keeperId)?.name ?? shop.name;

  /// Whether [who] names somebody in the party.
  bool knowsActor(String who) {
    try {
      actorFor(who);
      return true;
    } on InvalidMoveException {
      return false;
    }
  }

  /// Resolves an actor by id or by any word of their name, defaulting to the
  /// one at the front of the marching order.
  SessionActor actorFor(String? who) {
    if (who == null || who.trim().isEmpty) return primary;
    final needle = who.trim().toLowerCase();
    for (final actor in _actors) {
      if (actor.id.toLowerCase() == needle) return actor;
    }
    for (final actor in _actors) {
      if (actor.name.toLowerCase().split(RegExp(r'\s+')).contains(needle)) {
        return actor;
      }
    }
    throw InvalidMoveException('Nobody here is called "$who".');
  }

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
  List<String> applyPendingWorldState() => settleArcs().worldState;

  /// Marks finished any quest whose last objective has been met — paying its
  /// reward — and applies what finishing it changes about the world.
  ///
  /// The quests come back separately from the world-state flags, because
  /// "quest complete" and "the world shifts" are two different things to say.
  ({List<CampaignArc> completed, List<String> worldState}) settleArcs() {
    final completed = campaign.arcs.justCompleted(_flags);
    for (final arc in completed) {
      _set(arc.completionFlag);
    }
    final pending = campaign.arcs.pendingWorldStateChanges(_flags);
    pending.forEach(_set);
    return (completed: completed, worldState: pending);
  }

  /// Captures enough state to resume exactly where this left off.
  Map<String, Object?> snapshot() => {
        'campaignId': campaign.id,
        'roomId': _roomId,
        'cameFrom': _cameFrom,
        'hour': _hour,
        'road': {
          'dice': _roadDice.state,
          'steps': _steps,
          'whereabouts': Map<String, String?>.from(_whereabouts),
          'onHand': {
            for (final e in _onHand.entries) e.key: List<String>.from(e.value),
          },
        },
        'hunt': {
          'dice': _huntDice.state,
          'since': _sinceHunt,
          'survived': _huntsSurvived,
          if (_pursuer case final hunter?)
            'pursuer': {
              'creature': hunter.hunter.creatureId,
              if (hunter.adjustment != null) 'adjustment': hunter.adjustment,
            },
        },
        'flags': (_flags.toList()..sort()),
        'inventory': _inventory.toJson(),
        'ledger': _ledger.toJson(),
        'experience': _experience.toJson(),
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
    final flags = {
      for (final f in (snapshot['flags'] as List? ?? const [])) f.toString(),
    };

    // No pack in the snapshot means a save from before there was one; the
    // session rebuilds it from the loot flags instead.
    final inventory = snapshot.containsKey('inventory')
        ? PartyInventory.fromJson(campaign.gear, snapshot['inventory'])
        : null;

    final session = WorldSession(
      campaign: campaign,
      actors: actors,
      roller: DiceRoller.fromState((snapshot['rollerState'] as num).toInt()),
      roomId: snapshot['roomId']!.toString(),
      flags: flags,
      hour: (snapshot['hour'] as num?)?.toInt() ?? 8,
      inventory: inventory,
      cameFrom: snapshot['cameFrom']?.toString(),
      experience: snapshot.containsKey('experience')
          ? Experience.fromJson(snapshot['experience'])
          : null,
      ledger: LootLedger.fromJson(snapshot['ledger']),
    );
    final hunt = snapshot['hunt'];
    if (hunt is Map) {
      session._huntDice =
          DiceRoller.fromState((hunt['dice'] as num?)?.toInt() ?? 0);
      session._sinceHunt = (hunt['since'] as num?)?.toInt() ?? 0;
      session._huntsSurvived = (hunt['survived'] as num?)?.toInt() ?? 0;
      final pursuer = hunt['pursuer'];
      if (pursuer is Map) {
        session._pursuer = campaign.hunts.restore(
          pursuer['creature']?.toString() ?? '',
          pursuer['adjustment']?.toString(),
          campaign.bestiary,
        );
      }
    }
    final savedPack = snapshot['inventory'];
    // The roads pick up where they were, rather than re-rolled on load.
    final road = snapshot['road'];
    if (road is Map) {
      session._roadDice =
          DiceRoller.fromState((road['dice'] as num?)?.toInt() ?? 0);
      session._steps = (road['steps'] as num?)?.toInt() ?? 0;
      session._whereabouts
        ..clear()
        ..addAll({
          for (final e in (road['whereabouts'] as Map? ?? const {}).entries)
            e.key.toString(): e.value?.toString(),
        });
      session._onHand
        ..clear()
        ..addAll({
          for (final e in (road['onHand'] as Map? ?? const {}).entries)
            e.key.toString(): [
              for (final id in (e.value as List? ?? const [])) id.toString(),
            ],
        });
    }
    if (savedPack is Map && !savedPack.containsKey('coin')) {
      session._inventory.earn(_startingCoin(actors));
    }
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
