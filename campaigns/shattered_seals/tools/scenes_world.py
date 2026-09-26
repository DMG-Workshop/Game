"""The words around the hunt, and everything that is not a fight: rooms,
objects, shopkeepers, the weather, and the night."""

from scenes_fights import E, P, T

HUNTER_SCENES = {
    'c_hunt_copper_rat': {
        'setting': 'Nothing clever: a rat that smells money. But it found you.',
        'ambiance': [
            'Something else rustles in the ditch, and goes quiet.',
            'Your purse is heavier than it has ever felt.',
        ],
        'opening': [P('It is after the purse. Not the pack. The purse.')],
        'victory': [P('If the rats can smell it, so can everything else.')],
        'defeat': [T('You come round lighter, and the ditch is empty.')],
        'flee': [T('It does not chase you far. It has what it wanted.')],
    },
    'c_hunt_hedge_footpad': {
        'setting': (
            'Word gets round a market town. Somebody in the Sparrow heard '
            'what you paid for your drinks, and came out to see what else '
            'you had.'),
        'ambiance': [
            'A dog barks at a farm somewhere, and stops.',
            'The footpad\'s eyes keep going to your belts.',
        ],
        'opening': [
            E('Purses. On the ground. Nobody needs to be brave.'),
            P('You should have picked someone poorer.'),
        ],
        'victory': [
            P('Go home. Tell whoever sent you we are not worth the trouble.'),
        ],
        'defeat': [E('Told you. Nobody needed to be brave.')],
        'flee': [E('Keep running! Leave the purses next time!')],
    },
    'c_hunt_tithe_taker': {
        'setting': (
            'The Covenant keeps an account of what everybody has. Your line '
            'in it has grown long enough to send someone.'),
        'ambiance': [
            'The tithe-taker checks a figure against his page, and frowns.',
            'Red cord flutters at his wrist.',
        ],
        'opening': [
            E('I have your names, and I have your sum. The Covenant will '
              'take its share.'),
            P('Come and count it, then.'),
        ],
        'victory': [
            P('Burn that page. Then burn the book it came out of.'),
        ],
        'defeat': [E('Tithe collected. The balance will be called later.')],
        'flee': [E('You cannot run from a ledger. We will find you again.')],
    },
    'c_hunt_gilt_harpy': {
        'setting': (
            'Harpies line their nests with what glitters. She has seen '
            'yours from a long way up.'),
        'ambiance': [
            'Her song goes up and down the scale like a coin rolling.',
            'Brass feathers drift down around you.',
        ],
        'opening': [
            E('Pretty, pretty, pretty. Give me the pretty things.'),
            P('Come down here and take them.'),
        ],
        'victory': [P('Her nest must be full of rings. And fingers.')],
        'defeat': [E('Mine now. All the pretty things are mine.')],
        'flee': [E('Run, run! I can see you glitter from the clouds!')],
    },
    'c_hunt_hoard_wight': {
        'setting': (
            'Buried with his money, and robbed of it within the month. He '
            'has been following gold ever since, sure that each piece is his.'),
        'ambiance': [
            'The smell of grave earth and brass polish thickens.',
            'He counts under his breath, and loses his place, and starts '
            'again.',
        ],
        'opening': [
            E('Mine.'),
            P('None of this was ever yours.'),
            E('All of it. All of it was mine.'),
        ],
        'victory': [P('Put him back in the ground. Leave a coin on him.')],
        'defeat': [E('Mine. Mine. Mine.')],
        'flee': [E('I will find it. I always find it.')],
    },
    'c_hunt_ash_ogre': {
        'setting': (
            'An ogre with a sack, grey from the mines\' ash, going from '
            'traveller to traveller like a man picking apples.'),
        'ambiance': [
            'The sack clanks every time the ogre moves.',
            'Ash drifts off its shoulders in grey flakes.',
        ],
        'opening': [
            E('Shinies! Shinies for the sack!'),
            P('That sack is going to be your shroud.'),
        ],
        'victory': [P('Open the sack. Somebody will want their things back.')],
        'defeat': [E('Into the sack! Heavy ones!')],
        'flee': [E('Come back, little shinies!')],
    },
    'c_hunt_cinder_drake': {
        'setting': (
            'A drake can smell gold the way a hound smells meat, and you '
            'have been carrying a great deal of it through its valley.'),
        'ambiance': [
            'Heat comes off the drake in waves that bend the air.',
            'Sparks drop from its jaws and hiss out on the ground.',
        ],
        'opening': [
            T('The drake settles across the road, patient, and breathes out '
              'a long slow ribbon of smoke.'),
            P('It wants the gold. It is not getting it.'),
        ],
        'victory': [P('Cool it down before you touch it. Then check its gut.')],
        'defeat': [
            T('The drake noses through your packs, takes what glitters, and '
              'flies off heavy.'),
        ],
        'flee': [T('It does not chase. It can smell you from anywhere.')],
    },
    'c_hunt_red_vein_stalker': {
        'setting': (
            'Bloodstone given legs and one instruction by somebody in the '
            'Covenant. The instruction was your names.'),
        'ambiance': [
            'The red light inside it pulses faster the closer it gets.',
            'The ground rings under each step.',
        ],
        'opening': [
            T('It does not hurry. It never has to.'),
            P('Break it apart. It is only stone.'),
        ],
        'victory': [
            P('Somebody in the Covenant made that. Somebody who knows our '
              'names.'),
        ],
        'defeat': [
            T('It stands over you until it is sure, and then walks away '
              'toward the capital, reporting.'),
        ],
        'flee': [T('Behind you it keeps walking, at exactly the same pace.')],
    },
    'c_hunt_crimson_inquisitor': {
        'setting': (
            'The Covenant\'s accountant of last resort, sent when a name in '
            'the book has grown too large to be allowed.'),
        'ambiance': [
            'She makes a small note in her book between blows.',
            'Her spectacles catch the light and hide her eyes.',
        ],
        'opening': [
            E('You are worth a great deal. That is going to change.'),
            P('Come and change it.'),
            E('I intend to.'),
        ],
        'victory': [P('Take her book. I want to see who else is in it.')],
        'defeat': [E('Entered. Settled. Filed.')],
        'flee': [E('There is nowhere in Valorheim my book does not reach.')],
    },
    'c_hunt_tithe_knight': {
        'setting': (
            'A tax-collector three hundred years dead, still riding his '
            'round. The Crown that sent him is gone. The debt is not.'),
        'ambiance': [
            'The writ on its breastplate flaps in a wind that is not there.',
            'Its horse stands perfectly still, and has no breath.',
        ],
        'opening': [
            E('Monies owed to the Crown of Valorheim. Payable now.'),
            P('The Crown you collected for is dust.'),
            E('The debt is not.'),
        ],
        'victory': [P('Tear up the writ. Let him rest.')],
        'defeat': [E('Paid in part. The remainder is outstanding.')],
        'flee': [E('Arrears accrue.')],
    },
    'c_hunt_vessel_hound': {
        'setting': (
            'Something off the Shadow Vessel\'s own leash. It is not after '
            'your gold for itself. It is after it for the thing that sent '
            'it.'),
        'ambiance': [
            'The light goes grey wherever the hound walks.',
            'Every coin in your purse is cold.',
        ],
        'opening': [
            T('The shadow at your heel stands up on four legs, and does not '
              'bark.'),
            P('That is not a dog. Whatever it is, do not let it bite.'),
        ],
        'victory': [
            P('If the Vessel is sending hounds, it is awake enough to be '
              'hungry.'),
        ],
        'defeat': [
            T('When you wake, every coin you still have has gone black.'),
        ],
        'flee': [T('It does not run after you. It simply is behind you.')],
    },
    'c_hunt_hoardmother': {
        'setting': (
            'Old enough to remember when Valorheim paid her tribute. She '
            'has heard what you are worth, and she considers it overdue.'),
        'ambiance': [
            'Her shadow covers everything for a hundred yards.',
            'The ground shakes each time she shifts her weight.',
        ],
        'opening': [
            E('Tribute. Four hundred years of it. You will do to begin with.'),
            P('Valorheim does not pay you any more.'),
            E('Then Valorheim will be reminded.'),
        ],
        'victory': [
            P('Nobody is going to believe this. Take a tooth.'),
        ],
        'defeat': [E('Tribute accepted.')],
        'flee': [E('Run. I have been patient for four hundred years.')],
    },
}

