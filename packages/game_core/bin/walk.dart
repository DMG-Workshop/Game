import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';

const _defaultCampaign = '../../campaigns/shattered_seals';
const _defaultCharacter = '../pf2e_core/test/fixtures/korash.json';

const _directions = {
  'north',
  'south',
  'east',
  'west',
  'northeast',
  'northwest',
  'southeast',
  'southwest',
  'up',
  'down',
  'in',
  'out',
  'n',
  's',
  'e',
  'w',
  'ne',
  'nw',
  'se',
  'sw',
  'u',
  'd',
};

/// Walks a campaign world in the terminal.
///
///   dart run game_core:walk
///   dart run game_core:walk --seed=7 --commands="n,talk thorne,ask thorne about elara"
Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options.containsKey('help')) {
    stdout.writeln(_usage);
    return;
  }

  final campaignDir = options['campaign'] ?? _defaultCampaign;
  final seed = int.tryParse(options['seed'] ?? '') ??
      DateTime.now().millisecondsSinceEpoch;

  String? read(String name) {
    final file = File('$campaignDir/$name');
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  final world = read('world_config.json');
  final locations = read('locations.json');
  final npcs = read('npcs_and_dialogue.json');
  if (world == null || locations == null || npcs == null) {
    stderr.writeln('Not a campaign directory: $campaignDir');
    exitCode = 66;
    return;
  }

  final characterPaths = (options['characters'] ?? options['character'] ?? '')
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (characterPaths.isEmpty) characterPaths.add(_defaultCharacter);

  final Campaign campaign;
  final actors = <SessionActor>[];
  try {
    campaign = const CampaignLoader().load(
      id: 'campaign_i_shattered_seals',
      title: 'Campaign I: Shattered Seals',
      worldConfigJson: world,
      locationsJson: locations,
      npcsJson: npcs,
      gearJson: read('gear.json'),
      arcsJson: read('campaign_arcs.json'),
      bestiaryJson: read('bestiary.json'),
      itemsJson: read('world_items.json'),
      conversationsJson: read('conversations.json'),
      economyJson: read('economy.json'),
      huntJson: read('hunt.json'),
    );
    for (final path in characterPaths) {
      final file = File(path);
      if (!file.existsSync()) {
        stderr.writeln('No such character: $path');
        exitCode = 66;
        return;
      }
      final imported =
          const PathbuilderImporter().importJson(file.readAsStringSync());
      actors.add(SessionActor(
        id: _actorIdFor(imported.character.name, actors),
        character: imported.character,
      ));
    }
  } on CampaignFormatException catch (e) {
    stderr.writeln('Could not read the campaign: ${e.message}');
    exitCode = 65;
    return;
  } on PathbuilderImportException catch (e) {
    stderr.writeln('Could not read a character: ${e.message}');
    exitCode = 65;
    return;
  }

  final session = WorldSession(
    campaign: campaign,
    actors: actors,
    roller: DiceRoller(seed),
    roomId: options['room'],
    hour: int.tryParse(options['hour'] ?? '') ?? 8,
    // Starting from a given state, for trying a later part of the campaign
    // without replaying everything up to it.
    flags: (options['flags'] ?? '')
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toSet(),
  );
  // Extra gold to start with, for trying out what being rich brings.
  final gold = int.tryParse(options['gold'] ?? '') ?? 0;
  if (gold > 0) session.inventory.earn(gold * 100);

  stdout
    ..writeln('=' * 70)
    ..writeln('MARCHING ORDER — ${campaign.title}')
    ..writeln('${campaign.world.metadata.name} · seed $seed')
    ..writeln('=' * 70)
    ..writeln()
    ..writeln(_wrap(campaign.world.metadata.backgroundLore));
  for (final actor in session.actors) {
    stdout.writeln('\n  ${actor.id.padRight(8)} $actor');
  }

  final scripted = (options['commands'] ?? '')
      .split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();
  var scriptIndex = 0;

  // One reader for both loops, so a scripted playthrough can walk into a
  // fight and keep giving orders without the script knowing which mode it is
  // in.
  String? nextCommand({String prompt = '> '}) {
    if (scriptIndex < scripted.length) {
      final line = scripted[scriptIndex++];
      stdout.writeln('\n$prompt$line');
      return line;
    }
    if (scripted.isNotEmpty) return null;
    stdout.write('\n$prompt');
    return stdin.readLineSync(encoding: utf8)?.trim();
  }

  _renderRoom(session, full: true, showWeather: true);

  while (true) {
    final line = nextCommand();
    if (line == null) {
      if (scripted.isNotEmpty) stdout.writeln('\n(script exhausted)');
      break;
    }
    if (line.isEmpty) continue;
    if (line == 'quit' || line == 'q') break;
    final coinBefore = session.inventory.coin;
    final xpBefore = {
      for (final a in session.actors) a.id: session.experience.xpOf(a.id),
    };
    final tierBefore = session.notoriety.tier;
    final keepGoing = _handle(session, line, nextCommand);
    final gained = session.inventory.coin - coinBefore;
    if (gained > 0 && !line.toLowerCase().startsWith('sell')) {
      stdout.writeln('\n  [+${formatCoin(gained)} — the party has '
          '${formatCoin(session.inventory.coin)}]');
    }
    _announceExperience(session, xpBefore);
    _announceNotoriety(session, tierBefore);
    if (!keepGoing) break;
  }

  stdout
    ..writeln('\n${'-' * 70}')
    ..writeln('Resume: ${jsonEncode(session.snapshot())}');
}

