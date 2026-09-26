import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

import 'campaign_test.dart' show loadShatteredSeals;
import 'helpers.dart';

late Campaign _campaign;

/// The campaign with its sky replaced by [book].
Campaign _under(WeatherBook book) => Campaign(
      id: _campaign.id,
      title: _campaign.title,
      world: _campaign.world,
      locations: _campaign.locations,
      npcs: _campaign.npcs,
      gear: _campaign.gear,
      arcs: _campaign.arcs,
      bestiary: _campaign.bestiary,
      items: _campaign.items,
      conversations: _campaign.conversations,
      economy: _campaign.economy,
      hunts: _campaign.hunts,
      weather: book,
    );

/// A sky that does the same thing every day, everywhere.
WeatherBook _always(String weather) => WeatherBook(
      calendar: _campaign.weather.calendar,
      travel: _campaign.weather.travel,
      types: _campaign.weather.types,
      tables: {
        for (final region in _campaign.world.regions)
          region.id: {
            for (final season in _campaign.weather.calendar.seasons)
              season.id: [WeatherBand(upTo: 100, weather: weather)],
          },
      },
    );

WorldSession _world({
  Campaign? campaign,
  String room = 'MH_001_Square',
  int hour = 8,
  int seed = 3,
  Set<String> flags = const {},
}) =>
    WorldSession(
      campaign: campaign ?? _campaign,
      actors: [SessionActor(id: 'korash', character: loadKorash())],
      roller: DiceRoller(seed),
      roomId: room,
      hour: hour,
      flags: flags,
    );

WorldSession _restored(WorldSession world) => WorldSession.restore(
      campaign: world.campaign,
      actors: world.actors,
      snapshot:
          jsonDecode(jsonEncode(world.snapshot())) as Map<String, Object?>,
    );

/// Paces between the square and the forge, which are both in town.
void _pace(WorldSession world, int steps) {
  for (var i = 0; i < steps; i++) {
    world.move(world.roomId == 'MH_001_Square' ? 'west' : 'east');
  }
}

/// Waits an hour at a time until [test] says stop, or a day has gone.
List<WorldEvent> _waitUntil(
    WorldSession world, bool Function(List<WorldEvent>) test) {
  final seen = <WorldEvent>[];
  for (var i = 0; i < 30; i++) {
    world.advanceTime(1);
    seen.addAll(world.drainEvents());
    if (test(seen)) break;
  }
  return seen;
}

