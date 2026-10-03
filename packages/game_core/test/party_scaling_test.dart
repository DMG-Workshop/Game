import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;

List<Creature> _foes(String encounterId) => [
      for (final id
          in _campaign.bestiary.encounterById(encounterId)!.creatureIds)
        _campaign.bestiary.creatureById(id)!,
    ];

PartyScaling _scale(String encounterId, int partySize, {int level = 6}) =>
    scaleForParty(_foes(encounterId), partyLevel: level, partySize: partySize);

List<String> _names(PartyScaling s) => [for (final c in s.fielded) c.name];

WorldSession _world(int partySize, {bool scale = true}) => WorldSession(
      campaign: _campaign,
      actors: [
        for (var i = 0; i < partySize; i++)
          SessionActor(id: 'pc$i', character: loadMira()),
      ],
      roller: DiceRoller(3),
      roomId: 'WW_002_Deep',
      scaleFights: scale,
    );

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  group('a fight for fewer than four', () {
    test('comes as written to a party of four', () {
      final s = _scale('e_whisperwood_thralls', 4);
      expect(_names(s), ['Hollow Thrall', 'Hollow Thrall']);
      expect(s.changed, isFalse);
    });

    test('sends one of two thralls against two or three', () {
      // 30 XP written for four; 15 is half the budget, 22 three quarters.
      for (final size in [2, 3]) {
        final s = _scale('e_whisperwood_thralls', size);
        expect(_names(s), ['Hollow Thrall'], reason: 'party of $size');
        expect(s.weakened, isFalse, reason: 'party of $size');
      }
    });

    test('sends one, weakened, against one', () {
      final s = _scale('e_whisperwood_thralls', 1);
      expect(_names(s), ['Weak Hollow Thrall']);
      expect(s.fielded.single.level, 2);
      expect(s.fielded.single.maxHp, 20, reason: '35, less 15 for level 3');
    });

    test('never leaves the boss at home', () {
      final s = _scale('e_hollow_grove', 1);
      expect(_names(s), ['Weak The Hollow Avatar']);
      final two = _scale('e_hollow_grove', 2);
      expect(two.fielded.first.isBoss, isTrue);
    });

    test('leaves the lesser foes at home first', () {
      // Two cutthroats and a drowned thing, which is a level higher.
      final s = _scale('e_drowned_mill', 2);
      expect(_names(s), ['Mere-Drowned']);
    });

    test('changes nothing for a party already big enough', () {
      expect(_scale('e_ritual_chamber', 5).changed, isFalse);
    });
  });

  group('in the world', () {
    test('a lone character meets the scaled fight, and is told so', () {
      final fight = _world(1).beginEncounter();
      expect(fight.enemies.map((e) => e.name), ['Weak Hollow Thrall']);
      expect(fight.scaling?.changed, isTrue);
    });

    test('a party of four meets the fight as written', () {
      final fight = _world(4).beginEncounter();
      expect(fight.enemies, hasLength(2));
      expect(fight.scaling?.changed, isFalse);
    });

    test('scaling can be turned off, and stays off across a save', () {
      final world = _world(1, scale: false);
      expect(world.beginEncounter().enemies, hasLength(2));
      final restored = WorldSession.restore(
        campaign: _campaign,
        actors: world.actors,
        snapshot: world.snapshot(),
      );
      expect(restored.scaleFights, isFalse);
      expect(
          WorldSession.restore(
            campaign: _campaign,
            actors: world.actors,
            snapshot: _world(1).snapshot(),
          ).scaleFights,
          isTrue,
          reason: 'on unless a save says otherwise');
    });
  });
}
