import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marching_order/game_controller.dart';
import 'package:marching_order/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the title screen offers the sample character', (tester) async {
    await tester.pumpWidget(const MarchingOrderApp());
    await tester.pump();
    expect(find.text('Marching Order'), findsOneWidget);
    expect(find.textContaining('Play the sample'), findsOneWidget);
    expect(find.text('Continue'), findsNothing, reason: 'nothing saved yet');
  });

  test(
    'a game plays commands on the shared console, and saves itself',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final game = await GameController.start([
        await GameController.demoCharacter(),
      ]);
      await pumpEventQueue();
      expect(game.log, contains('Korash Blackearth'));
      expect(game.prompt, '> ');
      expect(game.chips.map((c) => c.command), contains('look'));

      game.send('inventory');
      await pumpEventQueue();
      expect(game.log, contains('> inventory'));
      expect(await GameController.hasSave(), isTrue);

      game.send('talk npc_009_jory');
      await pumpEventQueue();
      expect(game.prompt, 'say> ');
      final labels = game.chips.map((c) => c.label).toList();
      expect(labels, contains('Ask to see his stock'));
      expect(labels.last, 'Walk away');
      game.send(
        game.chips.firstWhere((c) => c.label == 'Ask to see his stock').command,
      );
      await pumpEventQueue();
      expect(game.log, contains("Tallow's Cart"), reason: 'the wares, listed');
      expect(game.log, contains('Minor Hearth-Water'));

      // At Jory's cart the party can trade, and a purchase is a real one.
      game.send('0');
      await pumpEventQueue();
      expect(game.canTrade, isTrue);
      expect(game.priceChange, 0, reason: 'nobody has haggled yet');
      expect(
        game.chips.map((c) => c.command),
        contains(GameController.tradeCommand),
      );
      final potion = game.wares.firstWhere(
        (r) => r.item.name == 'Minor Hearth-Water',
      );
      final coin = game.session.inventory.coin;
      game.send('buy ${potion.item.name}');
      await pumpEventQueue();
      expect(game.session.inventory.coin, coin - potion.price);
      final sold = game.sellable.firstWhere(
        (r) => r.item.name == 'Minor Hearth-Water',
      );
      expect(sold.inUse, isFalse);
      game.send('sell ${sold.item.name}');
      await pumpEventQueue();
      expect(game.session.inventory.coin, coin - potion.price + sold.price);

      final back = await GameController.resume();
      await pumpEventQueue();
      expect(back.log, contains('Picked up where you left off'));
    },
  );

  test('a won haggle shows on the Trade chip and in the prices', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final game = await GameController.start([
      await GameController.demoCharacter(),
    ]);
    await pumpEventQueue();
    await game.save();

    // Whatever the dice would have said, the flag the win sets is what the
    // shop reads: put it in the save and pick the game up again.
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().single;
    final saved = jsonDecode(prefs.getString(key)!) as Map<String, Object?>;
    final world = saved['world'] as Map<String, Object?>;
    world['flags'] = [...world['flags'] as List, 'jory_discount'];
    await prefs.setString(key, jsonEncode(saved));

    final haggled = await GameController.resume();
    await pumpEventQueue();
    expect(haggled.priceChange, -10);
    expect(haggled.chips.map((c) => c.label), contains('Trade · 10% off'));
    final sword = haggled.wares.firstWhere(
      (r) => r.item.name == 'Millhaven Guard Sword',
    );
    expect(sword.price, lessThan(sword.item.price));
  });
}