/// Returns false to end the session.
bool _handle(WorldSession session, String line,
    String? Function({String prompt}) nextCommand) {
  final words = line.split(RegExp(r'\s+'));
  final verb = words.first.toLowerCase();
  final rest = words.skip(1).join(' ');

  if (verb == 'quit' || verb == 'q') return false;

  if (_directions.contains(verb)) return _go(session, verb, nextCommand);
  if (verb == 'go' && rest.isNotEmpty) return _go(session, rest, nextCommand);

  switch (verb) {
    case 'look':
    case 'l':
      _renderRoom(session, full: true, showWeather: true);
      return true;

    case 'exits':
      final view = session.look();
      stdout.writeln('Exits: ${view.openDirections.join(', ')}');
      for (final barred in view.barredDirections) {
        stdout.writeln('  ${barred.direction}: '
            '${barred.reason ?? 'shut'}');
      }
      return true;

    case 'who':
      final npcs = session.look().npcs;
      if (npcs.isEmpty) {
        stdout.writeln('Nobody else is here.');
      } else {
        for (final npc in npcs) {
          final left = session.unraisedTopicsFor(npc);
          stdout.writeln('  ${npc.name}'
              '${left.isEmpty ? '' : '  (topics: ${left.join(', ')})'}');
        }
      }
      return true;

    case 'talk':
    case 'ask':
      return _talk(session, rest, nextCommand);

    case 'take':
    case 'get':
      return _takeOrDestroy(session, rest, destroy: false);

    case 'destroy':
    case 'break':
      return _takeOrDestroy(session, rest, destroy: true);

    case 'examine':
    case 'x':
      final item = session
          .look()
          .items
          .where((i) => i.name.toLowerCase().contains(rest.toLowerCase()))
          .firstOrNull;
      if (item == null || rest.isEmpty) {
        stdout.writeln('There is no "$rest" here to examine.');
      } else {
        stdout.writeln('\n${_wrap(item.description)}');
      }
      return true;

    case 'fight':
    case 'attack':
      return _fight(session, nextCommand,
          encounterId: rest.isEmpty ? null : rest);

    case 'wait':
      final hours = int.tryParse(rest) ?? 1;
      session.advanceTime(hours);
      stdout.writeln('Time passes. It is now hour ${session.hour}'
          '${session.isNight ? ', and dark' : ''}.');
      final echo = session.ambianceEcho();
      if (echo != null) stdout.writeln('\n${_wrap(echo)}');
      return true;

    case 'quests':
    case 'arcs':
      _renderArcs(session);
      return true;

    case 'loot':
    case 'inventory':
    case 'inv':
    case 'i':
      _renderInventory(session);
      return true;

    case 'list':
    case 'wares':
      _renderWares(session);
      return true;

    case 'buy':
      return _trade(session, rest, buying: true);

    case 'sell':
      return _trade(session, rest, buying: false);

    case 'value':
    case 'appraise':
      try {
        final quote = session.valueOf(rest);
        stdout.writeln('${_keeper(session)} would give you '
            '${formatCoin(quote.price)} for ${quote.item.name}.');
      } on InvalidMoveException catch (e) {
        stdout.writeln(_wrap(e.message));
      }
      return true;

    case 'purse':
    case 'coin':
    case 'money':
      stdout.writeln('The party has ${formatCoin(session.inventory.coin)}, '
          'and is worth ${formatCoin(session.wealth.total)} in all.');
      return true;

    case 'wealth':
    case 'worth':
    case 'notoriety':
      _renderWealth(session);
      return true;

    case 'ledger':
    case 'found':
      _renderLedger(session);
      return true;

    case 'xp':
    case 'experience':
    case 'level':
      _renderExperience(session);
      return true;

    case 'sheet':
    case 'stats':
      _renderSheet(session, rest);
      return true;

    case 'equip':
    case 'wield':
    case 'wear':
      return _equip(session, rest);

    case 'unequip':
    case 'remove':
      return _unequip(session, rest);

    case 'flags':
      final flags = session.flags.toList()..sort();
      stdout.writeln(flags.isEmpty ? '(none)' : flags.join('\n'));
      return true;

    case 'help':
      stdout.writeln(_commands);
      return true;

    default:
      stdout.writeln('I do not know how to "$verb". Try "help".');
      return true;
  }
}

