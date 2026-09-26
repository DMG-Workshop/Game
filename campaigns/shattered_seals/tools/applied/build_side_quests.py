"""Adds a side quest to every region of the map that lacked one, and one that
follows a party anywhere once it is being hunted: the creatures, fights,
objects and people each needs, and the quests themselves.

Already applied: kept as the record of what it added and why. It stops before
writing anything if the quests are already there.
"""
import os
import re
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
import house_json as h  # noqa: E402

os.chdir(os.path.dirname(TOOLS))

if '"side_names_for_the_hollow"' in open('campaign_arcs.json',
                                         encoding='utf-8').read():
    raise SystemExit('the side quests are already written')


def upsert(items, key, new):
    ids = {n[key] for n in new}
    return [i for i in items if i[key] not in ids] + new


# --- creatures and fights ----------------------------------------------------

CREATURES = [
    {
        'creature_id': 'c_ravencrest_scarecrow',
        'name': 'The Ravencrest Scarecrow',
        'level': 2,
        'description': (
            "Marta's scarecrow, down off its pole and three fields from where "
            'it was put: a turnip head gone soft, a coat that was her '
            "father's, and a child's ribbon round one wrist. It stands with "
            'its arms out, as though it were still keeping birds off '
            'something.'),
        'ac': 17,
        'hp': 30,
        'perception': 8,
        'fortitude': 11,
        'reflex': 5,
        'will': 8,
        'speed': 20,
        'traits': ['construct', 'shadow'],
        'attacks': [
            {'name': 'straw-stuffed grip', 'bonus': 11, 'damage': '1d10+4',
             'damage_type': 'B', 'reach': 'engaged'},
        ],
        'specials': [
            'Burns. It has stood in the rain for years, and it burns anyway.',
        ],
    },
    {
        'creature_id': 'c_red_veined_miner',
        'name': 'Red-Veined Miner',
        'level': 12,
        'description': (
            'Nine went down on the last shift. What is left of them is still '
            'down here, still working, with the red grain of the stone grown '
            'up through their arms like ivy up a wall. They do not stop '
            'swinging when you speak to them.'),
        'ac': 30,
        'hp': 269,
        'perception': 22,
        'fortitude': 25,
        'reflex': 19,
        'will': 22,
        'speed': 20,
        'traits': ['human', 'bloodstone'],
        'attacks': [
            {'name': 'miner\'s pick', 'bonus': 26, 'damage': '3d10+14',
             'damage_type': 'P', 'reach': 'engaged'},
        ],
        'specials': [
            'Keeps the rhythm of a working shift, and strikes on the beat.',
        ],
    },
    {
        'creature_id': 'c_thornhaven_warden',
        'name': 'Thornhaven Gate-Warden',
        'level': 13,
        'description': (
            "Malachai's household guard, in red-lacquered plate with the Vex "
            'crest filed off, and a halberd each. They are guarding the '
            'gatehouse from the outside, and its door from the inside, which '
            'tells you what it is for.'),
        'ac': 33,
        'hp': 235,
        'perception': 23,
        'fortitude': 26,
        'reflex': 23,
        'will': 20,
        'speed': 25,
        'traits': ['human', 'covenant'],
        'attacks': [
            {'name': 'halberd', 'bonus': 27, 'damage': '3d10+16',
             'damage_type': 'S', 'reach': 'near'},
        ],
        'specials': [
            'Holds the gatehouse door rather than give chase.',
        ],
    },
]

