import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';

const _defaultCampaign = '../../campaigns/shattered_seals';
const _defaultCharacter = '../pf2e_core/test/fixtures/korash.json';
const _defaultContent = '../../content/pf2e_remaster';

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
      ..writeln(GameConsole.wrap(campaign.world.metadata.backgroundLore));
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
  Future<String?> nextCommand({String prompt = '> '}) async {
    if (scriptIndex < scripted.length) {
      final line = scripted[scriptIndex++];
      stdout.writeln('\n$prompt$line');
      return line;
    }
    if (scripted.isNotEmpty) return null;
    stdout.write('\n$prompt');
    return stdin.readLineSync(encoding: utf8)?.trim();
  }

  final console = GameConsole(session, stdout, nextCommand)..begin();

  while (true) {
    final line = await nextCommand();
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
    if (!await console.play(line)) break;
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
$consoleCommands''';

String _actorIdFor(String name, List<SessionActor> existing) {
  final base = name.trim().split(RegExp(r'\s+')).first.toLowerCase();
  final taken = {for (final a in existing) a.id};
  if (!taken.contains(base)) return base;
  for (var n = 2;; n++) {
    if (!taken.contains('$base$n')) return '$base$n';
  }
}