bool _go(WorldSession session, String direction,
    String? Function({String prompt}) nextCommand) {
  final MoveResult result;
  try {
    result = session.move(direction);
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
    return true;
  }

  _renderRoom(session, full: true, showWeather: result.changedRegion);
  if (result.changedRegion) {
    final echo = session.ambianceEcho();
    if (echo != null) stdout.writeln('\n${_wrap(echo)}');
  }
  _announceArcs(session);

  // An ambush is not something to mention and move on from.
  final ambush = result.ambush;
  if (ambush != null) {
    return _fight(session, nextCommand, encounterId: ambush.id);
  }

  // Nor is something that has followed the party's money this far.
  final hunt = result.hunt;
  final roll = result.huntRoll;
  if (hunt != null) {
    stdout.writeln('\n  [The hunt: d100(${roll?.die}) against '
        '${roll?.chance}% — something has your scent]');
    stdout.writeln('\n${_wrap(hunt.description)}');
    return _fight(session, nextCommand, encounterId: hunt.id);
  }
  return true;
}

/// Accepts "talk thorne" for a conversation, and "ask thorne about elara" or
/// "talk thorne elara" for a single topic.
bool _talk(WorldSession session, String rest,
    String? Function({String prompt}) nextCommand) {
  if (rest.isEmpty) {
    stdout.writeln('Talk to whom?');
    return true;
  }
  final words = rest.split(RegExp(r'\s+'));
  final who = words.first;
  var topic = words.skip(1).join(' ');
  if (topic.toLowerCase().startsWith('about ')) {
    topic = topic.substring(6);
  }

  if (topic.isEmpty) {
    try {
      final conversation = session.beginConversation(who);
      if (conversation != null) {
        return _converse(
            session, conversation.npc, conversation.talk, nextCommand);
      }
    } on InvalidMoveException catch (e) {
      stdout.writeln(e.message);
      return true;
    }
  }

  try {
    final result = session.talk(who, topic: topic.isEmpty ? null : topic);
    stdout.writeln('\n${result.npc.name}:');
    stdout.writeln(_wrap('"${result.said}"', indent: '  '));

    if (result.isGreeting) {
      final left = session.unraisedTopicsFor(result.npc);
      if (left.isNotEmpty) {
        stdout.writeln('\n  (ask about: ${left.join(', ')})');
      }
    }
    for (final flag in result.flagsSet) {
      stdout.writeln('\n  [$flag]');
    }
    _announceArcs(session);
  } on InvalidMoveException catch (e) {
    stdout.writeln(e.message);
  }
  return true;
}

/// Runs a conversation to its end, or until the party walks away.
///
/// Its own loop for the same reason a fight has one: the verbs are different.
/// Everything said before walking away still counts.
bool _converse(
  WorldSession session,
  Npc npc,
  GameSession talk,
  String? Function({String prompt}) nextCommand,
) {
  final solo = session.actors.length == 1;
  stdout
    ..writeln('\n${'-' * 70}')
    ..writeln(npc.name.toUpperCase())
    ..writeln('-' * 70)
    ..writeln('\n${_wrap(talk.currentScene.body)}');

  var keepGoing = true;
  while (!talk.isFinished) {
    final options = talk.availableOptions();
    stdout.writeln('');
    for (var i = 0; i < options.length; i++) {
      stdout.writeln('  ${i + 1}. ${options[i].label}'
          '${_checkHint(talk, options[i], solo: solo)}');
    }
    stdout.writeln('  0. Walk away');

    final line = nextCommand(prompt: 'say> ');
    if (line == null) {
      stdout.writeln('\n(script exhausted mid-conversation)');
      keepGoing = false;
      break;
    }
    final choice = line.trim().toLowerCase();
    if (choice.isEmpty) continue;
    if (const {'0', 'bye', 'leave', 'walk away'}.contains(choice)) {
      stdout.writeln('\nYou leave ${npc.name} where you found them.');
      break;
    }

    final number = int.tryParse(choice);
    final option = number != null && number >= 1 && number <= options.length
        ? options[number - 1]
        : options
            .where((o) =>
                o.id == choice || o.label.toLowerCase().startsWith(choice))
            .firstOrNull;
    if (option == null) {
      stdout.writeln('Pick a number from the list, or 0 to walk away.');
      continue;
    }

    final GameEvent event;
    try {
      event = talk.choose(option.id);
    } on InvalidChoiceException catch (e) {
      stdout.writeln(e.message);
      continue;
    }

    if (event.said case final said?) {
      stdout.writeln('\n${_wrap('${event.actorName} says, "$said"')}');
    }
    final check = event.check;
    if (check != null) {
      stdout.writeln('\n  ~ ${solo ? '' : '${event.actorName} — '}'
          '${check.label}: d20(${check.dieRoll}) '
          '${_signed(check.modifier)} = ${check.total} vs DC ${check.dc} '
          '-> ${check.degree.displayName}'
          '${check.wasShiftedByNatural ? ' (natural ${check.dieRoll})' : ''}');
    }
    stdout.writeln('\n${_wrap(event.narration)}');

    // A new scene is a new beat; returning to the same one is not, and
    // repeating its opening every time would read like a stuck record.
    final movedTo = event.movedTo;
    if (movedTo != null && movedTo != event.sceneId) {
      stdout.writeln('\n${_wrap(talk.currentScene.body)}');
    }
  }

  final flags = session.concludeConversation(talk);
  for (final flag in flags) {
    stdout.writeln('\n  [$flag]');
  }
  _announceArcs(session);
  return keepGoing;
}

