import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;
late SpellBook _spells;

SessionActor _korash() => SessionActor(id: 'korash', character: loadKorash());

WorldSession _world({String room = 'WW_002_Deep', int seed = 3}) =>
    WorldSession(
      campaign: _campaign,
      actors: [_korash()],
      roller: DiceRoller(seed),
      roomId: room,
      spells: _spells,
    );

void main() {
  setUpAll(() {
    _campaign = loadShatteredSeals();
    _spells = const CampaignLoader().readSpells(
        File('../../content/pf2e_remaster/spells.json').readAsStringSync());
  });

  group('the spell table', () {
    test('loads from the content package, apart from any campaign', () {
      expect(_spells.byName('Fireball'), isNotNull);
      expect(_spells.byName('  needle darts '), isNotNull);
      expect(_spells.byName('Wish'), isNull);
    });

    test('cantrips are cast at half the caster\'s level, rounded up', () {
      expect(cantripRank(1), 1);
      expect(cantripRank(6), 3);
      expect(cantripRank(7), 4);
      expect(cantripRank(20), 10);
    });

    test('heightening adds dice for each step above the spell\'s rank', () {
      final fireball = _spells.byName('Fireball')!;
      expect(fireball.damageAt(3).toString(), '6d6');
      expect(fireball.damageAt(5).toString(), '10d6');
      final darts = _spells.byName('Needle Darts')!;
      expect(darts.damageAt(1).toString(), '3d4');
      expect(darts.damageAt(3).toString(), '5d4');
      final daze = _spells.byName('Daze')!;
      expect(daze.damageAt(1).toString(), '1d6');
      expect(daze.damageAt(3).toString(), '2d6', reason: 'every two ranks');
      expect(daze.damageAt(4).toString(), '2d6');
    });

    test('refuses a spell rolled against nothing, or heightened oddly', () {
      const loader = CampaignLoader();
      expect(
        () => loader.readSpells('{"spells": [{"name": "X", "rank": 1, '
            '"defense": "luck", "damage": "1d6"}]}'),
        throwsA(isA<CampaignFormatException>()),
      );
      expect(
        () => loader.readSpells('{"spells": [{"name": "X", "rank": 1, '
            '"defense": "will", "damage": "1d6", '
            '"heighten": {"every": 1, "damage": "1d8"}}]}'),
        throwsA(isA<CampaignFormatException>()),
      );
    });
  });

  group('what a character can cast', () {
    test('comes from their own sheet: what they prepared, at what DC', () {
      final world = _world();
      final options = world.castOptions('korash');
      final fireball = options.firstWhere((o) => o.spell.name == 'Fireball');
      expect(fireball.rank, 3);
      expect(fireball.cost, CastCost.prepared);
      expect(fireball.left, 1, reason: 'prepared once');
      final magus = _korash()
          .stats
          .spellcasting
          .firstWhere((v) => v.entry.name == 'Magus');
      expect(fireball.dc, magus.dc);
      final darts = options.firstWhere((o) => o.spell.name == 'Needle Darts');
      expect(darts.cost, CastCost.cantrip);
      expect(darts.rank, 3);
      expect(darts.attackBonus, magus.attackBonus);
    });

    test('says which of their spells have no numbers yet', () {
      final missing = _world().spellsWithoutNumbers('korash');
      expect(missing, contains('Enfeeble'));
      expect(missing, isNot(contains('Fireball')));
    });

    test('without a spell table, nothing is on offer', () {
      final world = WorldSession(
        campaign: _campaign,
        actors: [_korash()],
        roller: DiceRoller(3),
        roomId: 'WW_002_Deep',
      );
      expect(world.castOptions('korash'), isEmpty);
    });
  });

  group('casting in a fight', () {
    test('a burst catches everyone in the zone, and each saves', () {
      final world = _world();
      final fight = world.beginEncounter();
      final result = fight.cast('fireball');
      final caught = result.hits.map((h) => h.target.name).toList();
      expect(caught, contains('Hollow Thrall'));
      // Korash is standing with them, so the burst has him too.
      expect(caught, contains('Korash Blackearth'));
      final rolled = result.damageRoll!.total;
      for (final hit in result.hits) {
        expect(
            hit.damage,
            switch (hit.check.degree) {
              DegreeOfSuccess.criticalSuccess => 0,
              DegreeOfSuccess.success => rolled ~/ 2,
              DegreeOfSuccess.failure => rolled,
              DegreeOfSuccess.criticalFailure => rolled * 2,
            });
      }
      expect(fight.actionsLeft, 1, reason: 'two actions');
    });

    test('a prepared spell is spent, and stays spent after the fight', () {
      final world = _world();
      final fight = world.beginEncounter()..cast('fireball');
      fight.endTurn();
      if (!fight.isOver) {
        expect(() => fight.cast('fireball'),
            throwsA(isA<InvalidActionException>()));
      }
      final fireball = world
          .castOptions('korash')
          .firstWhere((o) => o.spell.name == 'Fireball');
      expect(fireball.left, 0);
      expect(fireball.isAvailable, isFalse);
    });

    test('a night\'s rest prepares it again', () {
      final world = _world(room: 'MH_002_GuardHall');
      world.vitalsOf('korash').expended['Magus|3|Fireball'] = 1;
      expect(
          world
              .castOptions('korash')
              .firstWhere((o) => o.spell.name == 'Fireball')
              .left,
          0);
      world.rest();
      expect(
          world
              .castOptions('korash')
              .firstWhere((o) => o.spell.name == 'Fireball')
              .left,
          1);
    });

    test('cantrips never run out', () {
      final world = _world();
      final fight = world.beginEncounter();
      for (var turn = 0; turn < 3 && !fight.isOver; turn++) {
        if (fight.isPartyTurn) fight.cast('needle darts');
        if (!fight.isOver) fight.endTurn();
      }
      expect(
          world
              .castOptions('korash')
              .firstWhere((o) => o.spell.name == 'Needle Darts')
              .isAvailable,
          isTrue);
    });

    test('a spell attack counts toward the multiple attack penalty', () {
      final fight = _world().beginEncounter();
      final darts = fight.cast('needle darts');
      expect(darts.hits.single.check.label, contains('spell attack'));
      final next = fight.strike(fight.targetsInReach().first.id);
      expect(next.penalty, -5);
    });

    test('a spell attack is the caster\'s own number against AC', () {
      final fight = _world().beginEncounter();
      final result = fight.cast('needle darts');
      final hit = result.hits.single;
      expect(hit.check.modifier, result.option.attackBonus);
      expect(hit.check.dc, hit.target.armorClass);
      if (hit.check.degree.isSuccess) {
        expect(hit.damage, hit.damageRoll!.total);
      } else {
        expect(hit.damage, 0);
      }
    });

    test('is refused out of range, without the actions, or unknown', () {
      final world = _world(room: 'WW_002_Deep');
      final fight = world.beginEncounter();
      expect(() => fight.cast('wish'), throwsA(isA<InvalidActionException>()));
      fight.cast('needle darts'); // two actions, one left
      expect(() => fight.cast('daze'), throwsA(isA<InvalidActionException>()));
    });

    test('what a spell does is told like a strike', () {
      final world = _world();
      final fight = world.beginEncounter();
      final script = FightScript(fight);
      final result = fight.cast('fireball');
      final said = script.afterSpell(result);
      // Thralls are mindless: whatever they say, they say by doing.
      expect(said.every((l) => !l.isSpeech || l.speaker != 'Hollow Thrall'),
          isTrue);
    });

    test('what has been spent survives a save', () {
      final world = _world();
      world.vitalsOf('korash').expended['Magus|3|Fireball'] = 1;
      final back = WorldSession.restore(
        campaign: _campaign,
        actors: world.actors,
        snapshot:
            jsonDecode(jsonEncode(world.snapshot())) as Map<String, Object?>,
        spells: _spells,
      );
      expect(back.vitalsOf('korash').expended['Magus|3|Fireball'], 1);
    });
  });
}
