import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

// A three-room road built to exercise the rules rather than the story:
//
//   Inn (A) --east--> Road (B, ambush) --east--> End (C, the bell)
//
// Ringing the bell brings the road fight back, which is the shape of every
// wrong turn in the real campaign.

const _world = '{"world_metadata": {"name": "Testland"}}';

const _locations = '''
{"towns": {}, "rooms": [
  {"room_id": "A_Inn", "title": "Inn", "description": "a",
   "exits": {"east": "B_Road"}},
  {"room_id": "B_Road", "title": "Road", "description": "b",
   "exits": {"west": "A_Inn", "east": "C_End"}},
  {"room_id": "C_End", "title": "End", "description": "c",
   "exits": {"west": "B_Road"}}
]}''';

const _npcs = '''
{"npcs": [
  {"npc_id": "npc_liar", "name": "Pell the Liar", "location": "A_Inn",
   "appearance": "x", "greeting": "Evening."},
  {"npc_id": "npc_mute", "name": "Silent Tom", "location": "A_Inn",
   "appearance": "x", "greeting": "Tom nods."}
]}''';

const _bestiary = '''
{"creatures": [
  {"creature_id": "c_straw", "name": "Straw Dummy", "level": -1, "ac": 5,
   "hp": 1, "perception": -5,
   "attacks": [{"name": "flop", "bonus": -10, "damage": "1"}]},
  {"creature_id": "c_wall", "name": "Standing Stone", "level": 10, "ac": 60,
   "hp": 900, "perception": -5,
   "attacks": [{"name": "nothing", "bonus": -20, "damage": "1"}]}
],
"encounters": [
  {"encounter_id": "e_road", "location": "B_Road", "name": "Men on the Road",
   "description": "They step out of the hedge.",
   "rearm_description": "They were waiting for you to come back.",
   "creatures": ["c_straw"], "start_zone": "engaged", "ambush": true,
   "victory_flags": ["road_cleared"], "rearm_on": ["bell_rung", "bell_rung_twice"]},
  {"encounter_id": "e_stone", "location": "C_End", "name": "A Stone",
   "description": "It is only a stone.", "creatures": ["c_wall"],
   "start_zone": "engaged", "victory_flags": ["stone_moved"]}
]}''';

const _items = '''
{"items": [
  {"item_id": "i_bell", "name": "A Bell", "location": "C_End",
   "description": "A brass bell.", "takeable": true,
   "acquire_flags": ["bell_rung"]}
]}''';

const _conversations = '''
{"conversations": [{
  "npc": "npc_liar",
  "entries": [
    {"scene": "caught", "requires": ["bell_rung"]},
    {"scene": "again", "requires": ["met_liar"]},
    {"scene": "hello"}
  ],
  "scenes": [
    {"id": "hello", "title": "Pell", "body": "\\"Road's clear,\\" he says.",
     "options": [
       {"id": "thank", "label": "Thank him", "say": "Thanks, friend.",
        "outcome": {"text": "He smiles.", "setFlags": ["met_liar", "believed_liar"],
                    "goTo": "bye"}},
       {"id": "watch", "label": "Watch his face", "say": "Clear, you say?",
        "check": {"stat": "perception", "dc": -10},
        "outcomes": {
          "success": {"text": "His eyes go to the door.",
                      "setFlags": ["met_liar", "caught_liar"], "goTo": "bye"},
          "failure": {"text": "He seems honest.",
                      "setFlags": ["met_liar", "believed_liar"], "goTo": "bye"}}},
       {"id": "stare", "label": "Stare him down", "say": "Try again.",
        "check": {"stat": "intimidation", "dc": 100},
        "outcomes": {
          "success": {"text": "He folds.", "goTo": "bye"},
          "failure": {"text": "He laughs at you.",
                      "setFlags": ["met_liar", "laughed_at"], "goTo": "hello"}}}
     ]},
    {"id": "again", "title": "Pell", "body": "\\"Back already?\\"",
     "options": [
       {"id": "forgive", "label": "Let it go", "say": "I believed you.",
        "outcome": {"text": "\\"Good.\\"", "clearFlags": ["caught_liar"],
                    "goTo": "bye"}},
       {"id": "gift", "label": "Take what he offers",
        "outcome": {"text": "He hands it over.",
                    "setFlags": ["loot_w_gift", "loot_w_nothing"], "goTo": "bye"}},
       {"id": "leave", "label": "Leave", "outcome": {"text": "You go.", "goTo": "bye"}}
     ]},
    {"id": "caught", "title": "Pell", "body": "He sees the bell in your hand.",
     "options": [
       {"id": "leave", "label": "Leave", "outcome": {"text": "You go.", "goTo": "bye"}}
     ]},
    {"id": "bye", "title": "Pell", "body": "He goes back to his cups.",
     "isEnding": true}
  ]
}]}''';

