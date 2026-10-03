import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marching_order/game_controller.dart';
import 'package:marching_order/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the title screen offers the sample character', (tester) async {
    await tester.pumpWidget(const MarchingOrderApp());
    await tester.pump();
    expect(find.text('Lanternfall'), findsOneWidget);
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
      expect(game.log, contains('Torvin Ashgrove'));
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
      expect(game.prompt, 'shop> ', reason: 'open across the counter');
      final stock = game.chips.map((c) => c.label).toList();
      expect(stock, contains('Minor Hearth-Water · 4 gp'));
      expect(stock.last, 'Back to Jory Tallow');

      // A sword bought over the counter comes with a question: who takes it.
      game.send(
        game.chips
            .firstWhere((c) => c.label.startsWith('Millhaven Guard Sword'))
            .command,
      );
      await pumpEventQueue();
      expect(game.prompt, 'equip> ');
      expect(game.chips.map((c) => c.label), [
        'Wield it',
        'Keep it in the pack',
      ]);
      game.send('1');
      await pumpEventQueue();
      expect(game.log, contains('takes up Millhaven Guard Sword'));
      expect(game.prompt, 'shop> ', reason: 'and back to the stock');

      // 0 goes back to Jory, and 0 again walks away from him.
      game.send('0');
      await pumpEventQueue();
      expect(game.prompt, 'say> ');
      game.send('0');
      await pumpEventQueue();
      expect(game.prompt, '> ');

      // Out in the square the party can trade too, and a purchase is real.
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

  test('the pack and a fight are menus of chips', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Seeded, so the fight starts the same way every time. Mira, the
    // caster the rules are tested against, rather than the sample: aiming
    // wants a caster.
    final game = await GameController.start([
      File('../../packages/pf2e_core/test/fixtures/mira.json')
          .readAsStringSync(),
    ], seed: 3);
    await pumpEventQueue();

    game.send('buy minor hearth-water');
    await pumpEventQueue();
    game.send('inventory');
    await pumpEventQueue();
    expect(game.prompt, 'pack> ');
    expect(game.chips.map((c) => c.label), [
      'Minor Hearth-Water',
      'Close the pack',
    ]);
    game.send('1');
    await pumpEventQueue();
    expect(game.chips.map((c) => c.label), [
      'Drink it',
      'Drop it',
      'Back to the pack',
    ]);
    game.send('0');
    await pumpEventQueue();
    game.send('0');
    await pumpEventQueue();
    expect(game.prompt, '> ');

    // Three steps west, something has been keeping pace: both thralls,
    // as written, so a spell has two to choose between.
    game.session.scaleFights = false;
    for (var i = 0; i < 3; i++) {
      game.send('west');
      await pumpEventQueue();
    }
    expect(game.prompt, 'fight> ');
    final orders = game.chips.map((c) => c.label).toList();
    expect(orders, contains('Strike Hollow Thrall 2'));
    expect(orders, contains('Cast Ignition…'), reason: 'two thralls to aim at');
    expect(orders, contains('End turn'));
    expect(orders.sublist(orders.length - 2), ['Status', 'Flee']);

    // Two thralls in reach: a spell asks which, and the answer is a chip.
    game.send(
      game.chips.firstWhere((c) => c.label == 'Cast Ignition…').command,
    );
    await pumpEventQueue();
    expect(game.prompt, 'aim> ');
    expect(game.chips.map((c) => c.label), [
      'Hollow Thrall 2',
      'Hollow Thrall 1',
      'Back to the fight',
    ]);
    game.send('2');
    await pumpEventQueue();
    expect(game.log, contains('Hollow Thrall 1: Ignition (spell attack)'));
  });

  test('the map is a chip, and its places are chips to travel by', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final game = await GameController.start([
      await GameController.demoCharacter(),
    ], seed: 3);
    await pumpEventQueue();
    expect(game.chips.map((c) => c.label), contains('Map'));

    game.send('map');
    await pumpEventQueue();
    expect(game.prompt, 'map> ');
    expect(game.log, contains('?--[Square]--?'), reason: 'fog, to begin');
    final ways = game.chips.map((c) => c.label).toList();
    expect(ways, contains('Explore north'));
    expect(ways.last, 'Put the map away');

    game.send(game.chips.firstWhere((c) => c.label == 'Explore north').command);
    await pumpEventQueue();
    expect(game.prompt, '> ');
    expect(game.log, contains('## The Guard Hall'));

    game.send('map');
    await pumpEventQueue();
    expect(
      game.chips.map((c) => c.label),
      contains(startsWith('The Bustling Market Square')),
      reason: 'somewhere been is somewhere to go back to',
    );
  });

  test('somebody who would join is a chip, and so is the party', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final game = await GameController.start([
      await GameController.demoCharacter(),
    ], seed: 3);
    await pumpEventQueue();
    expect(game.chips.map((c) => c.label), contains('Party'));

    // The tavern is east of the square, and Bren Cask is in it.
    game.send('east');
    await pumpEventQueue();
    expect(game.chips.map((c) => c.label), contains('Recruit: Cask'));

    game.send(game.chips.firstWhere((c) => c.label == 'Recruit: Cask').command);
    await pumpEventQueue();
    expect(game.prompt, 'hire> ');
    expect(game.chips.map((c) => c.label), ['Take Bren on', 'Not now']);
    game.send('1');
    await pumpEventQueue();
    expect(game.log, contains('Bren Cask joins the party.'));
    expect(game.chips.map((c) => c.label), isNot(contains('Recruit: Cask')));

    game.send('party');
    await pumpEventQueue();
    expect(game.prompt, 'party> ');
    expect(game.chips.map((c) => c.label), [
      'Torvin Ashgrove',
      'Bren Cask',
      'Close',
    ]);
  });

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
