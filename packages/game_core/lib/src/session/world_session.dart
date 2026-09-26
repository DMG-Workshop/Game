import 'package:pf2e_core/pf2e_core.dart';

import '../campaign/arc.dart';
import '../campaign/campaign.dart';
import '../campaign/creature.dart';
import '../campaign/difficulty.dart';
import '../campaign/economy.dart';
import '../campaign/gear.dart';
import '../campaign/hunt.dart';
import '../campaign/locations.dart';
import '../campaign/npc.dart';
import '../campaign/spell.dart';
import '../campaign/weather.dart';
import '../campaign/world.dart';
import '../campaign/world_item.dart';
import '../party/equipment.dart';
import '../party/experience.dart';
import '../party/vitals.dart';
import '../party/wealth.dart';
import 'casting.dart';
import 'encounter_session.dart';
import 'game_session.dart';
import 'item_use.dart';
import 'session_actor.dart';
import 'world_event.dart';

/// Thrown when the party is asked to do something they cannot do here.
class InvalidMoveException implements Exception {
  InvalidMoveException(this.message);

  final String message;

  @override
  String toString() => 'InvalidMoveException: $message';
}

/// Everything a client needs to render one room.
class RoomView {
  const RoomView({
    required this.room,
    required this.openDirections,
    required this.barredDirections,
    required this.npcs,
    this.items = const [],
    this.encounters = const [],
    this.town,
    this.region,
    this.weather,
    this.isNight = false,
  });

  final Room room;

  /// Directions the party can take now.
  final List<String> openDirections;

  /// Directions that exist but are currently shut, with why.
  final List<({String direction, String? reason})> barredDirections;

  final List<Npc> npcs;

  /// Objects lying here that the party can still do something with.
  final List<WorldItem> items;

  /// Fights waiting here that have not been resolved.
  final List<Encounter> encounters;

  final Town? town;
  final Region? region;

  /// The line describing the current weather, if the region has any.
  final String? weather;
  final bool isNight;

  @override
  String toString() => '${room.title} (${openDirections.join(', ')})';
}

/// The result of walking in a direction.
class MoveResult {
  const MoveResult({
    required this.from,
    required this.to,
    required this.direction,
    this.flagsSet = const [],
    this.changedRegion = false,
    this.ambush,
    this.hunt,
    this.huntRoll,
    this.minutes = 0,
  });

  final String from;
  final String to;
  final String direction;

  /// A fight that springs on arrival, which a client should start rather
  /// than merely mention.
  final Encounter? ambush;

  /// Something that has tracked the party down and caught them up here. Like
  /// an ambush, a client should start it rather than mention it.
  final Encounter? hunt;

  /// The d100 against the chance of being found, when one was rolled.
  final ({int die, int chance})? huntRoll;

  /// How long the way took, weather and all.
  final int minutes;

  /// Flags entering the new room set, which arcs may be watching.
  final List<String> flagsSet;

  /// True when the party crossed into a different region, which a client may
  /// want to mark with fresh weather or an establishing line.
  final bool changedRegion;
}

/// The result of raising a topic with someone.
class TalkResult {
  const TalkResult({
    required this.npc,
    required this.said,
    this.topic,
    this.isGreeting = false,
    this.flagsSet = const [],
    this.exhaustedTopics = false,
  });

  final Npc npc;

  /// What they said.
  final String said;

  /// The topic raised, or null for a greeting.
  final String? topic;
  final bool isGreeting;
  final List<String> flagsSet;

  /// True when this exchange was the last unraised topic they had.
  final bool exhaustedTopics;
}

/// A party moving through a campaign world.
///
/// The counterpart to `GameSession`: that one runs an authored scene graph,
/// this one runs the map. They share the flag set deliberately, so a scene
/// outcome can open a road and walking into a room can advance an arc,
/// without either knowing about the other.
class WorldSession {
  WorldSession({
    required this.campaign,
    required List<SessionActor> actors,
    required DiceRoller roller,
    String? roomId,
    Set<String>? flags,
    int hour = 8,
    int day = 1,
    PartyInventory? inventory,
    String? cameFrom,
    Experience? experience,
    LootLedger? ledger,
    SpellBook? spells,
  })  : _actors = List.of(actors),
        spells = spells ?? SpellBook(),
        _experience = experience ?? Experience(),
        _ledger = ledger ?? LootLedger(),
        // Salted off the world's own starting point, so a seed still fixes
        // everything, but a traveller's wandering never shifts a fight.
        _roadDice = DiceRoller(roller.state ^ 0x9E3779B9),
        // The hunt has dice of its own for the same reason: being rich must
        // not change the outcome of a fight the party would have had anyway.
        _huntDice = DiceRoller(roller.state ^ 0x5851F42D),
        // And the sky: weather is rolled every day, and must not reach into
        // the fights either.
        _skyDice = DiceRoller(roller.state ^ 0x2545F491),
        _cameFrom = cameFrom,
        _roller = roller,
        _roomId = roomId ?? _firstRoomOf(campaign),
        // Copied rather than kept: callers pass an unmodifiable view or a
        // set another session owns, and a session must not mutate either.
        _flags = {...?flags},
        _day = day < 1 ? 1 : day,
        _minute = (hour * 60) % _minutesInDay,
        _inventory = inventory ?? PartyInventory(gear: campaign.gear) {
    if (_actors.isEmpty) {
      throw ArgumentError.value(actors, 'actors', 'a session needs an actor');
    }
    if (campaign.locations.roomById(_roomId) == null) {
      throw ArgumentError.value(_roomId, 'roomId', 'no such room');
    }
    _experience.reconcile([
      for (final a in _actors)
        (id: a.id, level: a.character.level, sheetXp: a.character.xp),
    ]);

    // Without a pack of its own, a session works out what it is carrying from
    // the flags, which is how everything else here describes progress. It
    // also means a save written before the pack existed still has its loot.
    if (inventory == null) {
      for (final flag in _flags) {
        if (!flag.startsWith('loot_')) continue;
        final id = flag.substring('loot_'.length);
        if (campaign.gear.byId(id) != null) _inventory.add(id);
      }
      _inventory.earn(_startingCoin(_actors));
    }
    for (final npc in campaign.npcs.travellers) {
      _moveOn(npc);
    }
    for (final actor in _actors) {
      _vitals[actor.id] = ActorVitals.fresh(actor.stats);
    }
    _enter(_roomId);
    _todaysWeather();
  }

  static const int _minutesInDay = 24 * 60;

  final Campaign campaign;

  /// The spells the engine has numbers for, from a content package.
  final SpellBook spells;

  final List<SessionActor> _actors;
  final DiceRoller _roller;
  String _roomId;

  /// The room the party walked in from, which is the one way past an ambush.
  String? _cameFrom;
  final Set<String> _flags;

  /// The day of the campaign, from 1, and the minute of that day.
  int _day;
  int _minute;

  /// Dice for the weather, kept apart from the world's.
  DiceRoller _skyDice;

  /// Each region's weather for the last day the party was in it.
  final Map<String, DayWeather> _skies = {};

  /// How each character is holding up.
  final Map<String, ActorVitals> _vitals = {};

  /// How far the party has come since it last slept.
  Endurance _endurance = Endurance();

  /// What has happened since a client last asked.
  final List<WorldEvent> _events = [];

  /// The storm the party is in the middle of, as `<region>@<day>`.
  String? _caughtIn;

  /// True while the party is under a shelter it made itself.
  bool _sheltering = false;

  /// Minutes spent out in the current storm since the last exposure roll.
  int _exposedMinutes = 0;

  /// Storms the party has come through, so each pays once.
  final Set<String> _weathered = {};

  final PartyInventory _inventory;
  final Experience _experience;
  final LootLedger _ledger;

  /// Dice for whether anything finds the party, and what.
  DiceRoller _huntDice;

  /// Steps since something last found the party.
  int _sinceHunt = 0;

  /// Hunters the party has beaten.
  int _huntsSurvived = 0;

  /// Whatever has found the party and not yet been dealt with.
  Pursuer? _pursuer;

  /// Dice for who is where on the roads, kept apart from the world's dice.
  ///
  /// Travellers wander on these alone, so adding one to a campaign changes
  /// no fight, drop or weather roll in a game that was seeded before them.
  DiceRoller _roadDice;

  /// Steps the party has taken, which is what travellers keep time by.
  int _steps = 0;

  /// Where each traveller is; null while they are on the road between stops.
  final Map<String, String?> _whereabouts = {};

  /// What a travelling shop has on hand at its current stop.
  final Map<String, List<String>> _onHand = {};