String _checkHint(GameSession talk, SceneOption option, {required bool solo}) {
  final check = option.check;
  if (check == null) return '';
  final best = talk.suggestedActorFor(option.id);
  if (best == null) return '  (nobody can try this)';
  final who = solo ? '' : '${best.actor.name} ';
  return '  ($who${best.stat.formatted} vs DC ${check.dc})';
}

void _renderInventory(WorldSession session) {
  final pack = session.inventory;
  final carried = pack.carried;
  if (carried.isEmpty) {
    stdout.writeln('The pack is empty. You have what you arrived with.');
  } else {
    stdout.writeln('');
    for (final item in carried) {
      final count = pack.countOf(item.id);
      final holders = pack.holdersOf(item.id);
      final worn = holders.isEmpty ? '' : '  (on ${holders.join(', ')})';
      final name = count > 1 ? '${item.name} x$count' : item.name;
      stdout.writeln('  ${name.padRight(30)} '
          'level ${item.level} ${item.rarity.name} ${item.type}$worn');
      if (item.special != null) {
        stdout.writeln(_wrap(item.special!, indent: '    '));
      }
    }
  }
  stdout.writeln('\nPurse: ${formatCoin(pack.coin)}');
}

void _renderWares(WorldSession session) {
  final shop = session.shopHere;
  if (shop == null) {
    stdout.writeln('There is nobody here to trade with.');
    return;
  }
  final percent = shop.percentFor(session.flags);
  stdout.writeln('\n${shop.name} — ${_keeper(session)}'
      '${percent == 0 ? '' : percent < 0 ? '  (${-percent}% off, for you)' : '  (+$percent%, for you)'}');
  for (final row in session.wares()) {
    final dear = row.price > session.inventory.coin ? '  *' : '';
    stdout.writeln('  ${row.item.name.padRight(32)} '
        '${'level ${row.item.level}'.padRight(9)} '
        '${formatCoin(row.price).padLeft(12)}$dear');
  }
  stdout.writeln('\nThe party has ${formatCoin(session.inventory.coin)}.'
      '${session.wares().any((r) => r.price > session.inventory.coin) ? '  (* more than that)' : ''}');
}

bool _trade(WorldSession session, String what, {required bool buying}) {
  if (what.isEmpty) {
    stdout.writeln(buying ? 'Buy what?' : 'Sell what?');
    return true;
  }
  try {
    if (buying) {
      final bought = session.buy(what);
      stdout.writeln('\nYou buy ${bought.item.name} for '
          '${formatCoin(bought.price)}. The party has '
          '${formatCoin(session.inventory.coin)} left.');
    } else {
      final sold = session.sell(what);
      stdout.writeln('\n${_keeper(session)} gives you '
          '${formatCoin(sold.price)} for ${sold.item.name}. The party has '
          '${formatCoin(session.inventory.coin)}.');
    }
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
  }
  return true;
}

String _keeper(WorldSession session) {
  final shop = session.shopHere;
  if (shop == null) return 'Nobody';
  return session.campaign.npcs.byId(shop.keeperId)?.name ?? shop.name;
}

void _renderSheet(WorldSession session, String who) {
  try {
    final actor = who.isEmpty ? session.primary : session.actorFor(who);
    final stats = session.statsFor(actor.id);
    stdout.writeln('\n$actor');
    for (final line in stats.describe()) {
      stdout.writeln('  $line');
    }
    stdout.writeln('  HP ${actor.stats.maxHp}  '
        'Perception ${actor.stats.perception.formatted}  '
        'Class DC ${actor.stats.classDc}');
    stdout.writeln('  ${_xpLine(session.experience.progressOf(actor.id))}');
  } on InvalidMoveException catch (e) {
    stdout.writeln(e.message);
  }
}

/// Accepts "equip nail" and "equip korash nail".
bool _equip(WorldSession session, String rest) {
  if (rest.isEmpty) {
    stdout.writeln('Equip what?');
    return true;
  }
  final words = rest.split(RegExp(r'\s+'));
  String? who;
  var what = rest;
  if (words.length > 1 && session.knowsActor(words.first)) {
    who = words.first;
    what = words.skip(1).join(' ');
  }

  try {
    final before = session.statsFor(session.actorFor(who ?? '').id);
    final beforeAc = before.armorClass;
    final beforeAttack = before.attackBonus;
    final beforeDamage = before.damage.toString();

    final result = session.equip(what, who: who);
    final after = session.statsFor(result.actor.id);

    stdout.writeln('\n${result.actor.name} takes up ${result.item.name}'
        '${result.replaced == null ? '' : ', putting away '
            '${result.replaced!.name}'}.');
    if (result.slot == EquipSlot.armor) {
      stdout.writeln('  AC $beforeAc -> ${after.armorClass}');
    } else {
      stdout.writeln('  Strike ${_signed(beforeAttack)} $beforeDamage'
          ' -> ${_signed(after.attackBonus)} ${after.damage}');
    }
  } on EquipException catch (e) {
    stdout.writeln(_wrap(e.message));
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
  }
  return true;
}

