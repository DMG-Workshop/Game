import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';

const _defaultCharacter = '../pf2e_core/test/fixtures/korash.json';
const _defaultAdventure = 'assets/adventures/the_quiet_wake.json';

/// Plays an adventure in the terminal.
///
///   dart run game_core:play
///   dart run game_core:play --seed=7 --choices=examine-body,descend,read-ledger
Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options.containsKey('help')) {
    stdout.writeln(_usage);
    return;
  }

  final characterPaths = (options['characters'] ?? options['character'] ?? '')
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (characterPaths.isEmpty) characterPaths.add(_defaultCharacter);

  final adventurePath = options['adventure'] ?? _defaultAdventure;
  final seed = int.tryParse(options['seed'] ?? '') ??
      DateTime.now().millisecondsSinceEpoch;

  final adventureFile = File(adventurePath);
  for (final file in [...characterPaths.map(File.new), adventureFile]) {
    if (!file.existsSync()) {
      stderr.writeln('No such file: ${file.path}');
      exitCode = 66;
      return;
    }
  }

  final actors = <SessionActor>[];
  final Adventure adventure;
  try {
    for (final path in characterPaths) {
      final imported =
          const PathbuilderImporter().importJson(File(path).readAsStringSync());
      actors.add(SessionActor(
        id: _actorIdFor(imported.character.name, actors),
        character: imported.character,
      ));
    }
    adventure =
        const AdventureLoader().fromJson(adventureFile.readAsStringSync());
  } on PathbuilderImportException catch (e) {
    stderr.writeln('Could not read the character: ${e.message}');
    exitCode = 65;
    return;
  } on AdventureFormatException catch (e) {
    stderr.writeln('Could not read the adventure: ${e.message}');
    exitCode = 65;
    return;
  }

  final session = GameSession(
    adventure: adventure,
    actors: actors,
    roller: DiceRoller(seed),
  );

  // A statistic nobody in the party has is a content bug, not a bad roll.
  final missing = <String>{};
  for (final actor in session.actors) {
    missing.addAll(
        const AdventureLoader().unresolvableStats(adventure, actor.stats));
  }
  for (final actor in session.actors) {
    missing.removeWhere((key) => actor.statFor(key) != null);
  }
  if (missing.isNotEmpty) {
    stderr.writeln('Adventure references statistics nobody has: '
        '${(missing.toList()..sort()).join(', ')}');
    exitCode = 65;
    return;
  }

  stdout
    ..writeln('=' * 68)
    ..writeln(adventure.title)
    ..writeln('Party (seed $seed):');
  for (final actor in session.actors) {
    stdout.writeln('  ${actor.id.padRight(8)} $actor');
  }
  stdout.writeln('=' * 68);

  final scripted = (options['choices'] ?? '')
      .split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();
  var scriptIndex = 0;

  String? lastScene;
  while (true) {
    // Re-describe a location only on arrival, the way a MUD does; after an
    // action the narration already said what changed.
    final sceneId = session.currentScene.id;
    if (sceneId != lastScene) {
      _renderScene(session);
      lastScene = sceneId;
    }
    if (session.isFinished) break;

    final available = session.availableOptions();
    if (available.isEmpty) {
      stdout.writeln('\nThere is nothing more to do here.');
      break;
    }
    _renderOptions(session, available);

    final String? choice;
    if (scriptIndex < scripted.length) {
      choice = scripted[scriptIndex++];
      stdout.writeln('\n> $choice');
    } else if (scripted.isNotEmpty) {
      stdout.writeln('\n(script exhausted)');
      break;
    } else {
      stdout.write('\n> ');
      choice = stdin.readLineSync(encoding: utf8)?.trim();
      if (choice == null || choice == 'quit' || choice == 'q') break;
      if (choice == 'look' || choice == 'l') {
        _look(session);
        continue;
      }
    }

    // "examine-body korash" or "1 sela" names who attempts it; without a name
    // the best candidate does.
    final parts = choice.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final resolved =
        parts.isEmpty ? null : _resolveChoice(parts.first, available);
    final actorId = parts.length > 1 ? parts.elementAt(1) : null;
    if (resolved == null) {
      stdout.writeln('Not an option here.');
      continue;
    }

    try {
      _renderEvent(session.choose(resolved, actorId: actorId),
          solo: session.actors.length == 1);
    } on InvalidChoiceException catch (e) {
      stdout.writeln(e.message);
    }
  }

  stdout
    ..writeln('\n${'-' * 68}')
    ..writeln('${session.log.length} action(s). '
        'Flags: ${session.flags.isEmpty ? 'none' : (session.flags.toList()..sort()).join(', ')}')
    ..writeln('Resume snapshot: ${jsonEncode(session.snapshot().toJson())}');
}

