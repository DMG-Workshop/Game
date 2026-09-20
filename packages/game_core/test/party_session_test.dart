import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A session parked in the vault, where the interesting gate lives.
GameSession vaultSession({int seed = 1}) => GameSession(
      adventure: loadQuietWake(),
      actors: [
        SessionActor(id: 'korash', character: loadKorash()),
        SessionActor(id: 'sela', character: loadSela()),
      ],
      roller: DiceRoller(seed),
      sceneId: 'vault',
      flags: {'knows-thrall', 'suspicious'},
    );

void main() {
  group('constructing', () {
    test('needs at least one actor', () {
      expect(
        () => GameSession(
          adventure: loadQuietWake(),
          actors: const [],
          roller: DiceRoller(1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate actor ids', () {
      expect(
        () => GameSession(
          adventure: loadQuietWake(),
          actors: [
            SessionActor(id: 'a', character: loadKorash()),
            SessionActor(id: 'a', character: loadSela()),
          ],
          roller: DiceRoller(1),
        ),
        throwsArgumentError,
      );
    });

    test('a solo session is a party of one', () {
      final session = newSession();
      expect(session.actors, hasLength(1));
      expect(session.primary.id, 'pc');
      expect(session.character.name, 'Korash Blackearth');
    });

    test('a party can be built from a roster', () {
      final party = Party(id: 'p', name: 'P');
      final store = CharacterStore(party: party, idGenerator: () => 'a');
      store.importDirect(loadKorashPayload());

      final actors = party.toActors();
      expect(actors, hasLength(1));
      expect(actors.single.id, 'a');
      expect(actors.single.name, 'Korash Blackearth');
    });
  });

  group('candidates', () {
    test('ranks everyone who can attempt a check, best first', () {
      final session = newPartySession();
      final ranked = session.candidatesFor('speak-widow');
      expect(ranked.map((c) => c.actor.id), ['korash', 'sela']);
      expect(ranked.first.stat.total, 13); // Korash Diplomacy
      expect(ranked.last.stat.total, 9); // Sela Diplomacy
    });

    test('leaves out an actor with no such statistic at all', () {
      // Sela has no Lore: Undead — that is absence, not untrained.
      final session = newPartySession();
      final ranked = session.candidatesFor('examine-body');
      expect(ranked, hasLength(1));
      expect(ranked.single.actor.id, 'korash');
    });

    test('the best at a check need not be the obvious character', () {
      // Both are untrained in Religion, so the rogue's Wisdom beats the
      // undertaker's. Emergent, and exactly the texture the design wants.
      final session = newPartySession();
      final ranked = session.candidatesFor('recite-rites');
      expect(ranked.first.actor.id, 'sela');
      expect(ranked.first.stat.total, 2);
      expect(ranked.last.actor.id, 'korash');
      expect(ranked.last.stat.total, 0);
    });

    test('is empty for an option with no check', () {
      final session = newPartySession();
      expect(session.candidatesFor('leave'), isEmpty);
    });

    test('is empty for an option that is not in this scene', () {
      final session = newPartySession();
      expect(session.candidatesFor('no-such-option'), isEmpty);
    });

    test('suggests the best candidate', () {
      final session = newPartySession();
      expect(session.suggestedActorFor('examine-body')!.actor.id, 'korash');
      expect(session.suggestedActorFor('recite-rites')!.actor.id, 'sela');
      expect(session.suggestedActorFor('leave'), isNull);
    });
  });

  group('who rolls', () {
    test('without a named actor, the best one rolls', () {
      final session = newPartySession(seed: 7);
      final event = session.choose('recite-rites');
      expect(event.actorId, 'sela');
      expect(event.check!.modifier, 2);
    });

    test('a named actor rolls instead, even when worse', () {
      final session = newPartySession(seed: 7);
      final event = session.choose('recite-rites', actorId: 'korash');
      expect(event.actorId, 'korash');
      expect(event.actorName, 'Korash Blackearth');
      expect(event.check!.modifier, 0);
    });

    test('refuses an actor who has no such statistic', () {
      final session = newPartySession();
      expect(() => session.choose('examine-body', actorId: 'sela'),
          throwsA(isA<InvalidChoiceException>()));
    });

    test('refuses an actor who is not in the session', () {
      final session = newPartySession();
      expect(() => session.choose('examine-body', actorId: 'nobody'),
          throwsA(isA<InvalidChoiceException>()));
    });

    test('an option with no check records the primary actor', () {
      final session = newPartySession();
      final event = session.choose('leave');
      expect(event.check, isNull);
      expect(event.actorId, 'korash');
    });
  });

  group('gates with a party', () {
    test('an option opens when any one actor satisfies it', () {
      // Only Korash is an expert in Lore: Undead, but the option is offered.
      final session = vaultSession();
      expect(session.availableOptions().map((o) => o.id), contains('command'));
    });

    test('but only that actor may take it', () {
      final session = vaultSession();
      expect(session.choose('command', actorId: 'korash').actorId, 'korash');

      final another = vaultSession();
      expect(() => another.choose('command', actorId: 'sela'),
          throwsA(isA<InvalidChoiceException>()));
    });

    test('a gated option only ranks actors who pass the gate', () {
      final session = vaultSession();
      final ranked = session.candidatesFor('command');
      expect(ranked.map((c) => c.actor.id), ['korash']);
    });
  });

  group('replay with a party', () {
    test('a restored party session rolls what the original would have', () {
      final original = newPartySession(seed: 5);
      original.choose('examine-body');

      final resumed = GameSession.restore(
        adventure: loadQuietWake(),
        actors: [
          SessionActor(id: 'korash', character: loadKorash()),
          SessionActor(id: 'sela', character: loadSela()),
        ],
        snapshot: original.snapshot(),
      );

      expect(resumed.choose('recite-rites').check!.dieRoll,
          original.choose('recite-rites').check!.dieRoll);
    });

    test('the log records who acted, not only what happened', () {
      final session = newPartySession(seed: 3);
      session.choose('recite-rites');
      session.choose('examine-body');
      expect(session.log.map((e) => e.actorId), ['sela', 'korash']);
    });
  });
}
