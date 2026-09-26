import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _campaignDir = 'assets/campaign';
const _contentDir = 'assets/content';
const _demoCharacter = 'assets/characters/korash.json';
const _saveKey = 'marching_order.save';
const _saveVersion = 1;

/// Everything the console writes, collected for the log on screen.
class _LogSink implements StringSink {
  _LogSink(this.onWrite);

  final void Function(String text) onWrite;

  @override
  void write(Object? object) => onWrite('$object');

  @override
  void writeln([Object? object = '']) => onWrite('$object\n');

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      onWrite(objects.join(separator));

  @override
  void writeCharCode(int charCode) => onWrite(String.fromCharCode(charCode));
}

/// A tappable command: what the chip says, and what it sends.
typedef CommandChip = ({String label, String command});

/// Runs one game on the shared console, and keeps it saved on the device.
///
/// The console asks for input whenever it needs some; here that becomes a
/// pending future, completed when the player taps a chip or sends a line.
class GameController extends ChangeNotifier {
  GameController._(this.session, this._characters, {required bool resumed}) {
    // The screen wraps text itself, so the console never does.
    _console = GameConsole(session, _LogSink(_append), _ask, width: 100000);
    _append(
      '${'=' * 40}\n'
      'MARCHING ORDER\n${session.campaign.title}\n'
      '${'=' * 40}\n',
    );
    if (!resumed) {
      _append('\n${session.campaign.world.metadata.backgroundLore}\n');
    }
    for (final actor in session.actors) {
      _append('\n  $actor\n');
    }
    if (resumed) _append('\n(Picked up where you left off.)\n');
    _console.begin();
    unawaited(_run());
  }

  final WorldSession session;

  /// The Pathbuilder exports the party came from, kept for the save.
  final List<String> _characters;
  late final GameConsole _console;

  final StringBuffer _log = StringBuffer();
  Completer<String?>? _waiting;
  String _prompt = '> ';
  bool _over = false;

  /// Everything said so far.
  String get log => _log.toString();

  /// What the console is waiting for: `> ` walking, `say> ` in a
  /// conversation, `fight> ` in a fight.
  String get prompt => _prompt;

  bool get isOver => _over;

  void _append(String text) {
    _log.write(text);
    notifyListeners();
  }

  Future<String?> _ask({String prompt = '> '}) {
    _prompt = prompt;
    final waiting = _waiting = Completer<String?>();
    notifyListeners();
    return waiting.future;
  }

  /// Sends a line, as if typed at the prompt.
  void send(String line) {
    final waiting = _waiting;
    if (waiting == null || waiting.isCompleted || _over) return;
    _append('\n$_prompt$line\n');
    waiting.complete(line.trim());
  }

  Future<void> _run() async {
    while (true) {
      final line = await _ask();
      if (line == null) break;
      if (line.isEmpty) continue;
      if (line == 'quit' || line == 'q') break;
      if (line == 'save' || line.startsWith('save ')) {
        await save();
        _append('Saved on this device.\n');
        continue;
      }
      final keepGoing = await _console.play(line);
      await save();
      if (!keepGoing) break;
    }
    await save();
    _over = true;
    _append('\n(The game is saved. Start it again from the title screen.)\n');
  }