/// Accepts an option id or its menu number.
String? _resolveChoice(String input, List<SceneOption> available) {
  final asIndex = int.tryParse(input);
  if (asIndex != null) {
    if (asIndex < 1 || asIndex > available.length) return null;
    return available[asIndex - 1].id;
  }
  for (final option in available) {
    if (option.id == input) return option.id;
  }
  return null;
}

void _renderScene(GameSession session) {
  final scene = session.currentScene;
  stdout
    ..writeln('\n## ${scene.title}\n')
    ..writeln(_wrap(scene.body));
}

/// Shows the current location again on demand, as `look` would in a MUD.
void _look(GameSession session) => _renderScene(session);

void _renderOptions(GameSession session, List<SceneOption> available) {
  final solo = session.actors.length == 1;
  stdout.writeln('');
  for (var i = 0; i < available.length; i++) {
    final option = available[i];
    final check = option.check;
    var suffix = '';
    if (check != null) {
      final best = session.suggestedActorFor(option.id);
      if (best == null) {
        suffix = '  [nobody can roll ${check.statKey}]';
      } else {
        // Name who would roll it, and by how much they beat the next best —
        // with a party, that gap is the interesting part of the choice.
        final who = solo ? '' : '${best.actor.name}: ';
        suffix = '  [$who${best.stat.label} ${best.stat.formatted} '
            'vs DC ${check.dc}]';
      }
    }
    stdout.writeln('  ${i + 1}. ${option.label}$suffix');

    if (!solo && check != null) {
      final others = session.candidatesFor(option.id).skip(1);
      if (others.isNotEmpty) {
        stdout.writeln('       also: ${others.map((c) => '${c.actor.id} '
            '${c.stat.formatted}').join(', ')}');
      }
    }
  }
}

void _renderEvent(GameEvent event, {required bool solo}) {
  final check = event.check;
  if (check != null) {
    final who = solo ? '' : '${event.actorName} — ';
    stdout.writeln('\n  ~ $who${check.label}: d20(${check.dieRoll}) '
        '${check.modifier >= 0 ? '+' : ''}${check.modifier} = ${check.total} '
        'vs DC ${check.dc} -> ${check.degree.displayName}'
        '${check.wasShiftedByNatural ? ' (natural ${check.dieRoll})' : ''}');
  }
  stdout.writeln('\n${_wrap(event.narration)}');
}

/// A short, stable handle for typing at the prompt: first name, lower-cased,
/// suffixed only if two characters collide.
String _actorIdFor(String name, List<SessionActor> existing) {
  final base = name.trim().split(RegExp(r'\s+')).first.toLowerCase();
  final taken = {for (final a in existing) a.id};
  if (!taken.contains(base)) return base;
  for (var n = 2;; n++) {
    final candidate = '$base$n';
    if (!taken.contains(candidate)) return candidate;
  }
}

String _wrap(String text, {int width = 68}) {
  final out = <String>[];
  for (final paragraph in text.split('\n')) {
    if (paragraph.trim().isEmpty) {
      out.add('');
      continue;
    }
    final line = StringBuffer();
    for (final word in paragraph.split(' ')) {
      if (line.isNotEmpty && line.length + word.length + 1 > width) {
        out.add(line.toString());
        line.clear();
      }
      if (line.isNotEmpty) line.write(' ');
      line.write(word);
    }
    if (line.isNotEmpty) out.add(line.toString());
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

const _usage = '''
usage: play [options]

  --characters=A,B   One or more Pathbuilder exports, comma separated
                     (default: $_defaultCharacter)
  --adventure=PATH   Adventure JSON (default: $_defaultAdventure)
  --seed=N           Dice seed; omit for a random one
  --choices=a,b,c    Play a scripted sequence instead of reading stdin
  --help             Show this message

At the prompt, enter an option number or id. Add a name to say who attempts
it ("examine-body korash"); without one, the best candidate rolls. "look"
re-describes the room, "quit" ends the session.
''';