ENCOUNTERS = [
    {
        'encounter_id': 'e_oak_grove_scarecrow',
        'location': 'RF_002_OakGrove',
        'name': 'Still Keeping Watch',
        'description': (
            'In the middle of the oak ring, where no field has ever been, a '
            'scarecrow stands with its arms out. It was not here before. Its '
            'head turns to follow you.'),
        'creatures': ['c_ravencrest_scarecrow'],
        'start_zone': 'near',
        'requires': ['marta_told_of_the_scarecrow'],
        'victory_flags': ['scarecrow_burned'],
        'coin': '2d6+4',
    },
    {
        'encounter_id': 'e_lost_shift',
        'location': 'BM_002_DeepMine',
        'name': 'The Last Shift',
        'description': (
            'Down past the last lamp, picks are ringing in a steady rhythm, the '
            'way they would at the start of a shift. Two figures are working '
            'the red face with their backs to you. The tally-tokens on their '
            'belts catch the light.'),
        'creatures': ['c_red_veined_miner', 'c_red_veined_miner'],
        'start_zone': 'near',
        'requires': ['brask_asked_after_the_shift'],
        'victory_flags': ['freed_the_lost_shift'],
        'coin': '6d20+300',
    },
    {
        'encounter_id': 'e_thornhaven_watch',
        'location': 'TH_001_Gates',
        'name': 'The Gatehouse Watch',
        'description': (
            'Two gate-wardens stand in front of the gatehouse door, not the '
            'gate. Behind the door, very quietly, someone is crying, and '
            'someone else is telling them to hush.'),
        'creatures': ['c_thornhaven_warden', 'c_thornhaven_warden'],
        'start_zone': 'near',
        'victory_flags': ['thornhaven_watch_broken'],
        'coin': '8d20+400',
    },
]

best = h.load('bestiary.json')
# Hunters stay last, where build_hunt.py writes them.
hunters = [c for c in best['creatures'] if c['creature_id'].startswith('c_hunt_')]
story = [c for c in best['creatures'] if not c['creature_id'].startswith('c_hunt_')]
best['creatures'] = upsert(story, 'creature_id', CREATURES) + hunters
best['encounters'] = upsert(best['encounters'], 'encounter_id', ENCOUNTERS)
h.save('bestiary.json', best)

# --- objects -----------------------------------------------------------------

ITEMS = [
    {
        'item_id': 'i_name_tokens',
        'name': 'A String of Name-Tokens',
        'location': 'WW_002_Deep',
        'in_room': (
            'Where the thralls fell, a length of twine lies in the leaf '
            'litter, threaded with small carved tokens.'),
        'description': (
            'Eleven tokens of whittled ash on garden twine, each carved with a '
            'name in a careful hand: Tessaly. Orrin. Beck. Hal. The kind a '
            'family hangs over its door for luck.'),
        'takeable': True,
        'hidden_until': ['cleared_whisperwood_thralls'],
        'acquire_flags': ['item_acquired_name_tokens'],
        'on_take': (
            'You wind the twine round your hand. Somebody in the valley made '
            'these, one for each of them, and somebody else went round and '
            'took them all off the doors.'),
    },
    {
        'item_id': 'i_drowning_stone',
        'name': 'A Drowning-Stone',
        'location': 'MR_002_ReedBeds',
        'in_room': (
            'One of the stones the drowned came up with has come loose from '
            'its rope and lies in the shallows, squared off and far too '
            'regular to be anything the mere made.'),
        'description': (
            'A cut block of grey stone the size of a loaf, with an iron ring '
            'leaded into the top and a mark chiselled into one face: a tower '
            'over three lines of water.'),
        'takeable': True,
        'hidden_until': ['cleared_reed_beds'],
        'acquire_flags': ['item_acquired_drowning_stone'],
        'on_take': (
            'It is heavier than it looks. The mark is old, and somebody has '
            'cleaned the moss out of it recently, as if to be sure it could '
            'still be read.'),
    },
    {
        'item_id': 'i_shift_tallies',
        'name': "The Shift's Tallies",
        'location': 'BM_002_DeepMine',
        'in_room': (
            "The miners' brass tally-tokens lie where they fell, still on "
            'their strings.'),
        'description': (
            'Nine brass tokens stamped with numbers, one for each man who went '
            'down on the last shift. The foreman hands them out at the top of '
            'the shaft and takes them back at the end, and that is how he '
            'knows who is still below.'),
        'takeable': True,
        'hidden_until': ['freed_the_lost_shift'],
        'acquire_flags': ['item_acquired_shift_tallies'],
        'on_take': 'Nine. You count them twice. It seems important.',
    },
    {
        'item_id': 'i_gatehouse_door',
        'name': 'The Gatehouse Door',
        'location': 'TH_001_Gates',
        'in_room': (
            'The gatehouse beside the gates has a door of iron-bound oak, and '
            'no handle on the outside.'),
        'description': (
            'Heavy, locked, and newer than the gatehouse. Somebody behind it '
            'is being very quiet on purpose.'),
        'takeable': False,
        'destroyable': True,
        'requires': ['thornhaven_watch_broken'],
        'destroy_flags': ['freed_the_families'],
        'on_destroy': (
            'It takes a long time, and nobody inside makes a sound until it '
            'gives. Then there are eleven of them in the doorway, blinking: '
            "servants' children, a clerk's wife, a boy in a choir tunic, and "
            'a girl of about eleven with ink on her fingers, who asks before '
            'anything else whether you have come from the library.'),
    },
    {
        'item_id': 'i_readers_daybook',
        'name': "A Reader's Day-Book",
        'location': 'UA_002_OssuaryStair',
        'in_room': (
            'One of the Readers had a day-book in its coat, the pages gone '
            'soft with damp.'),
        'description': (
            "An archivist's day-book, kept in a small upright hand until about "
            'a year ago, when the entries stop. The last one reads: "Sent '
            'below to catalogue the sealed stacks. Hale says a fortnight."'),
        'takeable': True,
        'hidden_until': ['cleared_ossuary_stair'],
        'acquire_flags': ['item_acquired_readers_daybook'],
        'on_take': (
            'The name inside the cover is Pell Aubery, Under-Archivist. There '
            'are four more names on the flyleaf, crossed through one at a '
            'time in a different ink.'),
    },
]