  /// Chips for what makes sense right now.
  List<CommandChip> get chips {
    if (_prompt.startsWith('say')) {
      // The conversation's own choices, in its words.
      return [
        for (final c in _console.choices) (label: c.label, command: c.command),
      ];
    }
    if (_prompt.startsWith('fight')) {
      return const [
        (label: 'Strike', command: 'strike'),
        (label: 'Close in', command: 'close'),
        (label: 'Fall back', command: 'back'),
        (label: 'Spells', command: 'spells'),
        (label: 'Drink', command: 'use hearth-water'),
        (label: 'End turn', command: 'end'),
        (label: 'Status', command: 'status'),
        (label: 'Flee', command: 'flee'),
      ];
    }
    final view = session.look();
    return [
      for (final d in view.openDirections) (label: d, command: d),
      if (view.encounters.isNotEmpty) (label: 'Fight', command: 'fight'),
      for (final npc in view.npcs)
        (label: 'Talk: ${npc.name.split(' ').last}', command: 'talk ${npc.id}'),
      for (final item in view.items)
        (label: 'Take: ${item.name}', command: 'take ${item.name}'),
      if (session.shopHere != null) (label: 'Wares', command: 'list'),
      const (label: 'Look', command: 'look'),
      const (label: 'Pack', command: 'inventory'),
      const (label: 'Status', command: 'status'),
      const (label: 'Quests', command: 'quests'),
      const (label: 'Rest', command: 'rest'),
      const (label: 'Help', command: 'help'),
    ];
  }

  Map<String, Object?> _saveData() => {
    'version': _saveVersion,
    'characters': _characters,
    'world': session.snapshot(),
  };

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saveKey, jsonEncode(_saveData()));
  }

  // --- starting a game -------------------------------------------------------

  static Future<bool> hasSave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_saveKey) != null;
  }

  static Future<void> deleteSave() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_saveKey);
  }

  static Future<String> demoCharacter() =>
      rootBundle.loadString(_demoCharacter);

  /// A new game for the party exported as [characters].
  static Future<GameController> start(List<String> characters) async {
    final loaded = await _load(characters);
    final session = WorldSession(
      campaign: loaded.campaign,
      actors: loaded.actors,
      spells: loaded.spells,
      roller: DiceRoller(DateTime.now().millisecondsSinceEpoch % 1000000007),
    );
    return GameController._(session, characters, resumed: false);
  }

  /// The game saved on this device.
  static Future<GameController> resume() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_saveKey);
    if (raw == null) throw StateError('There is no saved game.');
    final saved = jsonDecode(raw) as Map<String, Object?>;
    if ((saved['version'] as num? ?? 0) > _saveVersion) {
      throw StateError('That save is from a newer version of the game.');
    }
    final characters = [for (final c in saved['characters'] as List) '$c'];
    final loaded = await _load(characters);
    final session = WorldSession.restore(
      campaign: loaded.campaign,
      actors: loaded.actors,
      spells: loaded.spells,
      snapshot: (saved['world'] as Map).cast<String, Object?>(),
    );
    return GameController._(session, characters, resumed: true);
  }

  static Future<
    ({Campaign campaign, List<SessionActor> actors, SpellBook spells})
  >
  _load(List<String> characters) async {
    Future<String?> read(String name) async {
      try {
        return await rootBundle.loadString('$_campaignDir/$name');
      } on FlutterError {
        return null;
      }
    }

    final campaign = const CampaignLoader().load(
      id: 'campaign_i_shattered_seals',
      title: 'Campaign I: Shattered Seals',
      worldConfigJson: (await read('world_config.json'))!,
      locationsJson: (await read('locations.json'))!,
      npcsJson: (await read('npcs_and_dialogue.json'))!,
      gearJson: await read('gear.json'),
      arcsJson: await read('campaign_arcs.json'),
      bestiaryJson: await read('bestiary.json'),
      itemsJson: await read('world_items.json'),
      conversationsJson: await read('conversations.json'),
      economyJson: await read('economy.json'),
      huntJson: await read('hunt.json'),
      weatherJson: await read('weather.json'),
    );
    final spells = const CampaignLoader().readSpells(
      await rootBundle.loadString('$_contentDir/spells.json'),
    );
    final actors = <SessionActor>[];
    for (final json in characters) {
      final character = const PathbuilderImporter().importJson(json).character;
      final base = character.name.split(' ').first.toLowerCase();
      var id = base;
      for (var n = 2; actors.any((a) => a.id == id); n++) {
        id = '$base$n';
      }
      actors.add(SessionActor(id: id, character: character));
    }
    return (campaign: campaign, actors: actors, spells: spells);
  }
}