  /// Topics already raised, keyed by npc id, so a conversation does not
  /// re-award a flag every time the same question is asked.
  final Map<String, Set<String>> _topicsRaised = {};

  /// Weather per region, rolled once on arrival and kept until the party
  /// leaves. Weather that changed every step would be noise, not atmosphere.
  final Map<String, String> _weatherByRegion = {};

  /// What the party's own sheets say they are carrying, pooled.
  ///
  /// The characters arrive with the coin Pathbuilder gave them, the same way
  /// they arrive with its weapons, because it is their money.
  static int _startingCoin(List<SessionActor> actors) =>
      actors.fold(0, (sum, actor) => sum + actor.character.money.totalInCopper);

  static String _firstRoomOf(Campaign campaign) {
    final rooms = campaign.locations.rooms.keys.toList()..sort();
    if (rooms.isEmpty) {
      throw ArgumentError.value(campaign, 'campaign', 'has no rooms');
    }
    return rooms.first;
  }

  List<SessionActor> get actors => List.unmodifiable(_actors);
  SessionActor get primary => _actors.first;

  /// What the party is carrying and who is wearing what.
  PartyInventory get inventory => _inventory;

  /// Who has earned how much experience.
  Experience get experience => _experience;

  /// Everything the party has come away with, and from where.
  LootLedger get ledger => _ledger;

  /// What the party is worth now, against what Pathfinder expects of it.
  Wealth get wealth => Wealth(
        coin: _inventory.coin,
        gear: _inventory.gearValue,
        expected: expectedWealth(level: _partyLevel, partySize: _actors.length),
      );

  int get _partyLevel =>
      partyLevel([for (final a in _actors) a.character.level]);

  /// How far word of the party's wealth has spread, and what it brings.
  Notoriety get notoriety {
    final worth = wealth;
    return Notoriety(
      wealth: worth,
      tier: campaign.hunts.tierFor(worth.percentOfExpected),
      partyLevel: _partyLevel,
      partySize: _actors.length,
    );
  }

  /// Whatever has tracked the party down and is waiting to be fought.
  Pursuer? get pursuer => _pursuer;

  /// How many hunters the party has beaten.
  int get huntsSurvived => _huntsSurvived;

  Set<String> get flags => Set.unmodifiable(_flags);

  String get roomId => _roomId;
  Room get currentRoom => campaign.locations.roomById(_roomId)!;

  int get hour => _minute ~/ 60;

  /// Minutes into the day.
  int get minute => _minute;

  /// The day of the campaign, counting from 1.
  int get day => _day;

  /// The day as the calendar has it.
  ({Season season, int dayOfSeason, int year}) get date =>
      campaign.weather.calendar.dateOf(_day);

  /// The time as a clock would show it: `14:05`.
  String get clock => '${hour.toString().padLeft(2, '0')}:'
      '${(_minute % 60).toString().padLeft(2, '0')}';

  bool get isNight => campaign.world.time.isNight(hour);

  Town? get currentTown => campaign.locations.townForRoom(_roomId);

  Region? get currentRegion {
    final town = currentTown;
    return town == null ? null : campaign.world.regionForTown(town.name);
  }

  /// The circumstance modifier the time of day applies to [statKey].
  int timeModifierFor(String statKey) =>
      campaign.world.time.modifierFor(statKey, hour: hour);

  /// Everything needed to render the room the party is standing in.
  RoomView look() {
    final room = currentRoom;
    final barred = <({String direction, String? reason})>[];
    for (final entry in room.exits.entries) {
      if (!entry.value.isOpen(_flags)) {
        barred.add((
          direction: entry.key,
          reason: entry.value.blockedMessage,
        ));
      }
    }
    barred.sort((a, b) => a.direction.compareTo(b.direction));

    return RoomView(
      room: room,
      openDirections: room.openDirections(_flags),
      barredDirections: barred,
      npcs: _npcsHere(),
      items: campaign.items.visibleIn(_roomId, _flags),
      encounters: campaign.bestiary.availableIn(_roomId, _flags),
      town: currentTown,
      region: currentRegion,
      weather: currentWeather,
      isNight: isNight,
    );
  }

  /// The weather line for where the party is.
  ///
  /// With a weather table, the day's roll for the region and the hour: a
  /// storm day is a storm only while the storm is on. Without one, a line
  /// from the region's own list, rolled once and kept.
  String? get currentWeather {
    final region = currentRegion;
    final now = weatherNow;
    if (now != null) return region?.weatherStates[now.id] ?? now.text;
    if (region == null || !region.hasWeather) return null;
    final chosen = _weatherByRegion[region.id];
    if (chosen != null) return region.weatherStates[chosen];
    final keys = region.weatherStates.keys.toList()..sort();
    final key = keys[_roller.rollDie(keys.length) - 1];
    _weatherByRegion[region.id] = key;
    return region.weatherStates[key];
  }

  /// Today's weather in the party's region, rolling it if nobody has yet.
  DayWeather? get weatherToday => _todaysWeather();

  /// The weather in effect right now: the storm while it is on, what it
  /// settles into either side of it, and the day's weather otherwise.
  WeatherType? get weatherNow {
    final today = _todaysWeather();
    if (today == null) return null;
    if (!today.type.isSevere) return today.type;
    if (today.isStormAt(_minute)) return today.type;
    return campaign.weather.typeById(today.type.after ?? '') ?? today.type;
  }

  /// True when the party is out in severe weather with nothing over them.
  bool get isExposed =>
      (weatherNow?.isSevere ?? false) && !currentRoom.shelter && !_sheltering;

  /// True while the party is under a shelter it made.
  bool get isSheltering => _sheltering;

  DayWeather? _todaysWeather() {
    final book = campaign.weather;
    final region = currentRegion;
    if (book.isEmpty || region == null) return null;
    final known = _skies[region.id];
    if (known != null && known.day == _day) return known;

    final date = book.calendar.dateOf(_day);
    final die = _skyDice.rollDie(100);
    final type = book.lookUp(region.id, date.season.id, die);
    if (type == null) return null;
    int? start;
    int? hours;
    if (type.isSevere) {
      // Between six in the morning and five in the evening, for two to eight
      // hours, and over by midnight.
      start = 5 + _skyDice.rollDie(12);
      final length = _skyDice.rollSum(2, 4);
      hours = length > 24 - start ? 24 - start : length;
    }
    final rolled = DayWeather(
      regionId: region.id,
      day: _day,
      season: date.season,
      die: die,
      type: type,
      stormStartHour: start,
      stormHours: hours,
    );
    _skies[region.id] = rolled;
    _events.add(WeatherRolled(rolled));
    return rolled;
  }

  // --- time ----------------------------------------------------------------

  /// Everything that has happened since the last time this was called.
  List<WorldEvent> drainEvents() {
    final out = List<WorldEvent>.of(_events);
    _events.clear();
    return out;
  }

  /// Lets [minutes] go by, a slice at a time, so that a storm breaking or a
  /// day turning in the middle of it lands at the right moment.
  void _pass(int minutes, {bool travelling = false, bool resting = false}) {
    final limits = campaign.weather.travel;
    final wasTired = _endurance.isFatigued(limits);
    final wasSpent = _endurance.isSpent(limits);
    final time = campaign.world.time;
    var left = minutes;
    while (left > 0) {
      final toHour = 60 - _minute % 60;
      final step = left < toHour ? left : toHour;
      final hourBefore = hour;
      _minute += step;
      left -= step;
      if (travelling) _endurance.travelMinutes += step;
      if (!resting) _endurance.awakeMinutes += step;
      if (_minute >= _minutesInDay) {
        _minute -= _minutesInDay;
        _day++;
        final date = campaign.weather.calendar.dateOf(_day);
        _events.add(NewDay(
          day: _day,
          season: date.season,
          dayOfSeason: date.dayOfSeason,
          year: date.year,
        ));
      }
      if (hour != hourBefore) {
        if (hour == time.dawnHour) {
          _events.add(DawnOrDusk(isDawn: true, echo: time.dawnEcho));
        } else if (hour == time.duskHour) {
          _events.add(DawnOrDusk(isDawn: false, echo: time.duskEcho));
        }
      }
      _weatherTick(step);
    }
    if (!wasSpent && _endurance.isSpent(limits)) {
      _events.add(const GrewTired(spent: true));
    } else if (!wasTired && _endurance.isFatigued(limits)) {
      _events.add(const GrewTired(spent: false));
    }
  }

