import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

void main() {
  group('parsing', () {
    test('reads dice with a bonus', () {
      final d = DamageExpression.parse('2d10+4');
      expect(d.diceCount, 2);
      expect(d.dieSize, 10);
      expect(d.flatBonus, 4);
      expect(d.toString(), '2d10+4');
    });

    test('reads dice alone', () {
      final d = DamageExpression.parse('1d6');
      expect(d.diceCount, 1);
      expect(d.dieSize, 6);
      expect(d.flatBonus, 0);
      expect(d.toString(), '1d6');
    });

    test('reads a flat number', () {
      final d = DamageExpression.parse('7');
      expect(d.diceCount, 0);
      expect(d.flatBonus, 7);
      expect(d.toString(), '7');
    });

    test('reads a negative modifier', () {
      final d = DamageExpression.parse('1d4-1');
      expect(d.flatBonus, -1);
      expect(d.minimum, 0);
    });

    test('tolerates whitespace', () {
      expect(DamageExpression.parse(' 3 d 8 + 2 '),
          DamageExpression.parse('3d8+2'));
    });

    test('rejects nonsense rather than guessing', () {
      expect(DamageExpression.tryParse('a lot'), isNull);
      expect(DamageExpression.tryParse(''), isNull);
      expect(DamageExpression.tryParse('d'), isNull);
      expect(DamageExpression.tryParse('2d'), isNull);
      expect(() => DamageExpression.parse('nope'), throwsFormatException);
    });

    test('rejects a die larger than the roller supports', () {
      expect(DamageExpression.tryParse('1d99999'), isNull);
    });
  });

  group('bounds', () {
    test('knows its range and average', () {
      final d = DamageExpression.parse('2d10+4');
      expect(d.minimum, 6); // 1+1+4
      expect(d.maximum, 24); // 10+10+4
      expect(d.average, 15); // 5.5 + 5.5 + 4
    });

    test('a flat expression has no spread', () {
      final d = DamageExpression.parse('5');
      expect(d.minimum, 5);
      expect(d.maximum, 5);
      expect(d.average, 5);
    });
  });

  group('rolling', () {
    test('stays within its own bounds', () {
      final d = DamageExpression.parse('2d10+4');
      final roller = DiceRoller(7);
      for (var i = 0; i < 2000; i++) {
        expect(d.roll(roller), inInclusiveRange(d.minimum, d.maximum));
      }
    });

    test('is reproducible for a given seed', () {
      final d = DamageExpression.parse('3d6+2');
      expect(d.roll(DiceRoller(42)), d.roll(DiceRoller(42)));
    });

    test('never returns less than zero', () {
      // A penalty larger than the dice should not heal the target.
      final d = DamageExpression.parse('1d4-10');
      final roller = DiceRoller(1);
      for (var i = 0; i < 200; i++) {
        expect(d.roll(roller), 0);
      }
    });

    test('a critical doubles the whole result, not the dice', () {
      // Pathfinder doubles the total. Rolling twice the dice would give a
      // different distribution, and the rules are explicit about which.
      final d = DamageExpression.parse('2d10+4');
      final normal = d.roll(DiceRoller(99));
      final critical = d.rollCritical(DiceRoller(99));
      expect(critical, normal * 2);
    });
  });

  group('a detailed roll', () {
    test('keeps every die and adds up to what roll() gives', () {
      final d = DamageExpression.parse('3d6+2');
      for (var seed = 0; seed < 50; seed++) {
        final detailed = d.rollDetailed(DiceRoller(seed));
        expect(detailed.dice, hasLength(3));
        expect(detailed.total, d.roll(DiceRoller(seed)));
        expect(detailed.total, detailed.dice.reduce((a, b) => a + b) + 2);
      }
    });

    test('takes exactly the dice roll() takes, so a seed replays the same', () {
      final a = DiceRoller(11);
      final b = DiceRoller(11);
      DamageExpression.parse('4d8+1').roll(a);
      DamageExpression.parse('4d8+1').rollDetailed(b);
      expect(a.state, b.state);
    });

    test('a critical is the same dice, doubled', () {
      final d = DamageExpression.parse('2d10+4');
      final crit = d.rollDetailed(DiceRoller(99), critical: true);
      expect(crit.dice, d.rollDetailed(DiceRoller(99)).dice);
      expect(crit.total, crit.base * 2);
      expect(crit.total, d.rollCritical(DiceRoller(99)));
    });

    test('reads the way a player would check it', () {
      final roll = DamageRoll(
        expression: DamageExpression.parse('2d10+4'),
        dice: const [7, 3],
      );
      expect(roll.toString(), '2d10+4 (7+3+4) = 14');
      expect(
        DamageRoll(
          expression: DamageExpression.parse('2d10+4'),
          dice: const [7, 3],
          critical: true,
        ).toString(),
        '2d10+4 (7+3+4) = 14, doubled to 28',
      );
      expect(
        DamageRoll(expression: DamageExpression.parse('1d4-1'), dice: const [3])
            .toString(),
        '1d4-1 (3-1) = 2',
      );
      expect(
        DamageRoll(
            expression: DamageExpression.parse('2d6'),
            dice: const [1, 6]).toString(),
        '2d6 (1+6) = 7',
      );
      expect(
        DamageRoll(expression: DamageExpression.parse('5'), dice: const [])
            .toString(),
        '5',
      );
    });

    test('is floored at zero like any other damage', () {
      final roll = DamageRoll(
        expression: DamageExpression.parse('1d4-10'),
        dice: const [2],
      );
      expect(roll.total, 0);
      expect(roll.toString(), '1d4-10 (2-10) = 0');
    });
  });

  test('value equality', () {
    expect(DamageExpression.parse('2d6+1'), DamageExpression.parse('2d6+1'));
    expect(DamageExpression.parse('2d6+1').hashCode,
        DamageExpression.parse('2d6+1').hashCode);
    expect(DamageExpression.parse('2d6+1'),
        isNot(DamageExpression.parse('2d6+2')));
  });
}
