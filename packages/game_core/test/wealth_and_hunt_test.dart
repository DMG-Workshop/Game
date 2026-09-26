import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;

SessionActor _korash() => SessionActor(id: 'korash', character: loadKorash());

/// A session whose purse holds [gold], and nothing else.
WorldSession _worth(int gold, {int seed = 3, String room = 'MH_001_Square'}) =>
    WorldSession(
      campaign: _campaign,
      actors: [_korash()],
      roller: DiceRoller(seed),
      roomId: room,
      inventory: PartyInventory(gear: _campaign.gear, coin: gold * 100),
    );

WorldSession _restored(WorldSession world) => WorldSession.restore(
      campaign: _campaign,
      actors: world.actors,
      snapshot:
          jsonDecode(jsonEncode(world.snapshot())) as Map<String, Object?>,
    );

/// Walks between the square and the forge until something finds the party,
/// returning the move that brought it, or null if nothing did.
MoveResult? _walkUntilHunted(WorldSession world, {int limit = 2000}) {
  for (var i = 0; i < limit; i++) {
    final result =
        world.move(world.roomId == 'MH_001_Square' ? 'west' : 'east');
    if (result.hunt != null) return result;
  }
  return null;
}

/// Plays a fight out by always striking the nearest thing.
EncounterSession _fightOut(EncounterSession fight) {
  var guard = 0;
  while (!fight.isOver && guard++ < 500) {
    if (fight.isPartyTurn) {
      final targets = fight.targetsInReach();
      if (targets.isEmpty) {
        fight.stride();
      } else {
        fight.strike(targets.first.id);
      }
      if (fight.actionsLeft == 0 && !fight.isOver) fight.endTurn();
    } else {
      fight.endTurn();
    }
  }
  return fight;
}

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  group('what a party is expected to be worth', () {
    test("is Pathfinder's character wealth, per character", () {
      expect(characterWealthGold, hasLength(20));
      expect(expectedWealth(level: 1, partySize: 1), 1500);
      expect(expectedWealth(level: 6, partySize: 1), 45000);
      expect(expectedWealth(level: 6, partySize: 4), 180000);
      expect(expectedWealth(level: 20, partySize: 1), 11200000);
    });

    test('rises every level', () {
      for (var i = 1; i < characterWealthGold.length; i++) {
        expect(characterWealthGold[i], greaterThan(characterWealthGold[i - 1]));
      }
    });

    test('reads levels off the end of the table as the nearest end', () {
      expect(expectedWealth(level: 0, partySize: 1),
          expectedWealth(level: 1, partySize: 1));
      expect(expectedWealth(level: 25, partySize: 1),
          expectedWealth(level: 20, partySize: 1));
    });
  });

  group('wealth', () {
    test('is coin and gear together, gear at what it costs', () {
      final world = _worth(100);
      world.inventory
        ..add('w_029_drovers_goad')
        ..add('w_029_drovers_goad');
      final goad = _campaign.gear.byId('w_029_drovers_goad')!;
      expect(world.wealth.coin, 10000);
      expect(world.wealth.gear, goad.price * 2);
      expect(world.wealth.total, 10000 + goad.price * 2);
    });

    test('is measured against a party of its size and level', () {
      final world = _worth(450);
      expect(world.wealth.expected, 45000);
      expect(world.wealth.percentOfExpected, 100);
    });

    test('knows what each character has on them', () {
      final world = _worth(0);
      world.inventory.add('w_029_drovers_goad');
      world.equip('goad');
      expect(world.inventory.valueOn('korash'),
          _campaign.gear.byId('w_029_drovers_goad')!.price);
      expect(world.inventory.valueOn('nobody'), 0);
    });

    test('buying does not make a party poorer, only differently rich', () {
      final world = _worth(1000, room: 'MH_001_Square');
      final before = world.wealth.total;
      final bought = world.buy(world.wares().first.item.id);
      expect(world.wealth.total, before - bought.price + bought.item.price);
    });
  });

  group('the loot ledger', () {
    test('records a fight: its coin, and each thing found, by name', () {
      final world = WorldSession(
        campaign: _campaign,
        actors: [_korash()],
        roller: DiceRoller(3),
        roomId: 'WW_002_Deep',
      );
      final fight = _fightOut(world.beginEncounter());
      expect(fight.outcome, EncounterOutcome.victory);
      world.concludeEncounter(fight);

      final entries = world.ledger.entries;
      expect(entries.where((e) => e.kind == LootKind.coin).single.copper,
          fight.coinEarned);
      expect(entries.map((e) => e.source).toSet(), {fight.encounter.name});
      expect(entries.where((e) => e.kind == LootKind.item).map((e) => e.itemId),
          [for (final item in fight.loot) item.id]);
      expect(world.ledger.totalCopper,
          fight.coinEarned + fight.loot.fold(0, (s, i) => s + i.price));
    });

    test('records a reward under whoever paid it', () {
      final world = WorldSession(
        campaign: _campaign,
        actors: [_korash()],
        roller: DiceRoller(3),
        roomId: 'MH_002_GuardHall',
      );
      final opened = world.beginConversation('thorne')!;
      // The conversation as it would stand once Thorne has paid up.
      final paid = GameSession(
        adventure: opened.talk.adventure,
        actors: world.actors,
        roller: DiceRoller(1),
        sceneId: opened.talk.currentScene.id,
        flags: {...world.flags, 'thorne_paid_fifty'},
      );
      world.concludeConversation(paid);
      final entry = world.ledger.entries.single;
      expect(entry.source, 'Captain Thorne');
      expect(entry.copper, 5000);
      expect(entry.kind, LootKind.coin);
    });

    test('a quest reward is written down with the quest', () {
      final world = WorldSession(
        campaign: _campaign,
        actors: [_korash()],
        roller: DiceRoller(3),
        roomId: 'MH_001_Square',
        flags: {
          'wendel_lie_uncovered',
          'wendel_dealt_with',
        },
      );
      world.settleArcs();
      final entry = world.ledger.entries.single;
      expect(entry.source, 'The Liar at the Sparrow');
      expect(entry.copper, 2000);
    });

    test('survives a save, and a save from before it loads empty', () {
      final world = _worth(0, room: 'WW_002_Deep');
      world.concludeEncounter(_fightOut(world.beginEncounter()));
      final back = _restored(world);
      expect(back.ledger.entries.map((e) => e.toJson()),
          world.ledger.entries.map((e) => e.toJson()));

      final old = world.snapshot()..remove('ledger');
      final legacy = WorldSession.restore(
          campaign: _campaign, actors: world.actors, snapshot: old);
      expect(legacy.ledger.isEmpty, isTrue);
    });
  });

  group('elite and weak creatures', () {
    const base = Creature(
      id: 'c_test',
      name: 'Test Beast',
      level: 5,
      armorClass: 21,
      maxHp: 75,
      perception: 12,
      fortitude: 12,
      reflex: 9,
      will: 11,
      attacks: [CreatureAttack(name: 'bite', attackBonus: 15, damage: '2d8+7')],
    );

    test("elite is Pathfinder's: +2 across, more HP, a level up", () {
      final elite = base.elite();
      expect(elite.name, 'Elite Test Beast');
      expect(elite.level, 6);
      expect(elite.armorClass, 23);
      expect(elite.maxHp, 95, reason: 'level 5-19 gains 20');
      expect(elite.perception, 14);
      expect([elite.fortitude, elite.reflex, elite.will], [14, 11, 13]);
      expect(elite.attacks.single.attackBonus, 17);
      expect(elite.attacks.single.damage, '2d8+9');
      expect(elite.id, base.id, reason: 'drops still find it');
    });

    test('weak is the same in reverse', () {
      final weak = base.weak();
      expect(weak.level, 4);
      expect(weak.armorClass, 19);
      expect(weak.maxHp, 60, reason: 'level 3-5 loses 15');
      expect(weak.attacks.single.damage, '2d8+5');
    });

    test('the low end moves two levels, as the rules say', () {
      const zero = Creature(
          id: 'z', name: 'Z', level: 0, armorClass: 15, maxHp: 15, attacks: []);
      const one = Creature(
          id: 'o', name: 'O', level: 1, armorClass: 15, maxHp: 20, attacks: []);
      expect(zero.elite().level, 2);
      expect(one.weak().level, -1);
      expect(one.weak().maxHp, 10);
    });

    test('damage that would go below its dice reads correctly', () {
      const tiny = Creature(
        id: 't',
        name: 'T',
        level: 2,
        armorClass: 15,
        maxHp: 20,
        attacks: [CreatureAttack(name: 'nip', attackBonus: 5, damage: '1d4+1')],
      );
      expect(tiny.weak().attacks.single.damage, '1d4-1');
    });
  });

  group('threat', () {
    test('a lone creature for four characters, by threat', () {
      expect(Threat.low.loneCreatureOffset(4), 1);
      expect(Threat.moderate.loneCreatureOffset(4), 2);
      expect(Threat.severe.loneCreatureOffset(4), 3);
      expect(Threat.extreme.loneCreatureOffset(4), 4);
    });

    test('and for one, where the budget is far smaller', () {
      expect(Threat.low.loneCreatureOffset(1), -3);
      expect(Threat.moderate.loneCreatureOffset(1), -2);
      expect(Threat.severe.loneCreatureOffset(1), -1);
      expect(Threat.extreme.loneCreatureOffset(1), 0);
    });
  });

  group('notoriety', () {
    test('climbs with wealth', () {
      final hunts = _campaign.hunts;
      expect(hunts.tierFor(0).name, 'Unremarked');
      // A party at what it is expected to be worth has not been noticed:
      // a level 1 character arrives with exactly that much.
      expect(hunts.tierFor(100).name, 'Unremarked');
      expect(hunts.tierFor(124).name, 'Unremarked');
      expect(hunts.tierFor(125).name, 'Noticed');
      expect(hunts.tierFor(200).name, 'Marked');
      expect(hunts.tierFor(300).name, 'Hunted');
      expect(hunts.tierFor(5000).name, 'Infamous');
    });

    test('richer brings a higher-level hunter', () {
      // Korash is level 6 and alone, so is expected to be worth 450 gp.
      final levels = [
        for (final gold in [450, 600, 900, 1400, 2300])
          _worth(gold).notoriety.hunterLevel,
      ];
      expect(levels, [null, 3, 4, 5, 6]);
    });

    test('and so does a higher party level, at the same wealth', () {
      final low = Notoriety(
        wealth: const Wealth(coin: 0, gear: 0, expected: 1),
        tier: _campaign.hunts.tierFor(250),
        partyLevel: 3,
        partySize: 4,
      );
      final high = Notoriety(
        wealth: const Wealth(coin: 0, gear: 0, expected: 1),
        tier: _campaign.hunts.tierFor(250),
        partyLevel: 15,
        partySize: 4,
      );
      expect(low.hunterLevel, 5);
      expect(high.hunterLevel, 17);
    });
  });

  group('the roster', () {
    test('can send a hunter at every level from -1 to 24', () {
      final levels =
          _campaign.hunts.reachableLevels(_campaign.bestiary).keys.toSet();
      for (var level = -1; level <= 24; level++) {
        expect(levels, contains(level), reason: 'level $level');
      }
    });

    test('every hunter is in the bestiary and carries coin', () {
      for (final hunter in _campaign.hunts.hunters) {
        expect(_campaign.bestiary.creatureById(hunter.creatureId), isNotNull);
        expect(DamageExpression.tryParse(hunter.coin), isNotNull);
        expect(hunter.arrival, isNotEmpty);
      }
      expect(_campaign.survey().huntProblems, isEmpty);
    });

    test('sends a creature written at the level before an adjusted one', () {
      final chosen =
          _campaign.hunts.choose(6, _campaign.bestiary, DiceRoller(1))!;
      expect(chosen.creature.name, 'Gilt Harpy');
      expect(chosen.adjustment, isNull);
    });

    test('adjusts one to fill a level nobody is written at', () {
      for (var seed = 0; seed < 20; seed++) {
        final chosen =
            _campaign.hunts.choose(7, _campaign.bestiary, DiceRoller(seed))!;
        expect(chosen.creature.level, 7);
        expect(chosen.adjustment, isNotNull);
      }
    });

    test('the survey notices a gap in the roster', () {
      final gappy = HuntTable(
        tiers: _campaign.hunts.tiers,
        hunters: [
          for (final h in _campaign.hunts.hunters)
            if (h.creatureId != 'c_hunt_ash_ogre') h,
        ],
      );
      final problems = gappy.problems(_campaign.bestiary,
          levels: [for (var l = 1; l <= 20; l++) l]);
      // Its neighbours, adjusted, still cover 9 and 11; 10 is nobody's.
      expect(problems.single, 'No hunter can be sent at level 10');
    });

    test('refuses a hunter with no coin', () {
      expect(
        () => const CampaignLoader()
            .readHunts('{"hunters": [{"creature": "c_hunt_copper_rat"}]}'),
        throwsA(isA<CampaignFormatException>()),
      );
    });
  });

  group('being hunted', () {
    test('a party worth no more than expected is never found', () {
      final world = _worth(450);
      expect(_walkUntilHunted(world, limit: 500), isNull);
      expect(world.pursuer, isNull);
    });

    test('a rich party is found, by something of the level its wealth earned',
        () {
      final world = _worth(1900);
      final found = _walkUntilHunted(world);
      expect(found, isNotNull);
      expect(found!.huntRoll!.die, lessThanOrEqualTo(found.huntRoll!.chance));
      expect(world.pursuer!.creature.level, world.notoriety.hunterLevel);
      expect(found.flagsSet, contains('hunted_first'));
    });

    test('nothing finds them within a few steps of the last time', () {
      final world = _worth(5000);
      for (var i = 0; i < _campaign.hunts.restSteps; i++) {
        final step = world.move(i.isEven ? 'west' : 'east');
        expect(step.hunt, isNull);
        expect(step.huntRoll, isNull);
      }
    });

    test('the hunter will not be walked away from', () {
      final world = _worth(1900);
      _walkUntilHunted(world);
      expect(() => world.move('east'), throwsA(isA<InvalidMoveException>()));
      expect(() => world.move('west'), throwsA(isA<InvalidMoveException>()));
    });

    test('is rolled on dice of its own, and changes no other roll', () {
      final rich = _worth(5000);
      final poor = _worth(0);
      final found = _walkUntilHunted(rich)!;
      for (var i = 0; i < rich.snapshotSteps; i++) {
        poor.move(poor.roomId == 'MH_001_Square' ? 'west' : 'east');
      }
      expect(found.hunt, isNotNull);
      expect(rich.snapshot()['rollerState'], poor.snapshot()['rollerState']);
      expect((rich.snapshot()['road'] as Map)['dice'],
          (poor.snapshot()['road'] as Map)['dice']);
    });

    test('beating a hunter pays like a fight, and counts', () {
      for (var seed = 1; seed < 40; seed++) {
        // Noticed: a low threat, so Korash should have the better of it.
        final world = _worth(600, seed: seed);
        if (_walkUntilHunted(world) == null) continue;
        final fight = _fightOut(world.beginEncounter());
        if (fight.outcome != EncounterOutcome.victory) continue;

        final coin = world.inventory.coin;
        final set = world.concludeEncounter(fight);
        expect(set, contains('hunt_survived_1'));
        expect(world.huntsSurvived, 1);
        expect(world.inventory.coin, coin + fight.coinEarned);
        expect(fight.coinEarned, greaterThan(0));
        expect(world.pursuer, isNull);
        expect(world.ledger.entries.first.source, startsWith('Hunted: '));
        expect(world.experience.xpOf('korash'), fight.xpEarned);
        return;
      }
      fail('Korash never beat a low-threat hunter in 40 seeds');
    });

    test('losing to one costs part of the purse', () {
      final world = _worth(5000);
      _walkUntilHunted(world);
      final fight = world.beginEncounter();
      var guard = 0;
      while (!fight.isOver && guard++ < 500) {
        fight.endTurn(); // standing there
      }
      expect(fight.outcome, EncounterOutcome.defeat);
      final before = world.inventory.coin;
      world.concludeEncounter(fight);
      expect(world.inventory.coin,
          before - before * _campaign.hunts.robPercent ~/ 100);
      expect(world.pursuer, isNull);
      expect(world.huntsSurvived, 0);
    });

    test('fleeing loses it, and pays nothing', () {
      final world = _worth(5000);
      _walkUntilHunted(world);
      final fight = world.beginEncounter()..flee();
      final coin = world.inventory.coin;
      expect(world.concludeEncounter(fight), isEmpty);
      expect(world.inventory.coin, coin);
      expect(world.pursuer, isNull);
      world.move(world.roomId == 'MH_001_Square' ? 'west' : 'east');
    });

    test('a hunter waiting when the game is saved is waiting when it loads',
        () {
      final world = _worth(5000);
      _walkUntilHunted(world);
      final back = _restored(world);
      expect(back.pursuer!.creature.name, world.pursuer!.creature.name);
      expect(back.pursuer!.creature.level, world.pursuer!.creature.level);
      expect(back.availableEncounters().first.id,
          world.availableEncounters().first.id);
      expect(back.snapshot()['hunt'], world.snapshot()['hunt']);
    });

    test('the arc conditions hunting sets are ones it can set', () {
      expect(_campaign.hunts.producesFlag('hunted_first'), isTrue);
      expect(_campaign.hunts.producesFlag('hunt_survived_3'), isTrue);
      expect(_campaign.hunts.producesFlag('hunt_survived_0'), isFalse);
      expect(HuntTable().producesFlag('hunted_first'), isFalse);
    });
  });
}

extension on WorldSession {
  int get snapshotSteps => (snapshot()['road'] as Map)['steps'] as int;
}
