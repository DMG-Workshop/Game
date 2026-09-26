"""Adds levels 14 to 20: what the Sundering opens under the capital.

Blood and Thrones ends by setting Trigger_Sundering_Earthquake_Event and
curing the King, and nothing took either up. Here the earthquake opens the
Palace Plaza onto the Quiet Kingdom that Valorheim was built over, the Queen
goes down to it, and the King is back on his feet to say so: a third main
quest, two side quests, eight rooms in two zones, ten creatures from the
creature-building tables and eight fights at levels 14 to 20.

Already applied: kept as the record of what it added and why. It stops before
writing anything if the Sundering is already there.
"""
import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
import house_json as h  # noqa: E402
from creature_tables import statblock  # noqa: E402

os.chdir(os.path.dirname(TOOLS))

SUNDERING = 'Trigger_Sundering_Earthquake_Event'

if '"tier_3_quiet_kingdom"' in open('campaign_arcs.json',
                                    encoding='utf-8').read():
    raise SystemExit('the Sundering is already written')


def add_unique(items, key, new):
    have = {i[key] for i in items}
    for item in new:
        if item[key] in have:
            raise SystemExit(f'{item[key]} already exists')
        items.append(item)


# --- rooms -------------------------------------------------------------------

loc = h.load('locations.json')
zones = loc['towns']['town_02_valorheim_capital']['zones']
zones['z_09_the_sundering'] = [
    'SD_001_Rift', 'SD_002_BuriedStreet', 'SD_003_UnmakingTemple',
    'SD_004_GuardPost']
zones['z_10_quiet_court'] = [
    'QK_001_CausewayOfNames', 'QK_002_QuietCourt', 'QK_003_WellOfSeals',
    'QK_004_Cradle']

rooms = {r['room_id']: r for r in loc['rooms']}
rooms['VC_001_Plaza']['exits']['down'] = {
    'to': 'SD_001_Rift',
    'requires': [SUNDERING],
    'minutes': 20,
    'blocked': 'The flagstones of the plaza are laid over something older. '
               'Stand still long enough and you can feel it through your '
               'boots, and you are not the only one in the square standing '
               'still to feel it.',
}

add_unique(loc['rooms'], 'room_id', [
    {
        'room_id': 'SD_001_Rift',
        'title': 'The Rift',
        'description':
            'The plaza fell in along a line as straight as a ruled margin, '
            'and the paving went down in slabs that lie now like the steps '
            'of a giant\'s stair. Palace light comes down the crack in a '
            'single blade. Below it the stone is older, darker, and cut by '
            'somebody who did not measure the way Valorheim measures.',
        'exits': {'up': {'to': 'VC_001_Plaza', 'minutes': 20},
                  'down': 'SD_002_BuriedStreet'},
    },
    {
        'room_id': 'SD_002_BuriedStreet',
        'title': 'The Buried Street',
        'description':
            'A street, whole, under the capital: doorways, shutters, a well '
            'with its bucket still on the chain, and overhead, instead of '
            'sky, the undersides of Valorheim\'s cellars. Every house has its '
            'door open. Every threshold has been swept. Nobody has lived here '
            'for a thousand years, and it is ready for visitors.',
        'exits': {'up': 'SD_001_Rift', 'east': 'SD_003_UnmakingTemple',
                  'west': 'SD_004_GuardPost'},
    },
    {
        'room_id': 'SD_003_UnmakingTemple',
        'title': 'The Temple of Unmaking',
        'description':
            'A round temple with no altar, only a floor worn into a shallow '
            'bowl by a great many people kneeling in one place for a great '
            'many years. The walls were carved once. They have been rubbed '
            'smooth, all but a single line near the floor that nobody could '
            'reach without lying down: WE CHOSE TO STOP. A stair goes down '
            'from the middle of the bowl.',
        'exits': {'west': 'SD_002_BuriedStreet',
                  'down': 'QK_001_CausewayOfNames'},
    },
    {
        'room_id': 'SD_004_GuardPost',
        'title': 'The Fallen Guard Post',
        'description':
            'Part of the palace came down into the street with the plaza: a '
            'guard post, whole, sitting at an angle among older houses with '
            'its lamp still on its hook. The door is off. There are boot '
            'marks going in, a great many of them, and none coming out.',
        'exits': {'east': 'SD_002_BuriedStreet'},
    },
    {
        'room_id': 'QK_001_CausewayOfNames',
        'title': 'The Causeway of Names',
        'description':
            'A causeway across a dark that has no floor you can see, paved '
            'in long stones, and every stone carved edge to edge with names '
            'in a script older than the kingdom. A great many of them have '
            'been scraped out, deep and fresh, as if by a tongue. At the '
            'near end the newest names are in plain letters, and the chisel '
            'that cut them is still lying beside the last.',
        'exits': {'up': 'SD_003_UnmakingTemple', 'north': 'QK_002_QuietCourt'},
    },
    {
        'room_id': 'QK_002_QuietCourt',
        'title': 'The Quiet Court',
        'description':
            'A throne room, and Valorheim\'s was copied from it: the same '
            'vault, the same dais, the same long approach meant to make '
            'visitors feel small. There is no perfume here, and no decay '
            'under it. There is nothing here at all but the court, still in '
            'its places, waiting for its king to finish a sentence he began '
            'a thousand years ago.',
        'exits': {'south': 'QK_001_CausewayOfNames',
                  'down': 'QK_003_WellOfSeals'},
    },
    {
        'room_id': 'QK_003_WellOfSeals',
        'title': 'The Well of Seals',
        'description':
            'A shaft going down through the rock in a spiral of seals, each '
            'one a great disc of red and black the size of a cart wheel, set '
            'into the wall like the rungs of a ladder for something very '
            'large. Most of them are broken. The Covenant\'s chisels are '
            'still in some of the cracks.',
        'exits': {'up': 'QK_002_QuietCourt', 'down': 'QK_004_Cradle'},
    },
    {
        'room_id': 'QK_004_Cradle',
        'title': 'The Vessel\'s Cradle',
        'description':
            'The bottom of the world, or of this one. A hollow in the rock '
            'shaped to hold something the size of a cathedral, and something '
            'is lying in it, the colour of the space between lamps. It is '
            'breathing slowly. A length of fine chain runs from it, across '
            'the floor, to a woman in a Queen\'s gown who is kneeling with '
            'her hands on it, as if she were warming them.',
        'exits': {'up': 'QK_003_WellOfSeals'},
    },
])
h.save('locations.json', loc)


