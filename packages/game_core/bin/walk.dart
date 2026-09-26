import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';

const _defaultCampaign = '../../campaigns/shattered_seals';
const _defaultCharacter = '../pf2e_core/test/fixtures/korash.json';
const _defaultContent = '../../content/pf2e_remaster';

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

  // A saved game names its own campaign and characters, so resuming needs
  // nothing but the file; anything given on the command line still wins.
  final resumePath = options['resume'];
  Map<String, Object?>? saved;
  if (resumePath != null) {
    try {
      saved = _readSave(resumePath);
    } on FormatException catch (e) {
      stderr.writeln('Could not resume from $resumePath: ${e.message}');
      exitCode = 66;
      return;
    }
  }
  var savePath = options['save'] ?? resumePath;

  final campaignDir =
      options['campaign'] ?? saved?['campaign'] as String? ?? _defaultCampaign;
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
  if (characterPaths.isEmpty && saved != null) {
    characterPaths.addAll([
      for (final p in (saved['characters'] as List? ?? const [])) '$p',
    ]);
  }
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
      economyJson: read('economy.json'),
      huntJson: read('hunt.json'),
      weatherJson: read('weather.json'),
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

  // Spells are rules content, read from their own package when it is there.
  final contentDir = options['content'] ?? _defaultContent;
  final spellFile = File('$contentDir/spells.json');
  final spells = spellFile.existsSync()
      ? const CampaignLoader().readSpells(spellFile.readAsStringSync())
      : SpellBook();

  final WorldSession session;
  if (saved != null) {
    try {
      session = WorldSession.restore(
        campaign: campaign,
        actors: actors,
        spells: spells,
        snapshot: (saved['world'] as Map).cast<String, Object?>(),
      );
    } on ArgumentError catch (e) {
      stderr.writeln('Could not resume from $resumePath: ${e.message}');
      exitCode = 65;
      return;
    }
  } else {
    session = WorldSession(
      campaign: campaign,
      actors: actors,
      spells: spells,
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
    // Extra gold to start with, for trying out what being rich brings.
    final gold = int.tryParse(options['gold'] ?? '') ?? 0;
    if (gold > 0) session.inventory.earn(gold * 100);
  }

  stdout
    ..writeln('=' * 70)
    ..writeln('MARCHING ORDER — ${campaign.title}')
    ..writeln(saved == null
        ? '${campaign.world.metadata.name} · seed $seed'
        : '${campaign.world.metadata.name} · resumed from $resumePath')
    ..writeln('=' * 70);
  if (saved == null) {
    stdout
      ..writeln()
      ..writeln(_wrap(campaign.world.metadata.backgroundLore));
  }
  for (final actor in session.actors) {
    stdout.writeln('\n  ${actor.id.padRight(8)} $actor');
  }
  if (saved != null) _announceReturn(session, saved);

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
  _announceEvents(session);

  while (true) {
    final line = nextCommand();
    if (line == null) {
      if (scripted.isNotEmpty) stdout.writeln('\n(script exhausted)');
      break;
    }
    if (line.isEmpty) continue;
    if (line == 'quit' || line == 'q') break;
    if (line == 'save' || line.startsWith('save ')) {
      final named = line.substring(4).trim();
      if (named.isNotEmpty) savePath = named;
      final path = savePath;
      if (path == null) {
        stdout.writeln('Save where? "save <file>".');
      } else {
        _writeSave(path, session, campaignDir, characterPaths);
      }
      continue;
    }
    final coinBefore = session.inventory.coin;
    final xpBefore = {
      for (final a in session.actors) a.id: session.experience.xpOf(a.id),
    };
    final tierBefore = session.notoriety.tier;
    final keepGoing = _handle(session, line, nextCommand);
    _announceEvents(session);
    final gained = session.inventory.coin - coinBefore;
    if (gained > 0 && !line.toLowerCase().startsWith('sell')) {
      stdout.writeln('\n  [+${formatCoin(gained)} — the party has '
          '${formatCoin(session.inventory.coin)}]');
    }
    _announceExperience(session, xpBefore);
    _announceNotoriety(session, tierBefore);
    if (!keepGoing) break;
  }

  stdout.writeln('\n${'-' * 70}');
  final path = savePath;
  if (path == null) {
    stdout.writeln('Nothing saved. Next time, start with --save=<file> or '
        'type "save <file>" to keep your place.');
  } else {
    _writeSave(path, session, campaignDir, characterPaths);
  }
}

/// Save files carry a version so an older walk can refuse a newer save
/// rather than misread it.
const _saveVersion = 1;

