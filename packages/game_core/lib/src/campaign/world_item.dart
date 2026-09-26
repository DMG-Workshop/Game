/// An object lying in the world that the party can pick up or destroy.
///
/// Distinct from a `GearItem`, which is equipment with statistics. This is a
/// thing in a room that a quest cares about: a doll in a grove, a geode in a
/// mine. Its whole mechanical weight is the flag it sets.
class WorldItem {
  const WorldItem({
    required this.id,
    required this.name,
    required this.location,
    this.description = '',
    this.inRoomText,
    this.takeable = true,
    this.destroyable = false,
    this.acquireFlags = const [],
    this.destroyFlags = const [],
    this.requiredFlags = const [],
    this.hiddenUntilFlags = const [],
    this.onTake,
    this.onDestroy,
  });

  final String id;
  final String name;

  /// Room it lies in.
  final String location;
  final String description;

  /// How it reads as part of the room, before anyone touches it.
  final String? inRoomText;

  final bool takeable;
  final bool destroyable;

  /// Flags set when it is taken.
  final List<String> acquireFlags;

  /// Flags set when it is destroyed.
  final List<String> destroyFlags;

  /// Flags that must be set before it can be touched at all.
  final List<String> requiredFlags;

  /// Flags that must be set before it is even visible.
  ///
  /// Separate from [requiredFlags] because "you cannot see it yet" and "you
  /// can see it but not yet touch it" are different scenes.
  final List<String> hiddenUntilFlags;

  /// Narration when taken.
  final String? onTake;

  /// Narration when destroyed.
  final String? onDestroy;

  bool isVisible(Set<String> flags) => hiddenUntilFlags.every(flags.contains);

  bool isReachable(Set<String> flags) =>
      isVisible(flags) && requiredFlags.every(flags.contains);

  /// True once the flags it sets are already set, so it is spent.
  bool isResolved(Set<String> flags) {
    final all = [...acquireFlags, ...destroyFlags];
    return all.isNotEmpty && all.any(flags.contains);
  }

  @override
  String toString() => '$name @ $location';
}

/// The campaign's world objects, indexed by room.
class ItemPlacements {
  ItemPlacements(List<WorldItem> items) : _items = List.of(items) {
    for (final item in _items) {
      _byRoom.putIfAbsent(item.location, () => []).add(item);
    }
  }

  final List<WorldItem> _items;
  final Map<String, List<WorldItem>> _byRoom = {};

  List<WorldItem> get all => List.unmodifiable(_items);
  int get length => _items.length;

  WorldItem? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<WorldItem> inRoom(String roomId) =>
      List.unmodifiable(_byRoom[roomId] ?? const []);

  /// Items in [roomId] the party can currently see and have not used up.
  List<WorldItem> visibleIn(String roomId, Set<String> flags) => [
        for (final item in inRoom(roomId))
          if (item.isVisible(flags) && !item.isResolved(flags)) item,
      ];

  /// Finds an item in [roomId] by id, name, or any word of its name.
  ///
  /// A query matches whole words of the name, in order, however it is
  /// punctuated: "tokens" and "name tokens" both find "A String of
  /// Name-Tokens", and "reader", "readers" and "reader's day book" all find
  /// "A Reader's Day-Book". Hyphens used to keep a word whole, so a player
  /// typing the obvious noun was told the thing in front of them was not
  /// there.
  WorldItem? findInRoom(String roomId, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final asked = _forms(needle);
    for (final item in inRoom(roomId)) {
      if (item.id.toLowerCase() == needle) return item;
      final names = _forms(item.name);
      for (final name in names) {
        if (asked.any((q) => q.isNotEmpty && ' $name '.contains(' $q '))) {
          return item;
        }
      }
    }
    return null;
  }

  /// Ways of writing [text] with the punctuation taken out: the apostrophe
  /// dropped, the possessive dropped, and the apostrophe as a break.
  static Set<String> _forms(String text) {
    final lower = text.toLowerCase();
    String squash(String s) => s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return {
      squash(lower.replaceAll(RegExp(r"['’]"), '')),
      squash(lower.replaceAll(RegExp(r"['’]s\b"), '')),
      squash(lower.replaceAll(RegExp(r"['’]"), ' ')),
    };
  }

  /// Items placed in a room that does not exist.
  List<WorldItem> misplacedIn(Set<String> knownRoomIds) => [
        for (final item in _items)
          if (!knownRoomIds.contains(item.location)) item,
      ];

  /// Every flag taking or destroying something can set.
  Set<String> get producibleFlags => {
        for (final item in _items) ...item.acquireFlags,
        for (final item in _items) ...item.destroyFlags,
      };

  @override
  String toString() => '$length items placed';
}
