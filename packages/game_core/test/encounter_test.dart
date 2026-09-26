import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;

ImportedCharacter _korash() => const PathbuilderImporter()
    .importJson(
        File('../pf2e_core/test/fixtures/korash.json').readAsStringSync())
    .character;

List<SessionActor> _party() =>
    [SessionActor(id: 'korash', character: _korash())];

/// A harmless creature, so a fight can be won without fifty rolls.
const _straw = Creature(
  id: 'c_straw',
  name: 'Straw Dummy',
  level: -1,
  armorClass: 5,
  maxHp: 1,
  perception: -5,
  attacks: [
    CreatureAttack(name: 'flop', attackBonus: -10, damage: '1'),
  ],
);

/// A creature that cannot be hurt quickly, for testing turn structure.
const _wall = Creature(
  id: 'c_wall',
  name: 'Standing Stone',
  level: 10,
  armorClass: 50,
  maxHp: 500,
  perception: -5,
  attacks: [
    CreatureAttack(name: 'nothing', attackBonus: -20, damage: '1'),
  ],
);

EncounterSession fight({
  required Encounter encounter,
  List<Creature> creatures = const [_straw],
  int seed = 1,
  GearTable? gear,
}) =>
    EncounterSession(
      encounter: encounter,
      bestiary: Bestiary(creatures: creatures, encounters: [encounter]),
      actors: _party(),
      roller: DiceRoller(seed),
      gear: gear,
    );

/// A table where the straw dummy carries one certainty and one long shot.
GearTable _lootTable() => GearTable(const [
      GearItem(
        id: 'i_certain',
        name: 'Certain Thing',
        level: 1,
        type: 'weapon',
        description: 'Always on it.',
        rarity: ItemRarity.unique,
        drops: [DropSource(creatureId: 'c_straw', chance: 100)],
      ),
      GearItem(
        id: 'i_longshot',
        name: 'Long Shot',
        level: 1,
        type: 'weapon',
        description: 'Hardly ever on it.',
        rarity: ItemRarity.rare,
        drops: [DropSource(creatureId: 'c_straw', chance: 1)],
      ),
    ]);

/// Plays a winnable fight to its end. The dummy strikes at -10 against AC 25,
/// so the only question is how many swings it takes.
EncounterSession _playOut(EncounterSession f) {
  var guard = 0;
  while (!f.isOver && guard++ < 100) {
    if (f.isPartyTurn) {
      final targets = f.targetsInReach();
      if (targets.isEmpty) {
        f.stride();
      } else {
        f.strike(targets.first.id);
      }
      if (f.actionsLeft == 0 && !f.isOver) f.endTurn();
    } else {
      f.endTurn();
    }
  }
  return f;
}

const _adjacent = Encounter(
  id: 'e_test',
  location: 'anywhere',
  name: 'Test',
  creatureIds: ['c_straw'],
  startZone: 'engaged',
  victoryFlags: ['test_won'],
);

/// A fight that cannot be finished quickly, for exercising turn structure.
const _standoff = Encounter(
  id: 'e_standoff',
  location: 'anywhere',
  name: 'Standoff',
  creatureIds: ['c_wall'],
  startZone: 'engaged',
);

/// The same, starting out of reach.
const _distant = Encounter(
  id: 'e_distant',
  location: 'anywhere',
  name: 'Distant',
  creatureIds: ['c_wall'],
  startZone: 'far',
);

