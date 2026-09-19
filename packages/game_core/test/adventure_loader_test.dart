import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const loader = AdventureLoader();

  group('loading', () {
    test('reads the sample adventure', () {
      final adventure = loadQuietWake();
      expect(adventure.id, 'the-quiet-wake');
      expect(adventure.scenes.length, 8);
      expect(adventure.startScene.id, 'chapel');
    });

    test('reads checks, outcomes and gates', () {
      final chapel = loadQuietWake().sceneById('chapel')!;
      final examine = chapel.optionById('examine-body')!;
      expect(examine.check!.statKey, 'lore:undead');
      expect(examine.check!.dc, 18);
      expect(examine.outcomes.length, 4);
      expect(examine.outcomes[DegreeOfSuccess.criticalSuccess]!.setFlags,
          containsAll(['knows-thrall', 'suspicious']));

      final descend = chapel.optionById('descend')!;
      expect(descend.gate.requiredFlags, ['suspicious']);
      expect(descend.automatic!.goTo, 'crypt');
    });

    test('reads a minimum proficiency gate', () {
      final vault = loadQuietWake().sceneById('vault')!;
      final command = vault.optionById('command')!;
      expect(command.gate.minProficiencyStat, 'lore:undead');
      expect(command.gate.minProficiency, Proficiency.expert);
    });

    test('accepts degree keys in several spellings', () {
      final adventure = loader.fromMap(minimalAdventure(options: [
        {
          'id': 'roll',
          'label': 'Roll',
          'check': {'stat': 'athletics', 'dc': 10},
          'outcomes': {
            'critical_success': {'text': 'Great'},
            'Success': {'text': 'Fine'},
            'fail': {'text': 'Poor'},
            'crit-failure': {'text': 'Awful'},
          },
        }
      ]));
      final option = adventure.sceneById('start')!.optionById('roll')!;
      expect(option.outcomes.keys, hasLength(4));
      expect(option.outcomes[DegreeOfSuccess.criticalFailure]!.text, 'Awful');
    });
  });

  group('validation', () {
    test('rejects a transition to a scene that does not exist', () {
      expect(
        () => loader.fromMap(minimalAdventure(options: [
          {
            'id': 'go',
            'label': 'Go',
            'outcome': {'text': 'You go.', 'goTo': 'nowhere'},
          }
        ])),
        throwsA(isA<AdventureFormatException>()),
      );
    });

    test('rejects an option with neither a check nor an outcome', () {
      expect(
        () => loader.fromMap(minimalAdventure(options: [
          {'id': 'inert', 'label': 'Do nothing'}
        ])),
        throwsA(isA<AdventureFormatException>()),
      );
    });

    test('rejects a check with no outcomes', () {
      expect(
        () => loader.fromMap(minimalAdventure(options: [
          {
            'id': 'roll',
            'label': 'Roll',
            'check': {'stat': 'athletics', 'dc': 10},
          }
        ])),
        throwsA(isA<AdventureFormatException>()),
      );
    });

    test('rejects duplicate scene ids', () {
      expect(
        () => loader.fromMap(minimalAdventure(extraScenes: [
          {'id': 'end', 'title': 'Again', 'body': 'Dup.', 'isEnding': true}
        ])),
        throwsA(isA<AdventureFormatException>()),
      );
    });

    test('rejects a dead end that is not marked as an ending', () {
      expect(
        () => loader.fromMap(minimalAdventure(extraScenes: [
          {'id': 'trap', 'title': 'Trap', 'body': 'Stuck.'}
        ])),
        throwsA(isA<AdventureFormatException>()),
      );
    });

    test('rejects an unknown degree key', () {
      expect(
        () => loader.fromMap(minimalAdventure(options: [
          {
            'id': 'roll',
            'label': 'Roll',
            'check': {'stat': 'athletics', 'dc': 10},
            'outcomes': {
              'partial': {'text': 'Sort of'}
            },
          }
        ])),
        throwsA(isA<AdventureFormatException>()),
      );
    });

    test('rejects malformed JSON and non-object roots', () {
      expect(() => loader.fromJson('nope'),
          throwsA(isA<AdventureFormatException>()));
      expect(() => loader.fromJson('[1,2,3]'),
          throwsA(isA<AdventureFormatException>()));
    });
  });

  group('stat keys', () {
    test('the sample adventure resolves entirely against Korash', () {
      final session = newSession();
      expect(
          loader.unresolvableStats(session.adventure, session.stats), isEmpty);
    });

    test('a mistyped lore is reported rather than silently rolled', () {
      final adventure = loader.fromMap(minimalAdventure(options: [
        {
          'id': 'roll',
          'label': 'Roll',
          'check': {'stat': 'lore:undad', 'dc': 10},
          'outcomes': {
            'success': {'text': 'Yes'},
            'failure': {'text': 'No'},
          },
        }
      ]));
      final session = newSession(adventure: adventure);
      expect(
          loader.unresolvableStats(adventure, session.stats), ['lore:undad']);
    });
  });
}