ROOM_AMBIANCE = {
    'MH_001_Square': [
        'A bread seller calls out a price, then lowers it without being asked.',
        'Pigeons settle on the fountain\'s rim and will not drink from it.',
        'Two women stop talking as you pass, and start again when you have.',
    ],
    'MH_002_GuardHall': [
        'A guard oils a blade that is already oiled.',
        'The duty roster by the door has names crossed out in a newer ink.',
        'Somebody has left a cold cup of tea on the map table.',
    ],
    'MH_003_Tavern': [
        'The fire spits, and three people look at the door at once.',
        'A tankard is set down very carefully on the bar.',
        'Somebody in the corner is humming a song they stop halfway through.',
    ],
    'MH_004_Temple': [
        'A candle gutters on the altar, and nobody moves to relight it.',
        'Somebody has left a loaf by the step, still warm.',
        'The smell of cold ash comes and goes like breath.',
    ],
    'MH_005_Forge': [
        'The coals tick as they settle.',
        'A horseshoe cools in the trough with a long hiss.',
        'The hammer rests on the anvil, waiting.',
    ],
    'WW_001_Edge': [
        'One of the iron nails in the trunks is weeping rust.',
        'A cart track fades into the leaf mould, and stops.',
        'Wind moves in the canopy, and not down here.',
    ],
    'WW_002_Deep': [
        'A twig snaps somewhere north of you, once.',
        'No birds. Not one.',
        'The light gets no brighter however long you stand here.',
    ],
    'WW_003_HollowGrove': [
        'The ground gives underfoot like a healing crust.',
        'The leaning trees creak without any wind.',
        'The turned earth in the centre is not quite still.',
    ],
    'RF_001_Farm': [
        'A penned cow lows at the treeline, and backs away from it.',
        'The washing on the line moves, stiff as boards.',
        'A kitchen door bangs somewhere, open and shut.',
    ],
    'RF_002_OakGrove': [
        'The scored bark on the largest oak seems deeper in this light.',
        'Acorns drop, one, two, and roll to the centre of the ring.',
        'Children\'s footprints, old ones, dried into the mud.',
    ],
    'VC_001_Plaza': [
        'A crimson banner snaps on its lamp post.',
        'Palace bells toll the hour, and one of them is off-key.',
        'A patrol in red cloaks marches past without looking at anyone.',
    ],
    'VC_002_ThroneRoom': [
        'A courtier laughs at something, too loudly.',
        'The perfume in the air cannot quite cover what is under it.',
        'Somewhere behind a curtain, the King is coughing.',
    ],
    'VC_003_GrandLibrary': [
        'A page turns, very loudly, three floors up.',
        'Dust hangs in the light from the high windows.',
        'Somebody coughs, and is shushed by nobody you can see.',
    ],
    'BM_001_Entrance': [
        'The shift bell rings for a shift that is not coming.',
        'The winch cable creaks, though nobody is at the handle.',
        'Red grit drifts across the spoil heaps.',
    ],
    'BM_002_DeepMine': [
        'The red veins in the walls pulse, very faintly.',
        'The air is warmer every step down.',
        'Far off, a pick strikes stone, on the beat.',
    ],
    'TH_001_Gates': [
        'Somebody has raked the gravel since you last looked.',
        'The briar pattern in the iron gates catches at your sleeve.',
        'A window high in the house is lit, and then is not.',
    ],
    'TH_002_RitualChamber': [
        'The silver in the circles shifts like mercury.',
        'Below the windows, the city burns in silence.',
        'Something under the floor turns over in its sleep.',
    ],
    'MR_001_MereRoad': [
        'Black water laps at the causeway, and there is no wind.',
        'The bell out on the mere rings once.',
        'Fresh footprints in the mud, going south, and none coming back.',
    ],
    'MR_002_ReedBeds': [
        'The reeds hiss and close behind you.',
        'Something moves under the water, big and slow.',
        'A rope trails across the causeway into the shallows.',
    ],
    'MR_003_DrownedMill': [
        'The locked wheel creaks against the weed.',
        'Water drips from the dais and dries on the floor.',
        'The mill smells of wet flour and old rot.',
    ],
    'UA_001_SealedStacks': [
        'Empty shelves, dusted and labelled, going back into the dark.',
        'A corrected label hangs by one pin, swinging.',
        'Your lamp finds nothing to read.',
    ],
    'UA_002_OssuaryStair': [
        'A skull in the wall has turned a little further toward the stair.',
        'Your footsteps echo down the spiral longer than they should.',
        'Somewhere below, pages turn.',
    ],
    'UA_003_FalseSeal': [
        'The painted seal shows its brush strokes when the light moves.',
        'The kneeling mats are worn in two places, as if by knees.',
        'Small sounds on the stair above, coming closer.',
    ],
}

