import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Runs the terminal client with [args], returning what it printed.
Future<ProcessResult> _walk(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/walk.dart', ...args],
    );

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('walk_save_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a game saved on the way out is picked up where it was left', () async {
    final save = '${dir.path}/game.json';
    final first = await _walk([
      '--seed=3',
      '--room=MH_001_Square',
      '--save=$save',
      '--commands=west,west',
    ]);
    expect(first.exitCode, 0, reason: '${first.stderr}');
    expect(first.stdout, contains('Saved to $save'));

    final written = jsonDecode(File(save).readAsStringSync()) as Map;
    expect(written['version'], 1);
    expect((written['world'] as Map)['roomId'], 'WW_001_Edge');
    expect(written['characters'], hasLength(1));

    final second = await _walk(['--resume=$save', '--commands=time']);
    expect(second.exitCode, 0, reason: '${second.stderr}');
    expect(second.stdout, contains('resumed from $save'));
    expect(second.stdout, contains('The Edge of Whisperwood'));
    expect(second.stdout, contains('09:15'),
        reason: 'the clock is where it was, not back at eight');
  });

  test('"save <file>" saves mid-game, and quitting saves there too', () async {
    final save = '${dir.path}/named.json';
    final run = await _walk([
      '--seed=3',
      '--room=MH_001_Square',
      '--commands=save $save,north',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final written = jsonDecode(File(save).readAsStringSync()) as Map;
    expect((written['world'] as Map)['roomId'], 'MH_002_GuardHall',
        reason: 'saved again on the way out, after walking north');
  });

  test('without anywhere to save, says how to', () async {
    final run = await _walk(['--seed=3', '--commands=look']);
    expect(run.stdout, contains('Nothing saved'));
  });

  test('refuses a file that is not a save, or a save from the future',
      () async {
    final junk = File('${dir.path}/junk.json')..writeAsStringSync('nope');
    final bad = await _walk(['--resume=${junk.path}']);
    expect(bad.exitCode, 66);
    expect(bad.stderr, contains('not a save file'));

    final future = File('${dir.path}/future.json')
      ..writeAsStringSync(jsonEncode({'version': 99, 'world': {}}));
    final newer = await _walk(['--resume=${future.path}']);
    expect(newer.exitCode, 66);
    expect(newer.stderr, contains('newer version'));
  });

  test('a sheet re-imported a level up is settled on resume', () async {
    final save = '${dir.path}/game.json';
    await _walk(['--seed=3', '--save=$save', '--commands=look']);

    final sheet = jsonDecode(
            File('../pf2e_core/test/fixtures/korash.json').readAsStringSync())
        as Map<String, Object?>;
    final build = (sheet['build'] ?? sheet) as Map<String, Object?>;
    build['level'] = (build['level'] as num).toInt() + 1;
    final levelled = File('${dir.path}/korash_up.json')
      ..writeAsStringSync(jsonEncode(sheet));

    final run = await _walk([
      '--resume=$save',
      '--characters=${levelled.path}',
      '--commands=look',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    expect(run.stdout, contains('comes back level 7, up from 6'));
  });
}
