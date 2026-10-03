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
///
/// A command written "#words" answers with the number of the latest menu
/// entry containing those words, so a test says what it picks rather than
/// where that happens to sit in the list.
///
/// Fights come as written, for four, unless [scaled]: the orders on offer
/// are easier to see with two thralls in the room than with one.
Future<String> _play(String room, List<String> commands,
    {int seed = 1,
    int gold = 0,
    List<String> carrying = const [],
    bool scaled = false,
    bool fighter = false}) async {
  final world = WorldSession(
    campaign: _campaign,
    // Mira the wizard, unless [fighter]: Torvin, the sample.
    actors: [
      fighter
          ? SessionActor(id: 'torvin', character: loadTorvin())
          : SessionActor(id: 'mira', character: loadMira()),
    ],
    roller: DiceRoller(seed),
    roomId: room,
    spells: _spells,
    scaleFights: scaled,
  );
  if (gold > 0) world.inventory.earn(gold * 100);
  for (final item in carrying) {
    world.inventory.add(item);
  }
  final out = StringBuffer();
  final queue = List.of(commands);
  Future<String?> next({String prompt = '> '}) async {
    if (queue.isEmpty) return null;
    var line = queue.removeAt(0);
    if (line.startsWith('#')) {
      final needle = line.substring(1);
      final entry = RegExp(r'^ *(\d+)\. (.*)$', multiLine: true)
          .allMatches(out.toString())
          .lastWhere((m) => m.group(2)!.contains(needle),
              orElse: () =>
                  throw StateError('no "$needle" on the menu:\n$out'));
      line = entry.group(1)!;
    }
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

  group('the shop', () {
    test('is a numbered list, and a number buys', () async {
      final log = await _play('MH_001_Square', ['list', '2', '0', 'purse']);
      expect(log, contains('1. Millhaven Guard Sword'));
      expect(log, contains('0. Leave the shop'));
      expect(log, contains('You buy Minor Hearth-Water for 4 gp'));
      expect(log, contains('The party has 266 gp'));
    });

    test('"buy" with a number works from the street', () async {
      final log = await _play('MH_001_Square', ['buy 2', 'purse']);
      expect(log, contains('You buy Minor Hearth-Water for 4 gp'));
    });

    test(
        'opens across the counter mid-conversation, at the haggled price, '
        'and 0 goes back to the keeper', () async {
      // Seed 1 makes the haggle a critical success: two in ten off.
      final log = await _play('MH_001_Square', [
        'talk jory', '1', '1', '#stock', //
        '#Millhaven Guard Sword', '0', '0', '#Leave',
      ]);
      expect(log, contains('You buy Millhaven Guard Sword for 8 sp'));
      expect(log, contains('0. Back to Jory Tallow'));
      expect(log, contains('Millhaven Guard Sword goes in the pack.'));
      expect(log, contains('[jory_discount_large]'),
          reason: 'the conversation went on to its end after the shop');
    });

    test('a number that is not on the list is asked again', () async {
      final log = await _play('MH_001_Square', ['list', '42', '0']);
      expect(log, contains('Pick a number from 0 to 8.'));
    });

    test('anything else typed there leaves it and is done', () async {
      final log = await _play('MH_001_Square', ['list', 'north']);
      expect(log, contains('## The Guard Hall'));
    });

    test('sells by number, without calling the money found', () async {
      final log = await _play('MH_001_Square', [
        'list', '#Minor Hearth-Water', '#Sell something', //
        '#Minor Hearth-Water', '0', '0',
      ]);
      expect(
          log, contains('Jory Tallow gives you 2 gp for Minor Hearth-Water'));
      expect(log, isNot(contains('[+2 gp')));
    });
  });

  group('buying something to wield', () {
    test('asks whether to take it up, with what it would change', () async {
      final log =
          await _play('MH_001_Square', ['buy guard sword', '1'], fighter: true);
      expect(log, contains('Torvin Ashgrove could wield it now:'));
      expect(
          log,
          contains('Wield it  Strike +16 2d8+4 (+1 Striking Longsword) '
              '-> +15 1d8+4'));
      expect(log, contains('Torvin Ashgrove takes up Millhaven Guard Sword'));
    });

    test('a command instead of an answer leaves it in the pack', () async {
      final log = await _play('MH_001_Square', ['buy guard sword', 'north']);
      expect(log, contains('## The Guard Hall'));
      expect(log, isNot(contains('takes up')));
    });
  });

  group('the pack', () {
    test('equips, puts away and drops by number', () async {
      final log = await _play('MH_001_Square', [
        'buy guard sword', '0', //
        'i', '#Millhaven', '#Wield it', //
        '#Millhaven', '#Put it away', //
        '#Millhaven', '#Drop it', '#Drop it', '0',
      ]);
      expect(log, contains('1. Millhaven Guard Sword'));
      expect(log, contains('Mira Quell takes up Millhaven Guard Sword'));
      expect(log, contains('(on Mira Quell)'));
      expect(log, contains('Mira Quell puts away Millhaven Guard Sword'));
      expect(log, contains('It will be gone for good.'));
      expect(log, contains('You leave Millhaven Guard Sword behind.'));
      expect(log, contains('The pack is empty'));
    });

    test('offers a draught to drink, and says who is not hurt', () async {
      final log =
          await _play('MH_001_Square', ['buy 2', 'i', '#Minor', '#Drink', '0']);
      expect(log, contains('Drink it  (HP 56/56)'));
      expect(log, contains('Mira Quell is not hurt.'));
    });
  });

  test('a fight cut down for a smaller party says so', () async {
    final log = await _play('WW_001_Edge', ['west'], seed: 3, scaled: true);
    expect(
        log.replaceAll(RegExp(r'\s+'), ' '),
        contains('(Written for four. Against your party of one, 1 of the 2 '
            'Hollow Thralls comes, and weakened.)'));
    expect(log, contains('Cast Daze at Weak Hollow Thrall'));
  });

  group('a fight', () {
    test('offers every order as a number', () async {
      final log = await _play('WW_001_Edge', ['west'], seed: 3);
      expect(log, contains('Strike Hollow Thrall 2  (35/35 HP)'));
      expect(log, contains('Strike Hollow Thrall 1  (35/35 HP)'));
      // Both thralls are in reach, so there is a choice to make.
      expect(
          log,
          contains('Cast Ignition  (2 actions, cantrip): choose a '
              'target'));
      expect(log, contains('End turn'));
      expect(log, contains('0. Flee'));
    });

    test('warns when a burst would catch the party', () async {
      final log = await _play('WW_001_Edge', ['west'], seed: 3);
      expect(
          log,
          contains('Cast Fireball  (2 actions, 2 left): catches Hollow Thrall '
              '2, Hollow Thrall 1 and Mira Quell — your own side too'));
    });

    test('casts a spell by its number, at whoever is picked', () async {
      final log = await _play(
          'WW_001_Edge', ['west', '#Cast Ignition', '#Hollow Thrall 1'],
          seed: 3);
      expect(log, contains('Ignition: at whom?'));
      expect(log, contains('Hollow Thrall 2  (35/35 HP, engaged)'));
      expect(log, contains('Mira Quell casts Ignition'));
      expect(log, contains('Hollow Thrall 1: Ignition (spell attack)'));
    });

    test('0 at "at whom?" goes back to the orders', () async {
      final log = await _play(
          'WW_001_Edge', ['west', '#Cast Ignition', '0', '#End turn'],
          seed: 3);
      expect(log, contains('0. Back to the fight'));
      expect(log, isNot(contains('casts Ignition')));
      expect('-- Mira Quell, round 1, 3 action(s) --'.allMatches(log),
          hasLength(2),
          reason: 'the same turn offered again, with nothing spent');
    });

    test('a burst can be dropped where it spares the party', () async {
      // Seed 10: one thrall at Mira's elbow, the other hanging back.
      final log = await _play(
          'WW_001_Edge', ['west', '#Cast Fireball', '#At Hollow Thrall 1'],
          seed: 10);
      expect(
          log,
          contains('At Hollow Thrall 2, engaged: catches Hollow Thrall 2 and '
              'Mira Quell — your own side too'));
      expect(
          log, contains('At Hollow Thrall 1, near: catches Hollow Thrall 1'));
      expect(log, contains('Hollow Thrall 1: Reflex against Fireball'));
      expect(log, isNot(contains('Mira Quell: Reflex against')));
    });

    test('offers a draught once somebody is hurt, and drinks it', () async {
      final log = await _play(
          'MH_001_Square',
          [
            'buy 2', 'west', 'west', 'west', '#Drink', //
          ],
          seed: 3);
      expect(
          log,
          contains('Drink Minor Hearth-Water  (1 action; you are at '
              '46/56 HP)'));
      expect(log, contains('Mira Quell drinks Minor Hearth-Water'));
    });

    test('says what a spell costs when there are too few actions', () async {
      final log = await _play('WW_001_Edge',
          ['west', '#Strike Hollow Thrall 2', '#Strike', 'cast ignition'],
          seed: 3);
      expect(
          log,
          contains('That takes 2 actions, and Mira Quell has '
              '1 left this turn.'));
    });
  });

  group('the map', () {
    const valley = ['g_038_map_of_the_valley'];

    test('starts in fog, with the ways out to explore', () async {
      final log = await _play('MH_001_Square', ['map', '0']);
      expect(
          log,
          contains('THE MILLHAVEN VALLEY  (as far as you have walked '
              'it)'));
      expect(log, contains('?--[Square]--?'));
      expect(log, contains('Explore north'));
      expect(log, contains('Sal Mercy sells maps of the valley'));
    });

    test('with the map, a number walks the whole way there', () async {
      final log = await _play('MH_001_Square', ['map', '#Ravencrest Farm'],
          carrying: valley);
      expect(log, contains("west, to Harrow's Forge"));
      expect(log, contains('west, to The Edge of Whisperwood'));
      expect(log, contains('## Ravencrest Farm'));
      expect(log, isNot(contains('Sal Mercy sells maps')),
          reason: 'the party has one');
    });

    test('something waiting on the way stops the walk', () async {
      final log = await _play('MH_001_Square', ['map', '#The Hollow Grove'],
          carrying: valley);
      expect(log, contains('## Deep Whisperwood'));
      expect(log, contains('SOMETHING KEEPING PACE'));
      expect(log, isNot(contains('## The Hollow Grove')));
    });

    test('a command typed at it puts it away and is done', () async {
      final log = await _play('MH_001_Square', ['map', 'north']);
      expect(log, contains('## The Guard Hall'));
    });

    test('Hale will sell a plan of the city across his desk', () async {
      final log = await _play(
          'VC_003_GrandLibrary',
          [
            'talk hale',
            '#empty sections',
            '#plan of the city',
            '#A Plan of Valorheim',
            '0',
          ],
          gold: 20);
      expect(log, contains("The Library's Copying Desk"));
      expect(log, contains('You buy A Plan of Valorheim for 12 gp'));
    });
  });

  test('a spell named on its own is cast', () async {
    final log =
        await _play('WW_001_Edge', ['west', 'spells', 'needle darts'], seed: 3);
    expect(log, contains('Daze (cantrip, rank 3, at will), Wizard'));
    expect(log, contains('Daze (cantrip, rank 3, at will), Witch'));
    expect(log, contains('casts Needle Darts'));
    expect(log, isNot(contains('In a fight you can:')));
  });

  test('a roll still on offer is not "nothing more to ask"', () async {
    // Wendel's story is told, and watching him tell it again is a
    // Perception check: the way to catch him lying.
    final log = await _play('MH_003_Tavern', ['talk wendel', '1', '0']);
    expect(log, contains('[Perception] Watch him while he tells it again'));
    expect(log, isNot(contains('Nothing more to ask Wendel Pike')));
  });

  test('somebody asked everything says there is nothing more', () async {
    final log = await _play('MH_004_Temple',
        ['talk aldus', '1', '1', '1', '1', '1', 'talk aldus', '1', '0']);
    expect(log, contains('(Nothing more to ask Brother Aldus for now.)'));
  });

  group('companions', () {
    test('asked to join, show their numbers and their fee, then come along',
        () async {
      final log = await _play('MH_003_Tavern', [
        'who',
        'talk bren',
        '#Ask her to join you',
        '#Take Bren on',
        'party',
      ]);
      expect(log, contains('(would join: Fighter, 20 gp)'));
      expect(log, contains('Bren Cask — Human Fighter, level 6'));
      expect(log, contains('Strike +17 2d12+4  (+1 Striking Greatsword)'));
      expect(log, contains('Asks 20 gp to join.'));
      expect(log, contains('Bren Cask joins the party.'));
      expect(log, contains('The party  (2 of 4)'));
      expect(log, contains('(companion)'));
    });

    test('no is no, and the talk goes on', () async {
      final log = await _play('MH_003_Tavern', [
        'talk bren',
        '#Ask her to join you',
        '0',
        '0',
        'party',
      ]);
      expect(log, isNot(contains('joins the party')));
      expect(log, contains('The party  (1 of 4)'));
    });

    test('a cleric shows what she can cast before she is hired', () async {
      final log = await _play('MH_004_Temple', ['recruit wren']);
      expect(log, contains('Spells: Heal x14 (up to 3rd rank)'));
      expect(log, contains('Cantrips: Daze, Void Warp'));
      expect(log, contains('Take Wren on  (15 gp)'));
    });

    test('are parted with from the party menu, and go home', () async {
      final log = await _play('MH_003_Tavern', [
        'recruit',
        '1',
        'party',
        '#Bren Cask',
        '#Part ways',
        '1',
        'who',
      ]);
      expect(log, contains('Bren Cask joins the party.'));
      expect(log, contains('Bren Cask leaves the party, back to'));
      expect(log, contains('(would join: Fighter)\n'),
          reason: 'already paid: no fee the second time');
    });

    test('an imported character has no door on the party menu', () async {
      final log = await _play('MH_003_Tavern', ['party', '1']);
      expect(log, contains('Mira Quell — Human Wizard, level 6'));
      expect(log, isNot(contains('Part ways')));
    });
  });
}
