/// Where a travelling NPC goes, and how restless they are.
class NpcRoute {
  const NpcRoute({
    required this.stops,
    this.every = 10,
    this.awayChance = 25,
  });

  /// Rooms they might be found in.
  final List<String> stops;

  /// How many steps the party takes before they move on.
  final int every;

  /// Percent chance, each time they move, of being on the road between
  /// stops — and so nowhere the party can find them.
  final int awayChance;
}

/// A character standing in a room, answering to keywords.
///
/// This is the classic MUD conversation: a greeting on approach, then topics
/// the player raises by name. It suits a text game far better than a dialogue
/// tree, because the player types what they are curious about rather than
/// picking from a list someone else wrote.
/// Something an NPC says when the party walks in, while the story stands a
/// certain way.
class NpcBark {
  const NpcBark({
    required this.line,
    this.requiredFlags = const [],
    this.forbiddenFlags = const [],
  });

  /// What they say; empty for nothing at all, as when they are not there.
  final String line;
  final List<String> requiredFlags;
  final List<String> forbiddenFlags;

  bool fits(Set<String> flags) =>
      requiredFlags.every(flags.contains) &&
      !forbiddenFlags.any(flags.contains);
}

class Npc {
  const Npc({
    required this.id,
    required this.name,
    required this.location,
    required this.appearance,
    required this.greeting,
    this.tier = 1,
    this.keywords = const {},
    this.route,
    this.barks = const [],
    this.appearsAfter = const [],
    this.leavesAfter = const [],
  });

  final String id;
  final String name;

  /// Room id this NPC stands in.
  final String location;

  /// Flags that must all be set before this NPC is anywhere to be found:
  /// somebody the story has not brought in yet.
  final List<String> appearsAfter;

  /// Flags any one of which takes this NPC out of the world: somebody the
  /// story has moved on.
  final List<String> leavesAfter;

  /// Whether this NPC is about, the way things stand.
  bool isPresent(Set<String> flags) =>
      appearsAfter.every(flags.contains) && !leavesAfter.any(flags.contains);

  /// Shown as part of the room, before anyone speaks.
  final String appearance;

  /// Said on first approach.
  final String greeting;

  /// What they say as the party walks in, first fitting one wins.
  final List<NpcBark> barks;

  /// What they say to the party walking in, the way things stand, or null.
  ///
  /// Nothing when no line fits: somebody the party has never met has not
  /// yet got anything to say to them, and their greeting is the first line
  /// of the conversation, where it would otherwise be said twice.
  String? barkFor(Set<String> flags) {
    for (final bark in barks) {
      if (bark.fits(flags)) return bark.line.isEmpty ? null : bark.line;
    }
    return null;
  }

  final int tier;

  /// Topic to reply, keyed by the word the player raises.
  final Map<String, String> keywords;

  /// Set for somebody who travels. They are never in [location] by right;
  /// the session decides where they are, on dice of its own.
  final NpcRoute? route;

  bool get travels => route != null;

  List<String> get topics => keywords.keys.toList()..sort();

  /// The reply for [topic], or null when this NPC has nothing on it.
  ///
  /// Matching is case-insensitive and forgiving: an exact key wins, otherwise
  /// any key contained in what the player typed. That way "ask about the
  /// covenant" finds `covenant` without the player guessing the exact word.
  String? replyTo(String topic) {
    final asked = topic.trim().toLowerCase();
    if (asked.isEmpty) return null;

    for (final entry in keywords.entries) {
      if (entry.key.toLowerCase() == asked) return entry.value;
    }
    // Longest key first, so "local undead" beats "undead" on the same input.
    final byLength = keywords.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in byLength) {
      if (asked.contains(entry.key.toLowerCase())) return entry.value;
    }
    return null;
  }

  /// Whether this NPC responds to [topic] at all.
  bool knows(String topic) => replyTo(topic) != null;

  /// `npc_005_queen_liora` becomes `queen_liora`.
  ///
  /// Used to name the flag set when every one of this NPC's topics has been
  /// raised, so the survey and the session agree on what that flag is called.
  String get slug {
    final parts = id.split('_');
    if (parts.length > 2 && parts.first == 'npc') {
      return parts.sublist(2).join('_');
    }
    return id;
  }

  @override
  String toString() => '$name @ $location';
}

/// Everyone in the campaign, indexed for lookup by room.
class NpcDirectory {
  NpcDirectory(List<Npc> npcs) : _npcs = List.of(npcs) {
    for (final npc in _npcs) {
      if (npc.travels) continue;
      _byRoom.putIfAbsent(npc.location, () => []).add(npc);
    }
  }

  final List<Npc> _npcs;
  final Map<String, List<Npc>> _byRoom = {};

  List<Npc> get all => List.unmodifiable(_npcs);

  int get length => _npcs.length;

  /// Everyone who stays put in [roomId]. Travellers are placed by the
  /// session, which knows where they have got to.
  List<Npc> inRoom(String roomId) =>
      List.unmodifiable(_byRoom[roomId] ?? const []);

  /// Everyone who moves about.
  List<Npc> get travellers => [
        for (final npc in _npcs)
          if (npc.travels) npc,
      ];

  Npc? byId(String id) {
    for (final npc in _npcs) {
      if (npc.id == id) return npc;
    }
    return null;
  }

  /// Finds an NPC in [roomId] by name or id, matching loosely on any word of
  /// their name so "thorne" reaches Captain Thorne Ironhelm.
  Npc? findInRoom(String roomId, String query) =>
      findAmong(inRoom(roomId), query);

  /// Finds one of [npcs] by name or id, the way [findInRoom] does.
  static Npc? findAmong(Iterable<Npc> npcs, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final npc in npcs) {
      if (npc.id.toLowerCase() == needle) return npc;
      if (npc.name.toLowerCase() == needle) return npc;
      final words = npc.name.toLowerCase().split(RegExp(r'\s+'));
      if (words.contains(needle)) return npc;
    }
    return null;
  }

  /// NPCs placed in a room that does not exist, or travelling to one.
  List<Npc> misplacedIn(Set<String> knownRoomIds) => [
        for (final npc in _npcs)
          if (!knownRoomIds.contains(npc.location) ||
              (npc.route?.stops.any((s) => !knownRoomIds.contains(s)) ?? false))
            npc
      ];
}
