import 'package:pf2e_core/pf2e_core.dart';

import '../campaign/arc.dart';
import '../campaign/atlas.dart';
import '../campaign/gear.dart';
import '../campaign/hunt.dart';
import '../campaign/npc.dart';
import '../campaign/spell.dart';
import '../party/equipment.dart';
import '../party/experience.dart';
import '../party/vitals.dart';
import '../party/wealth.dart';
import '../scene/scene.dart';
import 'casting.dart';
import 'encounter_session.dart';
import 'fight_script.dart';
import 'game_event.dart';
import 'game_session.dart';
import 'item_use.dart';
import 'map_drawing.dart';
import 'party_scaling.dart';
import 'session_actor.dart';
import 'world_event.dart';
import 'world_session.dart';

/// Every command the console knows, as a player would read them.
const consoleCommands = '''
  north/south/east/west/up/down (or n/s/e/w/u/d)  walk
  look                                            describe the room again
  exits                                           list ways out, open and shut
  map                                             the map of where you are,
                                                  and a number to travel
  who                                             who is here, and their topics
  talk <name>                                     talk to someone properly
  ask <name> about <topic>                        raise a single topic
  quests                                          arc progress
  xp                                              everyone's XP, level 1 to 20
  inventory (i)                                   the pack: pick something by
                                                  number to equip, use or drop
  list                                            the shop here: a number buys
  buy <item or number> / sell [item or number]    trade (you get half back)
  value <item>                                    what a shop would pay
  drop <item>                                     leave something behind
  purse                                           the party's coin
  wealth                                          what you're worth, and who
                                                  that brings after you
  ledger                                          everything found, and where
  sheet [who]                                     AC, Strike, HP as equipped
  party                                           who is with you: pick one
                                                  to look closer, or part ways
  recruit [who]                                   take on somebody here who
                                                  would join (party of 4 at most)
  dismiss <who>                                   part ways with a companion
  equip [who] <item>                              wield or wear something
  unequip [who] weapon|armour                     put it away again
  save [file]                                     save the game (resume with
                                                  --resume=<file>)
  wait [hours]                                    let time pass (no number:
                                                  wait out a storm)
  time                                            the day, the hour, the sky
  status                                          HP, spells, focus, fatigue
  spells [who]                                    what each of you can cast
  rest                                            sleep 8 hours: HP back,
                                                  spells and focus restored
  treat [who]                                     Treat Wounds (Medicine)
  use <item> [on <who>]                           drink a draught, or give
                                                  it (1 action in a fight)
  cast <spell> [on <who>]                         a healing spell, between
                                                  fights
  refocus                                         10 minutes: 1 focus back
  shelter                                         make shelter from a storm
  quit                                            stop
''';

const _directions = {
  'north',
  'south',
  'east',
  'west',
  'northeast',
  'northwest',
  'southeast',
  'southwest',
  'up',
  'down',
  'in',
  'out',
  'n',
  's',
  'e',
  'w',
  'ne',
  'nw',
  'se',
  'sw',
  'u',
  'd',
};

/// One entry in a numbered menu: how it reads in the text, and the shorter
/// thing a button for it says.
typedef _Entry = ({String text, String chip});

/// The game as text: a command in, what happens written out.
///
/// Everything a player sees is written to [out], and anything that needs
/// an answer mid-command — a line of conversation, an order in a fight —
/// asks [nextCommand] for it. The terminal answers from stdin; the app
/// answers when the player taps or types, which is why the asking is
/// asynchronous. Both clients are this one console, so they never tell the
/// game differently.
///
/// Menus — the shop, the pack, a fight — are numbered, with 0 to go back.
/// Anything typed at one that is not a number of its own leaves it and is
/// played as an ordinary command, so a menu never traps a player who
/// knows what they want to do.
class GameConsole {
  GameConsole(this.session, this.out, this.nextCommand, {this.width = 70});

  final WorldSession session;
  final StringSink out;
  final Future<String?> Function({String prompt}) nextCommand;

  /// Where prose is wrapped: a terminal's width, or wide enough never to
  /// wrap on a screen that wraps text itself.
  final int width;

  /// The choices on offer while a conversation waits for an answer: what
  /// to send, and what it says. Empty the rest of the time.
  List<({String command, String label})> get choices =>
      List.unmodifiable(_choices);
  List<({String command, String label})> _choices = const [];

  /// The fight under way, while there is one: for a client that wants to
  /// offer its spells or targets as buttons.
  EncounterSession? get fight => _current;
  EncounterSession? _current;

  /// Options that mean "show me what you sell", when a shopkeeper has them.
  static const _browsing = {'look', 'wares', 'stock', 'browse', 'ask_stock'};

  /// Options that mean "come with us", when somebody would.
  static const _joining = {'join', 'ask_join', 'hire', 'recruit'};

  /// A line a menu read that was not for it, waiting to be played.
  String? _pending;

  /// Coin that changed hands over a counter during this command: earned
  /// selling, less what was spent buying. Kept so that selling is not
  /// announced as money found.
  int _traded = 0;

  String _wrapped(String text, {String indent = ''}) =>
      wrap(text, width: width, indent: indent);

  /// Writes [entries] numbered from 1 and 0 for [back], and offers the same
  /// to a client as [choices].
  void _offer(List<_Entry> entries, String back) {
    final width = '${entries.length}'.length;
    for (var i = 0; i < entries.length; i++) {
      out.writeln('  ${'${i + 1}'.padLeft(width)}. ${entries[i].text}');
    }
    out.writeln('  ${'0'.padLeft(width)}. $back');
    _choices = [
      for (var i = 0; i < entries.length; i++)
        (command: '${i + 1}', label: entries[i].chip),
      (command: '0', label: back),
    ];
  }

  /// The answer to a menu of [count] entries: a number from it, or the line
  /// when it is anything else. Null when the input has run out.
  ///
  /// A number that is not on the menu is answered here, and asked again,
  /// rather than taken for a command.
  Future<({int? pick, String line})?> _read(String prompt, int count) async {
    while (true) {
      final pending = _pending;
      _pending = null;
      final line = pending ?? await nextCommand(prompt: prompt);
      if (line == null) {
        _choices = const [];
        return null;
      }
      final text = line.trim();
      final number = int.tryParse(text);
      if (number != null && (number < 0 || number > count)) {
        out.writeln('Pick a number from 0 to $count.');
        continue;
      }
      _choices = const [];
      return (pick: number, line: text);
    }
  }

  /// Describes where the game starts.
  void begin() {
    _renderRoom(session, full: true, showWeather: true);
    _announceEvents(session);
  }

  /// Plays one command, returning false once the player has stopped.
  Future<bool> play(String line) async {
    final coinBefore = session.inventory.coin;
    final xpBefore = {
      for (final a in session.actors) a.id: session.experience.xpOf(a.id),
    };
    final tierBefore = session.notoriety.tier;
    _traded = 0;
    var keepGoing = await _handle(session, line, nextCommand);
    // A menu that was left by typing a command leaves that command to play.
    while (keepGoing && _pending != null) {
      final next = _pending!;
      _pending = null;
      if (next.isEmpty) continue;
      keepGoing = await _handle(session, next, nextCommand);
    }
    _pending = null;
    _announceEvents(session);
    final gained = session.inventory.coin - coinBefore - _traded;
    if (gained > 0) {
      out.writeln('\n  [+${formatCoin(gained)} — the party has '
          '${formatCoin(session.inventory.coin)}]');
    }
    _announceExperience(session, xpBefore);
    _announceNotoriety(session, tierBefore);
    return keepGoing;
  }

