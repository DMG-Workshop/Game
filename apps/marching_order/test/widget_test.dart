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

      final back = await GameController.resume();
      await pumpEventQueue();
      expect(back.log, contains('Picked up where you left off'));
    },
  );
}