ITEM_LINES = {
    'i_elaras_doll': {'say_on_take': 'Dry. After three days of rain, dry. '
                      'Somebody has been keeping this for her.'},
    'i_bloodstone_geode': {'say_on_destroy': 'Break it. Whatever the city '
                           'has been drinking from, it stops now.'},
    'i_harrow_ledger': {'say_on_take': 'The Brother buried four this week. '
                        'This ledger says six.'},
    'i_decoy_bundle': {'say_on_take': 'Sacking and a stone. She was never '
                       'here. None of this was ever for her.'},
    'i_queens_letter': {'say_on_take': 'Royal wax. Read it. Read it twice.'},
    'i_name_tokens': {'say_on_take': 'Door-tokens. Somebody took these off '
                      'every house. Let us put them where they belong.'},
    'i_drowning_stone': {'say_on_take': 'That mark has been cleaned. '
                         'Somebody wanted it read.'},
    'i_shift_tallies': {'say_on_take': 'Nine. Brask will want to count them '
                        'himself.'},
    'i_gatehouse_door': {'say_on_destroy': 'Stand back from the door! We are '
                         'coming in!'},
    'i_readers_daybook': {'say_on_take': 'Pell Aubery. He had a name. They '
                          'all had names.'},
}

SHOP_LINES = {
    's_001_tallows_cart': {
        'greet': [
            'Capital goods at capital prices! Well. Nearly capital prices.',
            'Have a look. Take your time. I have nothing but time.',
        ],
        'buy': [
            'A fine choice. A fine, fine choice.',
            'Sold! You are the first customer I have had in a week.',
            'Look after it. They do not make many like that out here.',
        ],
        'sell': [
            'Hm. I can move that. Eventually.',
            'I will give you what it is worth to me, which is half. Sorry.',
        ],
        'broke': [
            'Ah. Not quite. Come back when your purse has caught up with '
            'your taste.',
        ],
    },
    's_002_mercys_mule': {
        'greet': [
            'Don\'t touch the mule. Look all you like at the rest.',
            'Different stock every time. Buy it now or never see it again.',
        ],
        'buy': [
            'Sold. No refunds, and don\'t ask me where I got it.',
            'Good eye. Patience here was sorry to see it go.',
        ],
        'sell': [
            'I\'ll take it off your hands. Half, and not a copper more.',
            'Hm. Somebody on the road will want this. Deal.',
        ],
        'broke': [
            'Mercy\'s the name, not charity. Come back with coin.',
        ],
    },
}

