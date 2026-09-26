import '../campaign/fight_scene.dart';
import 'encounter_session.dart';

/// A line as it will be said: who says it, and what.
class ScriptLine {
  const ScriptLine({required this.text, this.speaker});

  /// The name of whoever says it, or null for something told.
  final String? speaker;
  final String text;

  bool get isSpeech => speaker != null;

  @override
  String toString() => isSpeech ? '$speaker: "$text"' : text;
}

/// Says the words around a fight at the moments they belong to.
///
/// Reads the fight's scene and each creature's voice, and works out who is
/// speaking from who is actually there: a line written for "the enemy" goes
/// to whichever of them can talk and is still standing, and a line for "the
/// party" to whoever did the thing being talked about. Nothing here rolls a
/// die — which line comes next is a matter of order, not chance — so adding
/// words to a fight changes none of its numbers.
class FightScript {
  FightScript(this.fight) : scene = fight.encounter.scene ?? const FightScene();

  final EncounterSession fight;
  final FightScene scene;

  final Set<String> _bloodied = {};
  final Set<String> _down = {};
  bool _saidBloodied = false;
  bool _saidFirstDown = false;
  int _taunts = 0;
  int _lastRound = 0;

  /// What the place is like.
  String get setting => scene.setting;

  /// The first exchange, before anyone moves.
  List<ScriptLine> opening() => _render(scene.opening, pc: _partyAt(0));

  /// A line of ambiance for [round], once per round.
  ScriptLine? ambianceFor(int round) {
    if (round == _lastRound || scene.ambiance.isEmpty) return null;
    _lastRound = round;
    return ScriptLine(
        text: scene.ambiance[(round - 1) % scene.ambiance.length]);
  }

  /// What gets said about [strikes] just made.
  ///
  /// Only the turns worth a word: a creature landing a critical hit taunts,
  /// one badly hurt for the first time says so, one going down has a last
  /// word, and the first of them to fall draws something from the party.
  List<ScriptLine> after(Iterable<StrikeResult> strikes) {
    final out = <ScriptLine>[];
    for (final strike in strikes) {
      final attacker = strike.attacker;
      final target = strike.target;

      if (attacker.isEnemy && strike.isCritical && !attacker.isDown) {
        final taunts = attacker.creature?.voice?.taunts ?? const [];
        if (taunts.isNotEmpty) {
          out.add(_voiced(attacker, taunts[_taunts++ % taunts.length]));
        }
      }

      out.addAll(_notice(attacker, target));
    }
    return out;
  }

  /// A creature badly hurt for the first time says so; one going down has a
  /// last word; the first to fall draws something from the party.
  List<ScriptLine> _notice(Combatant attacker, Combatant target) {
    final out = <ScriptLine>[];
    if (!target.isEnemy) return out;
    if (target.isDown && _down.add(target.id)) {
      final dying = target.creature?.voice?.dying ?? const [];
      if (dying.isNotEmpty) {
        out.add(_voiced(target, dying[_down.length % dying.length]));
      }
      if (!_saidFirstDown) {
        _saidFirstDown = true;
        out.addAll(_render(scene.firstDown, pc: attacker));
      }
    } else if (!target.isDown &&
        target.hp * 2 <= target.maxHp &&
        _bloodied.add(target.id)) {
      final hurt = target.creature?.voice?.hurt ?? const [];
      if (hurt.isNotEmpty) {
        out.add(_voiced(target, hurt[_bloodied.length % hurt.length]));
      }
      if (!_saidBloodied) {
        _saidBloodied = true;
        out.addAll(_render(scene.bloodied, pc: attacker));
      }
    }
    return out;
  }

  /// What gets said about a spell just cast: the same turns as a strike,
  /// for everyone it caught.
  List<ScriptLine> afterSpell(SpellResult result) {
    final out = <ScriptLine>[];
    for (final hit in result.hits) {
      out.addAll(_notice(result.caster, hit.target));
    }
    return out;
  }

  /// The last words, however it ended.
  List<ScriptLine> closing() => switch (fight.outcome) {
        EncounterOutcome.victory => _render(scene.victory, pc: _standing()),
        EncounterOutcome.defeat => _render(scene.defeat, pc: _partyAt(0)),
        EncounterOutcome.fled => _render(scene.flee, pc: _partyAt(0)),
        null => const [],
      };

  // --- who says it ----------------------------------------------------------

  Combatant? _partyAt(int index) {
    final party = fight.party;
    return party.isEmpty ? null : party[index % party.length];
  }

  Combatant? _standing() =>
      fight.party.where((c) => !c.isDown).firstOrNull ?? _partyAt(0);

  /// The enemy best placed to speak: one that can talk, standing if any is.
  Combatant? _speakingEnemy() {
    final talkers = [
      for (final c in fight.enemies)
        if (c.creature?.voice?.speaks ?? true) c,
    ];
    return talkers.where((c) => !c.isDown).firstOrNull ?? talkers.firstOrNull;
  }

  String get _enemyName =>
      (_speakingEnemy() ?? fight.enemies.firstOrNull)?.name ?? 'them';

  List<ScriptLine> _render(List<SceneLine> lines, {Combatant? pc}) => [
        for (final line in lines) _line(line, pc: pc),
      ];

  ScriptLine _line(SceneLine line, {Combatant? pc}) {
    final text = _fill(line.text, pc: pc);
    return switch (line.speaker) {
      Speaker.pc => ScriptLine(speaker: pc?.name, text: text),
      Speaker.enemy => _speakingEnemy() == null
          ? ScriptLine(text: text)
          : ScriptLine(speaker: _speakingEnemy()!.name, text: text),
      Speaker.narrator => ScriptLine(text: text),
    };
  }

  /// A creature's own line: spoken if it talks, told if it does not.
  ScriptLine _voiced(Combatant who, String text) {
    final filled = _fill(text, pc: _partyAt(0), enemy: who.name);
    final speaks = who.creature?.voice?.speaks ?? true;
    return speaks
        ? ScriptLine(speaker: who.name, text: filled)
        : ScriptLine(text: filled);
  }

  String _fill(String text, {Combatant? pc, String? enemy}) => text
      .replaceAll('{enemy}', enemy ?? _enemyName)
      .replaceAll('{pc}', pc?.name ?? 'you');
}