  /// What the sky does to the party over [step] minutes just gone.
  void _weatherTick(int step) {
    final region = currentRegion;
    final today = _todaysWeather();
    if (region == null || today == null || !today.hasStorm) return;
    final key = '${region.id}@${today.day}';

    if (today.isStormAt(_minute)) {
      if (_caughtIn != key) {
        _caughtIn = key;
        _exposedMinutes = 0;
        _events.add(StormBroke(
          weather: today,
          sheltered: currentRoom.shelter || _sheltering,
        ));
      }
      if (!currentRoom.shelter && !_sheltering) {
        _exposedMinutes += step;
        while (_exposedMinutes >= 60) {
          _exposedMinutes -= 60;
          _expose(today);
        }
      }
      return;
    }

    if (_caughtIn == key && _minute >= today.stormEndMinute) {
      _caughtIn = null;
      _exposedMinutes = 0;
      if (_weathered.add(key)) {
        final own = _sheltering;
        final xp = own
            ? Accomplishment.moderate.xp
            : currentRoom.shelter
                ? Accomplishment.minor.xp
                : 0;
        _experience.award(_actors.map((a) => a.id), xp);
        _events.add(StormPassed(weather: today, xp: xp, ownShelter: own));
      }
      _sheltering = false;
    }
  }

  /// An hour out in severe weather: everyone saves against it.
  ///
  /// A basic Fortitude save against the DC for the party's level, as
  /// Pathfinder runs a hazard. The damage grows with the party, a set of dice
  /// for every five levels, so a storm stays a storm at level 15. It never
  /// takes anyone below 1 HP: weather wears a party down, it does not kill it
  /// in its sleep.
  void _expose(DayWeather today) {
    final dice = DamageExpression.tryParse(today.type.exposure ?? '');
    if (dice == null) return;
    final level = _partyLevel;
    final sets = (level + 4) ~/ 5;
    final scaled = DamageExpression(
      diceCount: dice.diceCount * sets,
      dieSize: dice.dieSize,
      flatBonus: dice.flatBonus * sets,
    );
    final dc = dcForLevel(level);
    for (final actor in _actors) {
      final vitals = _vitals[actor.id]!;
      final fort = actor.statFor('fortitude');
      final bonus = itemBonusFor(actor, 'fortitude', exposure: true);
      final save = CheckResolver.outcomeFor(
        dieRoll: _skyDice.d20(),
        modifier: fort == null ? bonus : withItemBonus(fort, bonus).total,
        dc: dc,
        label: 'Fortitude against the ${today.type.name.toLowerCase()}',
      );
      final roll = scaled.rollDetailed(_skyDice);
      final taken = switch (save.degree) {
        DegreeOfSuccess.criticalSuccess => 0,
        DegreeOfSuccess.success => roll.total ~/ 2,
        DegreeOfSuccess.failure => roll.total,
        DegreeOfSuccess.criticalFailure => roll.total * 2,
      };
      final lost =
          vitals.hurt(taken.clamp(0, vitals.hp - 1 < 0 ? 0 : vitals.hp - 1));
      _events
          .add(Exposure(actor: actor, save: save, damage: roll, hpLost: lost));
    }
  }

  /// Whether severe weather will be on here within the next [minutes].
  bool _stormWithin(int minutes) {
    final today = _todaysWeather();
    if (today == null || !today.hasStorm) return false;
    final start = today.stormStartHour! * 60;
    final end = today.stormEndMinute;
    return _minute < end && _minute + minutes > start;
  }

  // --- how the party is holding up -----------------------------------------

  /// The spells [actorId] could cast, and how many times more today.
  List<CastOption> castOptions(String actorId) {
    final actor = actorFor(actorId);
    return castOptionsFor(actor, _vitals[actor.id]!, spells);
  }

  /// Spell names on [actorId]'s sheet that the spell table has no numbers
  /// for, so a client can say why they are not on offer.
  List<String> spellsWithoutNumbers(String actorId) {
    final character = actorFor(actorId).character;
    final names = <String>{
      for (final entry in character.spellcasting)
        for (final list
            in entry.prepared.isEmpty ? entry.known : entry.prepared)
          ...list.spells,
      for (final focus in character.focus) ...[
        ...focus.cantrips,
        ...focus.spells,
      ],
    };
    return [
      for (final name in names)
        if (spells.byName(name) == null) name,
    ]..sort();
  }

  /// Hit points and what is left to cast with, for [actorId].
  ActorVitals vitalsOf(String actorId) => _vitals[actorFor(actorId).id]!;

  /// How far the party has come since it last rested.
  Endurance get endurance => _endurance;

  /// Pathfinder's Fatigued: -1 to AC and saves, until the party rests.
  bool get isFatigued => _endurance.isFatigued(campaign.weather.travel);

  /// Too tired to set out on a long stretch of road.
  bool get isSpent => _endurance.isSpent(campaign.weather.travel);

  /// Sleeps eight hours, and wakes rested.
  ///
  /// Pathfinder's night's rest: each character recovers their Constitution
  /// modifier (at least 1) times their level in HP, and makes their daily
  /// preparations — every spell slot and focus point back. Fatigue goes.
  /// Nobody sleeps with a hunter at the door or an ambush in the room, or out
  /// in the open with a storm coming.
  Map<String, int> rest() {
    _requireQuiet('rest');
    if (!currentRoom.shelter && !_sheltering && _stormWithin(8 * 60)) {
      throw InvalidMoveException('A ${todaysWeatherName.toLowerCase()} is '
          'coming, and nobody sleeps out in that. Find a roof, or make '
          'shelter first.');
    }
    _pass(8 * 60, resting: true);
    final healed = <String, int>{};
    for (final actor in _actors) {
      final vitals = _vitals[actor.id]!;
      healed[actor.id] = vitals.heal(restHealing(actor.character));
      vitals.prepare();
    }
    _endurance.rested();
    return healed;
  }

  String get todaysWeatherName => _todaysWeather()?.type.name ?? 'storm';

  /// Ten minutes of Treat Wounds, by whoever in the party is best at
  /// Medicine, on [who] or on whoever is worst hurt.
  ///
  /// Pathfinder's DC 15 for a trained healer: 2d8 back, 4d8 on a critical
  /// success, and 1d8 lost on a critical failure. A patient cannot be
  /// treated again for an hour.
  ({
    SessionActor healer,
    SessionActor patient,
    CheckOutcome check,
    DamageRoll? roll,
    int change,
  }) treatWounds({String? who}) {
    _requireQuiet('treat anyone');
    final healers = [
      for (final a in _actors)
        if (a.statFor('medicine') case final stat?
            when stat.proficiency != Proficiency.untrained)
          (
            actor: a,
            stat: withItemBonus(stat, itemBonusFor(a, 'medicine')),
          ),
    ]..sort((a, b) => b.stat.total.compareTo(a.stat.total));
    if (healers.isEmpty) {
      throw InvalidMoveException('Nobody in the party is trained in Medicine.');
    }
    final patient = _patient(who);
    final vitals = _vitals[patient.id]!;
    if (!vitals.isHurt) {
      throw InvalidMoveException('${patient.name} is not hurt.');
    }
    final now = _absoluteMinute;
    final last = vitals.lastTreatedAt;
    if (last != null && now - last < 60) {
      throw InvalidMoveException('${patient.name} was treated within the '
          'hour. It will not take again until ${60 - (now - last)} minutes '
          'from now.');
    }

    final healer = healers.first;
    final check = CheckResolver(_roller).resolve(
      modifier: healer.stat.total,
      dc: 15,
      label: 'Medicine (Treat Wounds)',
    );
    DamageRoll? roll;
    var change = 0;
    switch (check.degree) {
      case DegreeOfSuccess.criticalSuccess:
        roll = DamageExpression.parse('4d8').rollDetailed(_roller);
        change = vitals.heal(roll.total);
      case DegreeOfSuccess.success:
        roll = DamageExpression.parse('2d8').rollDetailed(_roller);
        change = vitals.heal(roll.total);
      case DegreeOfSuccess.failure:
        break;
      case DegreeOfSuccess.criticalFailure:
        roll = DamageExpression.parse('1d8').rollDetailed(_roller);
        change = -vitals.hurt(roll.total.clamp(0, vitals.hp - 1));
    }
    _pass(10);
    vitals.lastTreatedAt = _absoluteMinute;
    return (
      healer: healer.actor,
      patient: patient,
      check: check,
      roll: roll,
      change: change,
    );
  }

  /// [who], or whoever in the party is worst hurt for their size.
  SessionActor _patient(String? who) {
    if (who != null && who.trim().isNotEmpty) return actorFor(who);
    final hurt = [
      for (final a in _actors)
        if (_vitals[a.id]!.isHurt) a,
    ]..sort((a, b) => (_vitals[a.id]!.hp / _vitals[a.id]!.maxHp)
        .compareTo(_vitals[b.id]!.hp / _vitals[b.id]!.maxHp));
    if (hurt.isEmpty) throw InvalidMoveException('Nobody needs it.');
    return hurt.first;
  }