# --- creatures ---------------------------------------------------------------

CREATURES = [
    statblock(
        'c_crimson_zealot', 'Crimson Zealot', 14, style='standard',
        saves=('moderate', 'moderate', 'high'), traits=['human', 'covenant'],
        description=(
            'The last of the Covenant\'s faithful, who followed the Queen down '
            'when the rest ran. They have cut the crimson out of their coats '
            'and bound it round their wrists instead, tight enough to hurt.'),
        attacks=[
            dict(name='serrated glaive', type='S', primary=True, reach='near'),
            dict(name='crimson word', type='negative', reach='far'),
        ],
        specials=['Fights to the end. There is nothing left above for it to go '
                  'back to.']),
    statblock(
        'c_unmade', 'The Unmade', 14, style='brute',
        saves=('high', 'low', 'moderate'),
        traits=['undead', 'mindless', 'entropy'],
        description=(
            'Somebody of the Quiet Kingdom who chose, with the rest, to stop, '
            'and did not quite manage it. There is less of them than there '
            'should be, and the edges are soft, like a word rubbed out.'),
        attacks=[dict(name='unravelling touch', type='negative', primary=True)],
        specials=['Wherever it touches, cloth frays and iron rusts.']),
    statblock(
        'c_entropy_hierophant', 'Hierophant of the Unmaking', 18,
        style='standard', saves=('moderate', 'low', 'high'),
        traits=['undead', 'entropy'],
        description=(
            'The priest who led the Quiet Kingdom in its last prayer, kept on '
            'its feet by the unfinished end of it. Its vestments have faded '
            'to no colour at all. Its voice has not.'),
        attacks=[
            dict(name='rod of undoing', type='B', primary=True),
            dict(name='litany of ending', type='negative', reach='far'),
        ],
        specials=['Every line of the litany it finishes takes something from '
                  'the room: a colour, a sound, a name.']),
    statblock(
        'c_rift_maw', 'Rift-Maw', 17, style='brute',
        saves=('high', 'low', 'moderate'), traits=['beast', 'earth'],
        description=(
            'Something that lived in the rock under the capital and never '
            'needed to come up, until the rock split. It is mostly mouth, and '
            'the mouth is mostly stone.'),
        attacks=[
            dict(name='grinding jaws', type='P', primary=True),
            dict(name='tremor', type='B', reach='near'),
        ],
        specials=['Swallows what it kills whole, armour and all.']),
    statblock(
        'c_name_eater', 'The Name-Eater', 19, style='skirmisher',
        saves=('moderate', 'high', 'high'), speed=35,
        traits=['aberration', 'entropy'],
        description=(
            'The Quiet Kingdom\'s last servant, made to take every name off '
            'the causeway once its people were gone, so there would be '
            'nobody left to remember. It has been at the work a thousand '
            'years. It has got used to the taste.'),
        attacks=[
            dict(name='unwriting tongue', type='negative', primary=True,
                 on_critical='For a moment nobody in the party can remember '
                             'your name.'),
            dict(name='erasure', type='negative', reach='far'),
        ],
        specials=['Speaks only in names it has eaten. It has eaten a great '
                  'many.']),
    statblock(
        'c_quiet_king', 'The Last Quiet King', 20, style='standard',
        saves=('high', 'moderate', 'high'), traits=['undead', 'entropy'],
        description=(
            'His crown went up out of here long ago, to be traded from hand to '
            'hand in the kingdom above. When his people chose to stop he '
            'stayed to see it done, and it was never quite done. He is very '
            'tired, and very courteous, and he would like you to stop too.'),
        attacks=[
            dict(name='sceptre of quiet', type='B', primary=True),
            dict(name='decree of silence', type='negative', reach='far'),
        ],
        specials=['Asks each of you, before he fights you, whether you would '
                  'like to stop. He means it kindly.']),
    statblock(
        'c_quiet_courtier', 'Quiet Courtier', 16, style='skirmisher',
        saves=('low', 'high', 'moderate'), traits=['undead', 'entropy'],
        description=(
            'A courtier still in its place at the side of the approach, in '
            'robes gone the grey of old paper, with a thin blade it never '
            'draws until the King has finished speaking.'),
        attacks=[dict(name='etiquette blade', type='P', primary=True,
                      traits=['agile'])],
        specials=['Never raises its voice. Never needs to.']),
    statblock(
        'c_last_seal_breaker', 'Last Seal-Breaker', 19, style='standard',
        saves=('moderate', 'moderate', 'high'), traits=['human', 'covenant'],
        description=(
            'One of the Covenant\'s masons, who spent a life learning where a '
            'seal will crack, and has come down to the last of them with a '
            'chisel and a mallet and the patience of a stone-cutter.'),
        attacks=[
            dict(name='breaking chisel', type='P', primary=True),
            dict(name='shatter-word', type='force', reach='near'),
        ],
        specials=['Stops working the seal only long enough to kill you, and '
                  'goes straight back to it after.']),
    statblock(
        'c_shadow_vessel', 'The Shadow Vessel', 22, style='brute',
        saves=('high', 'moderate', 'high'), speed=40,
        traits=['shadow', 'entropy', 'unique'],
        description=(
            'What the Quiet Kingdom made to end itself, and then, at the '
            'last, chose not to use. It is not awake. It is dreaming, and '
            'what it dreams of is everything being still.'),
        attacks=[
            dict(name='unmaking grasp', type='negative', primary=True,
                 reach='near'),
            dict(name='the long dark', type='negative', reach='far',
                 on_critical='The light goes out of the world for a moment, '
                             'and does not come back all the way.'),
        ],
        specials=['It fights like something dreaming, and every wound it '
                  'takes wakes it a little more.']),
    statblock(
        'c_liora_vessel_bound', 'Liora, Vessel-Bound', 20, style='standard',
        saves=('moderate', 'moderate', 'high'),
        traits=['human', 'shadow', 'unique'],
        description=(
            'The Queen of Valorheim, on her knees in the Cradle with the '
            'Vessel\'s chain wound round both wrists. She has not come down '
            'here to wake it. She has come down to wear it.'),
        attacks=[
            dict(name='the Queen\'s knife', type='P', primary=True,
                 traits=['agile']),
            dict(name='royal command', type='negative', reach='far'),
        ],
        specials=['Where she bleeds, the Vessel does.']),
]