void main() {
  setUpAll(() => _campaign = loadShatteredSeals());

  itemBonusTests();

  group('the calendar', () {
    test('opens on day 12 of autumn, and turns the year after winter', () {
      final cal = _campaign.weather.calendar;
      expect(cal.dateOf(1).season.id, 'autumn');
      expect(cal.dateOf(1).dayOfSeason, 12);
      expect(cal.dateOf(1).year, 1);
      expect(cal.dateOf(19).dayOfSeason, 30);
      expect(cal.dateOf(20).season.id, 'winter');
      expect(cal.dateOf(20).dayOfSeason, 1);
      expect(cal.dateOf(50).season.id, 'spring');
      expect(cal.dateOf(50).year, 2);
      expect(cal.dateOf(1 + cal.daysInYear).season.id, 'autumn');
      expect(cal.dateOf(1 + cal.daysInYear).year, 2);
    });

    test('midnight is a new day, and says so', () {
      final world = _world(hour: 22)..drainEvents();
      world.advanceTime(3);
      expect(world.day, 2);
      expect(world.hour, 1);
      expect(world.drainEvents().whereType<NewDay>().single.day, 2);
    });

    test('dawn and dusk are announced as they pass', () {
      final world = _world(hour: 17)..drainEvents();
      world.advanceTime(14);
      final turns = world.drainEvents().whereType<DawnOrDusk>().toList();
      expect(turns.map((t) => t.isDawn), [false, true]);
    });
  });

  group('the weather', () {
    test('every region has a table for every season, covering the d100', () {
      expect(_campaign.survey().weatherProblems, isEmpty);
      for (final region in _campaign.world.regions) {
        for (final season in _campaign.weather.calendar.seasons) {
          final table = _campaign.weather.tableFor(region.id, season.id);
          expect(table.last.upTo, 100, reason: '${region.id} ${season.id}');
        }
      }
    });

    test('the survey notices a table that stops short, or a made-up sky', () {
      final book = WeatherBook(
        calendar: _campaign.weather.calendar,
        types: _campaign.weather.types,
        tables: {
          'r_x': {
            for (final s in _campaign.weather.calendar.seasons)
              s.id: const [
                WeatherBand(upTo: 60, weather: 'clear'),
                WeatherBand(upTo: 90, weather: 'frogs'),
              ],
          },
        },
      );
      final problems = book.problems(regionIds: ['r_x', 'r_missing']);
      expect(problems, contains(contains('stops at 90, not 100')));
      expect(problems, contains(contains('"frogs"')));
      expect(problems, contains(contains('r_missing has no weather')));
    });

    test('is rolled once a day per region, on its own table, and shown', () {
      final world = _world();
      final rolled = world.drainEvents().whereType<WeatherRolled>().single;
      final w = rolled.weather;
      expect(w.day, 1);
      expect(_campaign.weather.lookUp(w.regionId, w.season.id, w.die), w.type);
      _pace(world, 6);
      expect(world.drainEvents().whereType<WeatherRolled>(), isEmpty,
          reason: 'the same day, the same sky');
      world.advanceTime(24);
      expect(
          world.drainEvents().whereType<WeatherRolled>().single.weather.day, 2);
    });

    test('changes from day to day, within what the season allows', () {
      final world = _world(room: 'MH_002_GuardHall');
      final seen = <String>{};
      for (var d = 0; d < 18; d++) {
        seen.add(world.weatherToday!.type.id);
        world.advanceTime(24);
      }
      expect(seen.length, greaterThan(2));
      final autumn = {
        for (final band
            in _campaign.weather.tableFor('r_001_millhaven_valley', 'autumn'))
          band.weather,
      };
      expect(autumn.containsAll(seen), isTrue);
    });

    test("rolls on dice of its own, and never the world's", () {
      final world = _world(room: 'MH_002_GuardHall');
      final before = world.snapshot()['rollerState'];
      for (var d = 0; d < 10; d++) {
        world.advanceTime(24);
        world.weatherToday;
      }
      expect(world.snapshot()['rollerState'], before);
    });

    test('holds across a save', () {
      final world = _world()..advanceTime(30);
      final back = _restored(world);
      expect(back.day, world.day);
      expect(back.minute, world.minute);
      expect(back.weatherToday!.type, world.weatherToday!.type);
      expect(back.weatherToday!.die, world.weatherToday!.die);
      expect(back.drainEvents(), isEmpty, reason: 'loading is not news');
    });
  });

  group('the road', () {
    test(
        'takes minutes across town, an hour to the woods, a day to the '
        'capital', () {
      final world = _world(
          campaign: _under(_always('clear')),
          flags: {'Unlock_Travel_to_Valorheim'});
      expect(world.travelMinutes('west'), 15);
      world.move('west');
      expect(world.travelMinutes('west'), 60);
      world.move('east');
      expect(world.travelMinutes('northeast'), 480);
    });

    test('a stair is a stair', () {
      final world = _world(
          campaign: _under(_always('clear')),
          room: 'VC_003_GrandLibrary',
          flags: {'heard_of_the_under_archive'});
      expect(world.travelMinutes('down'), 10);
    });

    test('weather makes it longer, and a roof over both ends does not', () {
      final wet = _world(campaign: _under(_always('rain')));
      expect(wet.travelMinutes('west'), 23, reason: 'fifteen minutes in rain');
      final indoors =
          _world(campaign: _under(_always('rain')), room: 'MH_005_Forge');
      expect(indoors.travelMinutes('west'), 90,
          reason: 'out of the forge and into the wet');
    });

    test('moving takes the time it takes', () {
      final world = _world(campaign: _under(_always('clear')));
      final result = world.move('west');
      expect(result.minutes, 15);
      expect(world.clock, '08:15');
    });
  });

  group('getting tired', () {
    test('eight hours on the road is Fatigued, twelve is spent', () {
      final world = _world(campaign: _under(_always('clear')));
      for (var i = 0; i < 32; i++) {
        _pace(world, 1);
      }
      expect(world.endurance.travelMinutes, 480);
      expect(world.isFatigued, isTrue);
      expect(world.drainEvents().whereType<GrewTired>().single.spent, isFalse);
      for (var i = 0; i < 16; i++) {
        _pace(world, 1);
      }
      expect(world.isSpent, isTrue);
    });

    test('rain wears a party out sooner', () {
      final dry = _world(campaign: _under(_always('clear')));
      final wet = _world(campaign: _under(_always('rain')));
      for (var i = 0; i < 20; i++) {
        _pace(dry, 1);
        _pace(wet, 1);
      }
      expect(wet.endurance.travelMinutes,
          greaterThan(dry.endurance.travelMinutes));
    });

    test('a spent party can cross a square but not start a road', () {
      final world = _world(campaign: _under(_always('clear')));
      world.endurance.travelMinutes = 12 * 60;
      expect(world.isSpent, isTrue);
      world.move('west'); // fifteen minutes to the forge
      expect(() => world.move('west'), throwsA(isA<InvalidMoveException>()));
    });

    test('sixteen hours awake is Fatigued, road or not', () {
      final world = _world(room: 'MH_002_GuardHall')..advanceTime(16);
      expect(world.isFatigued, isTrue);
    });

    test('fatigue costs a point of AC in a fight', () {
      final world = _world(room: 'WW_002_Deep');
      final fresh = world.beginEncounter().party.single.armorClass;
      world.endurance.awakeMinutes = 16 * 60;
      final tired = world.beginEncounter().party.single.armorClass;
      expect(tired, fresh - 1);
    });
  });

  group('wounds', () {
    WorldSession fought() {
      final world = _world(room: 'WW_002_Deep');
      final fight = world.beginEncounter();
      var guard = 0;
      while (!fight.isOver && guard++ < 300) {
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
      world.concludeEncounter(fight);
      return world;
    }

    test('carry out of one fight and into the next', () {
      final world = fought();
      final v = world.vitalsOf('korash');
      expect(v.hp, lessThan(v.maxHp), reason: 'seed 3 costs something');
      // Picked up on the Mere Road, where the next fight is waiting.
      final snapshot =
          jsonDecode(jsonEncode(world.snapshot())) as Map<String, Object?>;
      snapshot['roomId'] = 'MR_001_MereRoad';
      snapshot['flags'] = [
        ...(snapshot['flags'] as List),
        'heard_of_the_mere_road',
      ];
      final there = WorldSession.restore(
          campaign: _campaign, actors: world.actors, snapshot: snapshot);
      expect(there.beginEncounter().party.single.hp, v.hp);
    });

    test('a party that loses comes to at 1 HP an hour later', () {
      final world = _world(room: 'WW_002_Deep');
      final fight = world.beginEncounter();
      var guard = 0;
      while (!fight.isOver && guard++ < 500) {
        fight.endTurn();
      }
      expect(fight.outcome, EncounterOutcome.defeat);
      final before = world.minute;
      world.concludeEncounter(fight);
      expect(world.vitalsOf('korash').hp, 1);
      expect(world.minute - before, greaterThanOrEqualTo(60));
    });

    test('rest restores Constitution times level, and the day\'s magic', () {
      final world = fought();
      final v = world.vitalsOf('korash');
      final before = v.hp;
      v.focus = 0;
      v.slotsLeft[1] = 0;
      final healed = world.rest()['korash']!;
      expect(healed, restHealing(loadKorash()).clamp(0, v.maxHp - before));
      expect(v.focus, v.maxFocus);
      expect(v.slotsLeft[1], v.slots[1]);
      expect(world.isFatigued, isFalse);
      expect(world.endurance.travelMinutes, 0);
    });

    test('takes eight hours', () {
      final world = _world(room: 'MH_002_GuardHall');
      world.rest();
      expect(world.clock, '16:00');
    });

    test('nobody sleeps with an ambush in the room or a hunter on them', () {
      final world = _world(room: 'WW_002_Deep');
      expect(world.rest, throwsA(isA<InvalidMoveException>()));
    });

    test('Treat Wounds heals 2d8 on a success, and not twice in an hour', () {
      for (var seed = 1; seed < 30; seed++) {
        final world = _world(room: 'MH_002_GuardHall', seed: seed);
        world.vitalsOf('korash').hp = 20;
        final t = world.treatWounds();
        if (t.check.degree != DegreeOfSuccess.success) continue;
        expect(t.roll!.dice, hasLength(2));
        expect(t.roll!.expression.dieSize, 8);
        expect(world.vitalsOf('korash').hp, 20 + t.change);
        expect(world.treatWounds, throwsA(isA<InvalidMoveException>()));
        world.advanceTime(1);
        world.treatWounds();
        return;
      }
      fail('no success in 30 seeds');
    });

    test('Treat Wounds is refused when nobody needs it', () {
      final world = _world(room: 'MH_002_GuardHall');
      expect(world.treatWounds, throwsA(isA<InvalidMoveException>()));
    });

    test('Refocus gives one point back, ten minutes at a time', () {
      final world = _world(room: 'MH_002_GuardHall');
      final v = world.vitalsOf('korash');
      expect(world.refocus, throwsA(isA<InvalidMoveException>()));
      v.focus = 0;
      world.refocus();
      expect(v.focus, 1);
      expect(world.clock, '08:10');
    });

    test('wounds and weariness survive a save', () {
      final world = fought();
      world.endurance.travelMinutes = 200;
      final back = _restored(world);
      expect(back.vitalsOf('korash').hp, world.vitalsOf('korash').hp);
      expect(back.endurance.travelMinutes, 200);
    });

    test('a save from before wounds loads at full health', () {
      final world = fought();
      final old = world.snapshot()
        ..remove('vitals')
        ..remove('endurance');
      final back = WorldSession.restore(
          campaign: _campaign, actors: world.actors, snapshot: old);
      final v = back.vitalsOf('korash');
      expect(v.hp, v.maxHp);
    });
  });

  group('storms', () {
    test('break over a party in the open, and every hour out costs', () {
      final world = _world(campaign: _under(_always('storm')), hour: 5)
        ..drainEvents();
      final seen = _waitUntil(world, (e) => e.whereType<Exposure>().isNotEmpty);
      final broke = seen.whereType<StormBroke>().single;
      expect(broke.sheltered, isFalse);
      final hit = seen.whereType<Exposure>().first;
      expect(hit.save.label, contains('Fortitude'));
      expect(hit.save.dc, dcForLevel(6));
      expect(world.vitalsOf('korash').hp,
          world.vitalsOf('korash').maxHp - hit.hpLost);
    });

    test('never take anyone below 1 HP', () {
      final world = _world(campaign: _under(_always('storm')), hour: 5);
      world.vitalsOf('korash').hp = 1;
      _waitUntil(world, (e) => e.whereType<StormPassed>().isNotEmpty);
      expect(world.vitalsOf('korash').hp, 1);
    });

    test('under a roof, cost nothing and pay a little for waiting out', () {
      final world = _world(
          campaign: _under(_always('storm')), room: 'MH_002_GuardHall', hour: 5)
        ..drainEvents();
      final seen =
          _waitUntil(world, (e) => e.whereType<StormPassed>().isNotEmpty);
      expect(seen.whereType<Exposure>(), isEmpty);
      expect(seen.whereType<StormBroke>().single.sheltered, isTrue);
      final passed = seen.whereType<StormPassed>().single;
      expect(passed.xp, Accomplishment.minor.xp);
      expect(world.experience.xpOf('korash'), passed.xp);
    });

    test('a shelter of your own pays more', () {
      for (var seed = 1; seed < 40; seed++) {
        final world =
            _world(campaign: _under(_always('storm')), hour: 5, seed: seed);
        _waitUntil(world, (e) => e.whereType<StormBroke>().isNotEmpty);
        final built = world.makeShelter();
        if (!built.check.degree.isSuccess) continue;
        expect(built.check.dc, dcForLevel(6));
        expect(world.isSheltering, isTrue);
        world.drainEvents();
        world.waitOutStorm();
        final seen = world.drainEvents();
        expect(seen.whereType<Exposure>(), isEmpty);
        expect(seen.whereType<StormPassed>().single.xp,
            Accomplishment.moderate.xp);
        expect(seen.whereType<StormPassed>().single.ownShelter, isTrue);
        return;
      }
      fail('no shelter went up in 40 seeds');
    });

    test('each storm pays once', () {
      final world = _world(
          campaign: _under(_always('storm')),
          room: 'MH_002_GuardHall',
          hour: 5);
      final seen = <WorldEvent>[];
      for (var h = 0; h < 30; h++) {
        world.advanceTime(1);
        seen.addAll(world.drainEvents());
      }
      final byDay = seen.whereType<StormPassed>().map((s) => s.weather.day);
      expect(byDay.toSet().length, byDay.length);
    });

    test('nobody sleeps out in one that is coming', () {
      final world = _world(campaign: _under(_always('storm')), hour: 5);
      // An hour before it breaks.
      world.advanceTime(world.weatherToday!.stormStartHour! - 6);
      expect(world.rest, throwsA(isA<InvalidMoveException>()));
      final indoors = _world(
          campaign: _under(_always('storm')),
          room: 'MH_002_GuardHall',
          hour: 5);
      indoors.rest();
    });

    test('there is no making shelter on a fine day, or under a roof', () {
      expect(_world(campaign: _under(_always('clear'))).makeShelter,
          throwsA(isA<InvalidMoveException>()));
      expect(
          _world(campaign: _under(_always('storm')), room: 'MH_002_GuardHall')
              .makeShelter,
          throwsA(isA<InvalidMoveException>()));
    });

    test('spoil a shot across open ground, and not one up close', () {
      final world =
          _world(campaign: _under(_always('fog')), room: 'WW_002_Deep');
      final fight = world.beginEncounter();
      expect(fight.rangedPenalty, 2);
    });

    test('a storm in progress is where you left it after a save', () {
      final world = _world(campaign: _under(_always('storm')), hour: 5);
      _waitUntil(world, (e) => e.whereType<StormBroke>().isNotEmpty);
      final back = _restored(world);
      expect(back.weatherNow!.isSevere, isTrue);
      expect(back.isExposed, isTrue);
    });
  });
}

void itemBonusTests() {
  group('item bonuses', () {
    WorldSession wearing(String itemId, {String room = 'MH_001_Square'}) {
      final world = _world(room: room);
      world.inventory.add(itemId);
      world.equip(itemId);
      return world;
    }

    test(
        'the Ravencrest Hide helps with Survival in the valley, not away '
        'from it', () {
      final korash = SessionActor(id: 'korash', character: loadKorash());
      final home = wearing('a_006_ravencrest_hide');
      expect(home.itemBonusFor(korash, 'survival'), 1);
      final away = wearing('a_006_ravencrest_hide', room: 'VC_001_Plaza');
      expect(away.itemBonusFor(korash, 'survival'), 0);
    });

    test('the Oilskin Brigandine helps against the weather, and only then', () {
      final korash = SessionActor(id: 'korash', character: loadKorash());
      final world = wearing('a_030_oilskin_brigandine');
      expect(world.itemBonusFor(korash, 'fortitude', exposure: true), 1);
      expect(world.itemBonusFor(korash, 'fortitude'), 0);
    });

    test('gear in the pack helps whoever makes the check', () {
      final world = _world();
      world.inventory.add('g_020_quiet_crown');
      final korash = world.actors.single;
      expect(world.itemBonusFor(korash, 'diplomacy'), 3);
      expect(world.itemBonusFor(korash, 'Intimidation'), 3);
    });

    test('a conversation check counts it', () {
      final plain = _world(room: 'MH_002_GuardHall');
      final crowned = _world(room: 'MH_002_GuardHall');
      crowned.inventory.add('g_020_quiet_crown');
      int diplomacy(WorldSession w) {
        final talk = w.beginConversation('thorne')!.talk..choose('ask_quest');
        return talk.candidatesFor('haggle').single.stat.total;
      }

      final sheet = loadKorash();
      final itemOnSheet = SessionActor(id: 'k', character: sheet)
          .statFor('diplomacy')!
          .itemBonus;
      expect(diplomacy(crowned) - diplomacy(plain), 3 - itemOnSheet);
    });

    test('item bonuses do not stack with the sheet\'s own', () {
      final stat =
          SessionActor(id: 'k', character: loadKorash()).statFor('diplomacy')!;
      final same = withItemBonus(stat, stat.itemBonus);
      expect(same.total, stat.total);
      final better = withItemBonus(stat, stat.itemBonus + 2);
      expect(better.total, stat.total + 2);
    });

    test('the survey notices a bonus that could never apply', () {
      final report = Campaign(
        id: 'x',
        title: 'x',
        world: _campaign.world,
        locations: _campaign.locations,
        npcs: _campaign.npcs,
        gear: GearTable(const [
          GearItem(
            id: 'i_x',
            name: 'Lost Charm',
            level: 1,
            type: 'gear',
            description: '',
            checkBonuses: [
              CheckBonus(stat: 'survival', bonus: 1, when: 'region:r_nowhere'),
            ],
          ),
        ]),
        arcs: _campaign.arcs,
      ).survey();
      expect(report.gearBonusProblems.single, contains('can never apply'));
    });
  });
}
