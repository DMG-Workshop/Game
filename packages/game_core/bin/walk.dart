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
      conversationsJson: read('conversations.json'),
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

  if (_directions.contains(verb)) return _go(session, verb, nextCommand);
  if (verb == 'go' && rest.isNotEmpty) return _go(session, rest, nextCommand);

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
    case 'inventory':
    case 'inv':
    case 'i':
      _renderInventory(session);
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

bool _go(WorldSession session, String direction,
    String? Function({String prompt}) nextCommand) {
  final MoveResult result;
  try {
    result = session.move(direction);
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
    return true;
  }

  _renderRoom(session, full: true, showWeather: result.changedRegion);
  if (result.changedRegion) {
    final echo = session.ambianceEcho();
    if (echo != null) stdout.writeln('\n${_wrap(echo)}');
  }
  _announceArcs(session);

  // An ambush is not something to mention and move on from.
  final ambush = result.ambush;
  if (ambush != null) {
    return _fight(session, nextCommand, encounterId: ambush.id);
  }
  return true;
}

/// Accepts "talk thorne" for a conversation, and "ask thorne about elara" or
/// "talk thorne elara" for a single topic.
bool _talk(WorldSession session, String rest,
    String? Function({String prompt}) nextCommand) {
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

  if (topic.isEmpty) {
    try {
      final conversation = session.beginConversation(who);
      if (conversation != null) {
        return _converse(
            session, conversation.npc, conversation.talk, nextCommand);
      }
    } on InvalidMoveException catch (e) {
      stdout.writeln(e.message);
      return true;
    }
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

/// Runs a conversation to its end, or until the party walks away.
///
/// Its own loop for the same reason a fight has one: the verbs are different.
/// Everything said before walking away still counts.
bool _converse(
  WorldSession session,
  Npc npc,
  GameSession talk,
  String? Function({String prompt}) nextCommand,
) {
  final solo = session.actors.length == 1;
  stdout
    ..writeln('\n${'-' * 70}')
    ..writeln(npc.name.toUpperCase())
    ..writeln('-' * 70)
    ..writeln('\n${_wrap(talk.currentScene.body)}');

  var keepGoing = true;
  while (!talk.isFinished) {
    final options = talk.availableOptions();
    stdout.writeln('');
    for (var i = 0; i < options.length; i++) {
      stdout.writeln('  ${i + 1}. ${options[i].label}'
          '${_checkHint(talk, options[i], solo: solo)}');
    }
    stdout.writeln('  0. Walk away');

    final line = nextCommand(prompt: 'say> ');
    if (line == null) {
      stdout.writeln('\n(script exhausted mid-conversation)');
      keepGoing = false;
      break;
    }
    final choice = line.trim().toLowerCase();
    if (choice.isEmpty) continue;
    if (const {'0', 'bye', 'leave', 'walk away'}.contains(choice)) {
      stdout.writeln('\nYou leave ${npc.name} where you found them.');
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
      stdout.writeln('Pick a number from the list, or 0 to walk away.');
      continue;
    }

    final GameEvent event;
    try {
      event = talk.choose(option.id);
    } on InvalidChoiceException catch (e) {
      stdout.writeln(e.message);
      continue;
    }

    if (event.said case final said?) {
      stdout.writeln('\n${_wrap('${event.actorName} says, "$said"')}');
    }
    final check = event.check;
    if (check != null) {
      stdout.writeln('\n  ~ ${solo ? '' : '${event.actorName} — '}'
          '${check.label}: d20(${check.dieRoll}) '
          '${_signed(check.modifier)} = ${check.total} vs DC ${check.dc} '
          '-> ${check.degree.displayName}'
          '${check.wasShiftedByNatural ? ' (natural ${check.dieRoll})' : ''}');
    }
    stdout.writeln('\n${_wrap(event.narration)}');

    // A new scene is a new beat; returning to the same one is not, and
    // repeating its opening every time would read like a stuck record.
    final movedTo = event.movedTo;
    if (movedTo != null && movedTo != event.sceneId) {
      stdout.writeln('\n${_wrap(talk.currentScene.body)}');
    }
  }

  final flags = session.concludeConversation(talk);
  for (final flag in flags) {
    stdout.writeln('\n  [$flag]');
  }
  _announceArcs(session);
  return keepGoing;
}

String _checkHint(GameSession talk, SceneOption option, {required bool solo}) {
  final check = option.check;
  if (check == null) return '';
  final best = talk.suggestedActorFor(option.id);
  if (best == null) return '  (nobody can try this)';
  final who = solo ? '' : '${best.actor.name} ';
  return '  ($who${best.stat.formatted} vs DC ${check.dc})';
}

void _renderInventory(WorldSession session) {
  final carried = session.inventory.carried;
  if (carried.isEmpty) {
    stdout.writeln('The pack is empty. You have what you arrived with.');
    return;
  }
  stdout.writeln('');
  for (final item in carried) {
    final holder = session.inventory.holderOf(item.id);
    final worn = holder == null ? '' : '  (on $holder)';
    stdout.writeln('  ${item.name.padRight(30)} '
        'level ${item.level} ${item.rarity.name} ${item.type}$worn');
    if (item.special != null) {
      stdout.writeln(_wrap(item.special!, indent: '    '));
    }
  }
}

void _renderSheet(WorldSession session, String who) {
  try {
    final actor = who.isEmpty ? session.primary : session.actorFor(who);
    final stats = session.statsFor(actor.id);
    stdout.writeln('\n$actor');
    for (final line in stats.describe()) {
      stdout.writeln('  $line');
    }
    stdout.writeln('  HP ${actor.stats.maxHp}  '
        'Perception ${actor.stats.perception.formatted}  '
        'Class DC ${actor.stats.classDc}');
  } on InvalidMoveException catch (e) {
    stdout.writeln(e.message);
  }
}

/// Accepts "equip nail" and "equip korash nail".
bool _equip(WorldSession session, String rest) {
  if (rest.isEmpty) {
    stdout.writeln('Equip what?');
    return true;
  }
  final words = rest.split(RegExp(r'\s+'));
  String? who;
  var what = rest;
  if (words.length > 1 && session.knowsActor(words.first)) {
    who = words.first;
    what = words.skip(1).join(' ');
  }

  try {
    final before = session.statsFor(session.actorFor(who ?? '').id);
    final beforeAc = before.armorClass;
    final beforeAttack = before.attackBonus;
    final beforeDamage = before.damage.toString();

    final result = session.equip(what, who: who);
    final after = session.statsFor(result.actor.id);

    stdout.writeln('\n${result.actor.name} takes up ${result.item.name}'
        '${result.replaced == null ? '' : ', putting away '
            '${result.replaced!.name}'}.');
    if (result.slot == EquipSlot.armor) {
      stdout.writeln('  AC $beforeAc -> ${after.armorClass}');
    } else {
      stdout.writeln('  Strike ${_signed(beforeAttack)} $beforeDamage'
          ' -> ${_signed(after.attackBonus)} ${after.damage}');
    }
  } on EquipException catch (e) {
    stdout.writeln(_wrap(e.message));
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
  }
  return true;
}

bool _unequip(WorldSession session, String rest) {
  if (rest.isEmpty) {
    stdout.writeln('Take off what — weapon or armour?');
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
    stdout.writeln(result.removed == null
        ? '${result.actor.name} had nothing there.'
        : '${result.actor.name} puts away ${result.removed!.name}.');
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
  }
  return true;
}

String _signed(int value) => value >= 0 ? '+$value' : '$value';

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
    stdout.writeln('\n${_wrap(session.describeEncounter(encounter))}');
    stdout.writeln(encounter.ambush
        ? '\n  (${encounter.name} — between you and the way on)'
        : '\n  (${encounter.name} — type "fight" to begin)');
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
  talk <name>                                     talk to someone properly
  ask <name> about <topic>                        raise a single topic
  quests                                          arc progress
  inventory (i)                                   what the party is carrying
  sheet [who]                                     AC, Strike, HP as equipped
  equip [who] <item>                              wield or wear something
  unequip [who] weapon|armour                     put it away again
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