best = h.load('bestiary.json')
# Hunters stay last, where build_hunt.py writes them.
hunters = [c for c in best['creatures'] if c['creature_id'].startswith('c_hunt_')]
story = [c for c in best['creatures']
         if not c['creature_id'].startswith('c_hunt_')]
add_unique(story, 'creature_id', CREATURES)
best['creatures'] = story + hunters


# --- fights --------------------------------------------------------------------

add_unique(best['encounters'], 'encounter_id', [
    {
        'encounter_id': 'e_rift_mouth',
        'location': 'SD_001_Rift',
        'name': 'The Queen\'s Rearguard',
        'description':
            'Two figures rise from behind the fallen paving with glaives '
            'already levelled. They were left here to see that nobody '
            'followed, and they have been looking forward to somebody trying.',
        'creatures': ['c_crimson_zealot', 'c_crimson_zealot'],
        'start_zone': 'near',
        'ambush': True,
        'victory_flags': ['cleared_the_rift'],
        'coin': '10d20+600',
    },
    {
        'encounter_id': 'e_buried_street',
        'location': 'SD_002_BuriedStreet',
        'name': 'Those Who Chose',
        'description':
            'Figures come out of the open doorways the way neighbours come '
            'out to see who is passing. There is not quite enough of any of '
            'them. They come to meet you anyway.',
        'creatures': ['c_unmade', 'c_unmade', 'c_unmade'],
        'start_zone': 'near',
        'ambush': True,
        'victory_flags': ['cleared_buried_street'],
        'coin': '10d20+900',
    },
    {
        'encounter_id': 'e_unmaking_temple',
        'location': 'SD_003_UnmakingTemple',
        'name': 'The Litany of Ending',
        'description':
            'In the bottom of the bowl a figure in colourless vestments is '
            'reading aloud, and one of the Unmade kneels in front of it, '
            'listening. The reading stops when you come in. The figure turns '
            'the page and begins on you.',
        'creatures': ['c_entropy_hierophant', 'c_unmade'],
        'start_zone': 'near',
        'ambush': True,
        'victory_flags': ['cleared_unmaking_temple'],
        'coin': '12d20+1500',
    },
    {
        'encounter_id': 'e_guard_post',
        'location': 'SD_004_GuardPost',
        'name': 'What the Patrol Found',
        'description':
            'The floor of the guard post heaves, and heaves again, and the '
            'boards go up in splinters round something that is mostly a '
            'mouth. It has been waiting under here since the last lot came '
            'in. It is hungry again.',
        'creatures': ['c_rift_maw'],
        'start_zone': 'near',
        'requires': ['aldric_asked_after_the_patrol'],
        'victory_flags': ['found_the_last_patrol'],
        'coin': '10d20+1200',
    },
    {
        'encounter_id': 'e_causeway_of_names',
        'location': 'QK_001_CausewayOfNames',
        'name': 'The Name-Eater',
        'description':
            'Out on the causeway something long and pale is bent over the '
            'stones, and the scraping sound is its tongue. It lifts its head. '
            'It says a name you do not know, and then one you do.',
        'creatures': ['c_name_eater'],
        'start_zone': 'far',
        'ambush': True,
        'victory_flags': ['cleared_causeway'],
        'coin': '12d20+2500',
    },
    {
        'encounter_id': 'e_quiet_court',
        'location': 'QK_002_QuietCourt',
        'name': 'The Quiet Court in Session',
        'description':
            'The King on the dais lifts his head for the first time in a '
            'thousand years. "Visitors," he says, and down the long approach '
            'two of his courtiers turn to face you, drawing thin blades with '
            'no hurry at all.',
        'creatures': ['c_quiet_king', 'c_quiet_courtier', 'c_quiet_courtier'],
        'start_zone': 'near',
        'ambush': True,
        'victory_flags': ['cleared_quiet_court'],
        'coin': '16d20+4500',
    },
    {
        'encounter_id': 'e_well_of_seals',
        'location': 'QK_003_WellOfSeals',
        'name': 'The Last Seal-Breakers',
        'description':
            'Two masons in Covenant aprons are working the lowest whole seal '
            'with chisels, in rhythm, like men setting a millstone. They put '
            'down the mallets when they see you. They pick up something '
            'heavier.',
        'creatures': ['c_last_seal_breaker', 'c_last_seal_breaker'],
        'start_zone': 'near',
        'ambush': True,
        'victory_flags': ['cleared_well_of_seals'],
        'coin': '16d20+6000',
    },
    {
        'encounter_id': 'e_vessels_cradle',
        'location': 'QK_004_Cradle',
        'name': 'The Vessel Wakes',
        'description':
            'The Queen stands, the chain running from her wrists to the thing '
            'in the Cradle, and the thing in the Cradle moves the way a '
            'sleeper moves when somebody says its name. "You are just in '
            'time," says Liora.',
        'creatures': ['c_shadow_vessel', 'c_liora_vessel_bound'],
        'start_zone': 'near',
        'ambush': True,
        'victory_flags': ['boss_defeated_shadow_vessel'],
        'coin': '20d20+10000',
    },
])
h.save('bestiary.json', best)


