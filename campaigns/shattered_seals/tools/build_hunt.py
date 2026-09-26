"""Writes the hunter roster into bestiary.json and the hunt table into
hunt.json.

Statblocks come from the creature-building tables in creature_tables.py, so
every hunter sits on the same curve as the rest of the bestiary.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import house_json as h  # noqa: E402
from creature_tables import statblock  # noqa: E402

os.chdir(os.path.dirname(HERE))


HUNTERS = [
    dict(
        cid='c_hunt_copper_rat', name='Copper-Tongue Rat', level=0,
        style='skirmisher', saves=('moderate', 'high', 'low'), speed=30,
        traits=['animal', 'hunter'],
        description=(
            'A rat the size of a terrier with a green stain round its muzzle, '
            'the colour a penny goes. They follow coin. Nobody in Millhaven '
            'can tell you how they know where it is.'),
        attacks=[dict(name='jaws', type='P', primary=True)],
        specials=['Goes for the purse, not the throat, until something '
                  'stands in the way.'],
        coin='1d6',
        arrival=(
            'Something small has been keeping to the ditch beside you for a '
            'while. It stops when you stop. Its nose is working at your '
            'belt.'),
    ),
    dict(
        cid='c_hunt_hedge_footpad', name='Hedge Footpad', level=2,
        style='skirmisher', saves=('low', 'high', 'moderate'),
        traits=['human', 'hunter'],
        description=(
            'Somebody who was in the Sparrow when you paid for your drinks, '
            'and a sister-in-law\'s hatchet, and a scarf over the face that '
            'fools nobody.'),
        attacks=[
            dict(name='hatchet', type='S', primary=True, traits=['agile']),
            dict(name='thrown stone', type='B', reach='far'),
        ],
        specials=['Runs the moment it is clear the money is not coming '
                  'quietly.'],
        coin='2d6',
        arrival=(
            'A figure steps out of the hedge ahead of you with the particular '
            'bad confidence of someone who has rehearsed this. "Purses. On '
            'the ground. Nobody needs to be brave."'),
    ),
    dict(
        cid='c_hunt_tithe_taker', name='Covenant Tithe-Taker', level=4,
        style='standard', saves=('moderate', 'moderate', 'high'),
        traits=['human', 'covenant', 'hunter'],
        description=(
            'The Covenant keeps an account of what everybody has. This one '
            'carries the page with your names on it, and a knife for '
            'crossing a name out.'),
        attacks=[
            dict(name='tally knife', type='S', primary=True,
                 traits=['agile']),
            dict(name='red cord', type='B', reach='near'),
        ],
        specials=['Reads out the sum you are worth before it starts, and '
                  'gets it right to the copper.'],
        coin='3d6+10',
        arrival=(
            'A young man in a good coat is waiting where the path narrows, '
            'reading from a folded page. He reads your names. Then a number. '
            '"The Covenant will take its share," he says, "and you will not '
            'be needing the rest."'),
    ),
    dict(
        cid='c_hunt_gilt_harpy', name='Gilt Harpy', level=6,
        style='skirmisher', saves=('moderate', 'high', 'low'), speed=40,
        traits=['beast', 'hunter'],
        description=(
            'Feathers the colour of old brass, and a woman\'s face that has '
            'never had to smile at anyone. She lines her nest with rings, '
            'and with the fingers that were in them.'),
        attacks=[
            dict(name='talons', type='S', primary=True),
            dict(name='diving rake', type='P', reach='near',
                 traits=['agile']),
        ],
        specials=['Sings when she is winning. Stop the song and she stops '
                  'being sure of herself.'],
        coin='4d10+30',
        arrival=(
            'A shadow goes over you twice. The third time it comes down, '
            'with a shriek like a gate hinge and its eyes fixed not on your '
            'face but on your hands.'),
    ),
    dict(
        cid='c_hunt_hoard_wight', name='Hoard-Wight', level=8,
        style='standard', saves=('high', 'low', 'moderate'),
        traits=['undead', 'hunter'],
        description=(
            'He was buried with his money on the understanding that it would '
            'stay with him. It did not. He has been walking the valley ever '
            'since, following gold he hopes is his.'),
        attacks=[
            dict(name='grave-cold grip', type='negative', primary=True,
                 on_critical='A coin in your purse goes black and will not '
                             'come clean.'),
            dict(name='miser\'s curse', type='negative', reach='near'),
        ],
        specials=['Stops to count any coin that is thrown down, and counts '
                  'slowly.'],
        coin='4d20+60',
        arrival=(
            'You smell him first: grave earth and brass polish. Then he is '
            'there in the road, a thin man in a burial coat with the pockets '
            'turned out, holding out a hand. "Mine," he says.'),
    ),
    dict(
        cid='c_hunt_ash_ogre', name='Ash Ogre', level=10,
        style='brute', saves=('high', 'low', 'moderate'),
        traits=['giant', 'hunter'],
        description=(
            'Nine feet of ogre gone grey from the fall of ash off the mines, '
            'carrying a club that was a pit prop and a sack that is already '
            'half full of other people\'s valuables.'),
        attacks=[dict(name='pit-prop club', type='B', primary=True,
                      reach='near')],
        specials=['Wants the sack filled more than it wants you dead, and '
                  'will take a bribe that is big enough.'],
        coin='6d20+140',
        arrival=(
            'The ground shakes before you see it. It comes round the bend '
            'with the sack over one shoulder, looks at your packs, and grins '
            'with every one of its teeth.'),
    ),
    dict(
        cid='c_hunt_cinder_drake', name='Cinder Drake', level=12,
        style='brute', saves=('high', 'moderate', 'moderate'), speed=40,
        traits=['dragon', 'fire', 'hunter'],
        description=(
            'A drake can smell gold the way a hound smells meat, and this one '
            'has smelled yours from the other side of the valley. Its scales '
            'shed sparks when it breathes.'),
        attacks=[
            dict(name='jaws', type='P', primary=True),
            dict(name='cinder spit', type='fire', reach='far'),
        ],
        specials=['Will not leave while it can smell the gold; will not '
                  'stay once the gold is out of reach.'],
        coin='8d20+320',
        arrival=(
            'Heat on the back of your neck, and a smell like a forge left '
            'burning overnight. The drake drops out of the smoke ahead of '
            'you and settles, patient, between you and the road.'),
    ),
    dict(
        cid='c_hunt_red_vein_stalker', name='Red-Vein Stalker', level=14,
        style='standard', saves=('high', 'low', 'moderate'),
        traits=['construct', 'bloodstone', 'hunter'],
        description=(
            'Bloodstone ore given legs and a single instruction by somebody '
            'in the Covenant. The instruction was your names. The red grain '
            'in it pulses when it is near what it wants.'),
        attacks=[
            dict(name='ore fist', type='B', primary=True),
            dict(name='shard volley', type='P', reach='far'),
        ],
        specials=['Does not tire, does not sleep, and does not stop walking '
                  'toward you until it is broken.'],
        coin='10d20+800',
        arrival=(
            'A red light comes through the dark like an ember in a grate, '
            'steady, getting closer. The ground rings under it. It does not '
            'hurry. It never has to.'),
    ),
    dict(
        cid='c_hunt_crimson_inquisitor', name='Crimson Inquisitor', level=16,
        style='standard', saves=('moderate', 'moderate', 'high'),
        traits=['human', 'covenant', 'hunter'],
        description=(
            'A woman in a red coat and a clerk\'s spectacles who has read '
            'your names in a ledger with a very large sum written next to '
            'them, and who does not like sums that stay large.'),
        attacks=[
            dict(name='ledger-blade', type='S', primary=True),
            dict(name='word of the Vessel', type='negative', reach='far',
                 on_critical='For a moment you cannot remember what you '
                             'were carrying.'),
        ],
        specials=['Will talk, if you ask what she wants. What she wants is '
                  'everything.'],
        coin='10d20+1900',
        arrival=(
            'She is sitting on a milestone with a book open on her knee. She '
            'closes it when she sees you, takes off her spectacles, and '
            'folds them away. "You are worth a great deal," she says. "That '
            'is going to change."'),
    ),
    dict(
        cid='c_hunt_tithe_knight', name='The Tithe-Knight', level=18,
        style='brute', saves=('high', 'low', 'high'),
        traits=['undead', 'hunter'],
        description=(
            'An armoured revenant who collected the Crown\'s taxes three '
            'hundred years ago, and who has never been told to stop. Its '
            'writ is still nailed to its breastplate.'),
        attacks=[
            dict(name='tax-collector\'s mace', type='B', primary=True),
            dict(name='summons', type='negative', reach='near'),
        ],
        specials=['Accepts payment in full. Nobody has ever had enough.'],
        coin='20d20+4600',
        arrival=(
            'Hooves on the road behind you, slow and exact. A knight in '
            'black plate draws up and unrolls a writ that has gone brown '
            'with age. "Monies owed," it says, in a voice like a vault '
            'door.'),
    ),
    dict(
        cid='c_hunt_vessel_hound', name='Hound of the Vessel', level=20,
        style='skirmisher', saves=('moderate', 'high', 'moderate'), speed=50,
        traits=['shadow', 'fiend', 'hunter'],
        description=(
            'Something the Shadow Vessel has let off its leash. It has the '
            'outline of a hound and the manners of a debt collector, and '
            'everywhere it has walked the gold has gone dull.'),
        attacks=[
            dict(name='unmaking bite', type='negative', primary=True),
            dict(name='shadow lunge', type='negative', reach='near',
                 traits=['agile']),
        ],
        specials=['Tarnishes gold it touches. What it takes, it takes for '
                  'the Vessel, not for itself.'],
        coin='20d20+13800',
        arrival=(
            'The light goes out of the coins in your purse all at once, as '
            'though someone had breathed on them. Then the shadow at your '
            'heel stands up on four legs.'),
    ),
    dict(
        cid='c_hunt_hoardmother', name='The Hoardmother', level=23,
        style='brute', saves=('high', 'moderate', 'high'), speed=60,
        traits=['dragon', 'hunter'],
        description=(
            'Old enough to remember when Valorheim paid her tribute, and '
            'offended that it stopped. She has heard what you are worth. '
            'She considers it hers.'),
        attacks=[
            dict(name='jaws', type='P', primary=True),
            dict(name='tail', type='B', reach='near'),
            dict(name='breath of the hoard', type='fire', reach='far',
                 on_critical='Whatever gold you carried is a puddle.'),
        ],
        specials=['Talks before she fights, and means every word of it.'],
        coin='40d20+40000',
        arrival=(
            'The sky goes dark from one edge to the other, and it is not '
            'cloud. The Hoardmother comes down in front of you like a '
            'building falling, and her first word is your names.'),
    ),
]

TIERS = [
    {'name': 'Unremarked', 'from_percent': 0, 'chance': 0,
     'description': 'Nobody has looked twice at what you carry.'},
    {'name': 'Noticed', 'from_percent': 125, 'threat': 'low', 'chance': 4,
     'description': 'People have started to look at your packs before they '
                    'look at your faces.'},
    {'name': 'Marked', 'from_percent': 200, 'threat': 'moderate', 'chance': 7,
     'description': 'Your names are being said in places you have not been, '
                    'with a sum after them.'},
    {'name': 'Hunted', 'from_percent': 300, 'threat': 'severe', 'chance': 10,
     'description': 'Things that should not be able to count are following '
                    'what you are worth.'},
    {'name': 'Infamous', 'from_percent': 500, 'threat': 'extreme',
     'chance': 14,
     'description': 'Everything in Valorheim with teeth and a taste for gold '
                    'knows where you are.'},
]

best = h.load('bestiary.json')
creatures = [c for c in best['creatures']
             if not c['creature_id'].startswith('c_hunt_')]
roster = []
for hunter in HUNTERS:
    spec = {k: v for k, v in hunter.items() if k not in ('coin', 'arrival')}
    creatures.append(statblock(**spec))
    roster.append({'creature': hunter['cid'], 'coin': hunter['coin'],
                   'arrival': hunter['arrival']})
best['creatures'] = creatures
h.save('bestiary.json', best)

h.save('hunt.json', {
    'rest_steps': 6,
    'rob_percent': 20,
    'notoriety': TIERS,
    'hunters': roster,
})
print(f'{len(HUNTERS)} hunters, levels',
      ', '.join(str(x['level']) for x in HUNTERS))