  /// Uses up one of something the party carries, on [who] or on whoever is
  /// worst hurt.
  ///
  /// A moment's work rather than ten minutes', so it takes no time and can
  /// be done with something at the door. The copy is spent before the dice
  /// are rolled: a draught drunk is gone however well it goes down.
  UseResult use(String what, {String? who}) {
    final item = _inventory.find(what);
    if (item == null) {
      throw InvalidMoveException('You are not carrying a "$what".');
    }
    final effect = item.use;
    if (effect == null) throw InvalidMoveException(cannotUseByHand(item));
    final patient = _patient(who);
    final vitals = _vitals[patient.id]!;
    if (!vitals.isHurt) {
      throw InvalidMoveException('${patient.name} is not hurt.');
    }
    _inventory.remove(item.id);
    final roll = effect.heal.rollDetailed(_roller);
    final healed = vitals.heal(roll.total);
    return UseResult(
      item: item,
      user: patient.name,
      target: patient.name,
      roll: roll,
      healed: healed,
      hp: vitals.hp,
      maxHp: vitals.maxHp,
    );
  }

  /// Ten minutes of Refocus: one focus point back for each character who
  /// has spent any.
  Map<String, int> refocus() {
    _requireQuiet('refocus');
    final back = <String, int>{};
    for (final actor in _actors) {
      final v = _vitals[actor.id]!;
      if (v.focus < v.maxFocus) {
        v.focus++;
        back[actor.id] = 1;
      }
    }
    if (back.isEmpty) {
      throw InvalidMoveException('Nobody has spent any focus to get back.');
    }
    _pass(10);
    return back;
  }

  /// Makes shelter against the weather out here, with Survival.
  ///
  /// Half an hour's work against the DC for the party's level, by whoever
  /// is best at it. On a success the party rides the storm out where it is;
  /// on a failure the shelter holds but leaks, and everyone takes one hour's
  /// exposure first; on a critical failure it comes down and they take the
  /// hour with nothing over them.
  ({SessionActor builder, CheckOutcome check}) makeShelter() {
    if (currentRoom.shelter) {
      throw InvalidMoveException('There is a roof here already.');
    }
    final today = _todaysWeather();
    if (today == null || !today.hasStorm || _minute >= today.stormEndMinute) {
      throw InvalidMoveException('There is no weather here worth sheltering '
          'from today.');
    }
    if (_sheltering) {
      throw InvalidMoveException('You are sheltering already.');
    }
    final builders = [
      for (final a in _actors)
        if (a.statFor('survival') case final stat?)
          (
            actor: a,
            stat: withItemBonus(stat, itemBonusFor(a, 'survival')),
          ),
    ]..sort((a, b) => b.stat.total.compareTo(a.stat.total));
    final builder = builders.isEmpty ? primary : builders.first.actor;
    final check = CheckResolver.outcomeFor(
      dieRoll: _skyDice.d20(),
      modifier: builders.isEmpty ? 0 : builders.first.stat.total,
      dc: dcForLevel(_partyLevel),
      label: 'Survival (make shelter)',
    );
    switch (check.degree) {
      case DegreeOfSuccess.criticalSuccess || DegreeOfSuccess.success:
        _sheltering = true;
        _pass(30);
      case DegreeOfSuccess.failure:
        _expose(today);
        _sheltering = true;
        _pass(30);
      case DegreeOfSuccess.criticalFailure:
        _pass(30);
        _expose(today);
    }
    return (builder: builder, check: check);
  }

  /// Waits for the day's storm to blow over, from under a roof or a
  /// shelter; or an hour, if there is no storm on.
  int waitOutStorm() {
    final today = _todaysWeather();
    if (today == null || !today.hasStorm || _minute >= today.stormEndMinute) {
      _pass(60);
      return 60;
    }
    if (isExposed ||
        (!currentRoom.shelter && !_sheltering && _stormWithin(1))) {
      throw InvalidMoveException('Out here? Find a roof, or make shelter.');
    }
    final minutes = today.stormEndMinute - _minute;
    _pass(minutes);
    return minutes;
  }

  int get _absoluteMinute => (_day - 1) * _minutesInDay + _minute;

  /// Refuses what cannot be done with something waiting to fight.
  void _requireQuiet(String doing) {
    final hunter = _pursuer;
    if (hunter != null) {
      throw InvalidMoveException(
          'Not with ${hunter.creature.name} on you. You cannot $doing now.');
    }
    final waiting = campaign.bestiary.ambushIn(_roomId, _flags);
    if (waiting != null) {
      throw InvalidMoveException(
          'Not with ${waiting.name} in the room. You cannot $doing now.');
    }
  }

  /// Everyone in the party, when the party is fatigued.
  Set<String> get _fatiguedIds =>
      isFatigued ? {for (final a in _actors) a.id} : const {};

  /// The best item bonus [actor] has to [statKey] from what they carry, here
  /// and now.
  ///
  /// What they are wielding and wearing counts for them alone; the pack's
  /// other gear counts for whoever is making the check, as if they were the
  /// one carrying it. [exposure] is true for a save against the weather.
  int itemBonusFor(SessionActor actor, String statKey,
      {bool exposure = false}) {
    final key = statKey.trim().toLowerCase();
    final loadout = _inventory.loadoutFor(actor.id);
    final sources = [
      if (loadout.weapon case final weapon?) weapon,
      if (loadout.armor case final armor?) armor,
      for (final item in _inventory.carried)
        if (EquipSlot.forType(item.type) == null) item,
    ];
    var best = 0;
    for (final item in sources) {
      for (final b in item.checkBonuses) {
        if (b.stat != key || b.bonus <= best) continue;
        if (_bonusApplies(b.when, exposure: exposure)) best = b.bonus;
      }
    }
    return best;
  }

  bool _bonusApplies(String? when, {required bool exposure}) {
    if (when == null) return true;
    if (when == 'exposure') return exposure;
    if (when.startsWith('region:')) {
      return currentRegion?.id == when.substring('region:'.length);
    }
    if (when.startsWith('zone:')) {
      return _zoneOf(_roomId) == when.substring('zone:'.length);
    }
    return false;
  }

  /// Counts lines already given out, so the next one is a different one.
  final Map<String, int> _lineCounts = {};

  /// The next of [lines], in turn, under [key]. No dice: which line comes
  /// next is a matter of order, so words never shift a roll.
  String? _next(String key, List<String> lines) {
    if (lines.isEmpty) return null;
    final n = _lineCounts.update(key, (c) => c + 1, ifAbsent: () => 0);
    return lines[n % lines.length];
  }

  /// NPCs already greeted, as `<npc>@<day>`, so a walk-in says hello once
  /// a day rather than every time the party crosses the threshold.
  final Set<String> _greeted = {};

  /// What the people here say as the party walks in: once a day each, the
  /// way the story stands.
  List<({Npc npc, String line})> greetingsHere() {
    final out = <({Npc npc, String line})>[];
    for (final npc in _npcsHere()) {
      final line = npc.barkFor(_flags);
      if (line == null || !_greeted.add('${npc.id}@$_day')) continue;
      out.add((npc: npc, line: line));
    }
    return out;
  }

  /// Something going on in the room the party is standing in.
  String? roomAmbiance() =>
      _next('room:${currentRoom.id}', currentRoom.ambiance);

  /// What the keeper here says, at [moment]: `greet`, `buy`, `sell`, or
  /// `broke` for a customer who cannot pay.
  ({String keeper, String line})? keeperSays(String moment) {
    final shop = shopHere;
    if (shop == null) return null;
    final lines = switch (moment) {
      'greet' => shop.lines.greet,
      'buy' => shop.lines.buy,
      'sell' => shop.lines.sell,
      'broke' => shop.lines.broke,
      _ => const <String>[],
    };
    final line = _next('shop:${shop.id}:$moment', lines);
    return line == null ? null : (keeper: _keeperName(shop), line: line);
  }

  /// What somebody in the party says, looking up at [weather].
  ({SessionActor who, String line})? remarkOn(WeatherType weather) =>
      weather.remark == null ? null : (who: primary, line: weather.remark!);

  /// The night the party just had: how it went, what was said settling
  /// down, and waking.
  ({String? night, ({SessionActor who, String line})? said, String? wake})
      nightLines({required bool indoors}) {
    final lines = campaign.weather.restLines;
    final said = _next('rest:pc', lines.pc);
    return (
      night: _next(indoors ? 'rest:in' : 'rest:out',
          indoors ? lines.indoors : lines.outdoors),
      said: said == null ? null : (who: primary, line: said),
      wake: _next('rest:wake', lines.wake),
    );
  }