# --- objects -------------------------------------------------------------------

items = h.load('world_items.json')
add_unique(items['items'], 'item_id', [
    {
        'item_id': 'i_patrol_roll',
        'name': 'The Patrol\'s Watch-Roll',
        'location': 'SD_004_GuardPost',
        'in_room':
            'Among what the maw brought up, a leather roll-case with the '
            'palace seal on it, chewed at one end.',
        'description':
            'The watch-roll of the Third Palace Patrol: eight names, and a '
            'tick beside each for every muster. The last muster, the night '
            'of the earthquake, has no ticks at all.',
        'takeable': True,
        'hidden_until': ['found_the_last_patrol'],
        'acquire_flags': ['item_acquired_patrol_roll'],
        'on_take':
            'Somebody went down the rift after the quake with seven men '
            'behind him and a roll to tick them off by. He did not get to '
            'tick them off.',
    },
    {
        'item_id': 'i_causeway_rubbing',
        'name': 'A Rubbing of the Newest Name',
        'location': 'QK_001_CausewayOfNames',
        'in_room':
            'At the near end of the causeway the newest name is cut in plain '
            'letters, clean and deep, with the chisel still beside it. A '
            'sheet of paper and a stick of wax lie ready, as if whoever cut '
            'it meant for somebody to take a copy.',
        'description':
            'A wax rubbing of a single name, cut into the causeway this week '
            'in a good clerkly hand: WENNA HALE.',
        'takeable': True,
        'hidden_until': ['cleared_causeway'],
        'acquire_flags': ['item_acquired_causeway_rubbing'],
        'on_take':
            'The causeway is where the Quiet Kingdom put the names of those it '
            'meant to stop first. The Queen has added one on her way down. It '
            'is an eleven-year-old girl\'s, and she has left the wax out so '
            'that somebody would carry the news back up.',
    },
    {
        'item_id': 'i_quiet_charter',
        'name': 'The Charter of the Quiet',
        'location': 'QK_002_QuietCourt',
        'in_room':
            'On the arm of the empty throne lies a tablet of black stone, '
            'written close on both sides, where the King set it down to rise.',
        'description':
            'The Quiet Kingdom\'s last law, in its own script and, below it, '
            'in Valorheim\'s, cut later by another hand: the first thing the '
            'kingdom above ever wrote.',
        'takeable': True,
        'hidden_until': ['cleared_quiet_court'],
        'acquire_flags': ['item_acquired_quiet_charter'],
        'on_take':
            'They made the Vessel to end everything, themselves first. At the '
            'last they could not bring themselves to wake it, and they sealed '
            'it instead, and stopped anyway, one by one, the slow way. The '
            'seals only hold against something waking on its own. They do '
            'not hold against somebody climbing in.\n\n'
            'The Queen has not come down here to wake the Vessel. She has '
            'come down to wear it.',
    },
])
h.save('world_items.json', items)


