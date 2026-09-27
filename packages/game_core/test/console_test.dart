import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;
late SpellBook _spells;

/// Plays [commands] through a console from [room], and returns everything
/// it printed.
Future<String> _play(String room, List<String> commands, {int seed = 1}) async {
  final world = WorldSession(
    campaign: _campaign,
    actors: [SessionActor(id: 'korash', character: loadKorash())],
    roller: DiceRoller(seed),
    roomId: room,
    spells: _spells,
  );
  final out = StringBuffer();
  final queue = List.of(commands);
  Future<String?> next({String prompt = '> '}) async {
    if (queue.isEmpty) return null;
    final line = queue.removeAt(0);
    out.writeln('$prompt$line');
    return line;
  }

  final console = GameConsole(world, out, next)..begin();
  while (true) {
    final line = await next();
    if (line == null || !await console.play(line)) break;
  }
  return out.toString();
}

void main() {
  setUpAll(() {
    _campaign = loadShatteredSeals();
    _spells = const CampaignLoader().readSpells(
        File('../../content/pf2e_remaster/spells.json').readAsStringSync());
  });

  test('a discount talked out of Jory is the price at once', () async {
    // Seed 1 makes the haggle a critical success: two in ten off.
    final log = await _play('MH_001_Square', ['talk jory', '1', '1', '3']);
    expect(log, contains('Two in ten off'));
    final stock = log.substring(log.lastIndexOf("Tallow's Cart —"));
    expect(stock, contains('(20% off, for you)'));
    expect(stock, contains('Millhaven Guard Sword'));
    expect(stock, contains('8 sp'), reason: '1 gp less a fifth');
    expect(stock, contains('(was 1 gp)'), reason: 'the saving shows');
  });

  test('without a discount, no price says what it was', () async {
    final log = await _play('MH_001_Square', ['list']);
    expect(log, isNot(contains('(was ')));
  });

  test('the stock list says how to buy and sell', () async {
    final log = await _play('MH_001_Square', ['list']);
    expect(log, contains('"buy <item>"'));
    expect(log, contains('"sell <item>"'));
  });

  test('a spell named on its own is cast', () async {
    final log =
        await _play('WW_001_Edge', ['west', 'spells', 'needle darts'], seed: 3);
    expect(log, contains('Daze (cantrip, rank 3, at will), Magus'));
    expect(log, contains('Daze (cantrip, rank 3, at will), Necromancer'));
    expect(log, contains('casts Needle Darts'));
    expect(log, isNot(contains('In a fight you can:')));
  });

  test('somebody asked everything says there is nothing more', () async {
    final log = await _play('MH_004_Temple',
        ['talk aldus', '1', '1', '1', '1', '1', 'talk aldus', '1', '0']);
    expect(log, contains('(Nothing more to ask Brother Aldus for now.)'));
  });
}