bool _unequip(WorldSession session, String rest) {
  if (rest.isEmpty) {
    stdout.writeln('Take off what — weapon or armour?');
    return true;
  }
  final words = rest.split(RegExp(r'\s+'));
  String? who;
  var slot = rest;
  if (words.length > 1 && session.knowsActor(words.first)) {
    who = words.first;
    slot = words.skip(1).join(' ');
  }

  try {
    final result = session.unequip(slot, who: who);
    stdout.writeln(result.removed == null
        ? '${result.actor.name} had nothing there.'
        : '${result.actor.name} puts away ${result.removed!.name}.');
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
  }
  return true;
}

String _signed(int value) => value >= 0 ? '+$value' : '$value';

/// What the party is worth, against what is expected of it, and what that
/// brings down on them.
void _renderWealth(WorldSession session) {
  final worth = session.wealth;
  final pack = session.inventory;
  final standing = session.notoriety;
  stdout
    ..writeln('\nThe party is worth ${formatCoin(worth.total)}.')
    ..writeln('  ${'Coin'.padRight(26)} ${formatCoin(worth.coin).padLeft(14)}')
    ..writeln('  ${'Gear, at what it costs'.padRight(26)} '
        '${formatCoin(worth.gear).padLeft(14)}');
  var onPeople = 0;
  for (final actor in session.actors) {
    final value = pack.valueOn(actor.id);
    onPeople += value;
    if (value == 0) continue;
    final loadout = pack.loadoutFor(actor.id);
    final names = [loadout.weapon?.name, loadout.armor?.name].nonNulls;
    stdout.writeln('    ${actor.name.padRight(24)} '
        '${formatCoin(value).padLeft(14)}  (${names.join(', ')})');
  }
  if (worth.gear - onPeople > 0) {
    stdout.writeln('    ${'In the pack'.padRight(24)} '
        '${formatCoin(worth.gear - onPeople).padLeft(14)}');
  }
  final size = session.actors.length;
  stdout
    ..writeln('\n${_wrap('A party of $size level ${standing.partyLevel} '
        '${size == 1 ? 'character' : 'characters'} is expected to be worth '
        '${formatCoin(worth.expected)}. You are at '
        '${worth.percentOfExpected}% of that.', indent: '  ')}')
    ..writeln('\nNotoriety: ${standing.tier.name}')
    ..writeln(_wrap(standing.tier.description, indent: '  '));

  final level = standing.hunterLevel;
  final threat = standing.tier.threat;
  if (standing.tier.isHunted && level != null && threat != null) {
    stdout.writeln(_wrap(
        'Each step there is a ${standing.tier.chance}% chance something '
        'finds you. It would come at level $level, which is a threat of '
        '"${threat.name}" for ${size == 1 ? 'one character' : '$size'}.',
        indent: '  '));
  }
  if (session.huntsSurvived > 0) {
    stdout.writeln('  Hunters beaten: ${session.huntsSurvived}');
  }
  stdout.writeln('');
  for (final tier in session.campaign.hunts.tiers) {
    final here = tier.name == standing.tier.name ? '>' : ' ';
    final brings = tier.isHunted
        ? '${tier.threat!.name} threat, ${tier.chance}% a step'
        : 'nothing comes';
    stdout.writeln('  $here ${tier.name.padRight(12)} '
        '${'from ${tier.fromPercent}%'.padRight(10)} $brings');
  }
}

/// Everything the party has come away with, and where from.
void _renderLedger(WorldSession session) {
  final ledger = session.ledger;
  if (ledger.isEmpty) {
    stdout.writeln('The party has found nothing yet.');
    return;
  }
  final things = switch (ledger.itemCount) {
    0 => 'nothing else',
    1 => 'one thing worth ${formatCoin(ledger.itemCopper)}',
    final n => '$n things worth ${formatCoin(ledger.itemCopper)}',
  };
  stdout.writeln('\nFound so far: ${formatCoin(ledger.totalCopper)} — '
      '${formatCoin(ledger.coinCopper)} in coin, and $things.\n');
  for (final entry in ledger.entries) {
    final what = entry.kind == LootKind.coin
        ? 'coin'
        : session.campaign.gear.byId(entry.itemId ?? '')?.name ??
            entry.itemId ??
            'something';
    stdout.writeln('  ${entry.source.padRight(30)} '
        '${what.padRight(28)} ${formatCoin(entry.copper).padLeft(12)}');
  }
}

/// Says so when the party's wealth moves them up, or down, the ladder.
void _announceNotoriety(WorldSession session, NotorietyTier before) {
  final now = session.notoriety.tier;
  if (now.name == before.name) return;
  final rising = now.fromPercent > before.fromPercent;
  stdout.writeln('\n  *** ${rising ? 'Word spreads' : 'Word dies down'}: you '
      'are ${now.name}. ***');
  stdout.writeln(_wrap(now.description, indent: '  '));
}

void _announceArcs(WorldSession session) {
  final settled = session.settleArcs();
  for (final arc in settled.completed) {
    stdout.writeln('\n  *** ${arc.isSide ? 'Side quest' : 'Quest'} complete: '
        '${arc.name}${_rewardNote(arc)} ***');
  }
  if (settled.worldState.isEmpty) return;
  stdout.writeln('\n  *** The world shifts: '
      '${settled.worldState.join(', ')} ***');
}

