"""Writes weather.json: the calendar, how long the road takes, the kinds of
weather and what they do, and each region's d100 table for each season.

Also marks which rooms have a roof over them, and gives the stair under the
library the few minutes it actually takes.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import house_json as h  # noqa: E402

os.chdir(os.path.dirname(HERE))

WEATHER = [
    {'id': 'clear', 'name': 'Clear', 'severity': 'fair', 'travel': 1.0,
     'text': 'The sky is clear from one edge to the other.'},
    {'id': 'overcast', 'name': 'Overcast', 'severity': 'fair', 'travel': 1.0,
     'text': 'Low grey cloud sits over everything like a lid.'},
    {'id': 'heat', 'name': 'Heat', 'severity': 'foul', 'travel': 1.25,
     'text': 'The air is heavy and still, and the road throws the heat back '
             'up at you.'},
    {'id': 'fog', 'name': 'Fog', 'severity': 'foul', 'travel': 1.25,
     'ranged_penalty': 2,
     'text': 'Fog lies in every hollow, and anything more than a spear\'s '
             'length away is a guess.'},
    {'id': 'rain', 'name': 'Rain', 'severity': 'foul', 'travel': 1.5,
     'ranged_penalty': 1,
     'text': 'Steady rain, the kind that finds its way in at the collar.'},
    {'id': 'snow', 'name': 'Snow', 'severity': 'foul', 'travel': 1.5,
     'ranged_penalty': 1,
     'text': 'Snow comes down thick and quiet and fills the road behind you.'},
    {'id': 'ash_fall', 'name': 'Ash-fall', 'severity': 'foul', 'travel': 1.25,
     'ranged_penalty': 1,
     'text': 'Grey ash drifts down out of a sky the colour of pewter.'},
    {'id': 'storm', 'name': 'Thunderstorm', 'severity': 'severe',
     'travel': 2.0, 'ranged_penalty': 2, 'exposure': '2d6', 'after': 'rain',
     'text': 'The storm breaks overhead: rain in sheets, and lightning close '
             'enough to taste.'},
    {'id': 'blizzard', 'name': 'Blizzard', 'severity': 'severe',
     'travel': 2.5, 'ranged_penalty': 4, 'exposure': '3d6', 'after': 'snow',
     'text': 'The blizzard comes in sideways. You cannot see your own hands.'},
    {'id': 'ash_storm', 'name': 'Ash-storm', 'severity': 'severe',
     'travel': 2.0, 'ranged_penalty': 4, 'exposure': '2d8',
     'after': 'ash_fall',
     'text': 'The mines breathe out, and the sky goes black with hot grit '
             'that scours skin and fills the lungs.'},
]

# d100 bands: [roll this or under, weather].
VALLEY = {
    'spring': [[30, 'clear'], [50, 'overcast'], [78, 'rain'], [92, 'fog'],
               [100, 'storm']],
    'summer': [[40, 'clear'], [55, 'overcast'], [70, 'heat'], [85, 'rain'],
               [90, 'fog'], [100, 'storm']],
    'autumn': [[20, 'clear'], [42, 'overcast'], [70, 'rain'], [90, 'fog'],
               [100, 'storm']],
    'winter': [[15, 'clear'], [35, 'overcast'], [50, 'fog'], [80, 'snow'],
               [88, 'rain'], [100, 'blizzard']],
}
HEARTLANDS = {
    'spring': [[25, 'clear'], [45, 'overcast'], [65, 'rain'], [85, 'ash_fall'],
               [95, 'storm'], [100, 'ash_storm']],
    'summer': [[30, 'clear'], [50, 'heat'], [60, 'overcast'],
               [80, 'ash_fall'], [92, 'storm'], [100, 'ash_storm']],
    'autumn': [[20, 'clear'], [40, 'overcast'], [60, 'rain'],
               [82, 'ash_fall'], [94, 'storm'], [100, 'ash_storm']],
    'winter': [[15, 'clear'], [35, 'overcast'], [60, 'snow'],
               [78, 'ash_fall'], [85, 'rain'], [95, 'blizzard'],
               [100, 'ash_storm']],
}

h.save('weather.json', {
    'calendar': {
        'seasons': [
            {'id': 'spring', 'name': 'Spring', 'days': 30},
            {'id': 'summer', 'name': 'Summer', 'days': 30},
            {'id': 'autumn', 'name': 'Autumn', 'days': 30},
            {'id': 'winter', 'name': 'Winter', 'days': 30},
        ],
        'start': {'season': 'autumn', 'day': 12},
    },
    'travel': {
        'same_zone_minutes': 15,
        'new_zone_minutes': 60,
        'new_town_minutes': 480,
        'fatigued_after_hours': 8,
        'exhausted_after_hours': 12,
        'awake_hours': 16,
    },
    'weather': WEATHER,
    'regions': {
        'r_001_millhaven_valley': VALLEY,
        'r_002_valorheim_heartlands': HEARTLANDS,
    },
})

# --- rooms with a roof ---------------------------------------------------------

SHELTERED = {
    'MH_002_GuardHall', 'MH_003_Tavern', 'MH_004_Temple', 'MH_005_Forge',
    'RF_001_Farm', 'VC_002_ThroneRoom', 'VC_003_GrandLibrary',
    'BM_002_DeepMine', 'TH_002_RitualChamber', 'MR_003_DrownedMill',
    'UA_001_SealedStacks', 'UA_002_OssuaryStair', 'UA_003_FalseSeal',
}

locations = h.load('locations.json')
for room in locations['rooms']:
    if room['room_id'] in SHELTERED:
        room['shelter'] = True
    else:
        room.pop('shelter', None)

# A stair is minutes, not the hour a new part of the map usually costs.
for room in locations['rooms']:
    if room['room_id'] == 'VC_003_GrandLibrary':
        room['exits']['down']['minutes'] = 10
    if room['room_id'] == 'UA_001_SealedStacks':
        up = room['exits']['up']
        room['exits']['up'] = {'to': up if isinstance(up, str) else up['to'],
                               'minutes': 10}
h.save('locations.json', locations)
print('weather.json written;', len(SHELTERED), 'rooms with a roof')