# --- people --------------------------------------------------------------------

npcs = h.load('npcs_and_dialogue.json')
for npc in npcs['npcs']:
    if npc['npc_id'] == 'npc_005_queen_liora':
        # She goes down with the Sundering, and the King has the throne back.
        npc['leaves_after'] = [SUNDERING]
add_unique(npcs['npcs'], 'npc_id', [
    {
        'npc_id': 'npc_012_aldric',
        'name': 'King Aldric',
        'location': 'VC_002_ThroneRoom',
        'tier': 2,
        'appears_after': ['NPC_King_Aldric_cured'],
        'appearance':
            'A gaunt man in a nightshirt, with the crown of Valorheim in his '
            'lap, sits on the lowest step of the dais rather than the throne, '
            'as if he has not yet decided whether it is still his.',
        'greeting':
            'You will be the ones I owe my wits to. Sit, if you like. There '
            'is nobody left in this room to tell you not to.',
        'keywords': {
            'queen':
                'My wife went down into the plaza the night it opened, with '
                'a length of chain and nobody to carry her train. I have been '
                'married to her for twenty years. I do not think I have met '
                'her.',
            'sundering':
                'The plaza split along a line older than the city. The '
                'surveyors say the palace was built along it on purpose. I '
                'should like very much to know whose purpose.',
            'patrol':
                'The Third Patrol went down the rift after her the same '
                'night, eight good men. The post they were keeping came down '
                'into the dark after them. Nobody has come back up.',
        },
    },
])
h.save('npcs_and_dialogue.json', npcs)


