/// XP a character needs to reach their next level. Pathfinder resets it to
/// zero on levelling rather than counting up forever.
const int xpToLevel = 1000;

/// The top of the track. Pathfinder's levels run from 1 to 20.
const int maxLevel = 20;

/// XP earned in all, from the start of level 1, by the time a character
/// reaches [level]: 0 at level 1, 19,000 at level 20.
int xpForLevel(int level) => (level.clamp(1, maxLevel) - 1) * xpToLevel;

/// Where one character stands on the road from level 1 to level 20.
class XpProgress {
  const XpProgress({required this.level, required this.xp});

  /// The level on their sheet.
  final int level;

  /// XP toward the next level, which may run past a thousand if the sheet
  /// has not been re-imported since.
  final int xp;

  bool get isMax => level >= maxLevel;

  /// XP earned in all since the start of level 1.
  int get total => xpForLevel(level) + xp;

  /// XP from level 1 to level 20.
  static int get fullTrack => xpForLevel(maxLevel);

  /// The level this much XP has earned, which is ahead of the sheet until
  /// it is levelled up in Pathbuilder.
  int get earnedLevel {
    final earned = level + xp ~/ xpToLevel;
    return earned > maxLevel ? maxLevel : earned;
  }

  /// XP still to find before the next level, or 0 once it is earned.
  int get toNext {
    if (isMax) return 0;
    final left = xpToLevel - xp;
    return left < 0 ? 0 : left;
  }

  /// Levels between the sheet and the top of the track.
  int get levelsToGo => maxLevel - earnedLevel;

  @override
  String toString() => isMax
      ? 'level $maxLevel, the top of the track'
      : 'level $level, $xp/$xpToLevel ($total/$fullTrack in all)';
}

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

  /// The level [actorId]'s XP is counting from: the one on their sheet.
  int levelOf(String actorId) => _level[actorId] ?? 1;

  /// Where [actorId] stands between level 1 and level 20.
  XpProgress progressOf(String actorId) =>
      XpProgress(level: levelOf(actorId), xp: xpOf(actorId));

  /// Whether [actorId] has enough to level up in Pathbuilder.
  bool readyToLevel(String actorId) =>
      levelOf(actorId) < maxLevel && xpOf(actorId) >= xpToLevel;

  /// Gives every one of [actorIds] [xp]. Everyone in the party earns the same
  /// XP for the same fight, as Pathfinder has it.
  ///
  /// The track ends at level 20: XP stops counting once it would carry a
  /// character past it, because there is no level 21 to spend it on.
  void award(Iterable<String> actorIds, int xp) {
    if (xp <= 0) return;
    for (final id in actorIds) {
      final ceiling = (maxLevel - levelOf(id)) * xpToLevel;
      final total = xpOf(id) + xp;
      _xp[id] = total > ceiling ? (ceiling < 0 ? 0 : ceiling) : total;
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