void main() {
  group('setting up', () {
    test('needs a party', () {
      expect(
        () => EncounterSession(
          encounter: _adjacent,
          bestiary: Bestiary(creatures: const [_straw]),
          actors: const [],
          roller: DiceRoller(1),
        ),
        throwsArgumentError,
      );
    });

    test('refuses an encounter naming a creature that does not exist', () {
      expect(
        () => EncounterSession(
          encounter: const Encounter(
            id: 'e',
            location: 'anywhere',
            name: 'T',
            creatureIds: ['c_nobody'],
          ),
          bestiary: Bestiary(creatures: const [_straw]),
          actors: _party(),
          roller: DiceRoller(1),
        ),
        throwsArgumentError,
      );
    });

    test('gives each copy of a creature its own identity', () {
      final f = fight(
        encounter: const Encounter(
          id: 'e',
          location: 'anywhere',
          name: 'T',
          creatureIds: ['c_straw', 'c_straw'],
          startZone: 'engaged',
        ),
      );
      // Order here is initiative, not construction, so identity is what
      // matters rather than sequence.
      expect(f.enemies.map((e) => e.id).toSet(), {'c_straw_1', 'c_straw_2'});
    });

    test('builds the party from their imported sheets', () {
      final f = fight(encounter: _adjacent);
      final korash = f.party.single;
      // The same numbers the character sheet shows.
      expect(korash.armorClass, 25);
      expect(korash.maxHp, 70);
      expect(korash.attackBonus, 15);
      expect(korash.damage.toString(), '2d10+4');
    });
  });

  group('striking', () {
    test('a hit deals damage and a kill ends the fight', () {
      final f = fight(encounter: _adjacent, seed: 3);
      // The straw dummy has AC 5 and 1 HP; any hit finishes it.
      final result = f.strike('c_straw_1');
      expect(result.isHit, isTrue);
      expect(result.targetDropped, isTrue);
      expect(f.outcome, EncounterOutcome.victory);
      expect(f.victoryFlags, ['test_won']);
    });

    test('the multiple attack penalty grows within a turn', () {
      final f = fight(encounter: _standoff, creatures: const [_wall]);
      expect(f.strike('c_wall_1').penalty, 0);
      expect(f.strike('c_wall_1').penalty, -5);
      expect(f.strike('c_wall_1').penalty, -10);
    });

    test('the penalty resets next turn', () {
      final f = fight(encounter: _standoff, creatures: const [_wall]);
      f.strike('c_wall_1');
      f.strike('c_wall_1');
      f.endTurn();
      expect(f.current.nextAttackPenalty, 0);
    });

    test('three actions a turn, and no more', () {
      final f = fight(encounter: _standoff, creatures: const [_wall]);
      expect(f.actionsLeft, 3);
      f.strike('c_wall_1');
      f.strike('c_wall_1');
      f.strike('c_wall_1');
      expect(f.actionsLeft, 0);
      expect(
          () => f.strike('c_wall_1'), throwsA(isA<InvalidActionException>()));
    });

    test('refuses a target out of reach', () {
      final f = fight(encounter: _distant, creatures: const [_wall]);
      expect(
        () => f.strike('c_wall_1'),
        throwsA(isA<InvalidActionException>()
            .having((e) => e.message, 'message', contains('too far'))),
      );
    });

    test('refuses a target that is not there', () {
      final f = fight(encounter: _adjacent);
      expect(
          () => f.strike('c_nobody'), throwsA(isA<InvalidActionException>()));
    });
  });

  group('position', () {
    test('striding closes one zone at a time', () {
      final f = fight(encounter: _distant, creatures: const [_wall]);
      expect(f.targetsInReach(), isEmpty);
      expect(f.stride().zone, 'near');
      expect(f.stride().zone, 'far');
      // Now level with the stone, which was standing at far all along.
      expect(f.targetsInReach(), isNotEmpty);
    });

    test('closing on an enemy already level with you does not step away', () {
      // The edge of the map used to hide this: the clamp stopped the step.
      // In the middle zone, "closing" on someone at arm's length walked the
      // party a zone backwards, out of their own reach.
      final f = fight(
        encounter: const Encounter(
          id: 'e_middle',
          location: 'anywhere',
          name: 'Middle',
          creatureIds: ['c_wall'],
          startZone: 'near',
        ),
        creatures: const [_wall],
      );
      expect(f.stride().zone, 'near');
      expect(f.targetsInReach(), isNotEmpty);
      expect(
        () => f.stride(),
        throwsA(isA<InvalidActionException>()
            .having((e) => e.message, 'message', contains('as close'))),
      );
      expect(f.current.zoneIndex, 1, reason: 'still level with the stone');
      expect(f.actionsLeft, 2, reason: 'a refused step costs nothing');
    });

    test('cannot close past an enemy already in reach', () {
      final f = fight(encounter: _adjacent);
      expect(
        () => f.stride(),
        throwsA(isA<InvalidActionException>()
            .having((e) => e.message, 'message', contains('as close'))),
      );
    });
  });

  group('turn order', () {
    test('initiative is rolled and the order is stable', () {
      final a = fight(encounter: _adjacent, seed: 11);
      final b = fight(encounter: _adjacent, seed: 11);
      expect(a.combatants.map((c) => c.id), b.combatants.map((c) => c.id));
    });

    test('enemy turns resolve as a block', () {
      final f = fight(encounter: _standoff, creatures: const [_wall]);
      final round = f.round;
      f.endTurn();
      // Back to the party, a round later, with actions restored.
      expect(f.isPartyTurn, isTrue);
      expect(f.actionsLeft, 3);
      expect(f.round, greaterThan(round));
    });
  });

  group('ending', () {
    test('fleeing ends the fight without victory flags', () {
      final f = fight(encounter: _standoff, creatures: const [_wall]);
      f.flee();
      expect(f.outcome, EncounterOutcome.fled);
      expect(f.victoryFlags, isEmpty);
      expect(
          () => f.strike('c_wall_1'), throwsA(isA<InvalidActionException>()));
    });

    test('victory flags are only earned by winning', () {
      final f = fight(encounter: _adjacent, seed: 3);
      expect(f.victoryFlags, isEmpty);
      f.strike('c_straw_1');
      expect(f.outcome, EncounterOutcome.victory);
      expect(f.victoryFlags, ['test_won']);
    });
  });

  group('loot', () {
    test('a fight with no loot table drops nothing', () {
      final f = _playOut(fight(encounter: _adjacent, seed: 3));
      expect(f.outcome, EncounterOutcome.victory);
      expect(f.loot, isEmpty);
      expect(f.lootFlags, isEmpty);
    });

    test('a guaranteed drop is on every one of them', () {
      for (var seed = 1; seed <= 12; seed++) {
        final f = _playOut(
            fight(encounter: _adjacent, seed: seed, gear: _lootTable()));
        expect(f.outcome, EncounterOutcome.victory);
        expect(f.loot.map((i) => i.id), contains('i_certain'),
            reason: 'seed $seed');
      }
    });

    test('a long shot stays a long shot', () {
      // One percent, so across forty fights it should turn up rarely or not
      // at all. A drop table that ignored its own chances would show here.
      var found = 0;
      for (var seed = 1; seed <= 40; seed++) {
        final f = _playOut(
            fight(encounter: _adjacent, seed: seed, gear: _lootTable()));
        if (f.loot.any((i) => i.id == 'i_longshot')) found++;
      }
      expect(found, lessThan(5));
    });

    test('two of the same creature is two chances, not two copies', () {
      final f = _playOut(fight(
        encounter: const Encounter(
          id: 'e',
          location: 'anywhere',
          name: 'T',
          creatureIds: ['c_straw', 'c_straw'],
          startZone: 'engaged',
        ),
        gear: _lootTable(),
      ));
      expect(f.outcome, EncounterOutcome.victory);
      expect(f.loot.where((i) => i.id == 'i_certain'), hasLength(1));
    });

    test('the same seed drops the same things', () {
      // Replayability: a phone and a browser must agree about what was on
      // the body, or a saved game is not the same game.
      final a =
          _playOut(fight(encounter: _adjacent, seed: 7, gear: _lootTable()));
      final b =
          _playOut(fight(encounter: _adjacent, seed: 7, gear: _lootTable()));
      expect(a.loot.map((i) => i.id), b.loot.map((i) => i.id));
    });

    test('reading the loot twice does not roll it again', () {
      final f =
          _playOut(fight(encounter: _adjacent, seed: 4, gear: _lootTable()));
      expect(
          f.loot.map((i) => i.id).toList(), f.loot.map((i) => i.id).toList());
    });

    test('nothing is carried off a fight that was not won', () {
      final f = fight(
          encounter: _standoff, creatures: const [_wall], gear: _lootTable());
      f.flee();
      expect(f.outcome, EncounterOutcome.fled);
      expect(f.loot, isEmpty);
    });

    test('loot is recorded as flags, like everything else', () {
      final f =
          _playOut(fight(encounter: _adjacent, seed: 3, gear: _lootTable()));
      expect(f.lootFlags, contains('loot_i_certain'));
    });
  });

  group('the real bosses', () {
    late Campaign campaign;
    setUpAll(() => campaign = loadShatteredSeals());

    test('every encounter names creatures that exist', () {
      expect(campaign.bestiary.missingCreatures, isEmpty);
    });

    test('every fight stands in a room that exists', () {
      expect(
          campaign.bestiary.misplacedIn(campaign.locations.rooms.keys.toSet()),
          isEmpty);
    });

    test('the Hollow Avatar waits until the doll is found', () {
      final avatar = campaign.bestiary.encounterById('e_hollow_grove')!;
      expect(avatar.isAvailable(const {}), isFalse);
      expect(avatar.isAvailable({'item_acquired_elaras_doll'}), isTrue);
    });

    test('Malachai waits until the mines are purged', () {
      final vex = campaign.bestiary.encounterById('e_ritual_chamber')!;
      expect(vex.isAvailable(const {}), isFalse);
      expect(vex.isAvailable({'item_destroyed_bloodstone_geode'}), isTrue);
    });

    test('a resolved fight does not happen twice', () {
      final avatar = campaign.bestiary.encounterById('e_hollow_grove')!;
      expect(
          avatar.isAvailable(
              {'item_acquired_elaras_doll', 'boss_defeated_hollow_avatar'}),
          isFalse);
    });

    test('the bosses set the flags their arcs wait on', () {
      expect(
          campaign.bestiary.victoryFlags,
          containsAll(
              ['boss_defeated_hollow_avatar', 'boss_defeated_malachai_vex']));
    });

    test('every creature has a usable damage expression', () {
      for (final creature in campaign.bestiary.creatures) {
        for (final attack in creature.attacks) {
          expect(DamageExpression.tryParse(attack.damage), isNotNull,
              reason: '${creature.name}: ${attack.name}');
        }
      }
    });

    test('a level 6 character alone loses to a level 8 boss', () {
      // Pathfinder budgets encounters for four characters, and this is the
      // point at which that stops being an abstract claim. The fight is not
      // mis-tuned; the party is.
      final avatar = campaign.bestiary.encounterById('e_hollow_grove')!;
      final f = EncounterSession(
        encounter: avatar,
        bestiary: campaign.bestiary,
        actors: _party(),
        roller: DiceRoller(5),
      );

      var guard = 0;
      while (!f.isOver && guard++ < 200) {
        if (f.isPartyTurn) {
          final targets = f.targetsInReach();
          if (targets.isEmpty) {
            f.stride();
          } else {
            f.strike(targets.first.id);
          }
          if (f.actionsLeft == 0 && !f.isOver) f.endTurn();
        } else {
          f.endTurn();
        }
      }
      expect(f.outcome, EncounterOutcome.defeat);
    });
  });
}
