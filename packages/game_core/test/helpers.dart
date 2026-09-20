import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';

ImportedCharacter loadKorash() => const PathbuilderImporter()
    .importJson(
        File('../pf2e_core/test/fixtures/korash.json').readAsStringSync())
    .character;

Adventure loadQuietWake() => const AdventureLoader()
    .fromJson(File('assets/adventures/the_quiet_wake.json').readAsStringSync());

String loadKorashPayload() =>
    File('../pf2e_core/test/fixtures/korash.json').readAsStringSync();

ImportedCharacter loadSela() => const PathbuilderImporter()
    .importJson(File('test/fixtures/sela.json').readAsStringSync())
    .character;

GameSession newSession({int seed = 1, Adventure? adventure}) =>
    GameSession.solo(
      adventure: adventure ?? loadQuietWake(),
      character: loadKorash(),
      roller: DiceRoller(seed),
    );

/// A two-actor session: Korash, who knows the dead, and Sela, who does not but
/// can sneak. Enough contrast to tell a real ranking from a coincidence.
GameSession newPartySession({int seed = 1, Adventure? adventure}) =>
    GameSession(
      adventure: adventure ?? loadQuietWake(),
      actors: [
        SessionActor(id: 'korash', character: loadKorash()),
        SessionActor(id: 'sela', character: loadSela()),
      ],
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
