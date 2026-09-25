import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';

const _defaultCampaign = '../../campaigns/shattered_seals';
const _defaultCharacter = '../pf2e_core/test/fixtures/korash.json';

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

/// Walks a campaign world in the terminal.
///
///   dart run game_core:walk
///   dart run game_core:walk --seed=7 --commands="n,talk thorne,ask thorne about elara"
Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options.containsKey('help')) {
    stdout.writeln(_usage);
    return;
  }

  final campaignDir = options['campaign'] ?? _defaultCampaign;
  final seed = int.tryParse(options['seed'] ?? '') ??
      DateTime.now().millisecondsSinceEpoch;

  String? read(String name) {
    final file = File('$campaignDir/$name');
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  final world = read('world_config.json');
  final locations = read('locations.json');
  final npcs = read('npcs_and_dialogue.json');
  if (world == null || locations == null || npcs == null) {
    stderr.writeln('Not a campaign directory: $campaignDir');
    exitCode = 66;
    return;
  }

  final characterPaths = (options['characters'] ?? options['character'] ?? '')
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (characterPaths.isEmpty) characterPaths.add(_defaultCharacter);

  final Campaign campaign;
  final actors = <SessionActor>[];
  try {
    campaign = const CampaignLoader().load(
      id: 'campaign_i_shattered_seals',
      title: 'Campaign I: Shattered Seals',
      worldConfigJson: world,
      locationsJson: locations,
      npcsJson: npcs,
      gearJson: read('gear.json'),
      arcsJson: read('campaign_arcs.json'),
      bestiaryJson: read('bestiary.json'),
      itemsJson: read('world_items.json'),
    );
    for (final path in characterPaths) {
      final file = File(path);
      if (!file.existsSync()) {
        stderr.writeln('No such character: $path');
        exitCode = 66;
        return;
      }
      final imported =
          const PathbuilderImporter().importJson(file.readAsStringSync());
      actors.add(SessionActor(
        id: _actorIdFor(imported.character.name, actors),
        character: imported.character,
      ));
    }
  } on CampaignFormatException catch (e) {
    stderr.writeln('Could not read the campaign: ${e.message}');
    exitCode = 65;
    return;
  } on PathbuilderImportException catch (e) {
    stderr.writeln('Could not read a character: ${e.message}');
    exitCode = 65;
    return;
  }

  final session = WorldSession(
    campaign: campaign,
    actors: actors,
    roller: DiceRoller(seed),
    roomId: options['room'],
    hour: int.tryParse(options['hour'] ?? '') ?? 8,
    // Starting from a given state, for trying a later part of the campaign
    // without replaying everything up to it.
    flags: (options['flags'] ?? '')
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toSet(),
  );

  stdout
    ..writeln('=' * 70)
    ..writeln('MARCHING ORDER — ${campaign.title}')
    ..writeln('${campaign.world.metadata.name} · seed $seed')
    ..writeln('=' * 70)
    ..writeln()
    ..writeln(_wrap(campaign.world.metadata.backgroundLore));
  for (final actor in session.actors) {
    stdout.writeln('\n  ${actor.id.padRight(8)} $actor');
  }

  final scripted = (options['commands'] ?? '')
      .split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();
  var scriptIndex = 0;

  // One reader for both loops, so a scripted playthrough can walk into a
  // fight and keep giving orders without the script knowing which mode it is
  // in.
  String? nextCommand({String prompt = '> '}) {
    if (scriptIndex < scripted.length) {
      final line = scripted[scriptIndex++];
      stdout.writeln('\n$prompt$line');
      return line;
    }
    if (scripted.isNotEmpty) return null;
    stdout.write('\n$prompt');
    return stdin.readLineSync(encoding: utf8)?.trim();
  }

  _renderRoom(session, full: true, showWeather: true);

  while (true) {
    final line = nextCommand();
    if (line == null) {
      if (scripted.isNotEmpty) stdout.writeln('\n(script exhausted)');
      break;
    }
    if (line.isEmpty) continue;
    if (line == 'quit' || line == 'q') break;
    if (!_handle(session, line, nextCommand)) break;
  }

  stdout
    ..writeln('\n${'-' * 70}')
    ..writeln('Resume: ${jsonEncode(session.snapshot())}');
}

