import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('option gating', () {
    test('hides an option until its flag is set', () {
      final session = newSession();
      expect(session.availableOptions().map((o) => o.id),
          isNot(contains('descend')));

      // Examining the body sets "suspicious" on a success or better; Korash
      // rolls Lore: Undead at +14 against DC 18, so drive it deterministically
      // instead of hoping.
      while (!session.flags.contains('suspicious')) {
        session.choose('examine-body');
      }
      expect(session.availableOptions().map((o) => o.id), contains('descend'));
    });

    test('a proficiency gate opens only at or above its rank', () {
      final stats = DerivedStats(loadKorash());
      const flags = <String>{};

      // Korash is expert in Lore: Undead.
      expect(
          const OptionGate(
                  minProficiencyStat: 'lore:undead',
                  minProficiency: Proficiency.expert)
              .allows(flags, stats),
          isTrue);
      expect(
          const OptionGate(
                  minProficiencyStat: 'lore:undead',
                  minProficiency: Proficiency.trained)
              .allows(flags, stats),
          isTrue);
      expect(
          const OptionGate(
                  minProficiencyStat: 'lore:undead',
                  minProficiency: Proficiency.master)
              .allows(flags, stats),
          isFalse);
    });

    test('a gate on an unknown statistic stays closed', () {
      final stats = DerivedStats(loadKorash());
      expect(
          const OptionGate(
                  minProficiencyStat: 'lore:nonsense',
                  minProficiency: Proficiency.trained)
              .allows(const {}, stats),
          isFalse);
    });

    test('forbidden flags close a gate', () {
      final stats = DerivedStats(loadKorash());
      const gate = OptionGate(forbiddenFlags: ['alarmed']);
      expect(gate.allows(const {}, stats), isTrue);
      expect(gate.allows({'alarmed'}, stats), isFalse);
    });
  });

  group('choosing', () {
    test('an automatic option needs no roll', () {
      final session = newSession();
      final event = session.choose('leave');
      expect(event.check, isNull);
      expect(event.movedTo, 'ending-walked-away');
      expect(session.isFinished, isTrue);
    });

    test('records the check and narration in the log', () {
      final session = newSession(seed: 12);
      final event = session.choose('examine-body');
      expect(event.index, 0);
      expect(event.sceneId, 'chapel');
      expect(event.optionId, 'examine-body');
      expect(event.check!.label, 'Lore: Undead');
      expect(event.check!.modifier, 14);
      expect(event.narration, isNotEmpty);
      expect(session.log, hasLength(1));
    });

    test('rejects an option that is not currently available', () {
      final session = newSession();
      expect(() => session.choose('descend'),
          throwsA(isA<InvalidChoiceException>()));
      expect(() => session.choose('no-such-option'),
          throwsA(isA<InvalidChoiceException>()));
    });

    test('rejects any choice once the session has ended', () {
      final session = newSession()..choose('leave');
      expect(() => session.choose('leave'),
          throwsA(isA<InvalidChoiceException>()));
    });

    test('clears flags as well as setting them', () {
      final adventure = const AdventureLoader().fromMap(minimalAdventure(
        options: [
          {
            'id': 'set',
            'label': 'Set',
            'outcome': {
              'text': 'Set.',
              'setFlags': ['marked'],
            },
          },
          {
            'id': 'clear',
            'label': 'Clear',
            'outcome': {
              'text': 'Cleared.',
              'clearFlags': ['marked'],
            },
          },
        ],
      ));
      final session = newSession(adventure: adventure);
      session.choose('set');
      expect(session.flags, contains('marked'));
      session.choose('clear');
      expect(session.flags, isNot(contains('marked')));
    });
  });

  group('outcome fallback', () {
    test('a critical falls back to its ordinary counterpart', () {
      const option = SceneOption(
        id: 'x',
        label: 'x',
        check: StatCheck(statKey: 'athletics', dc: 10),
        outcomes: {
          DegreeOfSuccess.success: Outcome(text: 'good'),
          DegreeOfSuccess.failure: Outcome(text: 'bad'),
        },
      );
      expect(option.outcomeFor(DegreeOfSuccess.criticalSuccess)!.text, 'good');
      expect(option.outcomeFor(DegreeOfSuccess.criticalFailure)!.text, 'bad');
    });

    test('an ordinary degree does not fall back to a critical', () {
      const option = SceneOption(
        id: 'x',
        label: 'x',
        check: StatCheck(statKey: 'athletics', dc: 10),
        outcomes: {
          DegreeOfSuccess.criticalSuccess: Outcome(text: 'great'),
        },
      );
      expect(option.outcomeFor(DegreeOfSuccess.success), isNull);
      expect(option.outcomeFor(DegreeOfSuccess.criticalSuccess)!.text, 'great');
    });
  });

  group('determinism and resume', () {
    test('the same seed and choices produce the same rolls', () {
      List<int> play() {
        final session = newSession(seed: 99);
        return [
          session.choose('examine-body').check!.dieRoll,
          session.choose('speak-widow').check!.dieRoll,
          session.choose('recite-rites').check!.dieRoll,
        ];
      }

      expect(play(), play());
    });

    test('a restored session rolls what the original would have rolled', () {
      final original = newSession(seed: 5);
      original.choose('examine-body');

      final snapshot = original.snapshot();
      final resumed = GameSession.restore(
        adventure: loadQuietWake(),
        character: loadKorash(),
        snapshot: snapshot,
      );

      expect(resumed.currentScene.id, original.currentScene.id);
      expect(resumed.flags, original.flags);
      expect(resumed.choose('recite-rites').check!.dieRoll,
          original.choose('recite-rites').check!.dieRoll);
    });

    test('a snapshot round-trips through JSON', () {
      final session = newSession(seed: 3)..choose('examine-body');
      final restored = SessionSnapshot.fromJson(session.snapshot().toJson());
      expect(restored.sceneId, session.currentScene.id);
      expect(restored.rollerState, session.snapshot().rollerState);
      expect(restored.flags, session.flags);
      expect(restored.eventCount, 1);
    });

    test('refuses a snapshot from a different adventure', () {
      final other = const AdventureLoader().fromMap(minimalAdventure());
      final session = newSession(adventure: other);
      expect(
        () => GameSession.restore(
          adventure: loadQuietWake(),
          character: loadKorash(),
          snapshot: session.snapshot(),
        ),
        throwsArgumentError,
      );
    });
  });

  test('the untrained option is genuinely worse than the expert one', () {
    // The design bet in one assertion: the same character is +14 at reading a
    // corpse and +0 at reciting over it, and the menu has to show both.
    final stats = DerivedStats(loadKorash());
    expect(stats.statByKey('lore:undead')!.total, 14);
    expect(stats.statByKey('religion')!.total, 0);
  });
}