String _rewardNote(CampaignArc arc) {
  final reward = arc.reward;
  if (reward == null || reward.isEmpty) return '';
  return ' (${[
    if (reward.copper > 0) formatCoin(reward.copper),
    if (reward.xp > 0) '${reward.xp} XP',
  ].join(', ')})';
}

/// One line on where a character stands between level 1 and level 20.
String _xpLine(XpProgress p) {
  if (p.isMax) {
    return 'Level $maxLevel — the top of the track, '
        '${groupThousands(p.total)} XP in all';
  }
  final ready = p.earnedLevel > p.level
      ? ' — level ${p.earnedLevel} earned; level up in Pathbuilder'
      : '';
  return 'XP ${groupThousands(p.xp)}/${groupThousands(xpToLevel)} toward '
      'level ${p.level + 1} · ${groupThousands(p.total)} of '
      '${groupThousands(XpProgress.fullTrack)} to level $maxLevel$ready';
}

/// Every character's place on the track from level 1 to level 20.
void _renderExperience(WorldSession session) {
  stdout.writeln('\nExperience: ${groupThousands(xpToLevel)} XP a level, '
      '${groupThousands(XpProgress.fullTrack)} from level 1 to level '
      '$maxLevel.');
  final numbers = [for (var l = 1; l <= maxLevel; l++) '$l'.padLeft(3)];
  for (final actor in session.actors) {
    final p = session.experience.progressOf(actor.id);
    // Filled to the sheet's level; a + for levels earned but not yet taken
    // in Pathbuilder; a dot for the road still ahead.
    final marks = [
      for (var l = 1; l <= maxLevel; l++)
        (l <= p.level
                ? '■'
                : l <= p.earnedLevel
                    ? '+'
                    : '·')
            .padLeft(3),
    ];
    stdout
      ..writeln('\n  ${actor.name} — level ${p.level}')
      ..writeln('  ${numbers.join()}')
      ..writeln('  ${marks.join()}')
      ..writeln(_wrap(_xpLine(p), indent: '    '));
  }
  stdout.writeln('\n  (■ reached, + earned and waiting on Pathbuilder, '
      '· still to come)');
}

/// Says what XP the last thing earned, and says so loudly for anyone it has
/// taken to their next level — which happens in Pathbuilder, not here.
void _announceExperience(WorldSession session, Map<String, int> before) {
  final xp = session.experience;
  final gained = {
    for (final a in session.actors) a.id: xp.xpOf(a.id) - (before[a.id] ?? 0),
  };
  final earned = gained.values.fold(0, (m, g) => g > m ? g : m);
  if (earned <= 0) return;
  stdout.writeln('\n  [+$earned XP each]');
  for (final actor in session.actors) {
    final was = before[actor.id] ?? 0;
    if (was < xpToLevel && xp.readyToLevel(actor.id)) {
      stdout.writeln('\n  *** ${actor.name} has ${xp.xpOf(actor.id)} XP — '
          'enough for level ${actor.character.level + 1}. Level up in '
          'Pathbuilder and re-import; the thousand comes off when the new '
          'sheet arrives. ***');
    }
  }
}

void _renderArcs(WorldSession session) {
  final active = session.activeArcs();
  if (active.isEmpty) {
    stdout.writeln('Nothing is underway.');
    return;
  }
  for (final arc in active) {
    final progress = arc.progress(session.flags);
    stdout.writeln('\n${arc.name}${arc.isSide ? '  (side quest)' : ''} '
        '(${progress.done}/${progress.total})${_rewardNote(arc)}');
    for (final objective in arc.objectives) {
      final done = session.flags.contains(objective.condition);
      stdout.writeln('  [${done ? 'x' : ' '}] ${objective.task}');
    }
  }
}

void _renderRoom(WorldSession session,
    {bool full = false, bool showWeather = false}) {
  final view = session.look();
  stdout.writeln('\n## ${view.room.title}');
  if (view.town != null) {
    stdout.writeln('   ${view.town!.name}'
        '${view.isNight ? ' · night' : ''}');
  }
  stdout.writeln();
  if (full) stdout.writeln(_wrap(view.room.description));
  // Weather is an arrival note, not a per-step refrain: repeating the same
  // fog line every time the party takes a step turns atmosphere into noise.
  if (showWeather && view.weather != null) {
    stdout.writeln('\n${_wrap(view.weather!)}');
  }

  for (final npc in view.npcs) {
    stdout.writeln('\n${_wrap(npc.appearance)}');
  }
  final shop = session.shopHere;
  if (shop != null) {
    stdout.writeln('\n  (${shop.name} — "list" to see what is for sale)');
  }

  for (final item in view.items) {
    if (item.inRoomText != null) {
      stdout.writeln('\n${_wrap(item.inRoomText!)}');
    }
  }

  for (final encounter in view.encounters) {
    stdout.writeln('\n${_wrap(session.describeEncounter(encounter))}');
    stdout.writeln(encounter.ambush
        ? '\n  (${encounter.name} — between you and the way on)'
        : '\n  (${encounter.name} — type "fight" to begin)');
  }

  stdout.writeln('\nExits: ${view.openDirections.join(', ')}'
      '${view.barredDirections.isEmpty ? '' : '  (barred: '
          '${view.barredDirections.map((b) => b.direction).join(', ')})'}');
}

String _actorIdFor(String name, List<SessionActor> existing) {
  final base = name.trim().split(RegExp(r'\s+')).first.toLowerCase();
  final taken = {for (final a in existing) a.id};
  if (!taken.contains(base)) return base;
  for (var n = 2;; n++) {
    if (!taken.contains('$base$n')) return '$base$n';
  }
}

String _wrap(String text, {int width = 70, String indent = ''}) {
  final out = <String>[];
  for (final paragraph in text.split('\n')) {
    if (paragraph.trim().isEmpty) {
      out.add('');
      continue;
    }
    final line = StringBuffer(indent);
    for (final word in paragraph.split(' ')) {
      if (line.length > indent.length &&
          line.length + word.length + 1 > width) {
        out.add(line.toString());
        line
          ..clear()
          ..write(indent);
      }
      if (line.length > indent.length) line.write(' ');
      line.write(word);
    }
    if (line.toString().trim().isNotEmpty) out.add(line.toString());
  }
  return out.join('\n');
}

Map<String, String> _parseArgs(List<String> args) {
  final out = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final body = arg.substring(2);
    final eq = body.indexOf('=');
    if (eq == -1) {
      out[body] = '';
    } else {
      out[body.substring(0, eq)] = body.substring(eq + 1);
    }
  }
  return out;
}

