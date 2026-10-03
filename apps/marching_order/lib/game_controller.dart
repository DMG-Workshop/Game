import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _campaignDir = 'assets/campaign';
const _contentDir = 'assets/content';
const _demoCharacter = 'assets/characters/torvin.json';
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
      'LANTERNFALL\n${session.campaign.title}\n'
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

  /// The chip command that opens the trade sheet rather than going to the
  /// console.
  static const tradeCommand = ':trade';

  /// Whether the console is free for a command: not mid-way through one.
  bool get isIdle {
    final waiting = _waiting;
    return !_over && waiting != null && !waiting.isCompleted;
  }

  /// True where there is a shop and the party is walking about, which is
  /// when buying and selling are commands the console takes.
  bool get canTrade => _prompt == '> ' && session.shopHere != null && !_over;

  /// Who keeps the shop here, and what it is called.
  String get shopName {
    final shop = session.shopHere;
    if (shop == null) return '';
    final keeper = session.campaign.npcs.byId(shop.keeperId)?.name;
    return keeper == null ? shop.name : '${shop.name} — $keeper';
  }

  /// The keeper's price change for this party, in percent: below zero for
  /// a discount talked out of them, above for one they took offence at.
  int get priceChange => session.shopHere?.percentFor(session.flags) ?? 0;

  /// What is on the shelf here, at what the party would pay.
  List<({GearItem item, int price})> get wares =>
      canTrade ? session.wares() : const [];

  /// What the party could sell here, for what, and whether it is being worn
  /// or wielded (and so cannot be sold until it is taken off).
  List<({GearItem item, int price, int copies, bool inUse})> get sellable => [
    for (final item in session.inventory.carried)
      (
        item: item,
        price: item.resalePrice,
        copies: session.inventory.countOf(item.id),
        inUse:
            session.inventory.holdersOf(item.id).length >=
            session.inventory.countOf(item.id),
      ),
  ];

  /// Chips for what makes sense right now.
  List<CommandChip> get chips {
    if (_prompt != '> ') {
      // A conversation, a fight, the shop or the pack: the console's own
      // numbered menu, in its words, with the way back (0) last.
      final menu = [
        for (final c in _console.choices) (label: c.label, command: c.command),
      ];
      final back = menu.where((c) => c.command == '0');
      return [
        ...menu.where((c) => c.command != '0'),
        if (_prompt.startsWith('fight'))
          const (label: 'Status', command: 'status'),
        ...back,
      ];
    }
    final view = session.look();
    return [
      for (final d in view.openDirections) (label: d, command: d),
      if (view.encounters.isNotEmpty) (label: 'Fight', command: 'fight'),
      for (final npc in view.npcs)
        (label: 'Talk: ${npc.name.split(' ').last}', command: 'talk ${npc.id}'),
      if (session.actors.length < WorldSession.fullParty)
        for (final npc in session.recruitsHere)
          (
            label: 'Recruit: ${npc.name.split(' ').last}',
            command: 'recruit ${npc.id}',
          ),
      for (final item in view.items)
        (label: 'Take: ${item.name}', command: 'take ${item.name}'),
      if (session.shopHere != null) ...[
        (
          label: priceChange < 0 ? 'Trade · ${-priceChange}% off' : 'Trade',
          command: tradeCommand,
        ),
        (label: 'Shop', command: 'list'),
      ],
      const (label: 'Look', command: 'look'),
      const (label: 'Map', command: 'map'),
      const (label: 'Pack', command: 'inventory'),
      const (label: 'Party', command: 'party'),
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

  /// A new game for the party exported as [characters], on dice seeded by
  /// the clock unless [seed] says otherwise.
  static Future<GameController> start(
    List<String> characters, {
    int? seed,
  }) async {
    final loaded = await _load(characters);
    final session = WorldSession(
      campaign: loaded.campaign,
      actors: loaded.actors,
      spells: loaded.spells,
      roller: DiceRoller(
        seed ?? DateTime.now().millisecondsSinceEpoch % 1000000007,
      ),
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
      mapsJson: await read('maps.json'),
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