# --- quests ----------------------------------------------------------------------

TIER_3 = {
    'arc_id': 'tier_3_quiet_kingdom',
    'name': 'The Quiet Kingdom',
    'reward': {'gp': 12000, 'xp': 'major'},
    'levels': [14, 20],
    'start_trigger': SUNDERING,
    'objectives': [
        {'id': 1, 'task': 'Ask the King where the Queen has gone',
         'condition': 'aldric_sent_you_down'},
        {'id': 2, 'task': 'Break the litany in the Temple of Unmaking',
         'condition': 'cleared_unmaking_temple'},
        {'id': 3, 'task': 'Learn what the Quiet Kingdom sealed away',
         'condition': 'item_acquired_quiet_charter'},
        {'id': 4, 'task': 'Stop the Vessel waking',
         'condition': 'boss_defeated_shadow_vessel'},
    ],
    'world_state_changes_on_completion': [
        'Seals_Restored',
        'End_of_Level_20_Campaign',
    ],
}

SIDE_QUESTS = [
    {
        'arc_id': 'side_kings_last_patrol',
        'name': 'The King\'s Last Patrol',
        'kind': 'side',
        'zone': 'z_09_the_sundering',
        'reward': {'gp': 2500, 'xp': 'moderate'},
        'levels': [14, 20],
        'start_trigger': 'aldric_asked_after_the_patrol',
        'objectives': [
            {'id': 1, 'task': 'Find the patrol that went down after the quake',
             'condition': 'found_the_last_patrol'},
            {'id': 2, 'task': 'Bring their watch-roll to the King',
             'condition': 'aldric_given_the_roll'},
        ],
    },
    {
        'arc_id': 'side_the_fifth_name',
        'name': 'The Fifth Name',
        'kind': 'side',
        'zone': 'z_10_quiet_court',
        'reward': {'gp': 5000, 'xp': 'moderate'},
        'levels': [14, 20],
        'start_trigger': 'item_acquired_causeway_rubbing',
        'objectives': [
            {'id': 1, 'task': 'Show the rubbing to Master Hale',
             'condition': 'hale_read_the_rubbing'},
            {'id': 2, 'task': 'Ask Brother Aldus to take the name back',
             'condition': 'aldus_took_back_the_name'},
        ],
    },
]

# campaign_arcs.json keeps its own hand layout, so it is edited as text:
# Blood and Thrones now ends at level 13 and leaves the campaign's end to
# the Quiet Kingdom, which follows it; the side quests go on the end.
text = open('campaign_arcs.json', encoding='utf-8').read()
old_tier_2 = ('      "levels": [11, 20],\n'
              '      "start_trigger": "enter_VC_001",')
assert text.count(old_tier_2) == 1
text = text.replace(old_tier_2, old_tier_2.replace('[11, 20]', '[11, 13]'))
old_end = ('        "Trigger_Sundering_Earthquake_Event",\n'
           '        "End_of_Level_20_Campaign"\n'
           '      ]\n'
           '    },\n')
assert text.count(old_end) == 1
text = text.replace(old_end, (
    '        "Trigger_Sundering_Earthquake_Event"\n'
    '      ]\n'
    '    },\n'
    '    ' + h.dumps(TIER_3, indent=2) + ',\n'))

body = ',\n'.join('    ' + h.dumps(a, indent=2) for a in SIDE_QUESTS)
cut = text.rstrip().rindex(']')
text = text[:cut].rstrip() + ',\n' + body + '\n  ]\n}\n'
open('campaign_arcs.json', 'w', encoding='utf-8').write(text)

print(f'8 rooms, {len(CREATURES)} creatures, 8 fights, 3 objects, the King, '
      f'1 main quest and {len(SIDE_QUESTS)} side quests')
