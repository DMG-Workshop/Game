"""Adds the wrong turns, their creatures and clues, and the new cast.

Already applied: kept as the record of what it added and why. It refuses to
add anything that is already there, so running it again is an error rather
than a duplicate.
"""
import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
import house_json as h  # noqa: E402

os.chdir(os.path.dirname(TOOLS))

REVEAL_MERE = 'deception_revealed_mere_road'
REVEAL_ARCHIVE = 'deception_revealed_under_archive'


def add_unique(items, key, new):
    have = {i[key] for i in items}
    for item in new:
        if item[key] in have:
            raise SystemExit(f'{item[key]} already exists')
        items.append(item)


# --- rooms -------------------------------------------------------------------

loc = h.load('locations.json')
loc['towns']['town_01_millhaven']['zones']['z_07_mere_road'] = [
    'MR_001_MereRoad', 'MR_002_ReedBeds', 'MR_003_DrownedMill']
loc['towns']['town_02_valorheim_capital']['zones']['z_08_under_archive'] = [
    'UA_001_SealedStacks', 'UA_002_OssuaryStair', 'UA_003_FalseSeal']

rooms = {r['room_id']: r for r in loc['rooms']}
rooms['MH_004_Temple']['exits']['south'] = {
    'to': 'MR_001_MereRoad',
    'requires': ['heard_of_the_mere_road'],
    'blocked': 'Past the graveyard wall the old Mere Road runs south into the '
               'reeds. Nobody in Millhaven uses it, and nobody has yet given '
               'you a reason to.',
}
rooms['VC_003_GrandLibrary']['exits']['down'] = {
    'to': 'UA_001_SealedStacks',
    'requires': ['heard_of_the_under_archive'],
    'blocked': 'Behind the catalogue desk there is a low iron door with no '
               'handle on this side. Whatever is under the library, the '
               'library does not show it to visitors.',
}

add_unique(loc['rooms'], 'room_id', [
    {
        'room_id': 'MR_001_MereRoad',
        'title': 'The Mere Road',
        'description':
            'An embanked causeway older than the town, running south across '
            'the flats with black water on either side. The ruts are fresh. '
            'So are the footprints, and there are a great many of them, all '
            'going south and all in step, as if whoever made them had taken '
            'care to leave exactly one trail and to make it easy to follow.',
        'exits': {'north': 'MH_004_Temple', 'south': 'MR_002_ReedBeds'},
    },
    {
        'room_id': 'MR_002_ReedBeds',
        'title': 'The Reed Beds',
        'description':
            'The causeway sinks until the mere laps across it. Reeds stand '
            'higher than a rider on either side, and something has been '
            'through them lately, snapping the stems at knee height in a line '
            'that runs beside the road for a long way and then simply stops. '
            "Someone has built a cairn of river stones at the water's edge "
            'this week. It marks nothing.',
        'exits': {'north': 'MR_001_MereRoad', 'south': 'MR_003_DrownedMill'},
    },
    {
        'room_id': 'MR_003_DrownedMill',
        'title': 'The Drowned Mill',
        'description':
            'The mill stands to its sills in the mere, its wheel locked in '
            'weed. Inside, the floor is dry on the millstone dais and nowhere '
            'else. The dais has been swept. A lamp on the beam above it has '
            'been lit and left to burn down, the way you would leave a light '
            'for someone you expected.',
        'exits': {'north': 'MR_002_ReedBeds'},
    },
    {
        'room_id': 'UA_001_SealedStacks',
        'title': 'The Sealed Stacks',
        'description':
            "The library's missing sections are down here, or their shelves "
            'are: row on row of them, empty, dusted and labelled. Every label '
            'has been corrected in the same neat hand to read NOT HELD. The '
            'dust between them has been walked into one clean path, straight '
            'down the middle, to a door at the far end.',
        'exits': {'up': 'VC_003_GrandLibrary', 'down': 'UA_002_OssuaryStair'},
    },
    {
        'room_id': 'UA_002_OssuaryStair',
        'title': 'The Ossuary Stair',
        'description':
            'A spiral stair cut down through a charnel layer older than the '
            'library, skulls set into the wall in courses like brick. Half of '
            'them have been turned to face the stone. At every landing there '
            'are fresh chisel marks with fresh grime rubbed into them: someone '
            'has gone to some trouble to make this stair look older than it '
            'is.',
        'exits': {'up': 'UA_001_SealedStacks', 'down': 'UA_003_FalseSeal'},
    },
    {
        'room_id': 'UA_003_FalseSeal',
        'title': 'The Sealed Vault',
        'description':
            'A round vault at the foot of the stair, and on its far wall a '
            'great seal in red and black of the kind the Covenant breaks: '
            'circles inside circles, and at the centre, a handprint. The '
            'chanting the archivist heard through the floor is here — a '
            'wind-organ set in the ceiling, turning slowly in a draught from '
            'nowhere, sounding its three notes over and over for nobody.',
        'exits': {'up': 'UA_002_OssuaryStair'},
    },
])
h.save('locations.json', loc)


