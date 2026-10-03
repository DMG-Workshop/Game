import 'dart:io';

import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

void main() {
  test('the sample is a level 5 fighter, as Pathbuilder would export him', () {
    final result = const PathbuilderImporter()
        .importJson(File('assets/characters/torvin.json').readAsStringSync());
    expect(result.report.warnings, isEmpty);
    final c = result.character;
    expect(c.name, 'Torvin Ashgrove');
    expect(c.className, 'Fighter');
    expect(c.level, 5);
    expect(c.spellcasting, isEmpty);

    final s = DerivedStats(c);
    expect(s.maxHp, 78,
        reason: '8 human + (10 fighter + 3 Con + 1 Toughness) x 5');
    expect(s.armorClass, 23, reason: '10 + trained 7 + full plate 6');
    expect(s.perception.total, 11, reason: 'expert 9 + Wisdom 2');
    final sword = c.weapons.single;
    expect(sword.display, '+1 Striking Longsword');
    expect(sword.attackBonus, 16, reason: 'master 11 + Strength 4 + 1');
    expect(sword.damageFormula, '2d8+4');
  });
}