/// Writes the game to [path]: the world, and where its campaign and
/// characters were read from, so resuming needs nothing but the file.
void _writeSave(String path, WorldSession session, String campaignDir,
    List<String> characterPaths) {
  final file = File(path);
  try {
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'version': _saveVersion,
      'campaign': Directory(campaignDir).absolute.path,
      'characters': [
        for (final p in characterPaths) File(p).absolute.path,
      ],
      'saved': 'day ${session.day}, ${session.clock}, '
          '${session.currentRoom.title}',
      'world': session.snapshot(),
    }));
    stdout.writeln('Saved to $path (day ${session.day}, ${session.clock}, '
        '${session.currentRoom.title}). Resume with --resume=$path');
  } on FileSystemException catch (e) {
    stdout.writeln('Could not save to $path: ${e.message}');
  }
}

/// Reads a save written by [_writeSave].
Map<String, Object?> _readSave(String path) {
  final file = File(path);
  if (!file.existsSync()) throw FormatException('there is no such file');
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    throw FormatException('it is not a save file');
  }
  if (decoded is! Map || decoded['world'] is! Map) {
    throw FormatException('it is not a save file');
  }
  final version = (decoded['version'] as num?)?.toInt() ?? 0;
  if (version > _saveVersion) {
    throw FormatException('it was written by a newer version (save format '
        '$version; this reads up to $_saveVersion)');
  }
  return decoded.cast<String, Object?>();
}