# --- creatures and fights ----------------------------------------------------

best = h.load('bestiary.json')
add_unique(best['creatures'], 'creature_id', [
    {
        'creature_id': 'c_covenant_cutthroat',
        'name': 'Covenant Cutthroat',
        'level': 2,
        'description':
            'A Millhaven face you half recognise from the market, with a '
            'cudgel in one hand and a length of red cord tied round the other '
            'wrist. Paid, and not paid enough to look you in the eye.',
        'ac': 18, 'hp': 30, 'perception': 7,
        'fortitude': 9, 'reflex': 9, 'will': 5, 'speed': 25,
        'traits': ['human', 'covenant'],
        'attacks': [
            {'name': 'cudgel', 'bonus': 10, 'damage': '1d6+4',
             'damage_type': 'B', 'reach': 'engaged'},
            {'name': 'sling', 'bonus': 9, 'damage': '1d6+2',
             'damage_type': 'B', 'reach': 'far'},
        ],
        'specials': [
            'Breaks and runs at the first real wound once the others are down.',
        ],
    },
    {
        'creature_id': 'c_mere_drowned',
        'name': 'Mere-Drowned',
        'level': 3,
        'description':
            'Something that went into the mere a long time ago with a rope '
            'round its ankles and a stone on the rope, and has come back up '
            "with both. It is not one of the Avatar's. Somebody else asked it "
            'up.',
        'ac': 17, 'hp': 50, 'perception': 8,
        'fortitude': 12, 'reflex': 5, 'will': 8, 'speed': 20,
        'traits': ['undead', 'mindless', 'water'],
        'attacks': [
            {'name': 'waterlogged grip', 'bonus': 12, 'damage': '1d10+5',
             'damage_type': 'B', 'reach': 'engaged'},
        ],
        'specials': [
            "Drags whatever it holds toward the water's edge instead of "
            'striking it again.',
        ],
    },
    {
        'creature_id': 'c_archive_warden',
        'name': 'Archive Warden',
        'level': 10,
        'description':
            'A suit of palace armour with nobody in it, walking a patrol it was '
            'given before the library had its present name. There is a key in '
            'its back, and the key is turning.',
        'ac': 30, 'hp': 150, 'perception': 18,
        'fortitude': 22, 'reflex': 15, 'will': 18, 'speed': 20,
        'traits': ['construct', 'mindless'],
        'attacks': [
            {'name': 'halberd', 'bonus': 22, 'damage': '2d10+12',
             'damage_type': 'S', 'reach': 'near'},
        ],
        'specials': [
            'Stops mid-swing if the key in its back is drawn out. Nobody can '
            'reach it from the front.',
        ],
    },
    {
        'creature_id': 'c_ossuary_reader',
        'name': 'Ossuary Reader',
        'level': 9,
        'description':
            'It was an archivist once, by the ink still in the creases of its '
            'knuckles. It has been kept down here to guard the stair, and fed '
            'just enough, and it is hungry now in a way that has nothing to do '
            'with reading.',
        'ac': 28, 'hp': 145, 'perception': 18,
        'fortitude': 18, 'reflex': 19, 'will': 17, 'speed': 30,
        'traits': ['undead', 'ghoul'],
        'attacks': [
            {'name': 'jaws', 'bonus': 20, 'damage': '2d8+10',
             'damage_type': 'P', 'reach': 'engaged'},
            {'name': 'claw', 'bonus': 20, 'damage': '2d6+10',
             'damage_type': 'S', 'reach': 'engaged', 'traits': ['agile']},
        ],
        'specials': [
            'Its claws numb; whatever they open finds its hands slow to answer.',
        ],
    },
])

for e in best['encounters']:
    if e['encounter_id'] == 'e_whisperwood_thralls':
        # It was always written as an ambush; now it behaves like one.
        e['ambush'] = True