items = h.load('world_items.json')
items['items'] = upsert(items['items'], 'item_id', ITEMS)
h.save('world_items.json', items)

# --- people ------------------------------------------------------------------

BRASK = {
    'npc_id': 'npc_011_brask',
    'name': 'Foreman Ruel Brask',
    'location': 'BM_001_Entrance',
    'tier': 2,
    'appearance': (
        "A heavyset man in a foreman's leather apron sits on an upturned ore "
        'cart by the tally board, turning a brass token over and over in his '
        'fingers.'),
    'greeting': (
        "If you're from the Crown, the answer's still no. If you're not, mind "
        'the shaft.'),
    'keywords': {
        'shift': (
            'Nine went down on the last shift. None came up. I have their '
            'tokens out, and nobody to give them back to me.'),
        'tally': (
            'A token going down, the token back coming up. That board has been '
            'wrong for a month.'),
        'deep workings': (
            "Crown's men put a guard on the bottom. Then the guard stopped "
            'coming up and all.'),
    },
}

npcs = h.load('npcs_and_dialogue.json')
npcs['npcs'] = upsert(npcs['npcs'], 'npc_id', [BRASK])
h.save('npcs_and_dialogue.json', npcs)

# --- quests ------------------------------------------------------------------

ZONES = {
    'side_liar_at_the_sparrow': 'z_01_proper',
    'side_undertakers_ledger': 'z_01_proper',
    'side_archivists_secret': 'z_04_palace_district',
}