/// Returns false to end the session.
bool _handle(WorldSession session, String line,
    String? Function({String prompt}) nextCommand) {
  final words = line.split(RegExp(r'\s+'));
  final verb = words.first.toLowerCase();
  final rest = words.skip(1).join(' ');

  if (verb == 'quit' || verb == 'q') return false;

  if (_directions.contains(verb)) return _go(session, verb);
  if (verb == 'go' && rest.isNotEmpty) return _go(session, rest);

  switch (verb) {
    case 'look':
    case 'l':
      _renderRoom(session, full: true, showWeather: true);
      return true;

    case 'exits':
      final view = session.look();
      stdout.writeln('Exits: ${view.openDirections.join(', ')}');
      for (final barred in view.barredDirections) {
        stdout.writeln('  ${barred.direction}: '
            '${barred.reason ?? 'shut'}');
      }
      return true;

    case 'who':
      final npcs = session.look().npcs;
      if (npcs.isEmpty) {
        stdout.writeln('Nobody else is here.');
      } else {
        for (final npc in npcs) {
          final left = session.unraisedTopicsFor(npc);
          stdout.writeln('  ${npc.name}'
              '${left.isEmpty ? '' : '  (topics: ${left.join(', ')})'}');
        }
      }
      return true;

    case 'talk':
    case 'ask':
      return _talk(session, rest);

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
        stdout.writeln('There is no "$rest" here to examine.');
      } else {
        stdout.writeln('\n${_wrap(item.description)}');
      }
      return true;

    case 'fight':
    case 'attack':
      return _fight(session, nextCommand,
          encounterId: rest.isEmpty ? null : rest);

    case 'wait':
      final hours = int.tryParse(rest) ?? 1;
      session.advanceTime(hours);
      stdout.writeln('Time passes. It is now hour ${session.hour}'
          '${session.isNight ? ', and dark' : ''}.');
      final echo = session.ambianceEcho();
      if (echo != null) stdout.writeln('\n${_wrap(echo)}');
      return true;

    case 'quests':
    case 'arcs':
      _renderArcs(session);
      return true;

    case 'loot':
    case 'recovered':
      final found = session.recoveredGear;
      if (found.isEmpty) {
        stdout.writeln('You have taken nothing off anything yet.');
      } else {
        for (final item in found) {
          stdout.writeln('  ${item.name.padRight(30)} '
              'level ${item.level} ${item.rarity.name} ${item.type}');
          if (item.special != null) {
            stdout.writeln(_wrap(item.special!, indent: '    '));
          }
        }
      }
      return true;

    case 'flags':
      final flags = session.flags.toList()..sort();
      stdout.writeln(flags.isEmpty ? '(none)' : flags.join('\n'));
      return true;

    case 'help':
      stdout.writeln(_commands);
      return true;

    default:
      stdout.writeln('I do not know how to "$verb". Try "help".');
      return true;
  }
}

bool _go(WorldSession session, String direction) {
  try {
    final result = session.move(direction);
    _renderRoom(session, full: true, showWeather: result.changedRegion);
    if (result.changedRegion) {
      final echo = session.ambianceEcho();
      if (echo != null) stdout.writeln('\n${_wrap(echo)}');
    }
    _announceArcs(session);
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
  }
  return true;
}

/// Accepts "talk thorne", "ask thorne about elara", "talk thorne elara".
bool _talk(WorldSession session, String rest) {
  if (rest.isEmpty) {
    stdout.writeln('Talk to whom?');
    return true;
  }
  final words = rest.split(RegExp(r'\s+'));
  final who = words.first;
  var topic = words.skip(1).join(' ');
  if (topic.toLowerCase().startsWith('about ')) {
    topic = topic.substring(6);
  }

  try {
    final result = session.talk(who, topic: topic.isEmpty ? null : topic);
    stdout.writeln('\n${result.npc.name}:');
    stdout.writeln(_wrap('"${result.said}"', indent: '  '));

    if (result.isGreeting) {
      final left = session.unraisedTopicsFor(result.npc);
      if (left.isNotEmpty) {
        stdout.writeln('\n  (ask about: ${left.join(', ')})');
      }
    }
    for (final flag in result.flagsSet) {
      stdout.writeln('\n  [$flag]');
    }
    _announceArcs(session);
  } on InvalidMoveException catch (e) {
    stdout.writeln(e.message);
  }
  return true;
}

void _announceArcs(WorldSession session) {
  final changes = session.applyPendingWorldState();
  if (changes.isEmpty) return;
  stdout.writeln('\n  *** The world shifts: ${changes.join(', ')} ***');
}