add_unique(best['encounters'], 'encounter_id', [
    {
        'encounter_id': 'e_mere_road_cutthroats',
        'location': 'MR_001_MereRoad',
        'name': 'Paid to Wait',
        'description':
            'Two figures stand up out of the reeds on either side of the '
            'causeway with cudgels already in hand. Neither of them looks '
            'surprised to see you.',
        'rearm_description':
            'There are two more of them on the causeway now, standing exactly '
            'where the first two stood, red cord at their wrists. They have '
            'been waiting for you to come back up this road. They knew you '
            'would.',
        'creatures': ['c_covenant_cutthroat', 'c_covenant_cutthroat'],
        'start_zone': 'near',
        'ambush': True,
        'rearm_on': [REVEAL_MERE],
        'victory_flags': ['cleared_mere_road'],
    },
    {
        'encounter_id': 'e_reed_beds_drowned',
        'location': 'MR_002_ReedBeds',
        'name': 'Up Out of the Water',
        'description':
            'The water on either side of the causeway stands up, and keeps '
            'standing up, and has arms.',
        'rearm_description':
            'The reeds you cut through have closed again, and the mere on '
            'either side of the road is standing up the way it did before. '
            'Something has called them back — the same something that rang '
            'the bell.',
        'creatures': ['c_mere_drowned', 'c_mere_drowned'],
        'start_zone': 'near',
        'ambush': True,
        'rearm_on': [REVEAL_MERE],
        'victory_flags': ['cleared_reed_beds'],
    },
    {
        'encounter_id': 'e_drowned_mill',
        'location': 'MR_003_DrownedMill',
        'name': "The Miller's Welcome",
        'description':
            'They were sitting in the dark on the far side of the millstone, '
            'and they are on their feet the moment your boots touch the dry '
            'boards. One of them is still holding a length of the same red '
            'cord as the bundle.',
        'creatures': ['c_covenant_cutthroat', 'c_mere_drowned',
                      'c_covenant_cutthroat'],
        'start_zone': 'near',
        'ambush': True,
        'victory_flags': ['cleared_drowned_mill'],
    },
    {
        'encounter_id': 'e_sealed_stacks_warden',
        'location': 'UA_001_SealedStacks',
        'name': 'The Night Patrol',
        'description':
            'At the end of a row of empty shelves, something in palace armour '
            'turns on its heel and begins, without hurrying, to walk towards '
            'you.',
        'rearm_description':
            'There is a suit on patrol between the shelves again — another, or '
            'the same one put back together. Someone came down the stair '
            'behind you and wound it; the key in its back is still turning.',
        'creatures': ['c_archive_warden'],
        'start_zone': 'far',
        'ambush': True,
        'rearm_on': [REVEAL_ARCHIVE],
        'victory_flags': ['cleared_sealed_stacks'],
    },
    {
        'encounter_id': 'e_ossuary_readers',
        'location': 'UA_002_OssuaryStair',
        'name': 'The Readers',
        'description':
            'Two of the skulls in the wall are not set in mortar, and neither '
            'are the things behind them. They climb down.',
        'rearm_description':
            'The skulls you left facing out have all been turned back to the '
            'wall, and the two empty niches are not empty any more.',
        'creatures': ['c_ossuary_reader', 'c_ossuary_reader'],
        'start_zone': 'near',
        'ambush': True,
        'rearm_on': [REVEAL_ARCHIVE],
        'victory_flags': ['cleared_ossuary_stair'],
    },
    {
        'encounter_id': 'e_false_seal',
        'location': 'UA_003_FalseSeal',
        'name': "The Vault's Keepers",
        'description':
            'Two figures in crimson rise from where they were kneeling in '
            'front of the seal, and a third thing, on a chain, rises with '
            'them. They were not praying. They were listening for your feet on '
            'the stair.',
        'creatures': ['c_covenant_acolyte', 'c_covenant_acolyte',
                      'c_ossuary_reader'],
        'start_zone': 'near',
        'ambush': True,
        'victory_flags': ['cleared_false_seal'],
    },
])
h.save('bestiary.json', best)


# --- the clues that give the game away ---------------------------------------

items = h.load('world_items.json')
add_unique(items['items'], 'item_id', [
    {
        'item_id': 'i_decoy_bundle',
        'name': 'A Bundle of Sacking',
        'location': 'MR_003_DrownedMill',
        'in_room':
            'On the swept millstone lies a bundle of sacking about the size of '
            'a sleeping child, tied off with red cord.',
        'description': 'Sacking, red cord, and a shape that is very nearly right.',
        'takeable': True,
        'requires': ['cleared_drowned_mill'],
        'acquire_flags': [REVEAL_MERE],
        'on_take':
            'It is heavy the wrong way. You cut the cord and river stones spill '
            'across the millstone, and among them a strip of red cloth knotted '
            'the way the Covenant knots it.\n\n'
            'Nobody carried a child down this road. Somebody wanted you to '
            'believe they had, and wanted you a long way from the Whisperwood '
            'while you believed it.\n\n'
            'From back up the causeway, faint across the water, a bell begins '
            'to ring.',
    },
    {
        'item_id': 'i_queens_letter',
        'name': 'A Letter Under Black Wax',
        'location': 'UA_003_FalseSeal',
        'in_room':
            "One of the kneelers left a courier's satchel by the mats. The flap "
            'is open, and there is a letter in it under a black wax seal.',
        'description': 'Heavy cream paper. The wax carries the royal cipher.',
        'takeable': True,
        'requires': ['cleared_false_seal'],
        'acquire_flags': [REVEAL_ARCHIVE],
        'on_take':
            'It is addressed to the keepers of the vault, and it is short.\n\n'
            "'Keep them below as long as they are willing to stay. Hale has "
            'done well; see that the girl is kept comfortable, and remind him '
            "of her if he wavers. — L.'\n\n"
            'The seal on the wall is painted plaster. Close enough to read by, '
            'you can see the brush strokes. Above you, the stair you came down '
            'is full of small sounds, and all of them are coming this way.',
    },
])
h.save('world_items.json', items)