WEATHER_REMARKS = {
    'clear': 'Good walking weather. Let us use it.',
    'overcast': 'Grey all day by the look of it.',
    'heat': 'Keep the water skins full. This will get worse.',
    'fog': 'Stay close. I cannot see ten feet in this.',
    'rain': 'We will be wet to the skin by noon.',
    'snow': 'Watch the road. It will be gone under this soon.',
    'ash_fall': 'Cover your mouths. That is not snow.',
    'storm': 'That sky is going to break. We need a roof, or we need to '
             'make one.',
    'blizzard': 'If we are caught out in this, we will not walk out of it. '
                'Shelter. Now.',
    'ash_storm': 'The mines are breathing out. Get under cover, all of us.',
}

REST_LINES = {
    'indoors': [
        'The fire burns down to embers. Somewhere a door creaks and settles.',
        'Rain on the roof, and the roof holds.',
        'Nobody sleeps well, but everybody sleeps.',
    ],
    'outdoors': [
        'The night is cold, and the watch is long.',
        'Something moves at the edge of the firelight, and thinks better '
        'of it.',
        'Stars come out between the clouds, few and far.',
    ],
    'pc': [
        'I will take first watch. Get some sleep.',
        'Wake me if anything comes. Anything.',
        'We have earned this. Sleep.',
    ],
    'wake': [
        'Morning comes grey and cold, and you are all still here.',
        'You wake stiff, but whole.',
        'Somebody has made tea. It is terrible. It is wonderful.',
    ],
}