  /// Returns false to end the session.
  Future<bool> _handle(WorldSession session, String line,
      Future<String?> Function({String prompt}) nextCommand) async {
    final words = line.split(RegExp(r'\s+'));
    final verb = words.first.toLowerCase();
    final rest = words.skip(1).join(' ');

    if (verb == 'quit' || verb == 'q') return false;

    if (_directions.contains(verb)) return _go(session, verb, nextCommand);
    if (verb == 'go' && rest.isNotEmpty) return _go(session, rest, nextCommand);

    switch (verb) {
      case 'look':
      case 'l':
        _renderRoom(session, full: true, showWeather: true);
        return true;

      case 'map':
        return _map(session);

      case 'exits':
        final view = session.look();
        out.writeln('Exits: ${view.openDirections.join(', ')}');
        for (final barred in view.barredDirections) {
          out.writeln('  ${barred.direction}: '
              '${barred.reason ?? 'shut'}');
        }
        return true;

      case 'who':
        final npcs = session.look().npcs;
        if (npcs.isEmpty) {
          out.writeln('Nobody else is here.');
        } else {
          for (final npc in npcs) {
            final left = session.unraisedTopicsFor(npc);
            out.writeln('  ${npc.name}'
                '${left.isEmpty ? '' : '  (topics: ${left.join(', ')})'}'
                '${_joinNote(session, npc)}');
          }
        }
        return true;

      case 'talk':
      case 'ask':
        return _talk(session, rest, nextCommand);

      case 'take':
      case 'get':
        return _takeOrDestroy(session, rest, destroy: false);

      case 'destroy':
      case 'break':
        return _takeOrDestroy(session, rest, destroy: true);

      case 'examine':
      case 'x':
        final item = session
            .look()
            .items
            .where((i) => i.name.toLowerCase().contains(rest.toLowerCase()))
            .firstOrNull;
        if (item == null || rest.isEmpty) {
          out.writeln('There is no "$rest" here to examine.');
        } else {
          out.writeln('\n${_wrapped(item.description)}');
        }
        return true;

      case 'fight':
      case 'attack':
        return _fight(session, nextCommand,
            encounterId: rest.isEmpty ? null : rest);

      case 'wait':
        final hours = int.tryParse(rest);
        try {
          if (hours == null) {
            final minutes = session.waitOutStorm();
            out.writeln(minutes > 60
                ? 'You wait out the weather: ${_duration(minutes)}.'
                : 'An hour goes by.');
          } else {
            session.advanceTime(hours);
            out.writeln('${_duration(hours * 60)} go by.');
          }
        } on InvalidMoveException catch (e) {
          out.writeln(_wrapped(e.message));
          return true;
        }
        _announceEvents(session);
        out.writeln('\nIt is ${_when(session)}.');
        final echo = session.ambianceEcho();
        if (echo != null) out.writeln('\n${_wrapped(echo)}');
        return true;

      case 'time':
      case 'date':
        out.writeln('It is ${_when(session)}.');
        return true;

      case 'status':
      case 'hp':
        _renderStatus(session);
        return true;

      case 'party':
        return _party(session);

      case 'recruit':
      case 'hire':
        return _recruit(session, rest);

      case 'dismiss':
        _dismiss(session, rest);
        return true;

      case 'spells':
        _renderSpells(session, rest);
        return true;

      case 'rest':
      case 'sleep':
      case 'camp':
        try {
          final indoors = session.currentRoom.shelter || session.isSheltering;
          final night = session.nightLines(indoors: indoors);
          if (night.said case final said?) _says(said.who.name, said.line);
          final healed = session.rest();
          if (night.night case final text?) out.writeln('\n${_wrapped(text)}');
          if (night.wake case final text?) out.writeln('\n${_wrapped(text)}');
          out.writeln('\nYou slept eight hours, and have made your '
              'preparations for the day.');
          for (final actor in session.actors) {
            final v = session.vitalsOf(actor.id);
            out.writeln('  ${actor.name}: +${healed[actor.id]} HP '
                '(${v.hp}/${v.maxHp})');
          }
          out.writeln('  Spell slots and focus restored. Nobody is tired.');
          out.writeln('\nIt is ${_when(session)}.');
        } on InvalidMoveException catch (e) {
          out.writeln(_wrapped(e.message));
        }
        return true;

      case 'treat':
      case 'heal':
        try {
          final t = session.treatWounds(who: rest.isEmpty ? null : rest);
          final c = t.check;
          final whose =
              t.healer.id == t.patient.id ? 'their own' : "${t.patient.name}'s";
          out.writeln('\n${t.healer.name} treats $whose '
              'wounds: d20(${c.dieRoll}) ${_signed(c.modifier)} = ${c.total} '
              'vs DC ${c.dc} — ${c.degree.displayName}');
          final roll = t.roll;
          final v = session.vitalsOf(t.patient.id);
          if (roll != null) {
            out.writeln('  ${t.change >= 0 ? 'heals' : 'hurts'} $roll: '
                '${t.change >= 0 ? '+' : ''}${t.change} HP (${v.hp}/${v.maxHp})');
          } else {
            out.writeln('  Ten minutes, and nothing to show for it.');
          }
        } on InvalidMoveException catch (e) {
          out.writeln(_wrapped(e.message));
        }
        return true;

      case 'use':
      case 'drink':
        final args = _useArgs(rest);
        if (args == null) {
          out.writeln('Use what? ("inventory" shows what you carry.)');
          return true;
        }
        try {
          _renderUse(session.use(args.what, who: args.who));
        } on InvalidMoveException catch (e) {
          out.writeln(_wrapped(e.message));
        }
        return true;

      case 'cast':
        // Between fights, only what mends: anything else waits for a fight.
        final args = _useArgs(rest);
        if (args == null) {
          out.writeln('Cast what? ("spells" lists them.)');
          return true;
        }
        try {
          final c = session.castHealing(args.what, who: args.who);
          final v = session.vitalsOf(c.patient.id);
          out.writeln('\n${c.caster.name} casts ${c.option.spell.name} '
              '(rank ${c.option.rank}) on ${c.patient.name}: ${c.roll}, '
              '+${c.healed} HP (${v.hp}/${v.maxHp}).');
        } on InvalidMoveException catch (e) {
          out.writeln(_wrapped(e.message));
        }
        return true;

      case 'refocus':
        try {
          final back = session.refocus();
          for (final id in back.keys) {
            final v = session.vitalsOf(id);
            out.writeln('${session.actorFor(id).name} refocuses: '
                '${v.focus}/${v.maxFocus} focus.');
          }
        } on InvalidMoveException catch (e) {
          out.writeln(_wrapped(e.message));
        }
        return true;

      case 'shelter':
        try {
          final built = session.makeShelter();
          final c = built.check;
          out.writeln('\n${built.builder.name} makes shelter: '
              'd20(${c.dieRoll}) ${_signed(c.modifier)} = ${c.total} vs DC '
              '${c.dc} — ${c.degree.displayName}');
          out.writeln(_wrapped(
              switch (c.degree) {
                DegreeOfSuccess.criticalSuccess =>
                  'A windbreak of cut branches and a groundsheet, pegged down '
                      'tight. It will hold.',
                DegreeOfSuccess.success =>
                  'Rough, but it will keep the worst off. Wait it out: "wait".',
                DegreeOfSuccess.failure =>
                  'It holds, more or less, once you have been soaked putting it '
                      'up. Wait it out: "wait".',
                DegreeOfSuccess.criticalFailure =>
                  'It comes down on top of you. You are still out in it.',
              },
              indent: '  '));
        } on InvalidMoveException catch (e) {
          out.writeln(_wrapped(e.message));
        }
        return true;

      case 'quests':
      case 'arcs':
        _renderArcs(session);
        return true;

      case 'loot':
      case 'inventory':
      case 'inv':
      case 'pack':
      case 'i':
        return _pack(session);

      case 'drop':
        if (rest.isEmpty) {
          out.writeln('Drop what? ("inventory" shows what you carry.)');
          return true;
        }
        _drop(session, rest);
        return true;

      case 'list':
      case 'wares':
      case 'shop':
        return _shop(session);

      case 'buy':
        if (rest.isEmpty) return _shop(session);
        return _buy(session, _wareNamed(session, rest));

      case 'sell':
        if (rest.isEmpty) return _sellMenu(session, back: 'Done selling');
        _sell(session, _carriedNamed(session, rest));
        return true;

      case 'value':
      case 'appraise':
        try {
          final quote = session.valueOf(rest);
          out.writeln('${_keeper(session)} would give you '
              '${formatCoin(quote.price)} for ${quote.item.name}.');
        } on InvalidMoveException catch (e) {
          out.writeln(_wrapped(e.message));
        }
        return true;

      case 'purse':
      case 'coin':
      case 'money':
        out.writeln('The party has ${formatCoin(session.inventory.coin)}, '
            'and is worth ${formatCoin(session.wealth.total)} in all.');
        return true;

      case 'wealth':
      case 'worth':
      case 'notoriety':
        _renderWealth(session);
        return true;

      case 'ledger':
      case 'found':
        _renderLedger(session);
        return true;

      case 'xp':
      case 'experience':
      case 'level':
        _renderExperience(session);
        return true;

      case 'sheet':
      case 'stats':
        _renderSheet(session, rest);
        return true;

      case 'equip':
      case 'wield':
      case 'wear':
        return _equip(session, rest);

      case 'unequip':
      case 'remove':
        return _unequip(session, rest);

      case 'flags':
        final flags = session.flags.toList()..sort();
        out.writeln(flags.isEmpty ? '(none)' : flags.join('\n'));
        return true;

      case 'help':
        out.writeln(consoleCommands);
        return true;

      default:
        out.writeln('I do not know how to "$verb". Try "help".');
        return true;
    }
  }

  Future<bool> _go(
    WorldSession session,
    String direction,
    Future<String?> Function({String prompt}) nextCommand, {
    bool brief = false,
  }) async {
    final MoveResult result;
    try {
      result = session.move(direction);
    } on InvalidMoveException catch (e) {
      out.writeln(_wrapped(e.message));
      _stopped = true;
      return true;
    }

    final ambush = result.ambush;
    final hunt = result.hunt;
    // On the way somewhere else, a room is a line, unless something is
    // waiting in it.
    if (brief && ambush == null && hunt == null) {
      out.writeln('  ${result.direction}, to ${session.currentRoom.title}'
          '  (${_shortTime(result.minutes)})');
      _announceArcs(session);
      _announceEvents(session);
      return true;
    }

    if (result.minutes >= 30) {
      out.writeln('\n  (${_duration(result.minutes)} on the road)');
    }
    _renderRoom(session, full: true, showWeather: result.changedRegion);
    final here = session.roomAmbiance();
    if (here != null) out.writeln('\n${_wrapped(here)}');
    if (result.changedRegion) {
      final echo = session.ambianceEcho();
      if (echo != null) out.writeln('\n${_wrapped(echo)}');
    }
    _announceArcs(session);
    _announceEvents(session);

    // An ambush is not something to mention and move on from.
    if (ambush != null) {
      _stopped = true;
      return _fight(session, nextCommand, encounterId: ambush.id);
    }

    // Nor is something that has followed the party's money this far.
    final roll = result.huntRoll;
    if (hunt != null) {
      _stopped = true;
      out.writeln('\n  [The hunt: d100(${roll?.die}) against '
          '${roll?.chance}% — something has your scent]');
      out.writeln('\n${_wrapped(hunt.description)}');
      return _fight(session, nextCommand, encounterId: hunt.id);
    }
    return true;
  }

  /// Set when a walk ends somewhere other than where it was going: a fight,
  /// or a road that would not be taken.
  bool _stopped = false;

  /// Walks [directions] one road at a time, a line for each place passed
  /// through and the whole of the last, and stops wherever something
  /// happens on the way.
  Future<bool> _travel(WorldSession session, List<String> directions) async {
    out.writeln('');
    for (var i = 0; i < directions.length; i++) {
      _stopped = false;
      final last = i == directions.length - 1;
      final keepGoing =
          await _go(session, directions[i], nextCommand, brief: !last);
      if (!keepGoing) return false;
      if (_stopped) {
        if (!last) out.writeln('\n(You stop here.)');
        return true;
      }
    }
    return true;
  }

  // --- the map -------------------------------------------------------------

  /// The town the party is in, drawn from what they know, with every known
  /// place they could walk to from here, nearest first, and the ways into
  /// what they do not know. A number sets off; 0 puts the map away.
  Future<bool> _map(WorldSession session) async {
    final map = session.mapHere;
    if (map == null) {
      out.writeln('Nobody has drawn a map of this place.');
      return true;
    }
    final charted = session.carriesMap(map);
    final here = session.currentRoom.id;
    final drawing = <String>[];
    out.writeln('\n${map.title.toUpperCase()}'
        '${charted ? '' : '  (as far as you have walked it)'}');
    for (final sheet in map.sheets) {
      final lines = drawSheet(
        sheet: sheet,
        map: map,
        knows: session.knowsRoom,
        exitsOf: session.knownExits,
        here: here,
      );
      if (lines.isEmpty) continue;
      if (sheet.title != map.title) {
        out.writeln('\n${sheet.title}'
            '${sheet.under == null ? '' : ', ${sheet.under}'}');
      }
      out.writeln('');
      for (final line in lines) {
        out.writeln('  $line');
      }
      drawing.addAll(lines);
      for (final way in _waysOff(session, map, sheet)) {
        out.writeln('  $way');
      }
    }
    out.writeln('\n  ${[
      '[ ] you are here',
      if (drawing.any((l) => l.contains('?'))) '? not explored',
      if (drawing.any((l) => l.contains(':'))) ': a way up or down',
    ].join('   ')}');
    final hint = map.hint;
    if (!charted && hint != null) out.writeln(_wrapped(hint, indent: '  '));