# --- the cast ----------------------------------------------------------------

npcs = h.load('npcs_and_dialogue.json')
add_unique(npcs['npcs'], 'npc_id', [
    {
        'npc_id': 'npc_002_marta',
        'name': 'Marta Whitmore',
        'location': 'RF_001_Farm',
        'tier': 1,
        'appearance':
            'A farm woman in a coat buttoned wrong stands at the fence, '
            'watching the treeline as if it might hand something back.',
        'greeting': "Are you from the Captain? Have you— no. No, you'd have said.",
        'keywords': {
            'elara':
                "She's nine. She's got my mother's temper and her father's "
                'ears, and she has never once in her life come home when she '
                'was called.',
            'grove':
                'The oak ring, back of the barn. Every child in the valley '
                'plays there, and every mother tells them not to.',
            'doll': "She takes it everywhere. She'd have had it with her.",
        },
    },
    {
        'npc_id': 'npc_003_aldus',
        'name': 'Brother Aldus',
        'location': 'MH_004_Temple',
        'tier': 1,
        'appearance':
            "A priest in a plain grey habit kneels at the altar, sorting the "
            "week's offerings into what can be eaten and what cannot.",
        'greeting':
            "Ashkyr keep you. If you've come to leave something, there is room "
            'on the step.',
        'keywords': {
            'burials':
                "Four this week. Each of them dead longer than they'd been "
                'missing, and each of them came to me with their eyes full of '
                'earth.',
            'shoe':
                "Elara Whitmore's. Her mother brought it in. I keep meaning to "
                "give it back, and I can't decide whether that would be a "
                'kindness.',
            'ashkyr':
                'Ashkyr keeps the hearth and the grave. Lately the grave has '
                'been keeping me.',
        },
    },
    {
        'npc_id': 'npc_004_harrow',
        'name': 'Ada Harrow',
        'location': 'MH_005_Forge',
        'tier': 1,
        'appearance':
            'The smith, broad and soot-grey, rests her hammer on the anvil and '
            "watches you the way she'd watch a horse she hadn't been told "
            'about.',
        'greeting':
            "If you want a horse shod, it'll be a week. If you want anything "
            "else, it'll be longer.",
        'keywords': {
            'nails': 'People buy nails. I sell them.',
            'commissions':
                "Four this week I'll not be paid for. I stack them in the order "
                'I heard.',
            'maul':
                'Seal-stone in the head, off the old boundary marker. I made '
                'three and finished one.',
        },
    },
    {
        'npc_id': 'npc_007_wendel',
        'name': 'Wendel Pike',
        'location': 'MH_003_Tavern',
        'tier': 1,
        'appearance':
            'The landlord, a round and pleasant man with a cloth over his '
            'shoulder, has a habit of standing near whoever is talking.',
        'greeting':
            "Welcome to the Sparrow! Sit anywhere but by the door — there's a "
            'draught.',
        'keywords': {
            'ale': 'Best in the valley, and the only one in the valley, which helps.',
            'news':
                "Tollgate on the capital road's shut till the Captain says "
                "otherwise, so half the county's drinking my cellar dry waiting "
                'on it. Ill wind.',
            'lamp':
                "For the late ones. Nobody wants to break their neck on the "
                'back stair in the dark.',
        },
    },
    {
        'npc_id': 'npc_008_hale',
        'name': 'Master Archivist Oswin Hale',
        'location': 'VC_003_GrandLibrary',
        'tier': 2,
        'appearance':
            'A thin man in ink-stained cuffs sits behind the catalogue desk, '
            'with the fixed, careful attention of someone who has not slept '
            'properly in a year.',
        'greeting':
            'Quietly, please. The library is open to all subjects of the Crown. '
            'Mostly.',
        'keywords': {
            'catalogue':
                'Every volume this library has ever held, in the order it came '
                'to us. Including the ones it no longer holds.',
            'missing': 'Removed for conservation, by order of the Crown.',
            'seals': 'Not here. Not in front of the shelves. Ask me properly.',
        },
    },
])
h.save('npcs_and_dialogue.json', npcs)

print('world written')
