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

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  group("Harrow's maul", () {
    test('is hers to keep while the thing in the wood is loose', () {
      final talk = _world('MH_005_Forge').beginConversation('harrow')!.talk;
      expect(talk.availableOptions().map((o) => o.id), isNot(contains('maul')));
    });

    test('is handed over once the Avatar is dead, and only once', () {
      final world =
          _world('MH_005_Forge', flags: {'boss_defeated_hollow_avatar'});
      final talk = world.beginConversation('harrow')!.talk..choose('maul');
      world.concludeConversation(talk);

      expect(
          world.inventory.find('thrall-breaker')?.id, 'w_009_thrall_breaker');
      final entry = world.ledger.entries.last;
      expect(entry.itemId, 'w_009_thrall_breaker');
      expect(entry.source, 'Ada Harrow');

      final again = world.beginConversation('harrow')!.talk;
      expect(
          again.availableOptions().map((o) => o.id), isNot(contains('maul')));
    });
  });

  group("Sal's late stock", () {
    final late = {
      'a_011_monarchs_vestment': 'dialogue_complete_queen_liora',
      'g_017_vessels_chain': 'boss_defeated_malachai_vex',
      'w_019_the_last_nail': 'boss_defeated_hollow_avatar',
      'g_020_quiet_crown': 'deception_revealed_under_archive',
    };

    test('comes out only after the story has been where it came from', () {
      final mule = _campaign.economy.shopKeptBy('npc_010_sal')!;
      final early = mule.onSaleFor({'Unlock_Travel_to_Valorheim'});
      for (final MapEntry(key: item, value: flag) in late.entries) {
        expect(early, isNot(contains(item)));
        expect(mule.onSaleFor({flag}), contains(item), reason: flag);
      }
    });

    test('costs what its level says, so the price is the gate', () {
      for (final id in late.keys) {
        final item = _campaign.gear.byId(id)!;
        expect(item.price, permanentItemPrice(item.level), reason: item.name);
      }
      expect(_campaign.gear.byId('g_020_quiet_crown')!.price, 70000 * 100);
    });
  });
}
