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

  test('value equality', () {
    expect(DamageExpression.parse('2d6+1'), DamageExpression.parse('2d6+1'));
    expect(DamageExpression.parse('2d6+1').hashCode,
        DamageExpression.parse('2d6+1').hashCode);
    expect(DamageExpression.parse('2d6+1'),
        isNot(DamageExpression.parse('2d6+2')));
  });
}
