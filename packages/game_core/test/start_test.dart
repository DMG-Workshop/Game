import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

void main() {
  test('a new game begins where the first quest does, not at room "A"', () {
    final world = WorldSession(
      campaign: loadShatteredSeals(),
      actors: [SessionActor(id: 'korash', character: loadKorash())],
      roller: DiceRoller(1),
    );
    // Shadows Over Millhaven starts on enter_MH_001; the Bloodstone Mine
    // Head merely sorts first.
    expect(world.currentRoom.id, 'MH_001_Square');
  });

  test('the console wraps prose to the width it is given', () async {
    final world = WorldSession(
      campaign: loadShatteredSeals(),
      actors: [SessionActor(id: 'korash', character: loadKorash())],
      roller: DiceRoller(1),
    );
    Future<String?> none({String prompt = ''}) async => null;
    final narrow = StringBuffer();
    GameConsole(world, narrow, none).begin();
    final wide = StringBuffer();
    GameConsole(world, wide, none, width: 100000).begin();
    int longest(StringBuffer b) =>
        b.toString().split('\n').fold(0, (m, l) => l.length > m ? l.length : m);
    expect(longest(narrow), lessThanOrEqualTo(80));
    expect(longest(wide), greaterThan(80));
  });
}
