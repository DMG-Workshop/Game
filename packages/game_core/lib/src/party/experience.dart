/// XP a character needs to reach their next level. Pathfinder resets it to
/// zero on levelling rather than counting up forever.
const int xpToLevel = 1000;

/// XP for defeating a creature [difference] levels above or below the party.
///
/// Pathfinder's own table. Anything five or more levels below the party is
/// no threat and worth nothing; anything more than four above is off the
/// table's end and paid as four, because a fight that far over the party's
/// head is not meant to be taken.
int creatureXp(int difference) => switch (difference) {
      <= -5 => 0,
      -4 => 10,
      -3 => 15,
      -2 => 20,
      -1 => 30,
      0 => 40,
      1 => 60,
      2 => 80,
      3 => 120,
      _ => 160,
    };

/// XP for an accomplishment of each size, as Pathfinder awards them.
enum Accomplishment {
  minor(10),
  moderate(30),
  major(80);

  const Accomplishment(this.xp);

  final int xp;

  static Accomplishment? tryParse(String source) {
    final needle = source.trim().toLowerCase();
    for (final a in values) {
      if (a.name == needle) return a;
    }
    return null;
  }
}

/// The party's level for working out what a creature is worth.
///
/// Pathfinder assumes a party of one level. Imported characters need not be,
/// so this is the average, rounded down: a level 6 and a level 7 fight as a
/// level 6 party, and nobody is paid as if the weaker one were not there.
int partyLevel(Iterable<int> levels) {
  final list = levels.toList();
  if (list.isEmpty) return 1;
  return list.reduce((a, b) => a + b) ~/ list.length;
}

/// Who has how much experience, and toward which level.
///
/// The game awards XP; it does not level anyone up. A character's level, feats
/// and choices live in Pathbuilder, so reaching [xpToLevel] is a prompt to
/// level up there and re-import. When the re-imported sheet comes back a level
/// higher, the thousand it cost comes off here.
class Experience {
  Experience();

  final Map<String, int> _xp = {};

  /// The level each character's XP is counting from.
  final Map<String, int> _level = {};

  /// Makes sure every actor has a record, and settles any whose sheet has
  /// gone up since the XP was earned. Returns who was settled, and by how
  /// many levels.
  List<({String actorId, int levels})> reconcile(
    Iterable<({String id, int level, int sheetXp})> actors,
  ) {
    final settled = <({String actorId, int levels})>[];
    for (final actor in actors) {
      final known = _level[actor.id];
      if (known == null) {
        // New to the party: their sheet is the record of what they had.
        _xp[actor.id] = actor.sheetXp < 0 ? 0 : actor.sheetXp;
        _level[actor.id] = actor.level;
      } else if (actor.level > known) {
        final gained = actor.level - known;
        final left = (_xp[actor.id] ?? 0) - gained * xpToLevel;
        _xp[actor.id] = left < 0 ? 0 : left;
        _level[actor.id] = actor.level;
        settled.add((actorId: actor.id, levels: gained));
      } else if (actor.level < known) {
        // Re-imported lower: a respec, or a mistake. Keep the XP; follow
        // the sheet's level.
        _level[actor.id] = actor.level;
      }
    }
    return settled;
  }

  int xpOf(String actorId) => _xp[actorId] ?? 0;

  /// Whether [actorId] has enough to level up in Pathbuilder.
  bool readyToLevel(String actorId) => xpOf(actorId) >= xpToLevel;

  /// Gives every one of [actorIds] [xp]. Everyone in the party earns the same
  /// XP for the same fight, as Pathfinder has it.
  void award(Iterable<String> actorIds, int xp) {
    if (xp <= 0) return;
    for (final id in actorIds) {
      _xp[id] = xpOf(id) + xp;
    }
  }

  Map<String, Object?> toJson() => {
        for (final id in (_xp.keys.toList()..sort()))
          id: {'xp': _xp[id], 'level': _level[id]},
      };

  static Experience fromJson(Object? json) {
    final experience = Experience();
    if (json is! Map) return experience;
    for (final entry in json.entries) {
      final record = entry.value;
      if (record is! Map) continue;
      final id = entry.key.toString();
      experience._xp[id] = (record['xp'] as num?)?.toInt() ?? 0;
      final level = (record['level'] as num?)?.toInt();
      if (level != null) experience._level[id] = level;
    }
    return experience;
  }

  @override
  String toString() =>
      _xp.entries.map((e) => '${e.key}: ${e.value}').join(', ');
}