void _renderArcs(WorldSession session) {
  final active = session.activeArcs();
  if (active.isEmpty) {
    stdout.writeln('Nothing is underway.');
    return;
  }
  for (final arc in active) {
    final progress = arc.progress(session.flags);
    stdout.writeln('\n${arc.name} (${progress.done}/${progress.total})');
    for (final objective in arc.objectives) {
      final done = session.flags.contains(objective.condition);
      stdout.writeln('  [${done ? 'x' : ' '}] ${objective.task}');
    }
  }
}

void _renderRoom(WorldSession session,
    {bool full = false, bool showWeather = false}) {
  final view = session.look();
  stdout.writeln('\n## ${view.room.title}');
  if (view.town != null) {
    stdout.writeln('   ${view.town!.name}'
        '${view.isNight ? ' · night' : ''}');
  }
  stdout.writeln();
  if (full) stdout.writeln(_wrap(view.room.description));
  // Weather is an arrival note, not a per-step refrain: repeating the same
  // fog line every time the party takes a step turns atmosphere into noise.
  if (showWeather && view.weather != null) {
    stdout.writeln('\n${_wrap(view.weather!)}');
  }

  for (final npc in view.npcs) {
    stdout.writeln('\n${_wrap(npc.appearance)}');
  }

  for (final item in view.items) {
    if (item.inRoomText != null) {
      stdout.writeln('\n${_wrap(item.inRoomText!)}');
    }
  }

  for (final encounter in view.encounters) {
    stdout.writeln('\n${_wrap(encounter.description)}');
    stdout.writeln('\n  (${encounter.name} — type "fight" to begin)');
  }

  stdout.writeln('\nExits: ${view.openDirections.join(', ')}'
      '${view.barredDirections.isEmpty ? '' : '  (barred: '
          '${view.barredDirections.map((b) => b.direction).join(', ')})'}');
}

String _actorIdFor(String name, List<SessionActor> existing) {
  final base = name.trim().split(RegExp(r'\s+')).first.toLowerCase();
  final taken = {for (final a in existing) a.id};
  if (!taken.contains(base)) return base;
  for (var n = 2;; n++) {
    if (!taken.contains('$base$n')) return '$base$n';
  }
}

String _wrap(String text, {int width = 70, String indent = ''}) {
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

Map<String, String> _parseArgs(List<String> args) {
  final out = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final body = arg.substring(2);
    final eq = body.indexOf('=');
    if (eq == -1) {
      out[body] = '';
    } else {
      out[body.substring(0, eq)] = body.substring(eq + 1);
    }
  }
  return out;
}

const _commands = '''
  north/south/east/west/up/down (or n/s/e/w/u/d)  walk
  look                                            describe the room again
  exits                                           list ways out, open and shut
  who                                             who is here, and their topics
  talk <name>                                     greet someone
  ask <name> about <topic>                        raise a topic
  quests                                          arc progress
  loot                                            what you have taken so far
  wait [hours]                                    let time pass
  quit                                            stop
''';

const _usage = '''
usage: walk [options]

  --campaign=DIR     Campaign directory (default: $_defaultCampaign)
  --characters=A,B   Pathbuilder exports (default: $_defaultCharacter)
  --seed=N           Dice seed; omit for a random one
  --room=ID          Start somewhere other than the first room
  --hour=N           Start at a given hour (default 8)
  --flags=a,b        Start with these flags already set
  --commands=a,b,c   Play a scripted sequence instead of reading stdin
  --help             Show this message

Commands:
$_commands''';

/// Takes or destroys something in the room.
bool _takeOrDestroy(WorldSession session, String what,
    {required bool destroy}) {
  if (what.isEmpty) {
    stdout.writeln(destroy ? 'Destroy what?' : 'Take what?');
    return true;
  }
  try {
    final result = destroy ? session.destroy(what) : session.take(what);
    stdout.writeln('\n${_wrap(result.said)}');
    for (final flag in result.flagsSet) {
      stdout.writeln('\n  [$flag]');
    }
    _announceArcs(session);
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
  }
  return true;
}

/// Runs a fight to its end.
///
/// A fight is its own mode with its own verbs, so it gets its own loop rather
/// than being folded into the walking one; a player in initiative should not
/// be offered directions to stroll in.
bool _fight(
  WorldSession session,
  String? Function({String prompt}) nextCommand, {
  String? encounterId,
}) {
  final EncounterSession fight;
  try {
    fight = session.beginEncounter(encounterId: encounterId);
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
    return true;
  }

  stdout
    ..writeln('\n${'=' * 70}')
    ..writeln(fight.encounter.name.toUpperCase())
    ..writeln('=' * 70);
  if (fight.encounter.description.isNotEmpty) {
    stdout.writeln('\n${_wrap(fight.encounter.description)}');
  }
  _renderCombatants(fight);

  while (!fight.isOver) {
    if (!fight.isPartyTurn) {
      _narrate(fight.endTurn());
      continue;
    }

    stdout.writeln('\n-- ${fight.current.name}, round ${fight.round}, '
        '${fight.actionsLeft} action(s) --');
    final targets = fight.targetsInReach();
    stdout.writeln(targets.isEmpty
        ? '   Nothing in reach. Close the distance.'
        : '   In reach: ${targets.map((t) => '${t.id} (${t.hp}/${t.maxHp})').join(', ')}');

    final line = nextCommand(prompt: 'fight> ');
    if (line == null) {
      stdout.writeln('\n(script exhausted mid-fight)');
      return false;
    }
    if (line.isEmpty) continue;

    final words = line.split(RegExp(r'\s+'));
    final verb = words.first.toLowerCase();
    final rest = words.skip(1).join(' ');

    try {
      switch (verb) {
        case 'strike':
        case 'hit':
          final target =
              rest.isEmpty ? (targets.isEmpty ? null : targets.first.id) : rest;
          if (target == null) {
            stdout.writeln('Nothing in reach to strike.');
            break;
          }
          final result = fight.strike(target);
          stdout.writeln('\n  ${_strikeLine(result)}');
        case 'close':
        case 'stride':
          final moved = fight.stride();
          stdout.writeln('\n  ${fight.current.name} closes to '
              '${moved.zone}.');
        case 'back':
        case 'withdraw':
          final moved = fight.stride(closer: false);
          stdout.writeln('\n  ${fight.current.name} falls back to '
              '${moved.zone}.');
        case 'end':
        case 'done':
          _narrate(fight.endTurn());
        case 'flee':
          fight.flee();
        case 'status':
          _renderCombatants(fight);
        case 'quit':
        case 'q':
          return false;
        default:
          stdout.writeln('In a fight you can: strike <target>, close, back, '
              'end, status, flee.');
      }
    } on InvalidActionException catch (e) {
      stdout.writeln('  ${e.message}');
    }

    if (fight.actionsLeft == 0 && !fight.isOver && fight.isPartyTurn) {
      _narrate(fight.endTurn());
    }
  }

  stdout.writeln('\n${'=' * 70}');
  switch (fight.outcome!) {
    case EncounterOutcome.victory:
      stdout.writeln('The fight is over. You are still standing.');
      final flags = session.concludeEncounter(fight);
      if (fight.loot.isNotEmpty) {
        stdout.writeln('\nAmong what is left:');
        for (final item in fight.loot) {
          stdout.writeln('\n  ${item.name} '
              '(level ${item.level} ${item.rarity.name} ${item.type})');
          stdout.writeln(_wrap(item.description, indent: '    '));
        }
      }
      for (final flag in flags) {
        stdout.writeln('\n  [$flag]');
      }
      _announceArcs(session);
    case EncounterOutcome.defeat:
      stdout.writeln('The party goes down. Valorheim does not stop for it.');
    case EncounterOutcome.fled:
      stdout.writeln('You break off and go.');
  }
  return true;
}

void _narrate(List<StrikeResult> log) {
  for (final result in log) {
    stdout.writeln('\n  ${_strikeLine(result)}');
  }
}

String _strikeLine(StrikeResult r) {
  final check = r.outcome;
  final penalty = r.penalty == 0 ? '' : ' (MAP ${r.penalty})';
  final roll = 'd20(${check.dieRoll}) ${check.modifier >= 0 ? '+' : ''}'
      '${check.modifier} = ${check.total} vs AC ${check.dc}$penalty';
  if (!r.isHit) return '${r.attacker.name} misses ${r.target.name} — $roll';
  final crit = r.isCritical ? ' critically' : '';
  final dropped = r.targetDropped ? ' ${r.target.name} goes down.' : '';
  return '${r.attacker.name}$crit hits ${r.target.name} for ${r.damage} — '
      '$roll.$dropped';
}

void _renderCombatants(EncounterSession fight) {
  stdout.writeln('');
  for (final c in fight.combatants) {
    final bar = c.isDown ? 'down' : '${c.hp}/${c.maxHp}';
    final where = fight.zones[c.zoneIndex];
    stdout.writeln('  ${c.isEnemy ? ' ' : '*'} ${c.id.padRight(22)} '
        '${bar.padLeft(8)}  $where');
  }
}