  /// A random ambiance line for the current region, or null if it has none.
  ///
  /// Returned rather than emitted on a timer: how often atmosphere intrudes
  /// is a presentation decision, and a phone and a terminal will not agree.
  String? ambianceEcho() {
    final echoes = currentRegion?.ambianceEchoes ?? const [];
    if (echoes.isEmpty) return null;
    return echoes[_roller.rollDie(echoes.length) - 1];
  }

  /// Walks [direction], returning what changed.
  MoveResult move(String direction) {
    final room = currentRoom;
    final exit = room.exit(direction);
    if (exit == null) {
      throw InvalidMoveException('There is no way $direction from here.');
    }
    if (!exit.isOpen(_flags)) {
      throw InvalidMoveException(
          exit.blockedMessage ?? 'The way $direction is shut.');
    }
    if (campaign.locations.roomById(exit.to) == null) {
      throw InvalidMoveException(
          'The way $direction leads to "${exit.to}", which does not exist.');
    }

    final hunter = _pursuer;
    if (hunter != null) {
      throw InvalidMoveException('${hunter.creature.name} has caught you up. '
          'Fight it, or flee.');
    }

    // Only the way back is open past an ambush. With no known way in — a
    // session started in the room — every way counts as back.
    final waiting = campaign.bestiary.ambushIn(_roomId, _flags);
    if (waiting != null && _cameFrom != null && exit.to != _cameFrom) {
      throw InvalidMoveException('${waiting.name} is between you and the way '
          'on. Fight, or go back the way you came.');
    }

    final minutes = travelMinutes(direction);
    final limits = campaign.weather.travel;
    if (minutes >= limits.newZoneMinutes && isSpent) {
      throw InvalidMoveException('You are too tired to take on the road. '
          'Rest first: there is only so far anyone can go in a day.');
    }

    final fromRegion = currentRegion?.id;
    final from = _roomId;
    _roomId = exit.to;
    _cameFrom = from;
    // A shelter stays where it was put up, and a storm is left behind with
    // the region it is in.
    _sheltering = false;
    if (currentRegion?.id != fromRegion) {
      _caughtIn = null;
      _exposedMinutes = 0;
    }
    final set = _enter(exit.to);
    _pass(minutes, travelling: true);

    _steps++;
    for (final npc in campaign.npcs.travellers) {
      if (_steps % npc.route!.every == 0) _moveOn(npc);
    }

    final ambush = campaign.bestiary.ambushIn(_roomId, _flags);
    final huntRoll = ambush == null ? _rollHunt() : null;
    final caught = _pursuer;
    if (caught != null && _set('hunted_first')) set.add('hunted_first');

    return MoveResult(
      from: from,
      to: exit.to,
      direction: exit.direction,
      flagsSet: set..sort(),
      changedRegion: currentRegion?.id != fromRegion,
      ambush: ambush,
      hunt: caught?.encounterIn(_roomId),
      huntRoll: huntRoll,
      minutes: minutes,
    );
  }

  /// How long the way [direction] would take now, weather and all.
  ///
  /// The exit's own time if it has one; otherwise a short walk within a part
  /// of the map, an hour into the next part, and a day's road to another
  /// town. Weather stretches all of it, and an unroofed road in a storm
  /// takes twice as long as it would on a fine day.
  int travelMinutes(String direction) {
    final exit = currentRoom.exit(direction);
    if (exit == null) return 0;
    final limits = campaign.weather.travel;
    final locations = campaign.locations;
    final base = exit.minutes ??
        (locations.townForRoom(_roomId)?.id !=
                locations.townForRoom(exit.to)?.id
            ? limits.newTownMinutes
            : _zoneOf(_roomId) == _zoneOf(exit.to)
                ? limits.sameZoneMinutes
                : limits.newZoneMinutes);
    final factor = currentRoom.shelter &&
            (campaign.locations.roomById(exit.to)?.shelter ?? false)
        ? 1.0
        : weatherNow?.travel ?? 1.0;
    return (base * factor).round();
  }

  String? _zoneOf(String roomId) =>
      campaign.locations.townForRoom(roomId)?.zoneForRoom(roomId)?.id;

  /// Rolls whether anything finds the party this step, and sends it if so.
  ///
  /// Never while a fight is already waiting here, and never within a few
  /// steps of the last one: a hunt is a threat on the road, not a treadmill.
  /// Returns the roll, or null when there was nothing to roll for.
  ({int die, int chance})? _rollHunt() {
    final hunts = campaign.hunts;
    if (hunts.isEmpty) return null;
    _sinceHunt++;
    if (_sinceHunt <= hunts.restSteps) return null;

    final standing = notoriety;
    final level = standing.hunterLevel;
    if (!standing.tier.isHunted || level == null) return null;

    final roll = (die: _huntDice.rollDie(100), chance: standing.tier.chance);
    if (roll.die > roll.chance) return roll;

    _pursuer = hunts.choose(level, campaign.bestiary, _huntDice);
    if (_pursuer != null) _sinceHunt = 0;
    return roll;
  }

  /// The room the party came in from, if the session knows it.
  String? get cameFrom => _cameFrom;

  /// How a fight looks from here, which is different the second time.
  String describeEncounter(Encounter encounter) =>
      encounter.descriptionFor(_flags);

  /// Marks a room as visited, returning the flags that were newly set.
  ///
  /// Both the full id and its short form are recorded, because the arcs
  /// abbreviate: `enter_MH_001` means `MH_001_Square`. Writing both means an
  /// arc can use either and neither convention has to win.
  List<String> _enter(String roomId) {
    final set = <String>[];
    for (final flag in {'enter_$roomId', 'enter_${_shortId(roomId)}'}) {
      if (_set(flag)) set.add(flag);
    }
    return set..sort();
  }

  /// Sets [flag], paying out any coin it carries. True when it was new.
  ///
  /// Every flag the world sets comes through here, so a reward keyed to one
  /// pays out once whichever way it was reached: a conversation, a fight,
  /// an object, or an arc finishing.
  bool _set(String flag) {
    if (!_flags.add(flag)) return false;
    _payReward(flag);
    return true;
  }

  void _payReward(String flag) {
    final payout = campaign.payoutFor(flag);
    if (payout == null) return;
    if (payout.copper > 0) {
      _inventory.earn(payout.copper);
      _ledger.recordCoin(campaign.payerFor(flag), payout.copper);
    }
    _experience.award(_actors.map((a) => a.id), payout.xp);
  }

  /// `MH_001_Square` becomes `MH_001`.
  static String _shortId(String roomId) {
    final parts = roomId.split('_');
    return parts.length < 2 ? roomId : '${parts[0]}_${parts[1]}';
  }

  /// Greets [who], or raises [topic] with them.
  ///
  /// Raising a topic sets `keyword_<topic>_unlocked`, and raising the last
  /// one an NPC has sets `dialogue_complete_<name>`. Both conventions are
  /// read off this campaign's own arc conditions rather than invented: its
  /// first objective waits on `keyword_quest_unlocked`, and its second tier
  /// on `dialogue_complete_queen_liora`.
  TalkResult talk(String who, {String? topic}) {
    final npc = _findNpcHere(who);
    if (npc == null) {
      throw InvalidMoveException('There is nobody called "$who" here.');
    }

    if (topic == null || topic.trim().isEmpty) {
      return TalkResult(npc: npc, said: npc.greeting, isGreeting: true);
    }

    final reply = npc.replyTo(topic);
    if (reply == null) {
      return TalkResult(
        npc: npc,
        said: '${npc.name} has nothing to say about that.',
        topic: topic,
      );
    }

    final matched = _matchedKeyword(npc, topic)!;
    final raised = _topicsRaised.putIfAbsent(npc.id, () => <String>{});
    final isNew = raised.add(matched);

    final set = <String>[];
    if (isNew) {
      final keywordFlag = 'keyword_${matched}_unlocked';
      if (_set(keywordFlag)) set.add(keywordFlag);
    }

    final exhausted = raised.length == npc.keywords.length;
    if (exhausted) {
      final completeFlag = 'dialogue_complete_${npc.slug}';
      if (_set(completeFlag)) set.add(completeFlag);
    }

    return TalkResult(
      npc: npc,
      said: reply,
      topic: matched,
      flagsSet: set..sort(),
      exhaustedTopics: exhausted,
    );
  }

