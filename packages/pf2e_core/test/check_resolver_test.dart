import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'fixture_loader.dart';

/// Resolves without rolling, so the rules are exercised in isolation.
CheckOutcome at(int die, {int modifier = 0, int dc = 20}) =>
    CheckResolver.outcomeFor(dieRoll: die, modifier: modifier, dc: dc);

void main() {
  group('degrees from the total', () {
    test('meeting the DC succeeds', () {
      expect(at(10, modifier: 10).degree, DegreeOfSuccess.success);
    });

    test('missing the DC by one fails', () {
      expect(at(9, modifier: 10).degree, DegreeOfSuccess.failure);
    });

    test('beating the DC by exactly ten critically succeeds', () {
      expect(at(10, modifier: 20).degree, DegreeOfSuccess.criticalSuccess);
    });

    test('beating the DC by nine is an ordinary success', () {
      expect(at(9, modifier: 20).degree, DegreeOfSuccess.success);
    });

    test('missing the DC by exactly ten critically fails', () {
      expect(at(10, modifier: 0).degree, DegreeOfSuccess.criticalFailure);
    });

    test('missing the DC by nine is an ordinary failure', () {
      expect(at(11, modifier: 0).degree, DegreeOfSuccess.failure);
    });

    test('negative modifiers resolve correctly', () {
      expect(at(15, modifier: -5, dc: 10).degree, DegreeOfSuccess.success);
      expect(
          at(5, modifier: -5, dc: 10).degree, DegreeOfSuccess.criticalFailure);
    });
  });

  group('natural 20 and natural 1', () {
    test('a natural 20 improves the degree by one step', () {
      // Total 20 + 0 = 20 meets DC 20, which is a success; the natural 20
      // lifts it to a critical success.
      final outcome = at(20, modifier: 0, dc: 20);
      expect(outcome.degreeBeforeNatural, DegreeOfSuccess.success);
      expect(outcome.degree, DegreeOfSuccess.criticalSuccess);
      expect(outcome.wasShiftedByNatural, isTrue);
    });

    test('a natural 20 on a failing total is only a success', () {
      // This is the rule most often implemented wrong: a natural 20 shifts one
      // degree, it does not jump straight to a critical success.
      final outcome = at(20, modifier: 0, dc: 25);
      expect(outcome.total, 20);
      expect(outcome.degreeBeforeNatural, DegreeOfSuccess.failure);
      expect(outcome.degree, DegreeOfSuccess.success);
    });

    test('a natural 20 on a critically failing total is only a failure', () {
      final outcome = at(20, modifier: 0, dc: 45);
      expect(outcome.degreeBeforeNatural, DegreeOfSuccess.criticalFailure);
      expect(outcome.degree, DegreeOfSuccess.failure);
    });

    test('a natural 1 worsens the degree by one step', () {
      final outcome = at(1, modifier: 29, dc: 20);
      expect(outcome.total, 30);
      expect(outcome.degreeBeforeNatural, DegreeOfSuccess.criticalSuccess);
      expect(outcome.degree, DegreeOfSuccess.success);
    });

    test('a natural 1 on a succeeding total becomes a failure', () {
      final outcome = at(1, modifier: 20, dc: 20);
      expect(outcome.degreeBeforeNatural, DegreeOfSuccess.success);
      expect(outcome.degree, DegreeOfSuccess.failure);
    });

    test('shifts clamp at both ends', () {
      // Already critical, cannot improve or worsen further.
      final best = at(20, modifier: 100, dc: 20);
      expect(best.degree, DegreeOfSuccess.criticalSuccess);
      expect(best.wasShiftedByNatural, isFalse);

      final worst = at(1, modifier: -100, dc: 20);
      expect(worst.degree, DegreeOfSuccess.criticalFailure);
      expect(worst.wasShiftedByNatural, isFalse);
    });

    test('a roll of 2 through 19 is never shifted', () {
      for (var die = 2; die <= 19; die++) {
        expect(at(die, modifier: 5, dc: 15).wasShiftedByNatural, isFalse,
            reason: 'die $die should not shift');
      }
    });
  });

  group('outcome record', () {
    test('retains every input for replay and narration', () {
      final outcome = at(13, modifier: 7, dc: 18);
      expect(outcome.dieRoll, 13);
      expect(outcome.modifier, 7);
      expect(outcome.dc, 18);
      expect(outcome.total, 20);
      expect(outcome.margin, 2);
      expect(outcome.isNaturalTwenty, isFalse);
      expect(outcome.isNaturalOne, isFalse);
    });

    test('reports a negative margin on a miss', () {
      expect(at(3, modifier: 0, dc: 20).margin, -17);
    });

    test('renders a readable line', () {
      expect(at(13, modifier: 7, dc: 18).toString(),
          'Check: d20(13) +7 = 20 vs DC 18 -> Success');
      expect(at(20, modifier: 0, dc: 35).toString(), contains('natural 20'));
    });

    test('rejects an impossible die face', () {
      expect(() => at(0), throwsArgumentError);
      expect(() => at(21), throwsArgumentError);
    });
  });

  group('degree helpers', () {
    test('classifies success and criticality', () {
      expect(DegreeOfSuccess.criticalSuccess.isSuccess, isTrue);
      expect(DegreeOfSuccess.success.isSuccess, isTrue);
      expect(DegreeOfSuccess.failure.isSuccess, isFalse);
      expect(DegreeOfSuccess.criticalFailure.isFailure, isTrue);
      expect(DegreeOfSuccess.success.isCritical, isFalse);
      expect(DegreeOfSuccess.criticalFailure.isCritical, isTrue);
    });

    test('shifts by arbitrary steps with clamping', () {
      expect(DegreeOfSuccess.failure.shiftedBy(2),
          DegreeOfSuccess.criticalSuccess);
      expect(DegreeOfSuccess.failure.shiftedBy(99),
          DegreeOfSuccess.criticalSuccess);
      expect(DegreeOfSuccess.success.shiftedBy(-99),
          DegreeOfSuccess.criticalFailure);
      expect(DegreeOfSuccess.success.shiftedBy(0), DegreeOfSuccess.success);
    });
  });

  group('rolling against a character', () {
    test('resolves a statistic derived from an import', () {
      final korash = loadKorash().character;
      final stats = DerivedStats(korash);
      final resolver = CheckResolver(DiceRoller(2024));

      final deception =
          resolver.resolveStat(stats.skill(CoreSkill.deception)!, dc: 20);
      expect(deception.label, 'Deception');
      expect(deception.modifier, 13);
      expect(deception.total, deception.dieRoll + 13);
    });

    test('an untrained statistic carries its weaker modifier', () {
      final stats = DerivedStats(loadKorash().character);
      final resolver = CheckResolver(DiceRoller(11));
      // Korash knows the dead, not the divine: Lore: Religion is +12 while
      // the Religion skill itself is untrained at +0.
      expect(
          resolver.resolveStat(stats.lore('Religion')!, dc: 20).modifier, 12);
      expect(
          resolver
              .resolveStat(stats.skill(CoreSkill.religion)!, dc: 20)
              .modifier,
          0);
    });

    test('is reproducible for a given seed', () {
      final stats = DerivedStats(loadKorash().character);
      CheckOutcome run() => CheckResolver(DiceRoller(777))
          .resolveStat(stats.skill(CoreSkill.athletics)!, dc: 18);
      expect(run().dieRoll, run().dieRoll);
      expect(run().degree, run().degree);
    });
  });
}