const _commands = '''
  north/south/east/west/up/down (or n/s/e/w/u/d)  walk
  look                                            describe the room again
  exits                                           list ways out, open and shut
  who                                             who is here, and their topics
  talk <name>                                     talk to someone properly
  ask <name> about <topic>                        raise a single topic
  quests                                          arc progress
  xp                                              everyone's XP, level 1 to 20
  inventory (i)                                   what the party is carrying
  list                                            what a shop here is selling
  buy <item> / sell <item>                        trade (you get half back)
  value <item>                                    what a shop would pay
  purse                                           the party's coin
  wealth                                          what you're worth, and who
                                                  that brings after you
  ledger                                          everything found, and where
  sheet [who]                                     AC, Strike, HP as equipped
  equip [who] <item>                              wield or wear something
  unequip [who] weapon|armour                     put it away again
  wait [hours]                                    let time pass
  quit                                            stop
''';

const _usage = '''
usage: walk [options]

  --campaign=DIR     Campaign directory (default: $_defaultCampaign)
  --characters=A,B   Pathbuilder exports (default: $_defaultCharacter)
  --seed=N           Dice seed; omit for a random one
  --room=ID          Start somewhere other than the first room
  --hour=N           Start at a given hour (default 8)
  --flags=a,b        Start with these flags already set
  --gold=N           Start with N more gold, to see who comes for it
  --commands=a,b,c   Play a scripted sequence instead of reading stdin
  --help             Show this message

Commands:
$_commands''';

/// Takes or destroys something in the room.
bool _takeOrDestroy(WorldSession session, String what,
    {required bool destroy}) {
  if (what.isEmpty) {
    stdout.writeln(destroy ? 'Destroy what?' : 'Take what?');
    return true;
  }
  try {
    final result = destroy ? session.destroy(what) : session.take(what);
    stdout.writeln('\n${_wrap(result.said)}');
    for (final flag in result.flagsSet) {
      stdout.writeln('\n  [$flag]');
    }
    _announceArcs(session);
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
  }
  return true;
}