const _gear = '''
{"gear": [{"item_id": "w_gift", "name": "A Gift", "level": 1, "type": "weapon",
  "description": "x", "traits": ["simple"],
  "stats": {"damage": "1d4", "bonus": 0, "magic": false}}]}''';

Campaign _road({String? conversations}) => const CampaignLoader().load(
      id: 'road',
      title: 'The Road',
      worldConfigJson: _world,
      locationsJson: _locations,
      npcsJson: _npcs,
      bestiaryJson: _bestiary,
      itemsJson: _items,
      gearJson: _gear,
      conversationsJson: conversations ?? _conversations,
    );

WorldSession _walk({
  int seed = 3,
  String room = 'A_Inn',
  Set<String>? flags,
  Campaign? campaign,
}) =>
    WorldSession(
      campaign: campaign ?? _road(),
      actors: [SessionActor(id: 'korash', character: loadKorash())],
      roller: DiceRoller(seed),
      roomId: room,
      flags: flags,
    );

/// Wins whatever fight is waiting. The dummy has AC 5 and 1 HP.
List<String> _winHere(WorldSession world) {
  final fight = world.beginEncounter();
  var guard = 0;
  while (!fight.isOver && guard++ < 50) {
    if (fight.isPartyTurn) {
      final targets = fight.targetsInReach();
      if (targets.isEmpty) {
        fight.stride();
      } else {
        fight.strike(targets.first.id);
      }
      if (fight.actionsLeft == 0 && !fight.isOver) fight.endTurn();
    } else {
      fight.endTurn();
    }
  }
  expect(fight.outcome, EncounterOutcome.victory);
  return world.concludeEncounter(fight);
}