/// Says where the party picks up, and what changed about them since: a
/// character re-imported from Pathbuilder a level up has had the thousand
/// XP it cost taken off, and a newcomer joins with their sheet's own XP.
void _announceReturn(WorldSession session, Map<String, Object?> saved) {
  stdout.writeln('\nYou pick up where you left off: day ${session.day}, '
      '${session.clock}, in ${session.currentRoom.title}.');
  final before = (saved['world'] as Map)['experience'];
  for (final actor in session.actors) {
    final record = before is Map ? before[actor.id] : null;
    if (record is! Map) {
      stdout.writeln('  ${actor.name} was not in this save, and joins the '
          'party now.');
      continue;
    }
    final was = (record['level'] as num?)?.toInt();
    final now = actor.character.level;
    if (was != null && now > was) {
      stdout.writeln('  ${actor.name} comes back level $now, up from $was: '
          '${groupThousands((now - was) * xpToLevel)} XP spent in '
          'Pathbuilder.');
    }
  }
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
      final hours = int.tryParse(rest);
      try {
        if (hours == null) {
          final minutes = session.waitOutStorm();
          stdout.writeln(minutes > 60
              ? 'You wait out the weather: ${_duration(minutes)}.'
              : 'An hour goes by.');
        } else {
          session.advanceTime(hours);
          stdout.writeln('${_duration(hours * 60)} go by.');
        }
      } on InvalidMoveException catch (e) {
        stdout.writeln(_wrap(e.message));
        return true;
      }
      _announceEvents(session);
      stdout.writeln('\nIt is ${_when(session)}.');
      final echo = session.ambianceEcho();
      if (echo != null) stdout.writeln('\n${_wrap(echo)}');
      return true;

    case 'time':
    case 'date':
      stdout.writeln('It is ${_when(session)}.');
      return true;

    case 'status':
    case 'hp':
    case 'party':
      _renderStatus(session);
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
        if (night.night case final text?) stdout.writeln('\n${_wrap(text)}');
        if (night.wake case final text?) stdout.writeln('\n${_wrap(text)}');
        stdout.writeln('\nYou slept eight hours, and have made your '
            'preparations for the day.');
        for (final actor in session.actors) {
          final v = session.vitalsOf(actor.id);
          stdout.writeln('  ${actor.name}: +${healed[actor.id]} HP '
              '(${v.hp}/${v.maxHp})');
        }
        stdout.writeln('  Spell slots and focus restored. Nobody is tired.');
        stdout.writeln('\nIt is ${_when(session)}.');
      } on InvalidMoveException catch (e) {
        stdout.writeln(_wrap(e.message));
      }
      return true;

    case 'treat':
    case 'heal':
      try {
        final t = session.treatWounds(who: rest.isEmpty ? null : rest);
        final c = t.check;
        final whose =
            t.healer.id == t.patient.id ? 'their own' : "${t.patient.name}'s";
        stdout.writeln('\n${t.healer.name} treats $whose '
            'wounds: d20(${c.dieRoll}) ${_signed(c.modifier)} = ${c.total} '
            'vs DC ${c.dc} — ${c.degree.displayName}');
        final roll = t.roll;
        final v = session.vitalsOf(t.patient.id);
        if (roll != null) {
          stdout.writeln('  ${t.change >= 0 ? 'heals' : 'hurts'} $roll: '
              '${t.change >= 0 ? '+' : ''}${t.change} HP (${v.hp}/${v.maxHp})');
        } else {
          stdout.writeln('  Ten minutes, and nothing to show for it.');
        }
      } on InvalidMoveException catch (e) {
        stdout.writeln(_wrap(e.message));
      }
      return true;

    case 'use':
    case 'drink':
      final args = _useArgs(rest);
      if (args == null) {
        stdout.writeln('Use what? ("inventory" shows what you carry.)');
        return true;
      }
      try {
        _renderUse(session.use(args.what, who: args.who));
      } on InvalidMoveException catch (e) {
        stdout.writeln(_wrap(e.message));
      }
      return true;

    case 'refocus':
      try {
        final back = session.refocus();
        for (final id in back.keys) {
          final v = session.vitalsOf(id);
          stdout.writeln('${session.actorFor(id).name} refocuses: '
              '${v.focus}/${v.maxFocus} focus.');
        }
      } on InvalidMoveException catch (e) {
        stdout.writeln(_wrap(e.message));
      }
      return true;

    case 'shelter':
      try {
        final built = session.makeShelter();
        final c = built.check;
        stdout.writeln('\n${built.builder.name} makes shelter: '
            'd20(${c.dieRoll}) ${_signed(c.modifier)} = ${c.total} vs DC '
            '${c.dc} — ${c.degree.displayName}');
        stdout.writeln(_wrap(
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
        stdout.writeln(_wrap(e.message));
      }
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

    case 'list':
    case 'wares':
      _renderWares(session);
      return true;

    case 'buy':
      return _trade(session, rest, buying: true);

    case 'sell':
      return _trade(session, rest, buying: false);

    case 'value':
    case 'appraise':
      try {
        final quote = session.valueOf(rest);
        stdout.writeln('${_keeper(session)} would give you '
            '${formatCoin(quote.price)} for ${quote.item.name}.');
      } on InvalidMoveException catch (e) {
        stdout.writeln(_wrap(e.message));
      }
      return true;

    case 'purse':
    case 'coin':
    case 'money':
      stdout.writeln('The party has ${formatCoin(session.inventory.coin)}, '
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

  if (result.minutes >= 30) {
    stdout.writeln('\n  (${_duration(result.minutes)} on the road)');
  }
  _renderRoom(session, full: true, showWeather: result.changedRegion);
  final here = session.roomAmbiance();
  if (here != null) stdout.writeln('\n${_wrap(here)}');
  if (result.changedRegion) {
    final echo = session.ambianceEcho();
    if (echo != null) stdout.writeln('\n${_wrap(echo)}');
  }
  _announceArcs(session);
  _announceEvents(session);

  // An ambush is not something to mention and move on from.
  final ambush = result.ambush;
  if (ambush != null) {
    return _fight(session, nextCommand, encounterId: ambush.id);
  }

  // Nor is something that has followed the party's money this far.
  final hunt = result.hunt;
  final roll = result.huntRoll;
  if (hunt != null) {
    stdout.writeln('\n  [The hunt: d100(${roll?.die}) against '
        '${roll?.chance}% — something has your scent]');
    stdout.writeln('\n${_wrap(hunt.description)}');
    return _fight(session, nextCommand, encounterId: hunt.id);
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
  final pack = session.inventory;
  final carried = pack.carried;
  if (carried.isEmpty) {
    stdout.writeln('The pack is empty. You have what you arrived with.');
  } else {
    stdout.writeln('');
    for (final item in carried) {
      final count = pack.countOf(item.id);
      final holders = pack.holdersOf(item.id);
      final worn = holders.isEmpty ? '' : '  (on ${holders.join(', ')})';
      final name = count > 1 ? '${item.name} x$count' : item.name;
      stdout.writeln('  ${name.padRight(30)} '
          'level ${item.level} ${item.rarity.name} ${item.type}$worn');
      if (item.special != null) {
        stdout.writeln(_wrap(item.special!, indent: '    '));
      }
    }
  }
  stdout.writeln('\nPurse: ${formatCoin(pack.coin)}');
}

void _renderWares(WorldSession session) {
  final shop = session.shopHere;
  if (shop == null) {
    stdout.writeln('There is nobody here to trade with.');
    return;
  }
  if (session.keeperSays('greet') case final k?) _says(k.keeper, k.line);
  final percent = shop.percentFor(session.flags);
  stdout.writeln('\n${shop.name} — ${_keeper(session)}'
      '${percent == 0 ? '' : percent < 0 ? '  (${-percent}% off, for you)' : '  (+$percent%, for you)'}');
  for (final row in session.wares()) {
    final dear = row.price > session.inventory.coin ? '  *' : '';
    stdout.writeln('  ${row.item.name.padRight(32)} '
        '${'level ${row.item.level}'.padRight(9)} '
        '${formatCoin(row.price).padLeft(12)}$dear');
  }
  stdout.writeln('\nThe party has ${formatCoin(session.inventory.coin)}.'
      '${session.wares().any((r) => r.price > session.inventory.coin) ? '  (* more than that)' : ''}');
}

bool _trade(WorldSession session, String what, {required bool buying}) {
  if (what.isEmpty) {
    stdout.writeln(buying ? 'Buy what?' : 'Sell what?');
    return true;
  }
  try {
    if (buying) {
      final bought = session.buy(what);
      stdout.writeln('\nYou buy ${bought.item.name} for '
          '${formatCoin(bought.price)}. The party has '
          '${formatCoin(session.inventory.coin)} left.');
      if (session.keeperSays('buy') case final k?) _says(k.keeper, k.line);
    } else {
      final sold = session.sell(what);
      stdout.writeln('\n${_keeper(session)} gives you '
          '${formatCoin(sold.price)} for ${sold.item.name}. The party has '
          '${formatCoin(session.inventory.coin)}.');
      if (session.keeperSays('sell') case final k?) _says(k.keeper, k.line);
    }
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
    if (e.message.contains('and the party has')) {
      if (session.keeperSays('broke') case final k?) _says(k.keeper, k.line);
    }
  }
  return true;
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
    stdout.writeln('\n$actor');
    for (final line in stats.describe()) {
      stdout.writeln('  $line');
    }
    stdout.writeln('  HP ${actor.stats.maxHp}  '
        'Perception ${actor.stats.perception.formatted}  '
        'Class DC ${actor.stats.classDc}');
    stdout.writeln('  ${_xpLine(session.experience.progressOf(actor.id))}');
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
  stdout.writeln('\nIt is ${_when(session)}.');
  for (final actor in session.actors) {
    final v = session.vitalsOf(actor.id);
    final slots = (v.slots.keys.toList()..sort())
        .map((r) => '${_ordinal(r)} ${v.slotsLeft[r] ?? 0}/${v.slots[r]}')
        .join(', ');
    stdout.writeln('  ${actor.name.padRight(24)} HP ${v.hp}/${v.maxHp}'
        '${v.maxFocus > 0 ? '   focus ${v.focus}/${v.maxFocus}' : ''}'
        '${slots.isEmpty ? '' : '   spells $slots'}');
  }
  final e = session.endurance;
  final limits = session.campaign.weather.travel;
  stdout.writeln('\n  ${_duration(e.travelMinutes).ifEmpty('No time')} on '
      'the road, ${_duration(e.awakeMinutes).ifEmpty('no time')} awake, '
      'since you last rested.');
  if (session.isSpent) {
    stdout.writeln('  The party is spent: no long roads until you rest.');
  } else if (session.isFatigued) {
    stdout.writeln('  The party is Fatigued: -1 to AC and saves until you '
        'rest.');
  } else {
    stdout.writeln('  About ${e.roadLeftHours(limits).toStringAsFixed(1)} '
        'hours before you tire.');
  }
  if (session.isExposed) {
    stdout.writeln(
        '  You are out in the ${session.weatherNow!.name.toLowerCase()} '
        'with nothing over you. Find a roof, or "shelter".');
  } else if (session.isSheltering) {
    stdout.writeln('  You are under a shelter of your own making.');
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
        stdout.writeln('\n  [Weather, ${_regionName(weather.regionId)}, '
            '${weather.season.name} ${session.campaign.weather.calendar.dateOf(weather.day).dayOfSeason}: '
            'd100(${weather.die}) — ${weather.type.name}$storm]');
        if (session.remarkOn(weather.type) case final r?) {
          _says(r.who.name, r.line);
        }
      case NewDay():
        stdout.writeln('\n  *** $event ***');
      case DawnOrDusk(:final echo):
        if (echo != null) stdout.writeln('\n${_wrap(echo)}');
      case StormBroke(:final weather, :final sheltered):
        stdout.writeln('\n  *** The ${weather.type.name.toLowerCase()} '
            'breaks. ***');
        stdout.writeln(_wrap(
            session.look().region?.weatherStates[weather.type.id] ??
                weather.type.text,
            indent: '  '));
        if (!sheltered) {
          stdout.writeln(_wrap(
              'You are out in the open. Find a roof, or make shelter here '
              '("shelter"). Every hour out in it will cost you.',
              indent: '  '));
        }
      case Exposure(:final actor, :final save, :final damage, :final hpLost):
        final v = session.vitalsOf(actor.id);
        stdout.writeln('  ${actor.name}: ${save.label} '
            'd20(${save.dieRoll}) ${_signed(save.modifier)} = ${save.total} '
            'vs DC ${save.dc} — ${save.degree.displayName}; $damage; '
            'loses $hpLost HP (${v.hp}/${v.maxHp})');
      case StormPassed(:final weather, :final xp, :final ownShelter):
        stdout.writeln('\n  *** The ${weather.type.name.toLowerCase()} blows '
            'over. ${xp == 0 ? 'You stood out in it, and you are still '
                'standing.' : ownShelter ? 'You rode it out under a shelter '
                'you made yourselves.' : 'You waited it out under a roof.'} ***');
      case GrewTired(:final spent):
        stdout.writeln(spent
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
  stdout
    ..writeln('\nThe party is worth ${formatCoin(worth.total)}.')
    ..writeln('  ${'Coin'.padRight(26)} ${formatCoin(worth.coin).padLeft(14)}')
    ..writeln('  ${'Gear, at what it costs'.padRight(26)} '
        '${formatCoin(worth.gear).padLeft(14)}');
  var onPeople = 0;
  for (final actor in session.actors) {
    final value = pack.valueOn(actor.id);
    onPeople += value;
    if (value == 0) continue;
    final loadout = pack.loadoutFor(actor.id);
    final names = [loadout.weapon?.name, loadout.armor?.name].nonNulls;
    stdout.writeln('    ${actor.name.padRight(24)} '
        '${formatCoin(value).padLeft(14)}  (${names.join(', ')})');
  }
  if (worth.gear - onPeople > 0) {
    stdout.writeln('    ${'In the pack'.padRight(24)} '
        '${formatCoin(worth.gear - onPeople).padLeft(14)}');
  }
  final size = session.actors.length;
  stdout
    ..writeln('\n${_wrap('A party of $size level ${standing.partyLevel} '
        '${size == 1 ? 'character' : 'characters'} is expected to be worth '
        '${formatCoin(worth.expected)}. You are at '
        '${worth.percentOfExpected}% of that.', indent: '  ')}')
    ..writeln('\nNotoriety: ${standing.tier.name}')
    ..writeln(_wrap(standing.tier.description, indent: '  '));

  final level = standing.hunterLevel;
  final threat = standing.tier.threat;
  if (standing.tier.isHunted && level != null && threat != null) {
    stdout.writeln(_wrap(
        'Each step there is a ${standing.tier.chance}% chance something '
        'finds you. It would come at level $level, which is a threat of '
        '"${threat.name}" for ${size == 1 ? 'one character' : '$size'}.',
        indent: '  '));
  }
  if (session.huntsSurvived > 0) {
    stdout.writeln('  Hunters beaten: ${session.huntsSurvived}');
  }
  stdout.writeln('');
  for (final tier in session.campaign.hunts.tiers) {
    final here = tier.name == standing.tier.name ? '>' : ' ';
    final brings = tier.isHunted
        ? '${tier.threat!.name} threat, ${tier.chance}% a step'
        : 'nothing comes';
    stdout.writeln('  $here ${tier.name.padRight(12)} '
        '${'from ${tier.fromPercent}%'.padRight(10)} $brings');
  }
}

/// Everything the party has come away with, and where from.
void _renderLedger(WorldSession session) {
  final ledger = session.ledger;
  if (ledger.isEmpty) {
    stdout.writeln('The party has found nothing yet.');
    return;
  }
  final things = switch (ledger.itemCount) {
    0 => 'nothing else',
    1 => 'one thing worth ${formatCoin(ledger.itemCopper)}',
    final n => '$n things worth ${formatCoin(ledger.itemCopper)}',
  };
  stdout.writeln('\nFound so far: ${formatCoin(ledger.totalCopper)} — '
      '${formatCoin(ledger.coinCopper)} in coin, and $things.\n');
  for (final entry in ledger.entries) {
    final what = entry.kind == LootKind.coin
        ? 'coin'
        : session.campaign.gear.byId(entry.itemId ?? '')?.name ??
            entry.itemId ??
            'something';
    stdout.writeln('  ${entry.source.padRight(30)} '
        '${what.padRight(28)} ${formatCoin(entry.copper).padLeft(12)}');
  }
}

/// Says so when the party's wealth moves them up, or down, the ladder.
void _announceNotoriety(WorldSession session, NotorietyTier before) {
  final now = session.notoriety.tier;
  if (now.name == before.name) return;
  final rising = now.fromPercent > before.fromPercent;
  stdout.writeln('\n  *** ${rising ? 'Word spreads' : 'Word dies down'}: you '
      'are ${now.name}. ***');
  stdout.writeln(_wrap(now.description, indent: '  '));
}

void _announceArcs(WorldSession session) {
  final settled = session.settleArcs();
  for (final arc in settled.completed) {
    stdout.writeln('\n  *** ${arc.isSide ? 'Side quest' : 'Quest'} complete: '
        '${arc.name}${_rewardNote(arc)} ***');
  }
  if (settled.worldState.isEmpty) return;
  stdout.writeln('\n  *** The world shifts: '
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
  stdout.writeln('\nExperience: ${groupThousands(xpToLevel)} XP a level, '
      '${groupThousands(XpProgress.fullTrack)} from level 1 to level '
      '$maxLevel.');
  final numbers = [for (var l = 1; l <= maxLevel; l++) '$l'.padLeft(3)];
  for (final actor in session.actors) {
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
    stdout
      ..writeln('\n  ${actor.name} — level ${p.level}')
      ..writeln('  ${numbers.join()}')
      ..writeln('  ${marks.join()}')
      ..writeln(_wrap(_xpLine(p), indent: '    '));
  }
  stdout.writeln('\n  (■ reached, + earned and waiting on Pathbuilder, '
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
  stdout.writeln('\n  [+$earned XP each]');
  for (final actor in session.actors) {
    final was = before[actor.id] ?? 0;
    if (was < xpToLevel && xp.readyToLevel(actor.id)) {
      stdout.writeln('\n  *** ${actor.name} has ${xp.xpOf(actor.id)} XP — '
          'enough for level ${actor.character.level + 1}. Level up in '
          'Pathbuilder and re-import; the thousand comes off when the new '
          'sheet arrives. ***');
    }
  }
}

void _renderArcs(WorldSession session) {
  final active = session.activeArcs();
  if (active.isEmpty) {
    stdout.writeln('Nothing is underway.');
    return;
  }
  for (final arc in active) {
    final progress = arc.progress(session.flags);
    stdout.writeln('\n${arc.name}${arc.isSide ? '  (side quest)' : ''} '
        '(${progress.done}/${progress.total})${_rewardNote(arc)}');
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
  final now = session.weatherNow;
  final date = session.date;
  stdout.writeln('   ${[
    if (view.town != null) view.town!.name,
    '${date.season.name} ${date.dayOfSeason}',
    session.clock + (view.isNight ? ' (night)' : ''),
    if (now != null)
      view.room.shelter
          ? 'indoors; ${now.name.toLowerCase()} outside'
          : now.name,
  ].join(' · ')}');
  stdout.writeln();
  if (full) stdout.writeln(_wrap(view.room.description));
  // Weather is an arrival note, not a per-step refrain: repeating the same
  // fog line every time the party takes a step turns atmosphere into noise.
  if (showWeather && view.weather != null && !view.room.shelter) {
    stdout.writeln('\n${_wrap(view.weather!)}');
  }

  for (final npc in view.npcs) {
    stdout.writeln('\n${_wrap(npc.appearance)}');
  }
  for (final greeting in session.greetingsHere()) {
    _says(greeting.npc.name, greeting.line);
  }
  final shop = session.shopHere;
  if (shop != null) {
    stdout.writeln('\n  (${shop.name} — "list" to see what is for sale)');
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
  xp                                              everyone's XP, level 1 to 20
  inventory (i)                                   what the party is carrying
  list                                            what a shop here is selling
  buy <item> / sell <item>                        trade (you get half back)
  value <item>                                    what a shop would pay
  purse                                           the party's coin
  wealth                                          what you're worth, and who
                                                  that brings after you
  ledger                                          everything found, and where
  sheet [who]                                     AC, Strike, HP as equipped
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
  refocus                                         10 minutes: 1 focus back
  shelter                                         make shelter from a storm
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
  --save=FILE        Save to FILE when you stop (and on "save")
  --resume=FILE      Pick up a saved game; it remembers its characters,
                     and a sheet re-imported a level up is settled on load
  --gold=N           Start with N more gold, to see who comes for it
  --content=DIR      Rules content (default: $_defaultContent)
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
    if (result.spoken case final spoken?) _says(spoken.who.name, spoken.line);
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
    ..writeln('=' * 70)
    ..writeln('\nInitiative (d20 + Perception):');
  for (final roll in fight.initiativeRolls) {
    stdout.writeln('  ${roll.combatant.isEnemy ? ' ' : '*'} '
        '${roll.combatant.name.padRight(26)} '
        'd20(${roll.die}) ${_signed(roll.modifier)} = ${roll.total}');
  }
  if (fight.rangedPenalty > 0) {
    stdout.writeln('\n  ${session.weatherNow?.name}: -${fight.rangedPenalty} '
        'to any strike across open ground.');
  }
  if (session.isFatigued) {
    stdout.writeln('  The party is Fatigued: -1 AC.');
  }

  final script = FightScript(fight);
  if (script.setting.isNotEmpty) {
    stdout.writeln('\n${_wrap(script.setting)}');
  }
  _speak(script.opening());

  if (fight.openingStrikes.isNotEmpty) {
    stdout.writeln('\nBefore anyone in the party can move:');
    _narrate(fight.openingStrikes, script);
  }
  _renderCombatants(fight);

  while (!fight.isOver) {
    if (!fight.isPartyTurn) {
      _narrate(fight.endTurn(), script);
      continue;
    }

    final ambiance = script.ambianceFor(fight.round);
    if (ambiance != null) stdout.writeln('\n${_wrap(ambiance.text)}');
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
          _narrate([result], script);
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
          _narrate(fight.endTurn(), script);
        case 'flee':
          fight.flee();
        case 'cast':
          _cast(fight, rest, script);
        case 'use':
        case 'drink':
          final args = _useArgs(rest);
          if (args == null) {
            stdout.writeln('Use what?');
            break;
          }
          _renderUse(fight.use(args.what, targetId: args.who));
        case 'spells':
          final options = fight.castOptions();
          stdout.writeln(options.isEmpty
              ? '  ${fight.current.name} has no spells the engine can cast.'
              : '  ${options.join('\n  ')}');
        case 'status':
          _renderCombatants(fight);
        case 'quit':
        case 'q':
          return false;
        default:
          stdout.writeln('In a fight you can: strike <target>, cast <spell> '
              '[target], spells, use <item> [on <who>], close, back, end, '
              'status, flee.');
      }
    } on InvalidActionException catch (e) {
      stdout.writeln('  ${e.message}');
    }

    if (fight.actionsLeft == 0 && !fight.isOver && fight.isPartyTurn) {
      _narrate(fight.endTurn(), script);
    }
  }

  stdout.writeln('\n${'=' * 70}');
  _speak(script.closing());
  switch (fight.outcome!) {
    case EncounterOutcome.victory:
      stdout.writeln('\nThe fight is over. You are still standing.');
      final flags = session.concludeEncounter(fight);
      _renderSpoils(fight);
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
      stdout.writeln('\nThe party goes down. Valorheim does not stop for it.');
      final before = session.inventory.coin;
      session.concludeEncounter(fight);
      stdout.writeln('\n  You come to an hour later, where you fell, everyone '
          'at 1 HP. Rest, or have your wounds treated, before the next one.');
      final taken = before - session.inventory.coin;
      if (taken > 0) {
        stdout.writeln('\n  ${fight.enemies.first.name} goes through your '
            'packs while you lie there, and takes ${formatCoin(taken)}.');
      }
    case EncounterOutcome.fled:
      stdout.writeln('\nYou break off and go.');
      session.concludeEncounter(fight);
  }
  return true;
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
  stdout.writeln('\n  $who: ${result.roll}, +${result.healed} HP '
      '(${result.hp}/${result.maxHp}).');
  if (result.revived) {
    stdout.writeln('  ${result.target} is back on their feet.');
  }
}

/// Casts a spell: "cast fireball", or "cast needle darts c_hollow_thrall_1".
void _cast(EncounterSession fight, String rest, FightScript script) {
  if (rest.isEmpty) {
    stdout.writeln('Cast what? ("spells" lists them.)');
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
  stdout.writeln('\n  ${result.caster.name} casts ${o.spell.name} '
      '(rank ${o.rank}, $cost)'
      '${result.damageRoll == null ? '' : ': ${result.damageRoll}'}');
  for (final hit in result.hits) {
    final c = hit.check;
    final against =
        o.spell.defense == SpellDefense.ac ? 'vs AC ${c.dc}' : 'vs DC ${c.dc}';
    final natural = c.wasShiftedByNatural ? ', natural ${c.dieRoll}' : '';
    stdout.writeln('    ${hit.target.name}: ${c.label} d20(${c.dieRoll}) '
        '${_signed(c.modifier)} = ${c.total} $against$natural — '
        '${c.degree.displayName}');
    final dice = hit.damageRoll;
    stdout.writeln('      ${dice == null ? '' : 'damage $dice; '}'
        'takes ${hit.damage}.${hit.dropped ? ' ${hit.target.name} goes down.' : ''}');
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
      stdout.writeln('\n${actor.name}:');
      if (options.isEmpty) stdout.writeln('  nothing the engine can cast yet');
      for (final o in options) {
        final uses = o.cost == CastCost.cantrip
            ? 'at will'
            : '${o.left} left (${o.cost.name})';
        final how = o.spell.defense == SpellDefense.ac
            ? 'spell attack ${_signed(o.attackBonus)}'
            : 'basic ${o.spell.defense.name}, DC ${o.dc}';
        stdout
            .writeln('  ${o.spell.name.padRight(16)} ${o.source.padRight(12)} '
                'rank ${o.rank}  ${o.spell.damageAt(o.rank)}  $how  $uses');
      }
      final missing = session.spellsWithoutNumbers(actor.id);
      if (missing.isNotEmpty) {
        stdout.writeln(_wrap(
            'Not in the spell table yet: ${missing.join(', ')}.',
            indent: '  '));
      }
    }
  } on InvalidMoveException catch (e) {
    stdout.writeln(e.message);
  }
}

/// Each strike with its dice, and whatever is said as the fight turns.
void _narrate(List<StrikeResult> log, FightScript script) {
  for (final result in log) {
    stdout.writeln('\n  ${_strikeLine(result)}');
    _speak(script.after([result]));
  }
}

/// Lines of a scene: speech attributed, narration told.
void _speak(Iterable<ScriptLine> lines) {
  for (final line in lines) {
    stdout.writeln(line.isSpeech
        ? '\n${_wrap('${line.speaker} says, "${line.text}"', indent: '  ')}'
        : '\n${_wrap(line.text, indent: '  ')}');
  }
}

/// Somebody in the party, or across a counter, saying something.
void _says(String who, String line) =>
    stdout.writeln('\n${_wrap('$who says, "$line"', indent: '  ')}');

/// A strike with its dice: the attack roll against AC, and on a hit the
/// damage dice as they fell.
String _strikeLine(StrikeResult r) {
  final check = r.outcome;
  final map = [
    if (r.penalty != 0) ', MAP ${r.penalty}',
    if (r.weatherPenalty != 0) ', weather ${r.weatherPenalty}',
  ].join();
  final natural = check.wasShiftedByNatural ? ', natural ${check.dieRoll}' : '';
  final verdict = switch (check.degree) {
    DegreeOfSuccess.criticalSuccess => 'CRITICAL HIT',
    DegreeOfSuccess.success => 'hit',
    _ => 'miss',
  };
  final head = '${r.attacker.name} strikes ${r.target.name}: '
      'd20(${check.dieRoll}) ${_signed(check.modifier)} = ${check.total} '
      'vs AC ${check.dc}$map$natural — $verdict';
  final damage = r.damageRoll;
  if (damage == null) return head;
  final dropped = r.targetDropped ? ' ${r.target.name} goes down.' : '';
  return '$head\n    damage $damage.$dropped';
}

/// The rolls that settle what a won fight was worth.
void _renderSpoils(EncounterSession fight) {
  if (fight.coinRoll case final coin?) {
    stdout.writeln('\n  Coin on the fallen: $coin gp');
  }
  if (fight.lootRolls.isNotEmpty) {
    stdout.writeln('  Searching them (d100, found at or under the chance):');
    for (final roll in fight.lootRolls) {
      stdout.writeln('    $roll');
    }
  }
  if (fight.xpAwards.isNotEmpty) {
    stdout.writeln('  XP, by level against the party\'s '
        '${fight.xpAwards.first.partyLevel}:');
    for (final award in fight.xpAwards) {
      stdout.writeln('    $award');
    }
  }
}

void _renderCombatants(EncounterSession fight) {
  stdout.writeln('');
  for (final c in fight.combatants) {
    final bar = c.isDown ? 'down' : '${c.hp}/${c.maxHp}';
    final where = fight.zones[c.zoneIndex];
    stdout.writeln('  ${c.isEnemy ? ' ' : '*'} ${c.id.padRight(28)} '
        '${bar.padLeft(8)}  $where');
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