  /// Starts a proper conversation with [who].
  ///
  /// Returns null when they have nothing to say beyond a greeting, which a
  /// client can fall back to with [talk]. The conversation runs on the world's
  /// own dice and starts from a copy of its flags; nothing it does reaches the
  /// world until [concludeConversation], so a conversation abandoned halfway
  /// still counts for whatever was said before it was.
  ({Npc npc, GameSession talk})? beginConversation(String who) {
    final npc = _findNpcHere(who);
    if (npc == null) {
      throw InvalidMoveException('There is nobody called "$who" here.');
    }
    final conversation = campaign.conversations.forNpc(npc.id);
    final opening = conversation?.openingFor(_flags);
    if (conversation == null || opening == null) return null;

    return (
      npc: npc,
      talk: GameSession(
        adventure: conversation.adventure,
        actors: _actors,
        roller: _roller,
        sceneId: opening,
        flags: _flags,
        itemBonusFor: itemBonusFor,
      ),
    );
  }

  /// Takes what a conversation changed back into the world, returning the
  /// flags it newly set.
  List<String> concludeConversation(GameSession conversation) {
    final before = Set.of(_flags);
    _flags
      ..clear()
      ..addAll(conversation.flags);
    final set = _flags.difference(before).toList()..sort();
    set.forEach(_payReward);

    // Somebody handing the party something is recorded the way a drop is,
    // so a gift and a kill end up in the same pack and the same ledger.
    final npcId = conversation.adventure.id.replaceFirst('conversation_', '');
    final giver = campaign.npcs.byId(npcId)?.name ?? npcId;
    for (final flag in set) {
      if (!flag.startsWith('loot_')) continue;
      final item = campaign.gear.byId(flag.substring('loot_'.length));
      if (item == null) continue;
      _inventory.add(item.id);
      _ledger.recordItem(giver, item);
    }
    return set;
  }