void main() {
  group('an ambush', () {
    test('springs when the party walks in', () {
      final world = _walk();
      final result = world.move('east');
      expect(result.ambush?.id, 'e_road');
    });

    test('leaves only the way back', () {
      final world = _walk()..move('east');
      expect(
        () => world.move('east'),
        throwsA(isA<InvalidMoveException>()
            .having((e) => e.message, 'message', contains('the way you came'))),
      );
      expect(world.move('west').to, 'A_Inn');
    });

    test('is still in the way after running from it', () {
      final world = _walk()..move('east');
      world.beginEncounter().flee();
      expect(() => world.move('east'), throwsA(isA<InvalidMoveException>()));
    });

    test('clears the way once it is won', () {
      final world = _walk()..move('east');
      final set = _winHere(world);
      expect(set, containsAll(['won_e_road_wave_0', 'road_cleared']));
      expect(world.move('east').to, 'C_End');
    });

    test('an ordinary fight never blocks anyone', () {
      final world = _walk(room: 'B_Road', flags: {'road_cleared'})
        ..move('east');
      expect(world.availableEncounters().single.id, 'e_stone');
      expect(world.move('west').to, 'B_Road');
    });

    test('a session started in the room may leave by any way', () {
      // With no way in known, there is no "back" to insist on.
      final world = _walk(room: 'B_Road');
      expect(world.move('east').to, 'C_End');
    });

    test('remembers the way back across a save', () {
      final campaign = _road();
      final world = _walk(campaign: campaign)..move('east');
      final restored = WorldSession.restore(
        campaign: campaign,
        actors: world.actors,
        snapshot: world.snapshot(),
      );
      expect(restored.cameFrom, 'A_Inn');
      expect(() => restored.move('east'), throwsA(isA<InvalidMoveException>()));
    });
  });

  group('a fight that comes back', () {
    test('comes back when its flag is set, as another wave', () {
      final world = _walk()..move('east');
      _winHere(world);
      world
        ..move('east')
        ..take('bell');

      final road = world.campaign.bestiary.encounterById('e_road')!;
      expect(road.waveFor(world.flags), 1);
      expect(road.isAvailable(world.flags), isTrue);
    });

    test('is waiting on the way back, and blocks the way home', () {
      final world = _walk()..move('east');
      _winHere(world);
      world
        ..move('east')
        ..take('bell');

      final back = world.move('west');
      expect(back.ambush?.id, 'e_road');
      // They came in from the far end this time, so home is the way on.
      expect(() => world.move('west'), throwsA(isA<InvalidMoveException>()));
      expect(world.move('east').to, 'C_End');
    });

    test('reads differently the second time', () {
      final world = _walk()..move('east');
      final road = world.campaign.bestiary.encounterById('e_road')!;
      expect(world.describeEncounter(road), 'They step out of the hedge.');
      _winHere(world);
      world
        ..move('east')
        ..take('bell')
        ..move('west');
      expect(world.describeEncounter(road),
          'They were waiting for you to come back.');
    });

    test('is done again once the second wave is beaten', () {
      final world = _walk()..move('east');
      _winHere(world);
      world
        ..move('east')
        ..take('bell')
        ..move('west');
      final set = _winHere(world);
      expect(set, contains('won_e_road_wave_1'));
      // The victory flag was already set, so winning again does not re-award
      // it; arcs watching it see nothing change.
      expect(set, isNot(contains('road_cleared')));
      expect(world.move('west').to, 'A_Inn');
    });

    test('each rearm flag is one more wave', () {
      final road = _road().bestiary.encounterById('e_road')!;
      expect(road.waveFor({'bell_rung', 'bell_rung_twice'}), 2);
      expect(
          road.isAvailable(
              {'bell_rung', 'bell_rung_twice', 'won_e_road_wave_1'}),
          isTrue,
          reason: 'wave 2 has not been beaten');
    });

    test('an old save that only has the victory flag still counts as won', () {
      final road = _road().bestiary.encounterById('e_road')!;
      expect(road.isAvailable({'road_cleared'}), isFalse);
    });

    test('a fight nobody has won is simply there, rearmed or not', () {
      final road = _road().bestiary.encounterById('e_road')!;
      expect(road.isAvailable({'bell_rung'}), isTrue);
    });
  });

  group('a conversation', () {
    test('opens where the story says it should', () {
      final world = _walk();
      expect(world.beginConversation('pell')!.talk.currentScene.id, 'hello');

      final met = _walk(flags: {'met_liar'});
      expect(met.beginConversation('pell')!.talk.currentScene.id, 'again');

      // Earlier entries win: being caught outranks having met.
      final caught = _walk(flags: {'met_liar', 'bell_rung'});
      expect(caught.beginConversation('pell')!.talk.currentScene.id, 'caught');
    });

    test('carries what the party said', () {
      final world = _walk();
      final talk = world.beginConversation('pell')!.talk;
      final event = talk.choose('thank');
      expect(event.said, 'Thanks, friend.');
      expect(event.actorName, 'Korash Blackearth');
      expect(event.narration, 'He smiles.');
    });

    test('an action is not rendered as speech', () {
      final world = _walk(flags: {'met_liar'});
      final event = world.beginConversation('pell')!.talk.choose('leave');
      expect(event.said, isNull);
    });

    test('rolls the party against the liar', () {
      final world = _walk();
      final talk = world.beginConversation('pell')!.talk;
      final event = talk.choose('watch');
      expect(event.check, isNotNull);
      expect(event.check!.degree.isSuccess, isTrue);
      expect(talk.flags, contains('caught_liar'));
    });

    test('a failed roll can send the talk back round', () {
      final world = _walk();
      final talk = world.beginConversation('pell')!.talk;
      talk.choose('stare');
      expect(talk.currentScene.id, 'hello');
      expect(talk.isFinished, isFalse);
    });

    test('changes nothing in the world until it is concluded', () {
      final world = _walk();
      final talk = world.beginConversation('pell')!.talk..choose('thank');
      expect(world.flags, isNot(contains('believed_liar')));
      final set = world.concludeConversation(talk);
      expect(set, containsAll(['met_liar', 'believed_liar']));
      expect(world.flags, contains('believed_liar'));
    });

    test('a flag it clears is cleared in the world too', () {
      final world = _walk(flags: {'met_liar', 'caught_liar'});
      final talk = world.beginConversation('pell')!.talk..choose('forgive');
      world.concludeConversation(talk);
      expect(world.flags, isNot(contains('caught_liar')));
    });

    test('walking off halfway keeps what was already said', () {
      final world = _walk();
      final talk = world.beginConversation('pell')!.talk..choose('stare');
      expect(talk.isFinished, isFalse);
      world.concludeConversation(talk);
      expect(world.flags, contains('laughed_at'));
    });

    test('what somebody hands over ends up in the pack', () {
      final world = _walk(flags: {'met_liar'});
      final talk = world.beginConversation('pell')!.talk..choose('gift');
      world.concludeConversation(talk);
      expect(world.inventory.carried.single.id, 'w_gift');
    });

    test('a gift the campaign has no item for is ignored, not fatal', () {
      final world = _walk(flags: {'met_liar'});
      final talk = world.beginConversation('pell')!.talk..choose('gift');
      expect(() => world.concludeConversation(talk), returnsNormally);
      expect(world.flags, contains('loot_w_nothing'));
    });

    test('somebody with nothing more to say has no conversation', () {
      expect(_walk().beginConversation('tom'), isNull);
    });

    test('somebody who is not here cannot be talked to', () {
      expect(() => _walk(room: 'B_Road').beginConversation('pell'),
          throwsA(isA<InvalidMoveException>()));
    });
  });

  group('reading conversations', () {
    test('refuses a way in that goes nowhere', () {
      expect(
        () => const CampaignLoader().readConversations('''
{"conversations": [{"npc": "n", "entries": [{"scene": "nope"}],
 "scenes": [{"id": "a", "title": "t", "body": "b", "isEnding": true}]}]}'''),
        throwsA(isA<CampaignFormatException>()
            .having((e) => e.message, 'message', contains('"nope"'))),
      );
    });

    test('refuses a conversation with no way in at all', () {
      expect(
        () => const CampaignLoader().readConversations('''
{"conversations": [{"npc": "n", "entries": [],
 "scenes": [{"id": "a", "title": "t", "body": "b", "isEnding": true}]}]}'''),
        throwsA(isA<CampaignFormatException>()),
      );
    });

    test('names the speaker when a line leads nowhere', () {
      expect(
        () => const CampaignLoader().readConversations('''
{"conversations": [{"npc": "npc_x", "entries": [{"scene": "a"}],
 "scenes": [{"id": "a", "title": "t", "body": "b", "options": [
   {"id": "o", "label": "l", "outcome": {"text": "t", "goTo": "gone"}}]}]}]}'''),
        throwsA(isA<CampaignFormatException>()
            .having((e) => e.message, 'message', contains('npc_x'))),
      );
    });

    test('the survey counts what conversations can set', () {
      final flags = _road().conversations.producibleFlags;
      expect(flags, containsAll(['met_liar', 'caught_liar', 'believed_liar']));
    });

    test('the survey reports a conversation for nobody', () {
      final campaign = _road(conversations: '''
{"conversations": [{"npc": "npc_ghost", "entries": [{"scene": "a"}],
 "scenes": [{"id": "a", "title": "t", "body": "b", "isEnding": true}]}]}''');
      expect(campaign.survey().orphanedConversations.single.npcId, 'npc_ghost');
    });
  });
}
