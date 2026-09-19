import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

void main() {
  group('determinism', () {
    test('the same seed produces the same sequence', () {
      final a = DiceRoller(12345);
      final b = DiceRoller(12345);
      final rollsA = [for (var i = 0; i < 200; i++) a.d20()];
      final rollsB = [for (var i = 0; i < 200; i++) b.d20()];
      expect(rollsA, rollsB);
    });

    test('different seeds diverge', () {
      final a = DiceRoller(1);
      final b = DiceRoller(2);
      final rollsA = [for (var i = 0; i < 50; i++) a.d20()];
      final rollsB = [for (var i = 0; i < 50; i++) b.d20()];
      expect(rollsA, isNot(rollsB));
    });

    test('state can be snapshotted and resumed mid-sequence', () {
      // This is what lets an async turn be suspended, synced, and continued
      // without changing any future roll.
      final original = DiceRoller(99);
      for (var i = 0; i < 17; i++) {
        original.d20();
      }
      final resumed = DiceRoller.fromState(original.state);

      final rest = [for (var i = 0; i < 40; i++) original.d20()];
      final replayed = [for (var i = 0; i < 40; i++) resumed.d20()];
      expect(replayed, rest);
    });

    test('negative seeds are accepted and stay deterministic', () {
      expect(
        [for (var i = 0; i < 20; i++) DiceRoller(-7).d20()].first,
        DiceRoller(-7).d20(),
      );
    });
  });

  group('cross-platform safety', () {
    test('worst-case arithmetic stays below 2^53', () {
      // Native Dart integers are 64-bit, but the web build backs them with
      // doubles that are only exact to 2^53. Exceeding this would make a
      // browser roll differently from a phone and break replay.
      const maxExactInteger = 9007199254740992; // 2^53
      final worstCase = (DiceRoller.modulus - 1) * DiceRoller.multiplier +
          DiceRoller.increment;
      expect(worstCase, lessThan(maxExactInteger));
    });

    test('state never leaves the 32-bit range', () {
      final roller = DiceRoller(2024);
      for (var i = 0; i < 5000; i++) {
        roller.d20();
        expect(roller.state, inInclusiveRange(0, DiceRoller.modulus - 1));
      }
    });
  });

  group('rolling', () {
    test('a d20 stays within 1..20', () {
      final roller = DiceRoller(7);
      for (var i = 0; i < 5000; i++) {
        expect(roller.d20(), inInclusiveRange(1, 20));
      }
    });

    test('every face of a d20 is reachable', () {
      final roller = DiceRoller(4242);
      final seen = <int>{};
      for (var i = 0; i < 5000; i++) {
        seen.add(roller.d20());
      }
      expect(seen.length, 20);
    });

    test('a d20 is not visibly biased', () {
      // Rejection sampling matters here: a plain modulo over a 16-bit window
      // would over-represent low faces, since 65536 is not a multiple of 20.
      final roller = DiceRoller(31337);
      final counts = List.filled(21, 0);
      const rolls = 40000;
      for (var i = 0; i < rolls; i++) {
        counts[roller.d20()]++;
      }
      const expected = rolls / 20; // 2000
      for (var face = 1; face <= 20; face++) {
        expect(counts[face], closeTo(expected, expected * 0.15),
            reason: 'face $face appeared ${counts[face]} times');
      }
    });

    test('rolls multiple dice and sums them', () {
      final roller = DiceRoller(5);
      final dice = roller.rollDice(3, 6);
      expect(dice.length, 3);
      for (final d in dice) {
        expect(d, inInclusiveRange(1, 6));
      }
      expect(DiceRoller(5).rollSum(3, 6), dice.fold(0, (a, b) => a + b));
    });

    test('a one-sided die always yields 1', () {
      final roller = DiceRoller(1);
      expect([for (var i = 0; i < 10; i++) roller.rollDie(1)], everyElement(1));
    });

    test('supports the largest allowed die', () {
      final roller = DiceRoller(8);
      expect(roller.rollDie(DiceRoller.maxSides),
          inInclusiveRange(1, DiceRoller.maxSides));
    });

    test('rejects invalid die sizes', () {
      final roller = DiceRoller(1);
      expect(() => roller.rollDie(0), throwsArgumentError);
      expect(() => roller.rollDie(-3), throwsArgumentError);
      // Above the 16-bit output window the rejection loop could never exit.
      expect(
          () => roller.rollDie(DiceRoller.maxSides + 1), throwsArgumentError);
    });

    test('rejects a negative dice count', () {
      expect(() => DiceRoller(1).rollDice(-1, 6), throwsArgumentError);
    });
  });
}