  /// Which of [npc]'s keywords answered [topic].
  String? _matchedKeyword(Npc npc, String topic) {
    final asked = topic.trim().toLowerCase();
    for (final key in npc.keywords.keys) {
      if (key.toLowerCase() == asked) return key;
    }
    final byLength = npc.keywords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in byLength) {
      if (asked.contains(key.toLowerCase())) return key;
    }
    return null;
  }

  /// Topics this NPC will answer that the party has not yet raised.
  List<String> unraisedTopicsFor(Npc npc) {
    final raised = _topicsRaised[npc.id] ?? const <String>{};
    return [
      for (final t in npc.topics)
        if (!raised.contains(t)) t
    ];
  }

  // --- objects -------------------------------------------------------------

  /// Takes an object from the room.
  ///
  /// Returns the narration and any flags set. Refuses rather than silently
  /// no-ops, because "nothing happened" is the worst possible answer to a
  /// player who typed a specific verb at a specific noun.
  ({
    WorldItem item,
    String said,
    List<String> flagsSet,
    ({SessionActor who, String line})? spoken,
  }) take(String query) {
    final item = _requireItem(query);
    if (!item.takeable) {
      throw InvalidMoveException('${item.name} is not something you can take.');
    }
    final set = <String>[];
    for (final flag in item.acquireFlags) {
      if (_set(flag)) set.add(flag);
    }
    return (
      item: item,
      said: item.onTake ?? 'You take ${item.name}.',
      flagsSet: set..sort(),
      spoken:
          item.sayOnTake == null ? null : (who: primary, line: item.sayOnTake!),
    );
  }

  /// Destroys an object in the room.
  ({
    WorldItem item,
    String said,
    List<String> flagsSet,
    ({SessionActor who, String line})? spoken,
  }) destroy(String query) {
    final item = _requireItem(query);
    if (!item.destroyable) {
      throw InvalidMoveException(
          '${item.name} is not something you can destroy.');
    }
    final set = <String>[];
    for (final flag in item.destroyFlags) {
      if (_set(flag)) set.add(flag);
    }
    return (
      item: item,
      said: item.onDestroy ?? 'You destroy ${item.name}.',
      flagsSet: set..sort(),
      spoken: item.sayOnDestroy == null
          ? null
          : (who: primary, line: item.sayOnDestroy!),
    );
  }

  WorldItem _requireItem(String query) {
    final item = campaign.items.findInRoom(_roomId, query);
    if (item == null) {
      throw InvalidMoveException('There is no "$query" here.');
    }
    if (!item.isVisible(_flags)) {
      throw InvalidMoveException('There is no "$query" here.');
    }
    if (item.isResolved(_flags)) {
      throw InvalidMoveException('You have already dealt with ${item.name}.');
    }
    if (!item.isReachable(_flags)) {
      throw InvalidMoveException('You cannot get at ${item.name} yet.');
    }
    return item;
  }

  // --- fights --------------------------------------------------------------

  /// Fights waiting in this room that have not been resolved, a hunter that
  /// has caught the party up first of all.
  List<Encounter> availableEncounters() => [
        if (_pursuer case final hunter?) hunter.encounterIn(_roomId),
        ...campaign.bestiary.availableIn(_roomId, _flags),
      ];

  /// Starts a fight, by id or by the first one waiting here.
  ///
  /// The returned session is separate state: a fight is its own mode, and
  /// folding initiative and actions into the walking session would make both
  /// harder to reason about.
  EncounterSession beginEncounter({String? encounterId}) {
    final available = availableEncounters();
    if (available.isEmpty) {
      throw InvalidMoveException('There is nothing to fight here.');
    }
    final encounter = encounterId == null
        ? available.first
        : available.where((e) => e.id == encounterId).firstOrNull;
    if (encounter == null) {
      throw InvalidMoveException('There is no fight called "$encounterId" '
          'waiting here.');
    }
    final hunter = _pursuer;
    return EncounterSession(
      encounter: encounter,
      bestiary: campaign.bestiary,
      actors: _actors,
      roller: _roller,
      gear: campaign.gear,
      loadouts: _inventory.loadouts(),
      // A hunter comes at the level it was sent at, which is not the level
      // the bestiary writes it at.
      foes: hunter != null && _isHunt(encounter, hunter)
          ? [hunter.creature]
          : null,
      // The party comes in as it is: hurt from the last one, tired from the
      // road, and fighting in whatever the sky is doing.
      hp: {for (final a in _actors) a.id: _vitals[a.id]!.hp},
      fatigued: _fatiguedIds,
      spells: spells,
      // What the party carries, so a draught drunk in a fight is gone.
      inventory: _inventory,
      vitals: _vitals,
      rangedPenalty: currentRoom.shelter ? 0 : weatherNow?.rangedPenalty ?? 0,
    );
  }

  bool _isHunt(Encounter encounter, Pursuer hunter) =>
      encounter.id == hunter.encounterIn(_roomId).id;

  /// Records the result of a fight, returning the flags it set.
  ///
  /// Called by the client once the fight is over, rather than by the fight
  /// itself, so that losing and fleeing are the caller's to narrate. Loot is
  /// recorded here too: a drop the party never went back for is not theirs.
  List<String> concludeEncounter(EncounterSession fight) {
    _afterFight(fight);
    final hunter = _pursuer;
    if (hunter != null && _isHunt(fight.encounter, hunter)) {
      return _concludeHunt(fight, hunter);
    }
    final set = <String>[];
    // Which wave was beaten is worked out before anything else changes, so
    // a victory flag that happened to rearm something could not skip a wave.
    final won = fight.outcome == EncounterOutcome.victory
        ? [fight.encounter.wonFlag(fight.encounter.waveFor(_flags))]
        : const <String>[];
    for (final flag in [...won, ...fight.victoryFlags, ...fight.lootFlags]) {
      if (_set(flag)) set.add(flag);
    }
    _collect(fight);
    return set..sort();
  }

  /// Carries the party's wounds out of a fight, and the time it took.
  ///
  /// Whoever went down in a fight the party won is brought round at 1 HP.
  /// A party that loses comes to an hour later, everyone at 1 HP, wherever
  /// they fell: nobody in Valorheim finishes a job that thoroughly.
  void _afterFight(EncounterSession fight) {
    final lost = fight.outcome == EncounterOutcome.defeat;
    for (final c in fight.party) {
      final vitals = _vitals[c.id];
      if (vitals == null) continue;
      vitals.hp = lost || c.hp <= 0 ? 1 : c.hp.clamp(1, vitals.maxHp);
    }
    // Six seconds a round, and an hour to come round from a beating.
    _pass(lost ? 60 : (fight.round * 6 + 59) ~/ 60);
  }

  /// Takes a won fight's coin, loot and XP, and writes them in the ledger.
  void _collect(EncounterSession fight) {
    final source = fight.encounter.name;
    for (final item in fight.loot) {
      _inventory.add(item.id);
      _ledger.recordItem(source, item);
    }
    _inventory.earn(fight.coinEarned);
    _ledger.recordCoin(source, fight.coinEarned);
    _experience.award(_actors.map((a) => a.id), fight.xpEarned);
  }

  /// Settles a fight with a hunter, however it went.
  ///
  /// Won, it pays like any fight and counts toward `hunt_survived_<n>`. Lost,
  /// the hunter takes its share of the purse, which is what it came for. Fled,
  /// it loses the trail. Either way it is gone, and the next one is a few
  /// steps off at least.
  List<String> _concludeHunt(EncounterSession fight, Pursuer hunter) {
    final set = <String>[];
    switch (fight.outcome) {
      case EncounterOutcome.victory:
        _huntsSurvived++;
        for (final flag in [
          'hunt_survived_$_huntsSurvived',
          ...fight.lootFlags,
        ]) {
          if (_set(flag)) set.add(flag);
        }
        _collect(fight);
      case EncounterOutcome.defeat:
        final taken = _inventory.coin * campaign.hunts.robPercent ~/ 100;
        if (taken > 0) _inventory.spend(taken);
      case EncounterOutcome.fled || null:
        break;
    }
    _pursuer = null;
    _sinceHunt = 0;
    return set..sort();
  }

  /// Gear the party is carrying.
  ///
  /// The flags record that a thing was *found*, which arcs can watch; the
  /// pack records that it is still had. They are set together and only the
  /// pack is authoritative.
  List<GearItem> get recoveredGear => _inventory.carried;

  // --- equipment -----------------------------------------------------------

  /// Puts a carried item on an actor, returning what it displaced.
  ///
  /// [who] may be an actor id or any word of their name, and [what] an item
  /// id or any word of its name, because that is what a player types.
  ({SessionActor actor, GearItem item, EquipSlot slot, GearItem? replaced})
      equip(String what, {String? who}) {
    final actor = actorFor(who);
    final item = _inventory.find(what);
    if (item == null) {
      throw InvalidMoveException('You are not carrying a "$what".');
    }
    final others =
        _inventory.holdersOf(item.id).where((h) => h != actor.id).toList();
    if (others.length >= _inventory.countOf(item.id)) {
      throw InvalidMoveException('${_namesOf(others)} already '
          '${others.length == 1 ? 'has' : 'have'} ${item.name}, and the '
          'party has no other.');
    }
    final result = _inventory.equip(actor.id, item.id);
    return (
      actor: actor,
      item: result.item,
      slot: result.slot,
      replaced: result.replaced,
    );
  }

  /// Takes whatever is in [slot] off an actor, returning it.
  ({SessionActor actor, GearItem? removed}) unequip(
    String slot, {
    String? who,
  }) {
    final actor = actorFor(who);
    final parsed = EquipSlot.tryParse(slot);
    if (parsed == null) {
      throw InvalidMoveException('There is no "$slot" to take off. Try '
          '${EquipSlot.values.map((s) => s.label).join(' or ')}.');
    }
    return (actor: actor, removed: _inventory.unequip(actor.id, parsed));
  }

  /// An actor's numbers with what they are wearing and wielding applied.
  EquippedStats statsFor(String actorId) => EquippedStats(
        actorFor(actorId).stats,
        _inventory.loadoutFor(actorFor(actorId).id),
      );

  // --- trade ---------------------------------------------------------------

  /// The shop kept in this room, if there is one.
  Shop? get shopHere {
    final fixed = campaign.economy.shopIn(_roomId);
    if (fixed != null) return fixed;
    for (final npc in _npcsHere()) {
      final shop = campaign.economy.shopKeptBy(npc.id);
      if (shop != null && shop.travels) return shop;
    }
    return null;
  }

  // --- travellers ----------------------------------------------------------

  /// Everyone in this room: those who stay put, and any traveller whose
  /// road has brought them here, as long as the story has them about.
  List<Npc> _npcsHere() => [
        for (final npc in campaign.npcs.inRoom(_roomId))
          if (npc.isPresent(_flags)) npc,
        for (final npc in campaign.npcs.travellers)
          if (_whereabouts[npc.id] == _roomId && npc.isPresent(_flags)) npc,
      ];

  Npc? _findNpcHere(String who) => NpcDirectory.findAmong(_npcsHere(), who);

  /// Where a traveller is now, or null while they are on the road.
  String? whereIs(String npcId) => _whereabouts[npcId];

  /// What a travelling shop has on hand at its current stop.
  List<String> onHandAt(String shopId) =>
      List.unmodifiable(_onHand[shopId] ?? const []);

  /// Sends [npc] to their next stop, or out onto the road, and packs their
  /// shop afresh: a different few things each time they are found.
  void _moveOn(Npc npc) {
    final route = npc.route!;
    final away = _roadDice.rollDie(100) <= route.awayChance;
    _whereabouts[npc.id] =
        away ? null : route.stops[_roadDice.rollDie(route.stops.length) - 1];

    final shop = campaign.economy.shopKeptBy(npc.id);
    if (shop == null || !shop.travels) return;
    final pool = shop.onSaleFor(_flags);
    final count = (shop.carries ?? pool.length).clamp(0, pool.length);
    // A partial shuffle on the road's dice: the first [count] are the pick.
    for (var i = 0; i < count; i++) {
      final j = i + _roadDice.rollDie(pool.length - i) - 1;
      final held = pool[i];
      pool[i] = pool[j];
      pool[j] = held;
    }
    _onHand[shop.id] = pool.take(count).toList();
  }

  /// What is on the shelf here, cheapest first, at what the party would pay.
  List<({GearItem item, int price})> wares() {
    final shop = _requireShop();
    final rows = [
      for (final id in shop.travels
          ? (_onHand[shop.id] ?? const <String>[])
          : shop.onSaleFor(_flags))
        if (campaign.gear.byId(id) case final item?)
          (item: item, price: shop.priceFor(item, _flags)),
    ];
    return rows..sort((a, b) => a.price.compareTo(b.price));
  }

  /// Buys one of something on the shelf.
  ({GearItem item, int price}) buy(String what) {
    final shop = _requireShop();
    final onSale = [
      for (final row in wares()) row.item,
    ];
    final item = PartyInventory.findIn(onSale, what);
    if (item == null) {
      throw InvalidMoveException('${_keeperName(shop)} has nothing called '
          '"$what" for sale.');
    }
    final price = shop.priceFor(item, _flags);
    try {
      _inventory.spend(price);
    } on EquipException catch (e) {
      throw InvalidMoveException(e.message);
    }
    _inventory.add(item.id);
    return (item: item, price: price);
  }

  /// What the keeper here would pay for something the party carries.
  ({GearItem item, int price}) valueOf(String what) {
    _requireShop();
    final item = _inventory.find(what);
    if (item == null) {
      throw InvalidMoveException('You are not carrying a "$what".');
    }
    return (item: item, price: item.resalePrice);
  }

  /// Sells one of something the party carries, for half its price.
  ///
  /// Anything can be sold, rare things included; selling the only one of a
  /// boss's weapon is a choice a player is allowed to regret.
  ({GearItem item, int price}) sell(String what) {
    final quote = valueOf(what);
    final holders = _inventory.holdersOf(quote.item.id);
    if (holders.length >= _inventory.countOf(quote.item.id)) {
      throw InvalidMoveException('${_namesOf(holders)} '
          '${holders.length == 1 ? 'is' : 'are'} using ${quote.item.name}. '
          'Take it off first.');
    }
    try {
      _inventory.remove(quote.item.id);
    } on EquipException catch (e) {
      throw InvalidMoveException(e.message);
    }
    _inventory.earn(quote.price);
    return quote;
  }

  Shop _requireShop() {
    final shop = shopHere;
    if (shop == null) {
      throw InvalidMoveException('There is nobody here to trade with.');
    }
    return shop;
  }

  /// Actor ids as a player would read them: "Korash Blackearth and Sela".
  String _namesOf(List<String> actorIds) => actorIds
      .map((id) => _actors.where((a) => a.id == id).firstOrNull?.name ?? id)
      .join(' and ');

  String _keeperName(Shop shop) =>
      campaign.npcs.byId(shop.keeperId)?.name ?? shop.name;

  /// Whether [who] names somebody in the party.
  bool knowsActor(String who) {
    try {
      actorFor(who);
      return true;
    } on InvalidMoveException {
      return false;
    }
  }

  /// Resolves an actor by id or by any word of their name, defaulting to the
  /// one at the front of the marching order.
  SessionActor actorFor(String? who) {
    if (who == null || who.trim().isEmpty) return primary;
    final needle = who.trim().toLowerCase();
    for (final actor in _actors) {
      if (actor.id.toLowerCase() == needle) return actor;
    }
    for (final actor in _actors) {
      if (actor.name.toLowerCase().split(RegExp(r'\s+')).contains(needle)) {
        return actor;
      }
    }
    throw InvalidMoveException('Nobody here is called "$who".');
  }

  /// Lets [hours] go by, into the next day if need be.
  void advanceTime(int hours) {
    if (hours < 0) {
      throw ArgumentError.value(hours, 'hours', 'must not be negative');
    }
    _pass(hours * 60);
  }

  /// Arcs that have started and are not yet finished.
  List<CampaignArc> activeArcs() => campaign.arcs.active(_flags);

  /// Applies any world-state changes owed by completed arcs, returning them.
  ///
  /// Owed rather than applied automatically at the moment they become due,
  /// because an arc finishing is something a client will want to announce
  /// before the world quietly changes underneath the player.
  List<String> applyPendingWorldState() => settleArcs().worldState;

  /// Marks finished any quest whose last objective has been met — paying its
  /// reward — and applies what finishing it changes about the world.
  ///
  /// The quests come back separately from the world-state flags, because
  /// "quest complete" and "the world shifts" are two different things to say.
  ({List<CampaignArc> completed, List<String> worldState}) settleArcs() {
    final completed = campaign.arcs.justCompleted(_flags);
    for (final arc in completed) {
      _set(arc.completionFlag);
    }
    final pending = campaign.arcs.pendingWorldStateChanges(_flags);
    pending.forEach(_set);
    return (completed: completed, worldState: pending);
  }

  /// Captures enough state to resume exactly where this left off.
  Map<String, Object?> snapshot() => {
        'campaignId': campaign.id,
        'roomId': _roomId,
        'cameFrom': _cameFrom,
        'hour': hour,
        'day': _day,
        'minute': _minute,
        'sky': {
          'dice': _skyDice.state,
          'days': [for (final d in _skies.values) d.toJson()],
          if (_caughtIn != null) 'caughtIn': _caughtIn,
          if (_sheltering) 'sheltering': true,
          if (_exposedMinutes > 0) 'exposed': _exposedMinutes,
          'weathered': (_weathered.toList()..sort()),
        },
        'vitals': {
          for (final e in _vitals.entries) e.key: e.value.toJson(),
        },
        'endurance': _endurance.toJson(),
        'road': {
          'dice': _roadDice.state,
          'steps': _steps,
          'whereabouts': Map<String, String?>.from(_whereabouts),
          'onHand': {
            for (final e in _onHand.entries) e.key: List<String>.from(e.value),
          },
        },
        'hunt': {
          'dice': _huntDice.state,
          'since': _sinceHunt,
          'survived': _huntsSurvived,
          if (_pursuer case final hunter?)
            'pursuer': {
              'creature': hunter.hunter.creatureId,
              if (hunter.adjustment != null) 'adjustment': hunter.adjustment,
            },
        },
        'flags': (_flags.toList()..sort()),
        'inventory': _inventory.toJson(),
        'ledger': _ledger.toJson(),
        'experience': _experience.toJson(),
        'rollerState': _roller.state,
        if (_weatherByRegion.isNotEmpty)
          'weather': Map<String, String>.from(_weatherByRegion),
        'topicsRaised': {
          for (final e in _topicsRaised.entries)
            e.key: (e.value.toList()..sort()),
        },
      };

  /// Rebuilds a session from a [snapshot].
  static WorldSession restore({
    required Campaign campaign,
    required List<SessionActor> actors,
    required Map<String, Object?> snapshot,
    SpellBook? spells,
  }) {
    final id = snapshot['campaignId']?.toString();
    if (id != null && id != campaign.id) {
      throw ArgumentError('Snapshot belongs to campaign "$id", not '
          '"${campaign.id}".');
    }
    final flags = {
      for (final f in (snapshot['flags'] as List? ?? const [])) f.toString(),
    };

    // No pack in the snapshot means a save from before there was one; the
    // session rebuilds it from the loot flags instead.
    final inventory = snapshot.containsKey('inventory')
        ? PartyInventory.fromJson(campaign.gear, snapshot['inventory'])
        : null;

    final session = WorldSession(
      campaign: campaign,
      actors: actors,
      roller: DiceRoller.fromState((snapshot['rollerState'] as num).toInt()),
      roomId: snapshot['roomId']!.toString(),
      flags: flags,
      hour: (snapshot['hour'] as num?)?.toInt() ?? 8,
      day: (snapshot['day'] as num?)?.toInt() ?? 1,
      inventory: inventory,
      cameFrom: snapshot['cameFrom']?.toString(),
      experience: snapshot.containsKey('experience')
          ? Experience.fromJson(snapshot['experience'])
          : null,
      ledger: LootLedger.fromJson(snapshot['ledger']),
      spells: spells,
    );
    final hunt = snapshot['hunt'];
    if (hunt is Map) {
      session._huntDice =
          DiceRoller.fromState((hunt['dice'] as num?)?.toInt() ?? 0);
      session._sinceHunt = (hunt['since'] as num?)?.toInt() ?? 0;
      session._huntsSurvived = (hunt['survived'] as num?)?.toInt() ?? 0;
      final pursuer = hunt['pursuer'];
      if (pursuer is Map) {
        session._pursuer = campaign.hunts.restore(
          pursuer['creature']?.toString() ?? '',
          pursuer['adjustment']?.toString(),
          campaign.bestiary,
        );
      }
    }
    final savedPack = snapshot['inventory'];
    // The roads pick up where they were, rather than re-rolled on load.
    final road = snapshot['road'];
    if (road is Map) {
      session._roadDice =
          DiceRoller.fromState((road['dice'] as num?)?.toInt() ?? 0);
      session._steps = (road['steps'] as num?)?.toInt() ?? 0;
      session._whereabouts
        ..clear()
        ..addAll({
          for (final e in (road['whereabouts'] as Map? ?? const {}).entries)
            e.key.toString(): e.value?.toString(),
        });
      session._onHand
        ..clear()
        ..addAll({
          for (final e in (road['onHand'] as Map? ?? const {}).entries)
            e.key.toString(): [
              for (final id in (e.value as List? ?? const [])) id.toString(),
            ],
        });
    }
    if (savedPack is Map && !savedPack.containsKey('coin')) {
      session._inventory.earn(_startingCoin(actors));
    }
    for (final e in (snapshot['weather'] as Map? ?? const {}).entries) {
      session._weatherByRegion[e.key.toString()] = e.value.toString();
    }
    for (final e in (snapshot['topicsRaised'] as Map? ?? const {}).entries) {
      session._topicsRaised[e.key.toString()] = {
        for (final t in (e.value as List? ?? const [])) t.toString(),
      };
    }
    final minute = (snapshot['minute'] as num?)?.toInt();
    if (minute != null) session._minute = minute % _minutesInDay;
    session._restoreSky(snapshot['sky']);
    final vitals = snapshot['vitals'];
    if (vitals is Map) {
      for (final actor in actors) {
        session._vitals[actor.id] = ActorVitals.restore(
            ActorVitals.fresh(actor.stats), vitals[actor.id]);
      }
    }
    session._endurance = Endurance.fromJson(snapshot['endurance']);
    // Loading a game is not news: whatever the constructor rolled to stand
    // up has been replaced by what was saved.
    session._events.clear();
    return session;
  }

  /// Puts the sky back as it was saved: the dice, each region's day, and
  /// the storm the party was in the middle of.
  void _restoreSky(Object? raw) {
    if (raw is! Map) return;
    _skyDice = DiceRoller.fromState((raw['dice'] as num?)?.toInt() ?? 0);
    _skies.clear();
    for (final d in (raw['days'] as List? ?? const [])) {
      if (d is! Map) continue;
      final type = campaign.weather.typeById(d['type']?.toString() ?? '');
      final day = (d['day'] as num?)?.toInt();
      final region = d['region']?.toString();
      if (type == null || day == null || region == null) continue;
      _skies[region] = DayWeather(
        regionId: region,
        day: day,
        season: campaign.weather.calendar.seasonOf(day),
        die: (d['die'] as num?)?.toInt() ?? 0,
        type: type,
        stormStartHour: (d['stormStart'] as num?)?.toInt(),
        stormHours: (d['stormHours'] as num?)?.toInt(),
      );
    }
    _caughtIn = raw['caughtIn']?.toString();
    _sheltering = raw['sheltering'] == true;
    _exposedMinutes = (raw['exposed'] as num?)?.toInt() ?? 0;
    _weathered
      ..clear()
      ..addAll([for (final k in (raw['weathered'] as List? ?? const [])) '$k']);
  }
}
