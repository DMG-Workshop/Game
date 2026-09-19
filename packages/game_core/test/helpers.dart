import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';

ImportedCharacter loadKorash() => const PathbuilderImporter()
    .importJson(
        File('../pf2e_core/test/fixtures/korash.json').readAsStringSync())
    .character;

Adventure loadQuietWake() => const AdventureLoader()
    .fromJson(File('assets/adventures/the_quiet_wake.json').readAsStringSync());

GameSession newSession({int seed = 1, Adventure? adventure}) => GameSession(
      adventure: adventure ?? loadQuietWake(),
      character: loadKorash(),
      roller: DiceRoller(seed),
    );

/// Minimal well-formed adventure for exercising the loader.
Map<String, Object?> minimalAdventure({
  List<Map<String, Object?>>? options,
  List<Map<String, Object?>>? extraScenes,
}) =>
    {
      'id': 'test',
      'title': 'Test',
      'startScene': 'start',
      'scenes': [
        {
          'id': 'start',
          'title': 'Start',
          'body': 'You are here.',
          'options': options ??
              [
                {
                  'id': 'go',
                  'label': 'Go',
                  'outcome': {'text': 'You go.', 'goTo': 'end'},
                }
              ],
        },
        {'id': 'end', 'title': 'End', 'body': 'Done.', 'isEnding': true},
        ...?extraScenes,
      ],
    };
