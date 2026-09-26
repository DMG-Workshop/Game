import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;

WorldSession _world(String room, {Set<String> flags = const {}}) =>
    WorldSession(
      campaign: _campaign,
      actors: [SessionActor(id: 'korash', character: loadKorash())],
      roller: DiceRoller(3),
      roomId: room,
      flags: flags,
    );

EncounterSession _fight(String encounterId, {int seed = 1}) => EncounterSession(
      encounter: _campaign.bestiary.encounterById(encounterId)!,
      bestiary: _campaign.bestiary,
      actors: [SessionActor(id: 'korash', character: loadKorash())],
      roller: DiceRoller(seed),
    );

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  group('coverage', () {
    test('nothing in the campaign happens with nothing said about it', () {
      expect(_campaign.survey().dialogueGaps, isEmpty);
    });

    test('every fight and every hunter has a whole scene', () {
      for (final e in _campaign.bestiary.encounters) {
        expect(e.scene, isNotNull, reason: e.id);
        expect(e.scene!.gaps(), isEmpty, reason: e.id);
      }
      for (final h in _campaign.hunts.hunters) {
        expect(h.scene!.gaps(), isEmpty, reason: h.creatureId);
      }
    });

    test('every creature has a voice, even the ones that cannot talk', () {
      for (final c in _campaign.bestiary.creatures) {
        expect(c.voice, isNotNull, reason: c.id);
        expect(c.voice!.gaps(), isEmpty, reason: c.id);
      }
      expect(_campaign.bestiary.creatureById('c_hollow_thrall')!.voice!.speaks,
          isFalse);
      expect(_campaign.bestiary.creatureById('c_malachai_vex')!.voice!.speaks,
          isTrue);
    });

    test('every room has something going on in it', () {
      for (final room in _campaign.locations.rooms.values) {
        expect(room.ambiance.length, greaterThanOrEqualTo(2), reason: room.id);
      }
    });

    test('the survey notices a fight nobody wrote words for', () {
      final report = Campaign(
        id: 'x',
        title: 'x',
        world: _campaign.world,
        locations: _campaign.locations,
        npcs: _campaign.npcs,
        gear: _campaign.gear,
        arcs: _campaign.arcs,
        bestiary: Bestiary(
          creatures: _campaign.bestiary.creatures,
          encounters: [
            ..._campaign.bestiary.encounters,
            const Encounter(
              id: 'e_silent',
              location: 'MH_001_Square',
              name: 'Silence',
              creatureIds: ['c_hollow_thrall'],
            ),
          ],
        ),
      ).survey();
      expect(report.dialogueGaps, contains('Silence (e_silent) has no scene'));
    });

    test('a line has one speaker, and a speaker it knows', () {
      expect(
        () => const CampaignLoader().readBestiary('''
          {"creatures": [], "encounters": [{"encounter_id": "e", "location": "r",
            "name": "n", "creatures": [], "scene": {"opening": [{"ghost": "boo"}]}}]}'''),
        throwsA(isA<CampaignFormatException>()),
      );
    });
  });

  group('a fight, told', () {
    test('the opening goes to whoever can talk on each side', () {
      final script = FightScript(_fight('e_mere_road_cutthroats'));
      final lines = script.opening();
      expect(lines.first.speaker, 'Covenant Cutthroat');
      expect(lines[1].speaker, 'Korash Blackearth');
      expect(lines.every((l) => l.isSpeech), isTrue);
    });

    test('the mindless do not speak: their lines are told', () {
      final script = FightScript(_fight('e_whisperwood_thralls'));
      final lines = script.opening();
      expect(lines.first.isSpeech, isFalse);
      expect(lines.last.speaker, 'Korash Blackearth');
    });

    test('one ambiance line a round, and not twice in a round', () {
      final script = FightScript(_fight('e_whisperwood_thralls'));
      final first = script.ambianceFor(1);
      expect(first, isNotNull);
      expect(script.ambianceFor(1), isNull);
      expect(script.ambianceFor(2)!.text, isNot(first!.text));
    });

    test(
        'a creature going down has its last word, and the first draws a '
        'reply', () {
      final fight = _fight('e_mere_road_cutthroats');
      final script = FightScript(fight);
      final victim = fight.enemies.first..hp = 0;
      final strike = StrikeResult(
        attacker: fight.party.single,
        target: victim,
        outcome: CheckResolver.outcomeFor(dieRoll: 15, modifier: 15, dc: 18),
        damage: 30,
        penalty: 0,
        targetDropped: true,
      );
      final said = script.after([strike]);
      expect(said.first.speaker, 'Covenant Cutthroat');
      expect(said.first.text, contains('Wendel'));
      expect(said.last.speaker, 'Korash Blackearth');
      expect(script.after([strike]), isEmpty, reason: 'once is enough');
    });

    test('the badly hurt say so, once', () {
      final fight = _fight('e_mere_road_cutthroats');
      final script = FightScript(fight);
      final hurt = fight.enemies.first..hp = 10;
      final strike = StrikeResult(
        attacker: fight.party.single,
        target: hurt,
        outcome: CheckResolver.outcomeFor(dieRoll: 15, modifier: 15, dc: 18),
        damage: 20,
        penalty: 0,
      );
      final said = script.after([strike]);
      expect(said.map((l) => l.text), contains(contains('paid enough')));
      expect(script.after([strike]), isEmpty);
    });

    test('a critical from them draws a taunt', () {
      final fight = _fight('e_ritual_chamber');
      final script = FightScript(fight);
      final malachai =
          fight.enemies.firstWhere((c) => c.name == 'Malachai Vex');
      final said = script.after([
        StrikeResult(
          attacker: malachai,
          target: fight.party.single,
          outcome: CheckResolver.outcomeFor(dieRoll: 20, modifier: 24, dc: 25),
          damage: 60,
          penalty: 0,
        ),
      ]);
      expect(said.single.speaker, 'Malachai Vex');
    });

    test('every way a fight ends has words', () {
      // Fled: the fight says so itself.
      final fled = _fight('e_hollow_grove')..flee();
      expect(FightScript(fled).closing(), isNotEmpty);

      // Won and lost: played out, one way and the other.
      final lost = _fight('e_hollow_grove', seed: 5);
      var guard = 0;
      while (!lost.isOver && guard++ < 500) {
        lost.endTurn();
      }
      expect(lost.outcome, EncounterOutcome.defeat);
      final defeat = FightScript(lost).closing();
      expect(defeat.single.speaker, 'The Hollow Avatar');

      final won = _fight('e_whisperwood_thralls');
      guard = 0;
      while (!won.isOver && guard++ < 500) {
        if (won.isPartyTurn) {
          final targets = won.targetsInReach();
          if (targets.isEmpty) {
            won.stride();
          } else {
            won.strike(targets.first.id);
          }
          if (won.actionsLeft == 0 && !won.isOver) won.endTurn();
        } else {
          won.endTurn();
        }
      }
      expect(won.outcome, EncounterOutcome.victory);
      final victory = FightScript(won).closing();
      expect(victory.last.speaker, 'Korash Blackearth');
    });

    test('saying things rolls no dice', () {
      final roller = DiceRoller(9);
      final fight = EncounterSession(
        encounter: _campaign.bestiary.encounterById('e_ritual_chamber')!,
        bestiary: _campaign.bestiary,
        actors: [SessionActor(id: 'korash', character: loadKorash())],
        roller: roller,
      );
      final before = roller.state;
      final script = FightScript(fight)..opening();
      script.ambianceFor(1);
      script.after(fight.openingStrikes);
      script.closing();
      expect(roller.state, before);
    });
  });

  group('everything else, said', () {
    test('rooms give out their ambiance a line at a time, in turn', () {
      final world = _world('MH_002_GuardHall');
      final lines = [for (var i = 0; i < 4; i++) world.roomAmbiance()];
      expect(lines.toSet().length, 3);
      expect(lines.first, lines.last);
    });

    test('picking something up comes with a word', () {
      final world = _world('RF_002_OakGrove');
      final taken = world.take('doll');
      expect(taken.spoken!.who.name, 'Korash Blackearth');
      expect(taken.spoken!.line, contains('Dry'));
    });

    test('shopkeepers talk across the counter', () {
      final world = _world('MH_001_Square');
      expect(world.keeperSays('greet')!.keeper, 'Jory Tallow');
      final first = world.keeperSays('buy')!.line;
      expect(world.keeperSays('buy')!.line, isNot(first));
      expect(world.keeperSays('broke'), isNotNull);
      expect(_world('MH_002_GuardHall').keeperSays('greet'), isNull);
    });

    test('the weather draws a remark', () {
      for (final type in _campaign.weather.types) {
        expect(type.remark, isNotNull, reason: type.id);
      }
      final world = _world('MH_001_Square');
      expect(world.remarkOn(world.weatherNow!)!.who.name, 'Korash Blackearth');
    });

    test('a night has its sounds, a word before sleep, and a waking', () {
      final world = _world('MH_002_GuardHall');
      final night = world.nightLines(indoors: true);
      expect(night.night, isNotNull);
      expect(night.said, isNotNull);
      expect(night.wake, isNotNull);
      expect(_campaign.weather.restLines.indoors, contains(night.night));
    });
  });

  group('walking in on people', () {
    test('a stranger says nothing until spoken to', () {
      expect(_world('MH_002_GuardHall').greetingsHere(), isEmpty);
    });

    test('once met, they say something, once a day', () {
      final world = _world('MH_002_GuardHall', flags: {'met_thorne'});
      expect(world.greetingsHere().single.line, 'Anything?');
      expect(world.greetingsHere(), isEmpty);
      world.advanceTime(24);
      expect(world.greetingsHere(), isNotEmpty);
    });

    test('what they say follows the story', () {
      final after = _world('MH_002_GuardHall',
          flags: {'met_thorne', 'boss_defeated_hollow_avatar'});
      expect(after.greetingsHere().single.line, contains('owes you'));
    });

    test('somebody who has gone says nothing', () {
      final world = _world('VC_002_ThroneRoom',
          flags: {'met_liora', 'boss_defeated_malachai_vex'});
      expect(world.greetingsHere(), isEmpty);
    });
  });
}