    final locations = session.campaign.locations;
    final routes = [
      for (final route in session.routes())
        if (locations.roomById(route.roomId) case final room?)
          (room: room, route: route),
    ];
    final explore = [
      for (final exit in session.currentRoom.exits.values)
        if (exit.isOpen(session.flags) && !session.knowsRoom(exit.to)) exit,
    ];
    // As wide as the longest name here and no wider: on a phone, a place,
    // how long, and which way all have to fit on one line.
    final names = [
      for (final r in routes) r.room.title,
      for (final exit in explore) 'Explore ${exit.direction}',
    ];
    final pad = names.fold(0, (w, n) => n.length > w ? n.length : w);
    final options = <({_Entry entry, List<String> directions})>[
      for (final (:room, :route) in routes)
        (
          entry: (
            text: '${room.title.padRight(pad)} '
                '${_shortTime(route.minutes).padLeft(6)}  '
                '${_route(route.directions)}',
            chip: '${room.title} · ${_shortTime(route.minutes)}',
          ),
          directions: route.directions,
        ),
      for (final exit in explore)
        (
          entry: (
            text: '${'Explore ${exit.direction}'.padRight(pad)} '
                '${_shortTime(session.travelMinutes(exit.direction)).padLeft(6)}',
            chip: 'Explore ${exit.direction}',
          ),
          directions: [exit.direction],
        ),
    ];
    out.writeln('\nWhere to, from ${session.currentRoom.title}:');
    if (options.isEmpty) out.writeln('  Nowhere you know of is open to you.');
    _offer([for (final o in options) o.entry], 'Put the map away');
    final got = await _read('map> ', options.length);
    if (got == null) return false;
    final pick = got.pick;
    if (pick == null) {
      if (got.line.isNotEmpty) _pending = got.line;
      return true;
    }
    if (pick == 0) return true;
    return _travel(session, options[pick - 1].directions);
  }

  /// The ways off [sheet] from the rooms on it the party knows: stairs to
  /// another sheet, and roads to another town.
  List<String> _waysOff(WorldSession session, TownMap map, MapSheet sheet) {
    final atlas = session.campaign.atlas;
    final locations = session.campaign.locations;
    final out = <String>[];
    for (final roomId in sheet.places.keys) {
      for (final exit in session.knownExits(roomId)) {
        if (sheet.places.containsKey(exit.to)) continue;
        final elsewhere = map.sheetOf(exit.to)?.title ??
            atlas.forRoom(exit.to)?.title ??
            locations.townForRoom(exit.to)?.name ??
            'somewhere';
        final known = session.knowsRoom(exit.to);
        out.add('${map.labelOf(roomId)}: ${exit.direction} to '
            '${known ? elsewhere : 'somewhere not yet explored'}'
            '${exit.isOpen(session.flags) ? '' : ' (shut)'}');
      }
    }
    return out;
  }

  /// "west ×3, north".
  String _route(List<String> directions) {
    final parts = <String>[];
    for (var i = 0; i < directions.length;) {
      var j = i;
      while (j < directions.length && directions[j] == directions[i]) {
        j++;
      }
      parts.add(j - i > 1 ? '${directions[i]} ×${j - i}' : directions[i]);
      i = j;
    }
    return parts.join(', ');
  }

  /// "15 min", "1 h 30", "8 h".
  String _shortTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  /// Accepts "talk thorne" for a conversation, and "ask thorne about elara" or
  /// "talk thorne elara" for a single topic.
  Future<bool> _talk(WorldSession session, String rest,
      Future<String?> Function({String prompt}) nextCommand) async {
    if (rest.isEmpty) {
      out.writeln('Talk to whom?');
      return true;
    }
    final words = rest.split(RegExp(r'\s+'));
    final who = words.first;
    var topic = words.skip(1).join(' ');
    if (topic.toLowerCase().startsWith('about ')) {
      topic = topic.substring(6);
    }

    if (topic.isEmpty) {
      try {
        final conversation = session.beginConversation(who);
        if (conversation != null) {
          return await _converse(
              session, conversation.npc, conversation.talk, nextCommand);
        }
      } on InvalidMoveException catch (e) {
        out.writeln(e.message);
        return true;
      }
    }

    try {
      final result = session.talk(who, topic: topic.isEmpty ? null : topic);
      out.writeln('\n${result.npc.name}:');
      out.writeln(_wrapped('"${result.said}"', indent: '  '));

      if (result.isGreeting) {
        final left = session.unraisedTopicsFor(result.npc);
        if (left.isNotEmpty) {
          out.writeln('\n  (ask about: ${left.join(', ')})');
        }
      }
      for (final flag in result.flagsSet) {
        out.writeln('\n  [$flag]');
      }
      _announceArcs(session);
    } on InvalidMoveException catch (e) {
      out.writeln(e.message);
    }
    return true;
  }

  /// Runs a conversation to its end, or until the party walks away.
  ///
  /// Its own loop for the same reason a fight has one: the verbs are different.
  /// Everything said before walking away still counts.
  Future<bool> _converse(
    WorldSession session,
    Npc npc,
    GameSession talk,
    Future<String?> Function({String prompt}) nextCommand,
  ) async {
    final solo = session.actors.length == 1;
    out
      ..writeln('\n${'-' * 70}')
      ..writeln(npc.name.toUpperCase())
      ..writeln('-' * 70)
      ..writeln('\n${_wrapped(talk.currentScene.body)}');

    var keepGoing = true;
    while (!talk.isFinished) {
      final options = talk.availableOptions();
      out.writeln('');
      // Somebody who has been asked everything says so, rather than
      // offering a menu that only has the door on it. Never beside a roll:
      // watching a liar tell it again is something more to ask.
      if (options.isNotEmpty &&
          options.every((o) => _endsTalk(talk, o) && o.check == null)) {
        out.writeln('  (Nothing more to ask ${npc.name} for now.)');
      }
      for (var i = 0; i < options.length; i++) {
        out.writeln('  ${i + 1}. ${options[i].label}'
            '${_checkHint(talk, options[i], solo: solo)}');
      }
      out.writeln('  0. Walk away');
      _choices = [
        for (var i = 0; i < options.length; i++)
          (command: '${i + 1}', label: options[i].label),
        (command: '0', label: 'Walk away'),
      ];

      final line = await nextCommand(prompt: 'say> ');
      _choices = const [];
      if (line == null) {
        out.writeln('\n(script exhausted mid-conversation)');
        keepGoing = false;
        break;
      }
      final choice = line.trim().toLowerCase();
      if (choice.isEmpty) continue;
      if (const {'0', 'bye', 'leave', 'walk away'}.contains(choice)) {
        out.writeln('\nYou leave ${npc.name} where you found them.');
        break;
      }

      final number = int.tryParse(choice);
      final option = number != null && number >= 1 && number <= options.length
          ? options[number - 1]
          : options
              .where((o) =>
                  o.id == choice || o.label.toLowerCase().startsWith(choice))
              .firstOrNull;
      if (option == null) {
        out.writeln('Pick a number from the list, or 0 to walk away.');
        continue;
      }

      final GameEvent event;
      try {
        event = talk.choose(option.id);
      } on InvalidChoiceException catch (e) {
        out.writeln(e.message);
        continue;
      }

      if (event.said case final said?) {
        out.writeln('\n${_wrapped('${event.actorName} says, "$said"')}');
      }
      final check = event.check;
      if (check != null) {
        out.writeln('\n  ~ ${solo ? '' : '${event.actorName} — '}'
            '${check.label}: d20(${check.dieRoll}) '
            '${_signed(check.modifier)} = ${check.total} vs DC ${check.dc} '
            '-> ${check.degree.displayName}'
            '${check.wasShiftedByNatural ? ' (natural ${check.dieRoll})' : ''}');
      }
      out.writeln('\n${_wrapped(event.narration)}');
      // Asking a shopkeeper to see the stock opens the shop across the
      // counter, at whatever price has just been talked out of them, and
      // 0 comes back to the conversation.
      if (_browsing.contains(option.id) &&
          session.shopHere?.keeperId == npc.id) {
        if (!await _shop(session, flags: talk.flags, backTo: npc.name)) {
          out.writeln('\n(script exhausted mid-conversation)');
          keepGoing = false;
          break;
        }
      }

      // Asking somebody to come along puts the question of terms: what they
      // would bring, and what they want for it. Once they say yes, they are
      // walking with the party, and the talk is over.
      if (_joining.contains(option.id) && npc.recruit != null) {
        final joined = await _hire(session, npc, talking: true);
        if (joined == null) {
          out.writeln('\n(script exhausted mid-conversation)');
          keepGoing = false;
          break;
        }
        if (joined) break;
      }

      // A new scene is a new beat; returning to the same one is not, and
      // repeating its opening every time would read like a stuck record.
      final movedTo = event.movedTo;
      if (movedTo != null && movedTo != event.sceneId) {
        out.writeln('\n${_wrapped(talk.currentScene.body)}');
      }
    }

    final flags = session.concludeConversation(talk);
    for (final flag in flags) {
      out.writeln('\n  [$flag]');
    }
    _announceArcs(session);
    return keepGoing;
  }

  /// Whether every way [option] can turn out ends the conversation.
  bool _endsTalk(GameSession talk, SceneOption option) {
    final outcomes = [
      if (option.automatic case final o?) o,
      ...option.outcomes.values,
    ];
    return outcomes.isNotEmpty &&
        outcomes.every((o) => talk.adventure.scenes[o.goTo]?.isEnding ?? false);
  }

  String _checkHint(GameSession talk, SceneOption option,
      {required bool solo}) {
    final check = option.check;
    if (check == null) return '';
    final best = talk.suggestedActorFor(option.id);
    if (best == null) return '  (nobody can try this)';
    final who = solo ? '' : '${best.actor.name} ';
    return '  ($who${best.stat.formatted} vs DC ${check.dc})';
  }

  // --- the party -----------------------------------------------------------

  /// The party as a menu: everyone's state, and a number to look closer at
  /// one of them, or to part ways with a companion. False when the input
  /// ran out.
  Future<bool> _party(WorldSession session) async {
    while (true) {
      final members = session.actors;
      if (_pending == null) {
        out.writeln('\nThe party  (${members.length} of '
            '${WorldSession.fullParty})');
        _offer([
          for (final a in members) _memberEntry(session, a),
        ], 'Close');
        if (members.length < WorldSession.fullParty) {
          final here = session.recruitsHere;
          out.writeln(here.isEmpty
              ? '\n  (Room for ${WorldSession.fullParty - members.length} '
                  'more. Some folk would join you, for a fee.)'
              : '\n  (${here.map((n) => n.name).join(' and ')} would join '
                  'you: "recruit".)');
        }
      }
      final got = await _read('party> ', members.length);
      if (got == null) return false;
      final pick = got.pick;
      if (pick == 0) return true;
      if (pick != null) {
        if (!await _member(session, members[pick - 1])) return false;
        continue;
      }
      if (got.line.isEmpty) continue;
      _pending = got.line;
      return true;
    }
  }

  _Entry _memberEntry(WorldSession session, SessionActor actor) {
    final v = session.vitalsOf(actor.id);
    final what = '${actor.character.className} ${actor.character.level}';
    return (
      text: '${actor.name.padRight(22)} ${what.padRight(12)} '
          'HP ${v.hp}/${v.maxHp}'
          '${session.isCompanion(actor.id) ? '  (companion)' : ''}',
      chip: actor.name,
    );
  }

  /// One member of the party up close, and for a companion, the door.
  Future<bool> _member(WorldSession session, SessionActor actor) async {
    out.writeln('');
    _describe(
      actor,
      session.statsFor(actor.id),
      session.vitalsOf(actor.id),
    );
    final companion = session.isCompanion(actor.id);
    final first = _familiar(actor.name);
    _offer([
      if (companion)
        (text: 'Part ways with $first', chip: 'Part ways with $first'),
    ], 'Back to the party');
    final got = await _read('member> ', companion ? 1 : 0);
    if (got == null) return false;
    if (got.pick == 1) {
      final home = session.campaign.locations
          .roomById(session.homeOf(actor.id) ?? '')
          ?.title;
      out.writeln('\n${_wrapped('$first would go back to '
          '${home ?? 'where you found them'}. Whatever $first wears stays '
          'with the party, and taking $first on again costs nothing.')}');
      _offer([(text: 'Part ways', chip: 'Part ways')], 'Keep $first');
      final sure = await _read('dismiss> ', 1);
      if (sure == null) return false;
      if (sure.pick == 1) {
        _dismiss(session, actor.id);
      } else if (sure.pick == null && sure.line.isNotEmpty) {
        _pending = sure.line;
      }
      return true;
    }
    if (got.pick == null && got.line.isNotEmpty) _pending = got.line;
    return true;
  }

  /// A character's numbers, as they would fight: AC, saves, the Strike,
  /// and what they can cast.
  void _describe(SessionActor actor, EquippedStats stats, ActorVitals vitals) {
    final c = actor.character;
    final d = actor.stats;
    out.writeln('${actor.name} — ${c.ancestry} ${c.className}, level '
        '${c.level}');
    out.writeln('  HP ${vitals.hp}/${vitals.maxHp}   AC ${stats.armorClass}'
        '   Perception ${d.perception.formatted}   '
        'Fort ${d.fortitude.formatted}  Ref ${d.reflex.formatted}  '
        'Will ${d.will.formatted}');
    out.writeln('  Strike ${_signed(stats.attackBonus)} ${stats.damage}  '
        '(${stats.weaponLabel}${stats.isRanged ? ', ranged' : ''})');
    final options = castOptionsFor(actor, vitals, session.spells);
    final casts = <String, int>{};
    final ranks = <String, int>{};
    final cantrips = <String>{};
    for (final o in options) {
      if (o.cost == CastCost.cantrip) {
        cantrips.add(o.spell.name);
        continue;
      }
      casts.update(o.spell.name, (n) => n + o.left, ifAbsent: () => o.left);
      if (o.rank > (ranks[o.spell.name] ?? 0)) ranks[o.spell.name] = o.rank;
    }
    if (casts.isNotEmpty) {
      out.writeln(_wrapped(
          'Spells: ${[
            for (final e in casts.entries)
              '${e.key} x${e.value} (up to ${_ordinal(ranks[e.key]!)} rank)',
          ].join(', ')}',
          indent: '  '));
    }
    if (cantrips.isNotEmpty) {
      out.writeln(_wrapped('Cantrips: ${cantrips.join(', ')}', indent: '  '));
    }
  }

  /// What a companion is called on the road: "Bren" for Bren Cask, "Wren"
  /// for Sister Wren.
  String _familiar(String name) {
    final words = name.split(' ');
    const titles = {'sister', 'brother', 'captain', 'foreman', 'master'};
    if (words.length > 1 && titles.contains(words.first.toLowerCase())) {
      return words[1];
    }
    return words.first;
  }

  /// "  (would join: Fighter, 20 gp)", for somebody who would.
  String _joinNote(WorldSession session, Npc npc) {
    final recruit = npc.recruit;
    if (recruit == null) return '';
    final fee = session.feeFor(npc);
    return '  (would join: ${recruit.className}'
        '${fee == 0 ? '' : ', ${formatCoin(fee)}'})';
  }

  /// "recruit" with or without a name: somebody here who would join.
  Future<bool> _recruit(WorldSession session, String who) async {
    final here = session.recruitsHere;
    if (here.isEmpty) {
      out.writeln('Nobody here is looking to join you.');
      return true;
    }
    final npc = who.isEmpty
        ? (here.length == 1 ? here.single : null)
        : NpcDirectory.findAmong(here, who);
    if (npc == null) {
      out.writeln(who.isEmpty
          ? 'Recruit whom? ${here.map((n) => n.name).join(', ')}.'
          : 'Nobody here called "$who" would join you.');
      return true;
    }
    out.writeln('');
    return await _hire(session, npc) != null;
  }

  /// What [npc] would bring to the party at its level, what they want for
  /// it, and the question. True once they have joined, false if not; null
  /// when the input ran out.
  Future<bool?> _hire(WorldSession session, Npc npc,
      {bool talking = false}) async {
    final would = session.companionFor(npc);
    out.writeln('');
    _describe(
        would, EquippedStats(would.stats), ActorVitals.fresh(would.stats));
    final fee = session.feeFor(npc);
    out.writeln(fee == 0
        ? '\n  Asks nothing to come along.'
        : '\n  Asks ${formatCoin(fee)} to join. The purse holds '
            '${formatCoin(session.inventory.coin)}.');
    if (session.whyNot(npc) case final reason?) {
      out.writeln(_wrapped(reason, indent: '  '));
      return false;
    }
    final first = _familiar(npc.name);
    _offer([
      (
        text: 'Take $first on${fee == 0 ? '' : '  (${formatCoin(fee)})'}',
        chip: 'Take $first on',
      ),
    ], 'Not now');
    final got = await _read('hire> ', 1);
    if (got == null) return null;
    if (got.pick == 1) {
      try {
        final actor = session.recruit(npc.id);
        out.writeln('\n${_wrapped('${actor.name} joins the party.')}');
        return true;
      } on InvalidMoveException catch (e) {
        out.writeln(_wrapped(e.message));
        return false;
      }
    }
    // In a conversation, anything but yes is no; out of one, a command
    // typed here is played.
    if (!talking && got.pick == null && got.line.isNotEmpty) {
      _pending = got.line;
    }
    return false;
  }

  void _dismiss(WorldSession session, String who) {
    if (who.trim().isEmpty) {
      final names = session.companions.map((a) => a.name).toList();
      out.writeln(names.isEmpty
          ? 'Nobody with you joined on the road.'
          : 'Part ways with whom? ${names.join(', ')}.');
      return;
    }
    try {
      final actor = session.dismiss(who);
      final home = session.campaign.locations
          .roomById(session.homeOf(actor.id) ?? '')
          ?.title;
      out.writeln('\n${_wrapped('${actor.name} leaves the party'
          '${home == null ? '' : ', back to $home'}.')}');
    } on InvalidMoveException catch (e) {
      out.writeln(_wrapped(e.message));
    }
  }

  // --- the pack ------------------------------------------------------------

  /// The pack as a menu: pick something to see what can be done with it.
  /// False when the input ran out.
  Future<bool> _pack(WorldSession session) async {
    while (true) {
      final pack = session.inventory;
      final carried = pack.carried;
      if (carried.isEmpty) {
        out.writeln('The pack is empty. You have what you arrived with.');
        out.writeln('\nPurse: ${formatCoin(pack.coin)}');
        return true;
      }
      if (_pending == null) {
        out.writeln('\nThe pack  (purse: ${formatCoin(pack.coin)})');
        _offer([
          for (final item in carried)
            (
              text: '${_packName(session, item).padRight(30)} '
                  'level ${item.level} ${item.rarity.name} ${item.type}'
                  '${_wornBy(session, item)}',
              chip: _packName(session, item),
            ),
        ], 'Close the pack');
      }
      final got = await _read('pack> ', carried.length);
      if (got == null) return false;
      final pick = got.pick;
      if (pick == 0) return true;
      if (pick != null) {
        if (!await _itemMenu(session, carried[pick - 1])) return false;
        continue;
      }
      if (got.line.isEmpty) continue;
      _pending = got.line;
      return true;
    }
  }

  /// "Minor Hearth-Water x2".
  String _packName(WorldSession session, GearItem item) {
    final count = session.inventory.countOf(item.id);
    return count > 1 ? '${item.name} x$count' : item.name;
  }

  /// "  (on Korash Blackearth)", for something being worn or wielded.
  String _wornBy(WorldSession session, GearItem item) {
    final holders = session.inventory.holdersOf(item.id);
    return holders.isEmpty
        ? ''
        : '  (on ${[
            for (final id in holders) session.actorFor(id).name,
          ].join(', ')})';
  }

  /// One thing from the pack, and what can be done with it: give it to
  /// somebody to wield or wear, take it off them, drink it, or drop it.
  Future<bool> _itemMenu(WorldSession session, GearItem item) async {
    final pack = session.inventory;
    final solo = session.actors.length == 1;
    final slot = EquipSlot.forType(item.type);
    final holders = pack.holdersOf(item.id);
    final actions = <({_Entry entry, Future<bool> Function() run})>[];

    if (slot != null) {
      for (final (:actor, :entry) in _equipEntries(session, item, slot)) {
        actions.add((
          entry: entry,
          run: () async {
            _equipItem(session, item.id, actor.id);
            return true;
          },
        ));
      }
      for (final id in holders) {
        final name = session.actorFor(id).name;
        actions.add((
          entry: (
            text: solo ? 'Put it away' : 'Take it off $name',
            chip: solo ? 'Put it away' : 'Take off $name',
          ),
          run: () async {
            try {
              final result = session.unequip(slot.name, who: id);
              out.writeln('\n${result.actor.name} puts away '
                  '${result.removed?.name ?? item.name}.');
            } on InvalidMoveException catch (e) {
              out.writeln(_wrapped(e.message));
            }
            return true;
          },
        ));
      }
    }
    if (item.use != null) {
      for (final actor in session.actors) {
        final v = session.vitalsOf(actor.id);
        final hp = 'HP ${v.hp}/${v.maxHp}';
        actions.add((
          entry: solo
              ? (text: 'Drink it  ($hp)', chip: 'Drink it')
              : (
                  text: 'Give it to ${actor.name}  ($hp)',
                  chip: 'Give to ${actor.name.split(' ').first}',
                ),
          run: () async {
            try {
              _renderUse(session.use(item.id, who: actor.id));
            } on InvalidMoveException catch (e) {
              out.writeln(_wrapped(e.message));
            }
            return true;
          },
        ));
      }
    }
    if (pack.countOf(item.id) > holders.length) {
      final one = pack.countOf(item.id) > 1;
      actions.add((
        entry: (
          text: one ? 'Drop one' : 'Drop it',
          chip: one ? 'Drop one' : 'Drop it',
        ),
        run: () => _confirmDrop(session, item),
      ));
    }

    out.writeln('\n${_packName(session, item)} — level ${item.level} '
        '${item.rarity.name} ${item.type}, worth ${formatCoin(item.price)}');
    if (item.description.isNotEmpty) {
      out.writeln(_wrapped(item.description, indent: '  '));
    }
    if (item.special case final special?) {
      out.writeln(_wrapped(special, indent: '  '));
    }
    if (holders.isNotEmpty) {
      final names = [for (final id in holders) session.actorFor(id).name];
      out.writeln('  ${names.join(' and ')} '
          '${names.length == 1 ? 'is' : 'are'} '
          '${slot == EquipSlot.armor ? 'wearing' : 'holding'} it.');
    }
    out.writeln('');
    _offer([for (final a in actions) a.entry], 'Back to the pack');
    final got = await _read('item> ', actions.length);
    if (got == null) return false;
    final pick = got.pick;
    if (pick == null) {
      if (got.line.isNotEmpty) _pending = got.line;
      return true;
    }
    if (pick == 0) return true;
    return actions[pick - 1].run();
  }

  /// Asks before leaving something behind for good.
  Future<bool> _confirmDrop(WorldSession session, GearItem item) async {
    out.writeln('\nLeave ${item.name} behind? It will be gone for good.');
    _offer([(text: 'Drop it', chip: 'Drop it')], 'Keep it');
    final got = await _read('drop> ', 1);
    if (got == null) return false;
    if (got.pick == 1) {
      _drop(session, item.id);
    } else if (got.pick == null && got.line.isNotEmpty) {
      _pending = got.line;
    }
    return true;
  }

  void _drop(WorldSession session, String what) {
    try {
      final item = session.drop(what);
      out.writeln('\nYou leave ${item.name} behind.');
    } on InvalidMoveException catch (e) {
      out.writeln(_wrapped(e.message));
    }
  }

  // --- the shop ------------------------------------------------------------

  /// The shop as a menu, until the party goes back: a number buys it,
  /// "sell" shows what the keeper would take, and 0 goes back.
  ///
  /// Opened from a conversation, [flags] are the conversation's, so a price
  /// just talked down is the price, and 0 goes back to [backTo]. Anything
  /// else said there gets told to pick a number. Opened from the street,
  /// anything else leaves the shop and is done instead.
  Future<bool> _shop(WorldSession session,
      {Set<String>? flags, String? backTo}) async {
    final shop = session.shopHere;
    if (shop == null) {
      out.writeln('There is nobody here to trade with.');
      return true;
    }
    final talking = backTo != null;
    if (session.keeperSays('greet') case final k?) _says(k.keeper, k.line);
    while (true) {
      final wares = session.wares(flags: flags);
      final canSell = session.inventory.carried.isNotEmpty;
      final count = wares.length + (canSell ? 1 : 0);
      if (_pending == null) {
        _renderWares(session, wares, flags: flags);
        _offer([
          for (final row in wares) _wareEntry(session, row),
          if (canSell) (text: 'Sell something', chip: 'Sell something'),
        ], talking ? 'Back to $backTo' : 'Leave the shop');
      }
      final got = await _read('shop> ', count);
      if (got == null) return false;
      final pick = got.pick;
      if (pick == 0) return true;
      if (pick != null) {
        final bought = pick <= wares.length
            ? await _buy(session, wares[pick - 1].item.id, flags: flags)
            : await _sellMenu(session, back: 'Back to the stock');
        if (!bought) return false;
        continue;
      }

      final line = got.line;
      final words = line.split(RegExp(r'\s+'));
      final verb = words.first.toLowerCase();
      final rest = words.skip(1).join(' ');
      switch (verb) {
        case '':
        case 'list':
        case 'wares':
          continue;
        case 'buy':
          if (rest.isEmpty) continue;
          if (!await _buy(session, _wareNamed(session, rest, flags: flags),
              flags: flags)) {
            return false;
          }
        case 'sell':
          if (rest.isEmpty) {
            if (!await _sellMenu(session, back: 'Back to the stock')) {
              return false;
            }
          } else {
            _sell(session, _carriedNamed(session, rest));
          }
        case 'back':
        case 'leave':
        case 'done':
        case 'bye':
          return true;
        default:
          if (talking) {
            out.writeln('Pick a number from the list, or 0 to go back to '
                '$backTo.');
          } else {
            _pending = line;
            return true;
          }
      }
    }
  }

  /// The stock, as a header over the numbered list.
  void _renderWares(
    WorldSession session,
    List<({GearItem item, int price})> wares, {
    Set<String>? flags,
  }) {
    final shop = session.shopHere!;
    final percent = shop.percentFor(flags ?? session.flags);
    out.writeln('\n${shop.name} — ${_keeper(session)}'
        '${percent == 0 ? '' : percent < 0 ? '  (${-percent}% off, for you)' : '  (+$percent%, for you)'}');
    final coin = session.inventory.coin;
    out.writeln('The party has ${formatCoin(coin)}.'
        '${wares.any((r) => r.price > coin) ? '  (* is more than that)' : ''}\n');
  }

  /// One row of the stock: its level and price, what it would have cost
  /// before a haggle, and a star when the party cannot afford it.
  _Entry _wareEntry(WorldSession session, ({GearItem item, int price}) row) {
    final dear = row.price > session.inventory.coin ? '  *' : '';
    final was = row.price == row.item.price
        ? ''
        : '  (was ${formatCoin(row.item.price)})';
    return (
      text: '${row.item.name.padRight(30)} '
          '${'level ${row.item.level}'.padRight(9)} '
          '${formatCoin(row.price).padLeft(12)}$was$dear',
      chip: '${row.item.name} · ${formatCoin(row.price)}',
    );
  }

  /// What the party could sell here, as a menu; a number sells one.
  Future<bool> _sellMenu(WorldSession session, {required String back}) async {
    if (session.shopHere == null) {
      out.writeln('There is nobody here to trade with.');
      return true;
    }
    while (true) {
      final carried = session.inventory.carried;
      if (carried.isEmpty) {
        out.writeln('\nThere is nothing in the pack to sell.');
        return true;
      }
      if (_pending == null) {
        out.writeln('\n${_keeper(session)} would give you, for one of each '
            '(half what it cost):\n');
        _offer([
          for (final item in carried)
            (
              text: '${_packName(session, item).padRight(30)} '
                  '${formatCoin(item.resalePrice).padLeft(12)}'
                  '${_inUse(session, item) ? '  (in use: take it off first)' : _wornBy(session, item)}',
              chip: '${item.name} · ${formatCoin(item.resalePrice)}',
            ),
        ], back);
      }
      final got = await _read('sell> ', carried.length);
      if (got == null) return false;
      final pick = got.pick;
      if (pick == 0) return true;
      if (pick != null) {
        _sell(session, carried[pick - 1].id);
        continue;
      }
      final words = got.line.split(RegExp(r'\s+'));
      if (words.first.toLowerCase() == 'sell' && words.length > 1) {
        _sell(session, _carriedNamed(session, words.skip(1).join(' ')));
        continue;
      }
      if (got.line.isNotEmpty) _pending = got.line;
      return true;
    }
  }

  /// Whether every copy of [item] is being worn or wielded.
  bool _inUse(WorldSession session, GearItem item) =>
      session.inventory.holdersOf(item.id).length >=
      session.inventory.countOf(item.id);

  /// A row of the stock by its number, or [what] as it was typed.
  String _wareNamed(WorldSession session, String what, {Set<String>? flags}) {
    final number = int.tryParse(what.trim());
    if (number == null || session.shopHere == null) return what;
    final wares = session.wares(flags: flags);
    return number >= 1 && number <= wares.length
        ? wares[number - 1].item.id
        : what;
  }

  /// Something in the pack by its number, or [what] as it was typed.
  String _carriedNamed(WorldSession session, String what) {
    final number = int.tryParse(what.trim());
    final carried = session.inventory.carried;
    return number != null && number >= 1 && number <= carried.length
        ? carried[number - 1].id
        : what;
  }

  /// Buys one of [what], then asks who is to use it, if it is something to
  /// wield or wear. False when the input ran out while asking.
  Future<bool> _buy(WorldSession session, String what,
      {Set<String>? flags}) async {
    final ({GearItem item, int price}) bought;
    try {
      bought = session.buy(what, flags: flags);
    } on InvalidMoveException catch (e) {
      out.writeln(_wrapped(e.message));
      if (e.message.contains('and the party has')) {
        if (session.keeperSays('broke') case final k?) _says(k.keeper, k.line);
      }
      return true;
    }
    _traded -= bought.price;
    out.writeln('\nYou buy ${bought.item.name} for '
        '${formatCoin(bought.price)}. The party has '
        '${formatCoin(session.inventory.coin)} left.');
    if (session.keeperSays('buy') case final k?) _says(k.keeper, k.line);
    return _offerToEquip(session, bought.item);
  }

  void _sell(WorldSession session, String what) {
    try {
      final sold = session.sell(what);
      _traded += sold.price;
      out.writeln('\n${_keeper(session)} gives you '
          '${formatCoin(sold.price)} for ${sold.item.name}. The party has '
          '${formatCoin(session.inventory.coin)}.');
      if (session.keeperSays('sell') case final k?) _says(k.keeper, k.line);
    } on InvalidMoveException catch (e) {
      out.writeln(_wrapped(e.message));
    }
  }

  // --- wielding and wearing ------------------------------------------------

  /// Something just bought to wield or wear: who takes it up, with what it
  /// would do for each of them, or 0 to leave it in the pack.
  Future<bool> _offerToEquip(WorldSession session, GearItem item) async {
    final slot = EquipSlot.forType(item.type);
    if (slot == null) return true;
    final entries = _equipEntries(session, item, slot);
    if (entries.isEmpty) return true;
    out.writeln(session.actors.length == 1
        ? '\n${session.primary.name} could '
            '${slot == EquipSlot.weapon ? 'wield' : 'wear'} it now:'
        : '\nWho takes ${item.name}?');
    _offer([for (final e in entries) e.entry], 'Keep it in the pack');
    final got = await _read('equip> ', entries.length);
    if (got == null) return false;
    final pick = got.pick;
    if (pick == null) {
      // Something else to do: it waits in the pack meanwhile.
      if (got.line.isNotEmpty) _pending = got.line;
    } else if (pick == 0) {
      out.writeln('\n${item.name} goes in the pack.');
    } else {
      _equipItem(session, item.id, entries[pick - 1].actor.id);
    }
    return true;
  }

  /// Everyone who could take up [item] and is not already using it, each
  /// with what it would do to their Strike or AC.
  List<({SessionActor actor, _Entry entry})> _equipEntries(
      WorldSession session, GearItem item, EquipSlot slot) {
    final solo = session.actors.length == 1;
    final verb = slot == EquipSlot.weapon ? 'Wield it' : 'Wear it';
    return [
      for (final actor in session.actors)
        if (session.statsFor(actor.id).loadout.inSlot(slot)?.id != item.id)
          (
            actor: actor,
            entry: (
              text: '${solo ? verb : actor.name.padRight(24)}  '
                  '${_change(session.statsFor(actor.id), item, slot)}',
              chip: solo ? verb : 'Give to ${actor.name.split(' ').first}',
            ),
          ),
    ];
  }

  /// "Strike +15 2d12+4 (Greataxe) -> +14 1d8+4", or "AC 25 (Leather) -> 26".
  String _change(EquippedStats now, GearItem item, EquipSlot slot) {
    final then = EquippedStats(now.base, now.loadout.replacing(slot, item));
    return slot == EquipSlot.weapon
        ? 'Strike ${_signed(now.attackBonus)} ${now.damage} '
            '(${now.weaponLabel}) -> ${_signed(then.attackBonus)} ${then.damage}'
        : 'AC ${now.armorClass} (${now.armorLabel}) -> ${then.armorClass}';
  }

  String _keeper(WorldSession session) {
    final shop = session.shopHere;
    if (shop == null) return 'Nobody';
    return session.campaign.npcs.byId(shop.keeperId)?.name ?? shop.name;
  }

  void _renderSheet(WorldSession session, String who) {
    try {
      final actor = who.isEmpty ? session.primary : session.actorFor(who);
      final stats = session.statsFor(actor.id);
      out.writeln('\n$actor');
      for (final line in stats.describe()) {
        out.writeln('  $line');
      }
      out.writeln('  HP ${actor.stats.maxHp}  '
          'Perception ${actor.stats.perception.formatted}  '
          'Class DC ${actor.stats.classDc}');
      out.writeln(session.isCompanion(actor.id)
          ? '  Joined on the road; keeps pace with the party\'s level.'
          : '  ${_xpLine(session.experience.progressOf(actor.id))}');
    } on InvalidMoveException catch (e) {
      out.writeln(e.message);
    }
  }

  /// Accepts "equip nail" and "equip korash nail".
  bool _equip(WorldSession session, String rest) {
    if (rest.isEmpty) {
      out.writeln('Equip what?');
      return true;
    }
    final words = rest.split(RegExp(r'\s+'));
    String? who;
    var what = rest;
    if (words.length > 1 && session.knowsActor(words.first)) {
      who = words.first;
      what = words.skip(1).join(' ');
    }
    _equipItem(session, what, who);
    return true;
  }

  /// Puts [what] on [who], and says what it changed.
  void _equipItem(WorldSession session, String what, String? who) {
    try {
      final before = session.statsFor(session.actorFor(who ?? '').id);
      final beforeAc = before.armorClass;
      final beforeAttack = before.attackBonus;
      final beforeDamage = before.damage.toString();

      final result = session.equip(what, who: who);
      final after = session.statsFor(result.actor.id);

      out.writeln('\n${result.actor.name} takes up ${result.item.name}'
          '${result.replaced == null ? '' : ', putting away '
              '${result.replaced!.name}'}.');
      if (result.slot == EquipSlot.armor) {
        out.writeln('  AC $beforeAc -> ${after.armorClass}');
      } else {
        out.writeln('  Strike ${_signed(beforeAttack)} $beforeDamage'
            ' -> ${_signed(after.attackBonus)} ${after.damage}');
      }
    } on EquipException catch (e) {
      out.writeln(_wrapped(e.message));
    } on InvalidMoveException catch (e) {
      out.writeln(_wrapped(e.message));
    }
  }

  bool _unequip(WorldSession session, String rest) {
    if (rest.isEmpty) {
      out.writeln('Take off what — weapon or armour?');
      return true;
    }
    final words = rest.split(RegExp(r'\s+'));
    String? who;
    var slot = rest;
    if (words.length > 1 && session.knowsActor(words.first)) {
      who = words.first;
      slot = words.skip(1).join(' ');
    }

    try {
      final result = session.unequip(slot, who: who);
      out.writeln(result.removed == null
          ? '${result.actor.name} had nothing there.'
          : '${result.actor.name} puts away ${result.removed!.name}.');
    } on InvalidMoveException catch (e) {
      out.writeln(_wrapped(e.message));
    }
    return true;
  }

  String _signed(int value) => value >= 0 ? '+$value' : '$value';

  /// "day 3 (day 14 of Autumn, year 1), 14:15, in the rain".
  String _when(WorldSession session) {
    final date = session.date;
    final now = session.weatherNow;
    return 'day ${session.day} (day ${date.dayOfSeason} of ${date.season.name}, '
        'year ${date.year}), ${session.clock}'
        '${session.isNight ? ', and dark' : ''}'
        '${now == null ? '' : '. ${now.name}${session.currentRoom.shelter ? ' outside' : ''}'}';
  }

  /// 90 as "1 hour 30 minutes".
  String _duration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return [
      if (h > 0) '$h ${h == 1 ? 'hour' : 'hours'}',
      if (m > 0) '$m ${m == 1 ? 'minute' : 'minutes'}',
    ].join(' ');
  }

  /// How everyone is holding up: HP, what is left to cast with, and how far
  /// the party can go before it has to stop.
  void _renderStatus(WorldSession session) {
    out.writeln('\nIt is ${_when(session)}.');
    for (final actor in session.actors) {
      final v = session.vitalsOf(actor.id);
      final slots = (v.slots.keys.toList()..sort())
          .map((r) => '${_ordinal(r)} ${v.slotsLeft[r] ?? 0}/${v.slots[r]}')
          .join(', ');
      out.writeln('  ${actor.name.padRight(24)} HP ${v.hp}/${v.maxHp}'
          '${v.maxFocus > 0 ? '   focus ${v.focus}/${v.maxFocus}' : ''}'
          '${slots.isEmpty ? '' : '   spells $slots'}');
    }
    final e = session.endurance;
    final limits = session.campaign.weather.travel;
    out.writeln('\n  ${_duration(e.travelMinutes).ifEmpty('No time')} on '
        'the road, ${_duration(e.awakeMinutes).ifEmpty('no time')} awake, '
        'since you last rested.');
    if (session.isSpent) {
      out.writeln('  The party is spent: no long roads until you rest.');
    } else if (session.isFatigued) {
      out.writeln('  The party is Fatigued: -1 to AC and saves until you '
          'rest.');
    } else {
      out.writeln('  About ${e.roadLeftHours(limits).toStringAsFixed(1)} '
          'hours before you tire.');
    }
    if (session.isExposed) {
      out.writeln(
          '  You are out in the ${session.weatherNow!.name.toLowerCase()} '
          'with nothing over you. Find a roof, or "shelter".');
    } else if (session.isSheltering) {
      out.writeln('  You are under a shelter of your own making.');
    }
  }

  String _ordinal(int n) => switch (n) {
        1 => '1st',
        2 => '2nd',
        3 => '3rd',
        _ => '${n}th',
      };

  /// Tells the player what the world did while time passed.
  void _announceEvents(WorldSession session) {
    for (final event in session.drainEvents()) {
      switch (event) {
        case WeatherRolled(:final weather):
          final storm = weather.hasStorm
              ? ', breaking at ${weather.stormStartHour}:00 for '
                  '${weather.stormHours} hours'
              : '';
          out.writeln('\n  [Weather, ${_regionName(weather.regionId)}, '
              '${weather.season.name} ${session.campaign.weather.calendar.dateOf(weather.day).dayOfSeason}: '
              'd100(${weather.die}) — ${weather.type.name}$storm]');
          if (session.remarkOn(weather.type) case final r?) {
            _says(r.who.name, r.line);
          }
        case NewDay():
          out.writeln('\n  *** $event ***');
        case DawnOrDusk(:final echo):
          if (echo != null) out.writeln('\n${_wrapped(echo)}');
        case StormBroke(:final weather, :final sheltered):
          out.writeln('\n  *** The ${weather.type.name.toLowerCase()} '
              'breaks. ***');
          out.writeln(_wrapped(
              session.look().region?.weatherStates[weather.type.id] ??
                  weather.type.text,
              indent: '  '));
          if (!sheltered) {
            out.writeln(_wrapped(
                'You are out in the open. Find a roof, or make shelter here '
                '("shelter"). Every hour out in it will cost you.',
                indent: '  '));
          }
        case Exposure(:final actor, :final save, :final damage, :final hpLost):
          final v = session.vitalsOf(actor.id);
          out.writeln('  ${actor.name}: ${save.label} '
              'd20(${save.dieRoll}) ${_signed(save.modifier)} = ${save.total} '
              'vs DC ${save.dc} — ${save.degree.displayName}; $damage; '
              'loses $hpLost HP (${v.hp}/${v.maxHp})');
        case StormPassed(:final weather, :final xp, :final ownShelter):
          out.writeln('\n  *** The ${weather.type.name.toLowerCase()} blows '
              'over. ${xp == 0 ? 'You stood out in it, and you are still '
                  'standing.' : ownShelter ? 'You rode it out under a shelter '
                  'you made yourselves.' : 'You waited it out under a roof.'} ***');
        case GrewTired(:final spent):
          out.writeln(spent
              ? '\n  *** The party is spent. No more long roads until you '
                  'rest. ***'
              : '\n  *** The party is Fatigued: -1 to AC and saves until '
                  'you rest. ***');
      }
    }
  }

  /// `r_001_millhaven_valley` as "the Millhaven Valley".
  String _regionName(String id) {
    final words = id
        .split('_')
        .skip(2)
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}');
    return 'the ${words.join(' ')}';
  }

  /// What the party is worth, against what is expected of it, and what that
  /// brings down on them.
  void _renderWealth(WorldSession session) {
    final worth = session.wealth;
    final pack = session.inventory;
    final standing = session.notoriety;
    out
      ..writeln('\nThe party is worth ${formatCoin(worth.total)}.')
      ..writeln(
          '  ${'Coin'.padRight(26)} ${formatCoin(worth.coin).padLeft(14)}')
      ..writeln('  ${'Gear, at what it costs'.padRight(26)} '
          '${formatCoin(worth.gear).padLeft(14)}');
    var onPeople = 0;
    for (final actor in session.actors) {
      final value = pack.valueOn(actor.id);
      onPeople += value;
      if (value == 0) continue;
      final loadout = pack.loadoutFor(actor.id);
      final names = [loadout.weapon?.name, loadout.armor?.name].nonNulls;
      out.writeln('    ${actor.name.padRight(24)} '
          '${formatCoin(value).padLeft(14)}  (${names.join(', ')})');
    }
    if (worth.gear - onPeople > 0) {
      out.writeln('    ${'In the pack'.padRight(24)} '
          '${formatCoin(worth.gear - onPeople).padLeft(14)}');
    }
    final size = session.actors.length;
    out
      ..writeln('\n${_wrapped('A party of $size level ${standing.partyLevel} '
          '${size == 1 ? 'character' : 'characters'} is expected to be worth '
          '${formatCoin(worth.expected)}. You are at '
          '${worth.percentOfExpected}% of that.', indent: '  ')}')
      ..writeln('\nNotoriety: ${standing.tier.name}')
      ..writeln(_wrapped(standing.tier.description, indent: '  '));

    final level = standing.hunterLevel;
    final threat = standing.tier.threat;
    if (standing.tier.isHunted && level != null && threat != null) {
      out.writeln(_wrapped(
          'Each step there is a ${standing.tier.chance}% chance something '
          'finds you. It would come at level $level, which is a threat of '
          '"${threat.name}" for ${size == 1 ? 'one character' : '$size'}.',
          indent: '  '));
    }
    if (session.huntsSurvived > 0) {
      out.writeln('  Hunters beaten: ${session.huntsSurvived}');
    }
    out.writeln('');
    for (final tier in session.campaign.hunts.tiers) {
      final here = tier.name == standing.tier.name ? '>' : ' ';
      final brings = tier.isHunted
          ? '${tier.threat!.name} threat, ${tier.chance}% a step'
          : 'nothing comes';
      out.writeln('  $here ${tier.name.padRight(12)} '
          '${'from ${tier.fromPercent}%'.padRight(10)} $brings');
    }
  }

  /// Everything the party has come away with, and where from.
  void _renderLedger(WorldSession session) {
    final ledger = session.ledger;
    if (ledger.isEmpty) {
      out.writeln('The party has found nothing yet.');
      return;
    }
    final things = switch (ledger.itemCount) {
      0 => 'nothing else',
      1 => 'one thing worth ${formatCoin(ledger.itemCopper)}',
      final n => '$n things worth ${formatCoin(ledger.itemCopper)}',
    };
    out.writeln('\nFound so far: ${formatCoin(ledger.totalCopper)} — '
        '${formatCoin(ledger.coinCopper)} in coin, and $things.\n');
    for (final entry in ledger.entries) {
      final what = entry.kind == LootKind.coin
          ? 'coin'
          : session.campaign.gear.byId(entry.itemId ?? '')?.name ??
              entry.itemId ??
              'something';
      out.writeln('  ${entry.source.padRight(30)} '
          '${what.padRight(28)} ${formatCoin(entry.copper).padLeft(12)}');
    }
  }

  /// Says so when the party's wealth moves them up, or down, the ladder.
  void _announceNotoriety(WorldSession session, NotorietyTier before) {
    final now = session.notoriety.tier;
    if (now.name == before.name) return;
    final rising = now.fromPercent > before.fromPercent;
    out.writeln('\n  *** ${rising ? 'Word spreads' : 'Word dies down'}: you '
        'are ${now.name}. ***');
    out.writeln(_wrapped(now.description, indent: '  '));
  }

  void _announceArcs(WorldSession session) {
    final settled = session.settleArcs();
    for (final arc in settled.completed) {
      out.writeln('\n  *** ${arc.isSide ? 'Side quest' : 'Quest'} complete: '
          '${arc.name}${_rewardNote(arc)} ***');
    }
    if (settled.worldState.isEmpty) return;
    out.writeln('\n  *** The world shifts: '
        '${settled.worldState.join(', ')} ***');
  }

  String _rewardNote(CampaignArc arc) {
    final reward = arc.reward;
    if (reward == null || reward.isEmpty) return '';
    return ' (${[
      if (reward.copper > 0) formatCoin(reward.copper),
      if (reward.xp > 0) '${reward.xp} XP',
    ].join(', ')})';
  }

  /// One line on where a character stands between level 1 and level 20.
  String _xpLine(XpProgress p) {
    if (p.isMax) {
      return 'Level $maxLevel — the top of the track, '
          '${groupThousands(p.total)} XP in all';
    }
    final ready = p.earnedLevel > p.level
        ? ' — level ${p.earnedLevel} earned; level up in Pathbuilder'
        : '';
    return 'XP ${groupThousands(p.xp)}/${groupThousands(xpToLevel)} toward '
        'level ${p.level + 1} · ${groupThousands(p.total)} of '
        '${groupThousands(XpProgress.fullTrack)} to level $maxLevel$ready';
  }

  /// Every character's place on the track from level 1 to level 20.
  void _renderExperience(WorldSession session) {
    out.writeln('\nExperience: ${groupThousands(xpToLevel)} XP a level, '
        '${groupThousands(XpProgress.fullTrack)} from level 1 to level '
        '$maxLevel.');
    final numbers = [for (var l = 1; l <= maxLevel; l++) '$l'.padLeft(3)];
    for (final actor in session.actors) {
      if (session.isCompanion(actor.id)) {
        out.writeln('\n  ${actor.name} — level ${actor.character.level}, '
            'keeping pace with the party');
        continue;
      }
      final p = session.experience.progressOf(actor.id);
      // Filled to the sheet's level; a + for levels earned but not yet taken
      // in Pathbuilder; a dot for the road still ahead.
      final marks = [
        for (var l = 1; l <= maxLevel; l++)
          (l <= p.level
                  ? '■'
                  : l <= p.earnedLevel
                      ? '+'
                      : '·')
              .padLeft(3),
      ];
      out
        ..writeln('\n  ${actor.name} — level ${p.level}')
        ..writeln('  ${numbers.join()}')
        ..writeln('  ${marks.join()}')
        ..writeln(_wrapped(_xpLine(p), indent: '    '));
    }
    out.writeln('\n  (■ reached, + earned and waiting on Pathbuilder, '
        '· still to come)');
  }

  /// Says what XP the last thing earned, and says so loudly for anyone it has
  /// taken to their next level — which happens in Pathbuilder, not here.
  void _announceExperience(WorldSession session, Map<String, int> before) {
    final xp = session.experience;
    final gained = {
      for (final a in session.actors) a.id: xp.xpOf(a.id) - (before[a.id] ?? 0),
    };
    final earned = gained.values.fold(0, (m, g) => g > m ? g : m);
    if (earned <= 0) return;
    out.writeln('\n  [+$earned XP each]');
    for (final actor in session.actors) {
      // A companion has no Pathbuilder sheet to level: they keep pace with
      // the rest of the party on their own.
      if (session.isCompanion(actor.id)) continue;
      final was = before[actor.id] ?? 0;
      if (was < xpToLevel && xp.readyToLevel(actor.id)) {
        out.writeln('\n  *** ${actor.name} has ${xp.xpOf(actor.id)} XP — '
            'enough for level ${actor.character.level + 1}. Level up in '
            'Pathbuilder and re-import; the thousand comes off when the new '
            'sheet arrives. ***');
      }
    }
  }

  void _renderArcs(WorldSession session) {
    final active = session.activeArcs();
    if (active.isEmpty) {
      out.writeln('Nothing is underway.');
      return;
    }
    for (final arc in active) {
      final progress = arc.progress(session.flags);
      out.writeln('\n${arc.name}${arc.isSide ? '  (side quest)' : ''} '
          '(${progress.done}/${progress.total})${_rewardNote(arc)}');
      for (final objective in arc.objectives) {
        final done = session.flags.contains(objective.condition);
        out.writeln('  [${done ? 'x' : ' '}] ${objective.task}');
      }
    }
  }

  void _renderRoom(WorldSession session,
      {bool full = false, bool showWeather = false}) {
    final view = session.look();
    out.writeln('\n## ${view.room.title}');
    final now = session.weatherNow;
    final date = session.date;
    out.writeln('   ${[
      if (view.town != null) view.town!.name,
      '${date.season.name} ${date.dayOfSeason}',
      session.clock + (view.isNight ? ' (night)' : ''),
      // A roof here is a place to wait out a storm, which is worth saying;
      // not that the party is under it, since a farm is mostly its yard.
      if (now != null) now.name,
      if (now != null && view.room.shelter) 'shelter here',
    ].join(' · ')}');
    out.writeln();
    if (full) out.writeln(_wrapped(view.room.description));
    // Weather is an arrival note, not a per-step refrain: repeating the same
    // fog line every time the party takes a step turns atmosphere into noise.
    if (showWeather && view.weather != null && !view.room.shelter) {
      out.writeln('\n${_wrapped(view.weather!)}');
    }

    for (final npc in view.npcs) {
      out.writeln('\n${_wrapped(npc.appearance)}');
    }
    for (final greeting in session.greetingsHere()) {
      _says(greeting.npc.name, greeting.line);
    }
    final shop = session.shopHere;
    if (shop != null) {
      out.writeln('\n  (${shop.name} — "list" to see what is for sale)');
    }

    for (final item in view.items) {
      if (item.inRoomText != null) {
        out.writeln('\n${_wrapped(item.inRoomText!)}');
      }
    }

    for (final encounter in view.encounters) {
      out.writeln('\n${_wrapped(session.describeEncounter(encounter))}');
      out.writeln(encounter.ambush
          ? '\n  (${encounter.name} — between you and the way on)'
          : '\n  (${encounter.name} — type "fight" to begin)');
    }

    out.writeln('\nExits: ${view.openDirections.join(', ')}'
        '${view.barredDirections.isEmpty ? '' : '  (barred: '
            '${view.barredDirections.map((b) => b.direction).join(', ')})'}');
  }

  /// Wraps [text] to [width], each line starting with [indent].
  static String wrap(String text, {int width = 70, String indent = ''}) {
    final out = <String>[];
    for (final paragraph in text.split('\n')) {
      if (paragraph.trim().isEmpty) {
        out.add('');
        continue;
      }
      final line = StringBuffer(indent);
      for (final word in paragraph.split(' ')) {
        if (line.length > indent.length &&
            line.length + word.length + 1 > width) {
          out.add(line.toString());
          line
            ..clear()
            ..write(indent);
        }
        if (line.length > indent.length) line.write(' ');
        line.write(word);
      }
      if (line.toString().trim().isNotEmpty) out.add(line.toString());
    }
    return out.join('\n');
  }

  /// Takes or destroys something in the room.
  bool _takeOrDestroy(WorldSession session, String what,
      {required bool destroy}) {
    if (what.isEmpty) {
      out.writeln(destroy ? 'Destroy what?' : 'Take what?');
      return true;
    }
    try {
      final result = destroy ? session.destroy(what) : session.take(what);
      if (result.spoken case final spoken?) _says(spoken.who.name, spoken.line);
      out.writeln('\n${_wrapped(result.said)}');
      for (final flag in result.flagsSet) {
        out.writeln('\n  [$flag]');
      }
      _announceArcs(session);
    } on InvalidMoveException catch (e) {
      out.writeln(_wrapped(e.message));
    }
    return true;
  }

  /// Runs a fight to its end.
  ///
  /// A fight is its own mode with its own verbs, so it gets its own loop rather
  /// than being folded into the walking one; a player in initiative should not
  /// be offered directions to stroll in.
  Future<bool> _fight(
    WorldSession session,
    Future<String?> Function({String prompt}) nextCommand, {
    String? encounterId,
  }) async {
    final EncounterSession fight;
    try {
      fight = session.beginEncounter(encounterId: encounterId);
    } on InvalidMoveException catch (e) {
      out.writeln(_wrapped(e.message));
      return true;
    }
    _current = fight;
    try {
      return await _fightOut(session, nextCommand, fight);
    } finally {
      _current = null;
    }
  }

  Future<bool> _fightOut(
    WorldSession session,
    Future<String?> Function({String prompt}) nextCommand,
    EncounterSession fight,
  ) async {
    out
      ..writeln('\n${'=' * 70}')
      ..writeln(fight.encounter.name.toUpperCase())
      ..writeln('=' * 70)
      ..writeln('\nInitiative (d20 + Perception):');
    for (final roll in fight.initiativeRolls) {
      out.writeln('  ${roll.combatant.isEnemy ? ' ' : '*'} '
          '${roll.combatant.name.padRight(26)} '
          'd20(${roll.die}) ${_signed(roll.modifier)} = ${roll.total}');
    }
    if (fight.scaling case final s? when s.changed) {
      out.writeln('\n${_wrapped(_scalingNote(s), indent: '  ')}');
    }
    if (fight.rangedPenalty > 0) {
      out.writeln('\n  ${session.weatherNow?.name}: -${fight.rangedPenalty} '
          'to any strike across open ground.');
    }
    if (session.isFatigued) {
      out.writeln('  The party is Fatigued: -1 AC.');
    }

    final script = FightScript(fight);
    if (script.setting.isNotEmpty) {
      out.writeln('\n${_wrapped(script.setting)}');
    }
    _speak(script.opening());

    if (fight.openingStrikes.isNotEmpty) {
      out.writeln('\nBefore anyone in the party can move:');
      _narrate(fight.openingStrikes, script);
    }
    _renderCombatants(fight);

    while (!fight.isOver) {
      if (!fight.isPartyTurn) {
        _narrate(fight.endTurn(), script);
        continue;
      }

      final ambiance = script.ambianceFor(fight.round);
      if (ambiance != null) out.writeln('\n${_wrapped(ambiance.text)}');
      out.writeln('\n-- ${fight.current.name}, round ${fight.round}, '
          '${fight.actionsLeft} action(s) --');
      final targets = fight.targetsInReach();
      if (targets.isEmpty) {
        out.writeln('   Nothing in reach. Close the distance.');
      }
      final menu = _fightMenu(session, fight, targets);
      _offer([for (final m in menu) m.entry], 'Flee');

      final got = await _read('fight> ', menu.length);
      if (got == null) {
        out.writeln('\n(script exhausted mid-fight)');
        return false;
      }
      final pick = got.pick;
      var line = switch (pick) {
        null => got.line,
        0 => 'flee',
        _ => menu[pick - 1].command,
      };
      if (line.startsWith(_aimOrder)) {
        final aimed = await _aim(fight, line.substring(_aimOrder.length));
        if (aimed == null) {
          out.writeln('\n(script exhausted mid-fight)');
          return false;
        }
        line = aimed;
      }
      if (line.isEmpty) continue;

      final words = line.split(RegExp(r'\s+'));
      final verb = words.first.toLowerCase();
      final rest = words.skip(1).join(' ');

      try {
        switch (verb) {
          case 'strike':
          case 'hit':
            final target = rest.isEmpty
                ? (targets.isEmpty ? null : targets.first.id)
                : rest;
            if (target == null) {
              out.writeln('Nothing in reach to strike.');
              break;
            }
            final result = fight.strike(target);
            _narrate([result], script);
          case 'close':
          case 'stride':
            final moved = fight.stride();
            out.writeln('\n  ${fight.current.name} closes to '
                '${moved.zone}.');
          case 'back':
          case 'withdraw':
            final moved = fight.stride(closer: false);
            out.writeln('\n  ${fight.current.name} falls back to '
                '${moved.zone}.');
          case 'end':
          case 'done':
            _narrate(fight.endTurn(), script);
          case 'flee':
            fight.flee();
          case 'cast':
            _cast(fight, rest, script);
          case 'use':
          case 'drink':
            final args = _useArgs(rest);
            if (args == null) {
              out.writeln('Use what?');
              break;
            }
            _renderUse(fight.use(args.what, targetId: args.who));
          case 'spells':
            // Where each comes from, so a cantrip known twice (from two
            // classes) reads as two ways to cast it, not a mistake.
            final options = fight.castOptions();
            out.writeln(options.isEmpty
                ? '  ${fight.current.name} has no spells the engine can cast.'
                : '  ${[
                    for (final o in options) '$o, ${o.source}',
                  ].join('\n  ')}');
          case 'status':
            _renderCombatants(fight);
          case 'quit':
          case 'q':
            return false;
          // A spell's name on its own casts it: "ignition" is as good as
          // "cast ignition".
          case _
              when fight.castOptions().any((o) =>
                  line.toLowerCase().startsWith(o.spell.name.toLowerCase())):
            _cast(fight, line, script);
          default:
            out.writeln('In a fight you can: strike <target>, cast <spell> '
                '[target], spells, use <item> [on <who>], close, back, end, '
                'status, flee.');
        }
      } on InvalidActionException catch (e) {
        out.writeln('  ${e.message}');
      }

      if (fight.actionsLeft == 0 && !fight.isOver && fight.isPartyTurn) {
        _narrate(fight.endTurn(), script);
      }
    }

    out.writeln('\n${'=' * 70}');
    _speak(script.closing());
    switch (fight.outcome!) {
      case EncounterOutcome.victory:
        out.writeln('\nThe fight is over. You are still standing.');
        final flags = session.concludeEncounter(fight);
        _renderSpoils(fight);
        if (fight.loot.isNotEmpty) {
          out.writeln('\nAmong what is left:');
          for (final item in fight.loot) {
            out.writeln('\n  ${item.name} '
                '(level ${item.level} ${item.rarity.name} ${item.type})');
            out.writeln(_wrapped(item.description, indent: '    '));
          }
        }
        // Which return of a fight was won is the engine's bookkeeping, not
        // news: the flags worth showing are what the win changed.
        for (final flag in flags) {
          if (_waveFlag.hasMatch(flag)) continue;
          out.writeln('\n  [$flag]');
        }
        _announceArcs(session);
      case EncounterOutcome.defeat:
        out.writeln('\nThe party goes down. Valorheim does not stop for it.');
        final before = session.inventory.coin;
        session.concludeEncounter(fight);
        out.writeln('\n  You come to an hour later, where you fell, everyone '
            'at 1 HP. Rest, or have your wounds treated, before the next one.');
        final taken = before - session.inventory.coin;
        if (taken > 0) {
          out.writeln('\n  ${fight.enemies.first.name} goes through your '
              'packs while you lie there, and takes ${formatCoin(taken)}.');
        }
      case EncounterOutcome.fled:
        out.writeln('\nYou break off and go.');
        session.concludeEncounter(fight);
    }
    return true;
  }

  /// The orders open to whoever's turn it is: strike what is in reach, cast
  /// what they have the actions and the slots for, drink or hand over what
  /// the pack holds, move, or end the turn. Fleeing is 0.
  List<({_Entry entry, String command})> _fightMenu(
    WorldSession session,
    EncounterSession fight,
    List<Combatant> targets,
  ) {
    final me = fight.current;
    final left = fight.actionsLeft;
    final named = <String>{};
    return [
      for (final t in targets)
        (
          entry: (
            text: 'Strike ${_called(fight, t)}  (${t.hp}/${t.maxHp} HP)',
            chip: 'Strike ${_called(fight, t)}',
          ),
          command: 'strike ${t.id}',
        ),
      if (fight.canClose)
        (entry: (text: 'Close in', chip: 'Close in'), command: 'close'),
      // Once each by name, as the first way of casting it that works now:
      // a cantrip known from two classes is one spell to the player.
      for (final o in fight.castOptions())
        if (fight.aimsFor(o) case final aims
            when aims.isNotEmpty && named.add(o.spell.name))
          aims.length == 1
              ? _castEntry(fight, o, aims.single.caught)
              : _aimEntry(o),
      for (final item in session.inventory.carried)
        if (item.use case final use? when use.actions <= left) ...[
          if (me.hp < me.maxHp)
            (
              entry: (
                text: 'Drink ${_packName(session, item)}  '
                    '(${_actions(use.actions)}; you are at '
                    '${me.hp}/${me.maxHp} HP)',
                chip: 'Drink ${item.name}',
              ),
              command: 'use ${item.id}',
            ),
          for (final ally in fight.party)
            if (ally.id != me.id &&
                ally.zoneIndex == me.zoneIndex &&
                ally.hp < ally.maxHp)
              (
                entry: (
                  text: 'Give ${item.name} to ${ally.name}  '
                      '(${ally.isDown ? 'down' : '${ally.hp}/${ally.maxHp} HP'})',
                  chip: 'Give ${item.name} to ${ally.name.split(' ').first}',
                ),
                command: 'use ${item.id} on ${ally.id}',
              ),
        ],
      if (fight.canFallBack)
        (entry: (text: 'Fall back', chip: 'Fall back'), command: 'back'),
      (entry: (text: 'End turn', chip: 'End turn'), command: 'end'),
    ];
  }

  /// A spell as a fight offers it: at whom, what it costs, and, for a burst,
  /// everyone it would catch, the party included.
  ({_Entry entry, String command}) _castEntry(
    EncounterSession fight,
    CastOption o,
    List<Combatant> caught,
  ) {
    final cost = _cost(o);
    if (o.spell.heals) {
      final target = caught.single;
      return (
        entry: (
          text: 'Cast ${o.spell.name} on ${_called(fight, target)}  ($cost; '
              '${target.isDown ? 'down' : '${target.hp}/${target.maxHp} HP'})',
          chip: 'Cast ${o.spell.name}',
        ),
        command: 'cast ${o.spell.name} ${target.id}',
      );
    }
    if (!o.spell.area) {
      final target = caught.single;
      return (
        entry: (
          text: 'Cast ${o.spell.name} at ${_called(fight, target)}  ($cost)',
          chip: 'Cast ${o.spell.name}',
        ),
        command: 'cast ${o.spell.name} ${target.id}',
      );
    }
    final ours = caught.any((c) => !c.isEnemy);
    return (
      entry: (
        text: 'Cast ${o.spell.name}  ($cost): catches '
            '${_catches(fight, caught)}',
        chip: 'Cast ${o.spell.name}${ours ? ' (hits you too)' : ''}',
      ),
      command:
          'cast ${o.spell.name} ${caught.firstWhere((c) => c.isEnemy, orElse: () => caught.first).id}',
    );
  }

  /// A spell with more than one way to aim it: picking it asks which.
  ({_Entry entry, String command}) _aimEntry(CastOption o) => (
        entry: (
          text: 'Cast ${o.spell.name}  (${_cost(o)}): choose '
              '${o.spell.heals ? 'who' : o.spell.area ? 'where' : 'a target'}',
          chip: 'Cast ${o.spell.name}…',
        ),
        command: '$_aimOrder${o.spell.name}',
      );

  /// The flag recording that one return of a fight was won.
  static final _waveFlag = RegExp(r'^won_.+_wave_\d+$');

  /// Marks a fight order that still needs a target picked.
  static const _aimOrder = ':aim ';

  /// Where to aim [spellName]: each enemy in range, or for a burst each
  /// place it could land and everyone standing there. The order to give,
  /// empty to go back to the others, or null when the input ran out.
  Future<String?> _aim(EncounterSession fight, String spellName) async {
    final option = fight
        .castOptions()
        .where((o) => o.spell.name == spellName && fight.aimsFor(o).isNotEmpty)
        .firstOrNull;
    if (option == null) return '';
    final aims = fight.aimsFor(option);
    final area = option.spell.area;
    out.writeln('\n${option.spell.name}: '
        '${option.spell.heals ? 'on whom?' : area ? 'where?' : 'at whom?'}');
    _offer([
      for (final (:target, :caught) in aims)
        option.spell.heals
            ? (
                text: '${_called(fight, target)}  ('
                    '${target.isDown ? 'down' : '${target.hp}/${target.maxHp} HP'})',
                chip: _called(fight, target),
              )
            : area
                ? (
                    text: 'At ${_called(fight, target)}, '
                        '${fight.zones[target.zoneIndex]}: catches '
                        '${_catches(fight, caught)}',
                    chip: 'At ${_called(fight, target)}'
                        '${caught.any((c) => !c.isEnemy) ? ' (hits you too)' : ''}',
                  )
                : (
                    text: '${_called(fight, target)}  (${target.hp}/'
                        '${target.maxHp} HP, ${fight.zones[target.zoneIndex]})',
                    chip: _called(fight, target),
                  ),
    ], 'Back to the fight');
    final got = await _read('aim> ', aims.length);
    if (got == null) return null;
    return switch (got.pick) {
      null => got.line,
      0 => '',
      final pick => 'cast ${option.spell.name} ${aims[pick - 1].target.id}',
    };
  }

  /// "Hollow Thrall 2 and Korash Blackearth — your own side too".
  String _catches(EncounterSession fight, List<Combatant> caught) {
    final names = [for (final c in caught) _called(fight, c)];
    final list = names.length == 1
        ? names.single
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    return caught.any((c) => !c.isEnemy) ? '$list — your own side too' : list;
  }

  String _cost(CastOption o) => '${_actions(o.spell.actions)}, '
      '${o.cost == CastCost.cantrip ? 'cantrip' : '${o.left} left'}';

  String _actions(int n) => n == 1 ? '1 action' : '$n actions';

  /// A combatant as the fight under way calls them.
  String _nameOf(Combatant c) {
    final fight = _current;
    return fight == null ? c.name : _called(fight, c);
  }

  /// A combatant's name, numbered when there is more than one of them.
  String _called(EncounterSession fight, Combatant c) {
    final alike = fight.combatants.where((o) => o.name == c.name).toList();
    if (alike.length < 2) return c.name;
    final number = RegExp(r'(\d+)$').firstMatch(c.id)?.group(1) ??
        '${alike.indexOf(c) + 1}';
    return '${c.name} $number';
  }

  /// "(Written for four. Against your party of one, 1 of the 2 Hollow
  /// Thralls comes, and weakened.)"
  String _scalingNote(PartyScaling s) {
    const sizes = ['none', 'one', 'two', 'three'];
    final party =
        'your party of ${s.partySize < sizes.length ? sizes[s.partySize] : s.partySize}';
    final names = {for (final c in s.written) c.name};
    final what = names.length == 1
        ? '${names.single}${s.written.length == 1 ? '' : 's'}'
        : 'foes';
    final thinned = s.fielded.length < s.written.length;
    final single = s.fielded.length == 1;
    final comes = thinned
        ? '${s.fielded.length} of the ${s.written.length} $what '
            '${single ? 'comes' : 'come'}'
        : single
            ? 'it comes'
            : 'they come';
    return '(Written for four. Against $party, $comes'
        '${s.weakened ? '${thinned ? ', and' : ''} weakened' : ''}.)';
  }

  /// "hearth-water", or "hearth-water on sela": what to use, and on whom.
  ({String what, String? who})? _useArgs(String rest) {
    final text = rest.trim();
    if (text.isEmpty) return null;
    final on = text.toLowerCase().lastIndexOf(' on ');
    if (on < 0) return (what: text, who: null);
    return (
      what: text.substring(0, on).trim(),
      who: text.substring(on + 4).trim()
    );
  }

  /// What using something did, the dice included.
  void _renderUse(UseResult result) {
    final item = result.item.name;
    final who = result.onSelf
        ? '${result.user} drinks $item'
        : '${result.user} gets $item into ${result.target}';
    out.writeln('\n  $who: ${result.roll}, +${result.healed} HP '
        '(${result.hp}/${result.maxHp}).');
    if (result.revived) {
      out.writeln('  ${result.target} is back on their feet.');
    }
  }

  /// Casts a spell: "cast fireball", or "cast needle darts c_hollow_thrall_1".
  void _cast(EncounterSession fight, String rest, FightScript script) {
    if (rest.isEmpty) {
      out.writeln('Cast what? ("spells" lists them.)');
      return;
    }
    final words = rest.split(RegExp(r'\s+'));
    String? target;
    if (words.length > 1 && fight.combatantById(words.last) != null) {
      target = words.removeLast();
    }
    final result = fight.cast(words.join(' '), targetId: target);
    final o = result.option;
    final cost = switch (o.cost) {
      CastCost.cantrip => 'cantrip',
      CastCost.prepared => 'prepared, ${o.left - 1} left',
      CastCost.slot => 'rank ${o.rank} slot, ${o.left - 1} left',
      CastCost.focus => 'focus point, ${o.left - 1} left',
    };
    out.writeln('\n  ${result.caster.name} casts ${o.spell.name} '
        '(rank ${o.rank}, $cost)'
        '${result.damageRoll == null ? '' : ': ${result.damageRoll}'}');
    for (final m in result.mended) {
      out.writeln('    ${_nameOf(m.target)}: heals ${m.roll}, +${m.healed} HP '
          '(${m.target.hp}/${m.target.maxHp})'
          '${m.revived ? '. ${_nameOf(m.target)} is back on their feet.' : '.'}');
    }
    for (final hit in result.hits) {
      final c = hit.check;
      final against = o.spell.defense == SpellDefense.ac
          ? 'vs AC ${c.dc}'
          : 'vs DC ${c.dc}';
      final natural = c.wasShiftedByNatural ? ', natural ${c.dieRoll}' : '';
      out.writeln('    ${_nameOf(hit.target)}: ${c.label} d20(${c.dieRoll}) '
          '${_signed(c.modifier)} = ${c.total} $against$natural — '
          '${c.degree.displayName}');
      final dice = hit.damageRoll;
      out.writeln('      ${dice == null ? '' : 'damage $dice; '}'
          'takes ${hit.damage}.${hit.dropped ? ' ${_nameOf(hit.target)} goes down.' : ''}');
    }
    _speak(script.afterSpell(result));
  }

  /// What each character can cast, how many times more today, and anything
  /// on their sheet the spell table has no numbers for yet.
  void _renderSpells(WorldSession session, String who) {
    try {
      final actors = who.isEmpty ? session.actors : [session.actorFor(who)];
      for (final actor in actors) {
        final options = session.castOptions(actor.id);
        out.writeln('\n${actor.name}:');
        if (options.isEmpty) out.writeln('  nothing the engine can cast yet');
        for (final o in options) {
          final uses = o.cost == CastCost.cantrip
              ? 'at will'
              : '${o.left} left (${o.cost.name})';
          final how = o.spell.heals
              ? 'heals'
              : o.spell.defense == SpellDefense.ac
                  ? 'spell attack ${_signed(o.attackBonus)}'
                  : 'basic ${o.spell.defense.name}, DC ${o.dc}';
          out.writeln('  ${o.spell.name.padRight(16)} ${o.source.padRight(12)} '
              'rank ${o.rank}  ${o.spell.damageAt(o.rank)}  $how  $uses');
        }
        final missing = session.spellsWithoutNumbers(actor.id);
        if (missing.isNotEmpty) {
          out.writeln(_wrapped(
              'Not in the spell table yet: ${missing.join(', ')}.',
              indent: '  '));
        }
      }
    } on InvalidMoveException catch (e) {
      out.writeln(e.message);
    }
  }

  /// Each strike with its dice, and whatever is said as the fight turns.
  void _narrate(List<StrikeResult> log, FightScript script) {
    for (final result in log) {
      out.writeln('\n  ${_strikeLine(result)}');
      _speak(script.after([result]));
    }
  }

  /// Lines of a scene: speech attributed, narration told.
  void _speak(Iterable<ScriptLine> lines) {
    for (final line in lines) {
      out.writeln(line.isSpeech
          ? '\n${_wrapped('${line.speaker} says, "${line.text}"', indent: '  ')}'
          : '\n${_wrapped(line.text, indent: '  ')}');
    }
  }

  /// Somebody in the party, or across a counter, saying something.
  void _says(String who, String line) =>
      out.writeln('\n${_wrapped('$who says, "$line"', indent: '  ')}');

  /// A strike with its dice: the attack roll against AC, and on a hit the
  /// damage dice as they fell.
  String _strikeLine(StrikeResult r) {
    final check = r.outcome;
    final map = [
      if (r.penalty != 0) ', MAP ${r.penalty}',
      if (r.weatherPenalty != 0) ', weather ${r.weatherPenalty}',
    ].join();
    final natural =
        check.wasShiftedByNatural ? ', natural ${check.dieRoll}' : '';
    final verdict = switch (check.degree) {
      DegreeOfSuccess.criticalSuccess => 'CRITICAL HIT',
      DegreeOfSuccess.success => 'hit',
      _ => 'miss',
    };
    final head = '${_nameOf(r.attacker)} strikes ${_nameOf(r.target)}: '
        'd20(${check.dieRoll}) ${_signed(check.modifier)} = ${check.total} '
        'vs AC ${check.dc}$map$natural — $verdict';
    final damage = r.damageRoll;
    if (damage == null) return head;
    final dropped = r.targetDropped ? ' ${_nameOf(r.target)} goes down.' : '';
    return '$head\n    damage $damage.$dropped';
  }

  /// The rolls that settle what a won fight was worth.
  void _renderSpoils(EncounterSession fight) {
    if (fight.coinRoll case final coin?) {
      out.writeln('\n  Coin on the fallen: $coin gp');
    }
    if (fight.lootRolls.isNotEmpty) {
      out.writeln('  Searching them (d100, found at or under the chance):');
      for (final roll in fight.lootRolls) {
        out.writeln('    $roll');
      }
    }
    if (fight.xpAwards.isNotEmpty) {
      out.writeln('  XP, by level against the party\'s '
          '${fight.xpAwards.first.partyLevel}:');
      for (final award in fight.xpAwards) {
        out.writeln('    $award');
      }
    }
  }

  void _renderCombatants(EncounterSession fight) {
    out.writeln('');
    for (final c in fight.combatants) {
      final bar = c.isDown ? 'down' : '${c.hp}/${c.maxHp}';
      final where = fight.zones[c.zoneIndex];
      out.writeln(
          '  ${c.isEnemy ? ' ' : '*'} ${_called(fight, c).padRight(28)} '
          '${bar.padLeft(8)}  $where');
    }
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