/// Runs a fight to its end.
///
/// A fight is its own mode with its own verbs, so it gets its own loop rather
/// than being folded into the walking one; a player in initiative should not
/// be offered directions to stroll in.
bool _fight(
  WorldSession session,
  String? Function({String prompt}) nextCommand, {
  String? encounterId,
}) {
  final EncounterSession fight;
  try {
    fight = session.beginEncounter(encounterId: encounterId);
  } on InvalidMoveException catch (e) {
    stdout.writeln(_wrap(e.message));
    return true;
  }

  stdout
    ..writeln('\n${'=' * 70}')
    ..writeln(fight.encounter.name.toUpperCase())
    ..writeln('=' * 70)
    ..writeln('\nInitiative (d20 + Perception):');
  for (final roll in fight.initiativeRolls) {
    stdout.writeln('  ${roll.combatant.isEnemy ? ' ' : '*'} '
        '${roll.combatant.name.padRight(26)} '
        'd20(${roll.die}) ${_signed(roll.modifier)} = ${roll.total}');
  }
  if (fight.openingStrikes.isNotEmpty) {
    stdout.writeln('\nBefore anyone in the party can move:');
    _narrate(fight.openingStrikes);
  }
  _renderCombatants(fight);

  while (!fight.isOver) {
    if (!fight.isPartyTurn) {
      _narrate(fight.endTurn());
      continue;
    }

    stdout.writeln('\n-- ${fight.current.name}, round ${fight.round}, '
        '${fight.actionsLeft} action(s) --');
    final targets = fight.targetsInReach();
    stdout.writeln(targets.isEmpty
        ? '   Nothing in reach. Close the distance.'
        : '   In reach: ${targets.map((t) => '${t.id} (${t.hp}/${t.maxHp})').join(', ')}');

    final line = nextCommand(prompt: 'fight> ');
    if (line == null) {
      stdout.writeln('\n(script exhausted mid-fight)');
      return false;
    }
    if (line.isEmpty) continue;

    final words = line.split(RegExp(r'\s+'));
    final verb = words.first.toLowerCase();
    final rest = words.skip(1).join(' ');

    try {
      switch (verb) {
        case 'strike':
        case 'hit':
          final target =
              rest.isEmpty ? (targets.isEmpty ? null : targets.first.id) : rest;
          if (target == null) {
            stdout.writeln('Nothing in reach to strike.');
            break;
          }
          final result = fight.strike(target);
          stdout.writeln('\n  ${_strikeLine(result)}');
        case 'close':
        case 'stride':
          final moved = fight.stride();
          stdout.writeln('\n  ${fight.current.name} closes to '
              '${moved.zone}.');
        case 'back':
        case 'withdraw':
          final moved = fight.stride(closer: false);
          stdout.writeln('\n  ${fight.current.name} falls back to '
              '${moved.zone}.');
        case 'end':
        case 'done':
          _narrate(fight.endTurn());
        case 'flee':
          fight.flee();
        case 'status':
          _renderCombatants(fight);
        case 'quit':
        case 'q':
          return false;
        default:
          stdout.writeln('In a fight you can: strike <target>, close, back, '
              'end, status, flee.');
      }
    } on InvalidActionException catch (e) {
      stdout.writeln('  ${e.message}');
    }

    if (fight.actionsLeft == 0 && !fight.isOver && fight.isPartyTurn) {
      _narrate(fight.endTurn());
    }
  }

  stdout.writeln('\n${'=' * 70}');
  switch (fight.outcome!) {
    case EncounterOutcome.victory:
      stdout.writeln('The fight is over. You are still standing.');
      final flags = session.concludeEncounter(fight);
      _renderSpoils(fight);
      if (fight.loot.isNotEmpty) {
        stdout.writeln('\nAmong what is left:');
        for (final item in fight.loot) {
          stdout.writeln('\n  ${item.name} '
              '(level ${item.level} ${item.rarity.name} ${item.type})');
          stdout.writeln(_wrap(item.description, indent: '    '));
        }
      }
      for (final flag in flags) {
        stdout.writeln('\n  [$flag]');
      }
      _announceArcs(session);
    case EncounterOutcome.defeat:
      stdout.writeln('The party goes down. Valorheim does not stop for it.');
      final before = session.inventory.coin;
      session.concludeEncounter(fight);
      final taken = before - session.inventory.coin;
      if (taken > 0) {
        stdout.writeln('\n  ${fight.enemies.first.name} goes through your '
            'packs while you lie there, and takes ${formatCoin(taken)}.');
      }
    case EncounterOutcome.fled:
      stdout.writeln('You break off and go.');
      session.concludeEncounter(fight);
  }
  return true;
}

void _narrate(List<StrikeResult> log) {
  for (final result in log) {
    stdout.writeln('\n  ${_strikeLine(result)}');
  }
}

/// A strike with its dice: the attack roll against AC, and on a hit the
/// damage dice as they fell.
String _strikeLine(StrikeResult r) {
  final check = r.outcome;
  final map = r.penalty == 0 ? '' : ', MAP ${r.penalty}';
  final natural = check.wasShiftedByNatural ? ', natural ${check.dieRoll}' : '';
  final verdict = switch (check.degree) {
    DegreeOfSuccess.criticalSuccess => 'CRITICAL HIT',
    DegreeOfSuccess.success => 'hit',
    _ => 'miss',
  };
  final head = '${r.attacker.name} strikes ${r.target.name}: '
      'd20(${check.dieRoll}) ${_signed(check.modifier)} = ${check.total} '
      'vs AC ${check.dc}$map$natural — $verdict';
  final damage = r.damageRoll;
  if (damage == null) return head;
  final dropped = r.targetDropped ? ' ${r.target.name} goes down.' : '';
  return '$head\n    damage $damage.$dropped';
}

/// The rolls that settle what a won fight was worth.
void _renderSpoils(EncounterSession fight) {
  if (fight.coinRoll case final coin?) {
    stdout.writeln('\n  Coin on the fallen: $coin gp');
  }
  if (fight.lootRolls.isNotEmpty) {
    stdout.writeln('  Searching them (d100, found at or under the chance):');
    for (final roll in fight.lootRolls) {
      stdout.writeln('    $roll');
    }
  }
  if (fight.xpAwards.isNotEmpty) {
    stdout.writeln('  XP, by level against the party\'s '
        '${fight.xpAwards.first.partyLevel}:');
    for (final award in fight.xpAwards) {
      stdout.writeln('    $award');
    }
  }
}

void _renderCombatants(EncounterSession fight) {
  stdout.writeln('');
  for (final c in fight.combatants) {
    final bar = c.isDown ? 'down' : '${c.hp}/${c.maxHp}';
    final where = fight.zones[c.zoneIndex];
    stdout.writeln('  ${c.isEnemy ? ' ' : '*'} ${c.id.padRight(28)} '
        '${bar.padLeft(8)}  $where');
  }
}