def bark(line, requires=(), unless=()):
    b = {}
    if requires:
        b['requires'] = list(requires)
    if unless:
        b['unless'] = list(unless)
    b['line'] = line
    return b


# What each of them says as the party walks in, the way things stand. First
# fitting one wins; their greeting if none does. An empty line is silence.
NPC_BARKS = {
    'npc_001_thorne': [
        bark('Millhaven owes you. Sit down before you fall down.',
             requires=['boss_defeated_hollow_avatar']),
        bark('You are wet to the knee. Where have you been?',
             requires=['deception_revealed_mere_road'],
             unless=['thorne_asked_about_mere_road']),
        bark('Anything?', requires=['met_thorne']),
    ],
    'npc_002_marta': [
        bark('Elara! Look who has come.',
             requires=['boss_defeated_hollow_avatar']),
        bark('What is that you are carrying? Let me see.',
             requires=['item_acquired_elaras_doll'], unless=['marta_saw_doll']),
        bark('Any news? No. You would have said.', requires=['met_marta']),
    ],
    'npc_003_aldus': [
        bark('Ashkyr keep you. I mean it rather more than usual.',
             requires=['boss_defeated_hollow_avatar']),
        bark('Back again? The bread is fresh, if you want it.',
             requires=['met_aldus']),
    ],
    'npc_004_harrow': [
        bark('Hammer is quieter these days. Good.',
             requires=['boss_defeated_hollow_avatar']),
        bark('Still here, then.', requires=['met_harrow']),
    ],
    'npc_005_queen_liora': [
        bark('', requires=['boss_defeated_malachai_vex']),
        bark('Back from the library so soon? How diligent.',
             requires=['deception_revealed_under_archive'],
             unless=['liora_confronted']),
        bark('Again? The court will talk.', requires=['met_liora']),
    ],
    'npc_006_malachai': [
        bark('', requires=['boss_defeated_malachai_vex']),
    ],
    'npc_007_wendel': [
        bark('Come to gloat? Go on, then. Everyone else has.',
             requires=['wendel_arrested']),
        bark('', requires=['wendel_fled']),
        bark('You. You came back up the Mere Road.',
             requires=['deception_revealed_mere_road'],
             unless=['wendel_confessed']),
        bark('Back again! What will it be?', requires=['met_wendel']),
    ],
    'npc_008_hale': [
        bark('Quietly, please. Oh. It is you. Thank you.',
             requires=['boss_defeated_malachai_vex']),
        bark('Find her. Please.', requires=['hale_confessed']),
        bark('You found the letter. I can see it on your faces.',
             requires=['deception_revealed_under_archive']),
        bark('Yes?', requires=['met_hale']),
    ],
    'npc_009_jory': [
        bark('The wagon is in! Come and look, come and look!',
             requires=['Unlock_Travel_to_Valorheim']),
        bark('Back for more? I knew you had taste.', requires=['met_jory']),
    ],
    'npc_010_sal': [
        bark('You are on the board, you know. Everybody is reading it.',
             requires=['hunted_first'], unless=['sal_named_the_broker']),
        bark('You again. Anyone would think you were following me.',
             requires=['met_sal']),
    ],
    'npc_011_brask': [
        bark('Board is clean. First time in a month.',
             requires=['brask_given_the_tallies']),
        bark('Well? Anything down there?',
             requires=['brask_asked_after_the_shift']),
    ],
}