NEW_ARCS = [
    {
        'arc_id': 'side_names_for_the_hollow',
        'name': 'Names for the Hollow',
        'kind': 'side',
        'zone': 'z_02_whisperwood',
        'reward': {'gp': 15, 'xp': 'moderate'},
        'levels': [1, 10],
        'start_trigger': 'item_acquired_name_tokens',
        'objectives': [
            {'id': 1, 'task': 'Take the names to Brother Aldus',
             'condition': 'aldus_took_the_names'},
        ],
    },
    {
        'arc_id': 'side_scarecrow_walks',
        'name': 'The Scarecrow Walks',
        'kind': 'side',
        'zone': 'z_03_ravencrest',
        'reward': {'gp': 15, 'xp': 'moderate'},
        'levels': [1, 10],
        'start_trigger': 'marta_told_of_the_scarecrow',
        'objectives': [
            {'id': 1, 'task': 'Find what walked off the pole',
             'condition': 'scarecrow_burned'},
            {'id': 2, 'task': 'Tell the Whitmores it is done',
             'condition': 'marta_scarecrow_settled'},
        ],
    },
    {
        'arc_id': 'side_stones_on_the_rope',
        'name': 'Stones on the Rope',
        'kind': 'side',
        'zone': 'z_07_mere_road',
        'reward': {'gp': 25, 'xp': 'moderate'},
        'levels': [1, 10],
        'start_trigger': 'item_acquired_drowning_stone',
        'objectives': [
            {'id': 1, 'task': 'Show the stone to someone who would know the mark',
             'condition': 'thorne_knew_the_stone'},
            {'id': 2, 'task': 'Ask Brother Aldus to say the words for the drowned',
             'condition': 'aldus_blessed_the_drowned'},
        ],
    },
    {
        'arc_id': 'side_lost_shift',
        'name': 'The Lost Shift',
        'kind': 'side',
        'zone': 'z_05_bloodstone_mines',
        'reward': {'gp': 600, 'xp': 'moderate'},
        'levels': [11, 20],
        'start_trigger': 'brask_asked_after_the_shift',
        'objectives': [
            {'id': 1, 'task': 'Find the last shift in the deep workings',
             'condition': 'freed_the_lost_shift'},
            {'id': 2, 'task': 'Bring their tallies up to Foreman Brask',
             'condition': 'brask_given_the_tallies'},
        ],
    },
    {
        'arc_id': 'side_families_in_the_gatehouse',
        'name': 'The Families in the Gatehouse',
        'kind': 'side',
        'zone': 'z_06_thornhaven',
        'reward': {'gp': 900, 'xp': 'moderate'},
        'levels': [11, 20],
        'start_trigger': 'enter_TH_001',
        'objectives': [
            {'id': 1, 'task': 'Break the watch on the gatehouse',
             'condition': 'thornhaven_watch_broken'},
            {'id': 2, 'task': 'Open the gatehouse',
             'condition': 'freed_the_families'},
        ],
    },
    {
        'arc_id': 'side_readers_names',
        'name': "The Readers' Names",
        'kind': 'side',
        'zone': 'z_08_under_archive',
        'reward': {'gp': 500, 'xp': 'moderate'},
        'levels': [11, 20],
        'start_trigger': 'item_acquired_readers_daybook',
        'objectives': [
            {'id': 1, 'task': 'Give the day-book to Master Hale',
             'condition': 'hale_given_the_daybook'},
        ],
    },
    {
        'arc_id': 'side_price_on_your_heads',
        'name': 'A Price on Your Heads',
        'kind': 'side',
        'reward': {'gp': 150, 'xp': 'major'},
        'levels': [1, 20],
        'start_trigger': 'hunted_first',
        'objectives': [
            {'id': 1, 'task': 'Survive three hunts',
             'condition': 'hunt_survived_3'},
            {'id': 2, 'task': 'Find out from Sal Mercy who is paying',
             'condition': 'sal_named_the_broker'},
        ],
    },
]

# campaign_arcs.json keeps its own hand layout, so it is edited as text.
text = open('campaign_arcs.json', encoding='utf-8').read()
for arc_id in [a['arc_id'] for a in NEW_ARCS]:
    assert f'"{arc_id}"' not in text, f'{arc_id} is already written'
for arc_id, zone in ZONES.items():
    pattern = (r'("arc_id": "' + re.escape(arc_id) +
               r'",\n\s+"name": "[^"]*",\n(\s+)"kind": "side",\n)')
    text, n = re.subn(pattern, r'\1\2"zone": "' + zone + '",\n', text)
    assert n == 1, arc_id

body = ',\n'.join('    ' + h.dumps(a, indent=2) for a in NEW_ARCS)
assert text.rstrip().endswith('}\n  ]\n}'.strip()) or text.rstrip().endswith(']\n}')
cut = text.rstrip().rindex(']')
text = text[:cut].rstrip() + ',\n' + body + '\n  ]\n}\n'
open('campaign_arcs.json', 'w', encoding='utf-8').write(text)

print(f'{len(CREATURES)} creatures, {len(ENCOUNTERS)} fights, {len(ITEMS)} '
      f'objects, 1 foreman, {len(NEW_ARCS)} side quests')
