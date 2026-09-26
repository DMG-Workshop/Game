/// Who says a line in a fight.
enum Speaker {
  /// Whoever on the other side can talk.
  enemy,

  /// Somebody in the party.
  pc,

  /// Nobody: it is what happens, told.
  narrator;

  static Speaker? tryParse(String source) {
    final needle = source.trim().toLowerCase();
    for (final s in values) {
      if (s.name == needle) return s;
    }
    return switch (needle) {
      'text' => Speaker.narrator,
      _ => null,
    };
  }
}

/// One line of a fight's script.
///
/// `{enemy}` and `{pc}` in the text become the names of whoever is on each
/// side, so a line can be written once and fit whoever is there.
class SceneLine {
  const SceneLine(this.speaker, this.text);

  final Speaker speaker;
  final String text;

  @override
  String toString() => '${speaker.name}: $text';
}

/// The words around a fight: where it is, what it feels like while it goes
/// on, and what both sides say when it starts, turns, and ends.
///
/// Words at the moments that matter, not a line for every swing: a fight is
/// told in its dice, and the talk is for where the two sides antagonise each
/// other.
class FightScene {
  const FightScene({
    this.setting = '',
    this.ambiance = const [],
    this.opening = const [],
    this.bloodied = const [],
    this.firstDown = const [],
    this.victory = const [],
    this.defeat = const [],
    this.flee = const [],
  });

  /// What the place is like, and what is at stake in it.
  final String setting;

  /// Small things that happen around the fight, one a round.
  final List<String> ambiance;

  /// The first exchange, before anyone moves.
  final List<SceneLine> opening;

  /// When one of them is first badly hurt.
  final List<SceneLine> bloodied;

  /// When the first of them goes down.
  final List<SceneLine> firstDown;

  final List<SceneLine> victory;
  final List<SceneLine> defeat;
  final List<SceneLine> flee;

  /// What this scene is missing, in words an author can act on.
  List<String> gaps() => [
        if (setting.trim().isEmpty) 'no setting',
        if (ambiance.length < 2) 'fewer than two lines of ambiance',
        if (!opening.any((l) => l.speaker == Speaker.pc))
          'nothing the party says to open it',
        if (victory.isEmpty) 'nothing said when it is won',
        if (defeat.isEmpty) 'nothing said when it is lost',
        if (flee.isEmpty) 'nothing said when the party runs',
      ];

  @override
  String toString() => setting;
}

/// What a creature says, or does in place of saying, when a fight turns.
class CreatureVoice {
  const CreatureVoice({
    this.speaks = true,
    this.taunts = const [],
    this.hurt = const [],
    this.dying = const [],
  });

  /// False for the mindless: their lines are what they do, told.
  final bool speaks;

  /// When it lands a hard blow.
  final List<String> taunts;

  /// When it is first badly hurt.
  final List<String> hurt;

  /// When it goes down.
  final List<String> dying;

  List<String> gaps() => [
        if (taunts.isEmpty) 'no taunt',
        if (hurt.isEmpty) 'nothing when it is hurt',
        if (dying.isEmpty) 'nothing when it goes down',
      ];
}
