"""Thirty side quests, none of them needed to finish the story.

Each is somebody who wants something done. Asking them sets
`sq_<key>_taken`, which starts the quest; what they want is one or more of
an object to find (which is only there once the job is taken), a word from
somebody else, or a fight won; and going back to them sets `sq_<key>_done`,
which finishes it and pays.

build_quests.py writes the quests and the objects into the campaign data;
build_conversations.py puts the asking, the word and the handing-in into
the conversations of the people involved.

Speech is written «like this», as in build_conversations.py.
"""

T2 = 'Unlock_Travel_to_Valorheim'
T3 = 'Trigger_Sundering_Earthquake_Event'

# Where in each person's conversation the quests are offered and handed in:
# the scenes they come back to between questions.
HUBS = {
    'npc_001_thorne': ['thorne_case', 'thorne_after'],
    'npc_002_marta': ['marta_ask', 'marta_home'],
    'npc_003_aldus': ['aldus_ask', 'aldus_after'],
    'npc_004_harrow': ['harrow_ask', 'harrow_after'],
    'npc_008_hale': ['hale_desk', 'hale_ashamed', 'hale_home'],
    'npc_009_jory': ['jory_talk'],
    'npc_012_aldric': ['aldric_ask', 'aldric_after'],
    'npc_019_rook': ['rook_talk'],
    'npc_020_venn': ['venn_talk'],
}

NAMES = {
    'npc_001_thorne': 'Captain Thorne',
    'npc_002_marta': 'Marta',
    'npc_003_aldus': 'Brother Aldus',
    'npc_004_harrow': 'Harrow',
    'npc_008_hale': 'Master Hale',
    'npc_009_jory': 'Jory',
    'npc_012_aldric': 'King Aldric',
    'npc_019_rook': 'Sergeant Rook',
    'npc_020_venn': 'Quartermaster Venn',
}


def item(room, name, in_room, description, on_take, say):
    return ('item', dict(room=room, name=name, in_room=in_room,
                         description=description, on_take=on_take, say=say))


def word(npc, label, say, reply):
    return ('word', dict(npc=npc, label=label, say=say, reply=reply))


def fight(flag, task):
    return ('fight', dict(flag=flag, task=task))


def quest(key, name, zone, levels, giver, unlock, gp, xp, ask, objectives,
          back, task):
    """[ask] and [back] are (label, said, reply); [task] says what to do."""
    return dict(key=key, name=name, zone=zone, levels=levels, giver=giver,
                unlock=unlock, gp=gp, xp=xp, ask=ask, objectives=objectives,
                back=back, task=task)


T1 = [1, 10]
TT2 = [11, 20]
TT3 = [14, 20]

QUESTS = [
    # --- Millhaven and the valley ------------------------------------------
    quest('bad_water', 'Bad Water', 'z_01_proper', T1, 'npc_003_aldus',
          ['met_aldus', 'cleared_whisperwood_thralls'], 10, 'minor',
          ('Ask if the temple needs anything',
           'Is there anything the temple needs, Brother?',
           '«The well.» He wipes his hands. «It tastes of iron since the '
           'wood went bad. The spring runs under the forge before it gets '
           'here. If something has been dropped in the channel, I would '
           'like it out.»'),
          [item('MH_005_Forge', 'A Sack of Rusted Nails',
                'Down in the spring channel under the quench trough, a sack '
                'of rusted nails has burst open in the water.',
                'Old nails, hundreds of them, the iron bleeding red into '
                'the spring.',
                'You haul it out dripping. The water runs clear behind it '
                'almost at once.',
                'Somebody\'s spares for the nail-trees. They went in the '
                'spring when the sack split.')],
          ('Tell him the well is clear',
           'The spring was full of nails. It is clear now.',
           '«Nails.» He closes his eyes. «Of course it was. Ashkyr keep you; '
           'the bread will taste of bread again.»'),
          'Find what is fouling the temple well'),

    quest('roster', 'The Watch Roster', 'z_01_proper', T1, 'npc_019_rook',
          ['met_rook'], 10, 'minor',
          ('Ask if the Watch needs a hand',
           'Anything we can do for the Watch, Sergeant?',
           '«The roster.» She holds up a sheet with three names struck '
           'through. «The Captain has to sign the new one, and he will not '
           'look at it. Get him to sign it. He will do it for strangers. He '
           'will not do it for me.»'),
          [word('npc_001_thorne', 'Ask him to sign the Watch roster',
                'Sergeant Rook needs the new roster signed.',
                'He looks at the sheet a long time, at the three names, and '
                'signs it without a word. Then he writes a fourth name '
                'underneath: his own.')],
          ('Give her the signed roster',
           'Signed. He put himself on it too.',
           '«Did he.» She folds it very carefully. «Then we are ten.»'),
          'Get the Captain to sign the Watch roster'),

    quest('watch_horn', 'The Lost Horn', 'z_02_whisperwood', T1,
          'npc_001_thorne', ['keyword_quest_unlocked',
                             'cleared_whisperwood_thralls'], 20, 'moderate',
          ('Ask what else was lost in the wood',
           'Did the Watch lose anything else in the wood?',
           '«A horn.» His jaw works. «Corporal Penn carried it. He did not '
           'come back and neither did the horn. It was his father\'s. I '
           'would like his mother to have it.»'),
          [item('WW_002_Deep', 'A Watch Horn',
                'Half buried in the leaves beside the path is a brass horn '
                'on a frayed green cord.',
                'A Watch horn, dented, the tower-and-water mark worn almost '
                'smooth by a thumb.',
                'You shake the leaves out of it. It still sounds, once, '
                'thin and far too loud in the quiet wood.',
                'Corporal Penn\'s. His mother should have this.')],
          ('Give him Penn\'s horn',
           'We found Corporal Penn\'s horn.',
           'He takes it in both hands. For a while he does not say '
           'anything. «I will take it to her myself,» he says. «Thank '
           'you.»'),
          'Find Corporal Penn\'s horn in the deep wood'),

    quest('jorys_crate', 'Jory\'s Crate', 'z_07_mere_road', T1,
          'npc_009_jory', ['met_jory', 'heard_of_the_mere_road'], 15,
          'minor',
          ('Ask what he lost on the road',
           'You came in by the Mere Road once, didn\'t you?',
           '«Once.» He shudders. «A crate went off the back of the cart on '
           'the causeway and I did not stop for it. Best cutlery in the '
           'valley. If it is still there, it is still mine.»'),
          [item('MR_001_MereRoad', 'A Crate Stamped TALLOW',
                'Wedged in the reeds at the edge of the causeway is a crate '
                'stamped TALLOW in red paint.',
                'A pedlar\'s crate, swollen with damp, full of forks.',
                'It comes up out of the mud with a sucking noise and a '
                'rattle of cutlery.',
                'Forks. He nearly died for forks.')],
          ('Give him his crate',
           'Your forks, Jory.',
           '«My forks!» He hugs the crate. «I will sell every one of them '
           'to somebody who deserves them.»'),
          'Find Jory\'s crate on the Mere Road'),

    quest('lost_ewes', 'The Lost Ewes', 'z_02_whisperwood', T1,
          'npc_002_marta', ['met_marta'], 15, 'minor',
          ('Ask about the empty sheepfold',
           'The fold behind the house is empty.',
           '«The ewes went the night Elara did.» She looks at the treeline. '
           '«They will be dead. But the bell-collar was her grandmother\'s, '
           'and I would like it back.»'),
          [item('WW_001_Edge', 'A Bell-Collar',
                'Caught on a thorn at the treeline, a leather collar with a '
                'little copper bell hangs very still.',
                'An old ewe\'s collar, the bell green with age.',
                'You work it free of the thorn. The bell does not ring, and '
                'then, when you have stopped expecting it, it does.',
                'The bell from the Ravencrest fold. Marta will want this.')],
          ('Give her the bell-collar',
           'This was on a thorn at the edge of the wood.',
           'She rings it once, and smiles for the first time since you met '
           'her. «Elara used to follow this home.»'),
          'Find the bell-collar from Marta\'s fold'),

    quest('seal_stone', 'Seal-Stone', 'z_07_mere_road', T1,
          'npc_004_harrow', ['harrow_told_of_the_maul'], 25, 'moderate',
          ('Ask if she could make another maul',
           'Could you make another maul like that one?',
           '«Not without the stone.» She taps the head on the wall. «The '
           'boundary marker at the mill end of the causeway broke in the '
           'flood. Bring me a piece of it, and I will try a fourth.»'),
          [item('MR_003_DrownedMill', 'A Piece of Seal-Stone',
                'Among the rubble by the mill race lies a broken slab of '
                'grey stone, carved with the edge of a seal.',
                'Seal-stone, heavier than it should be, cold on the warmest '
                'day.',
                'It takes two hands to lift. Something in the water below '
                'the race stops moving when you do.',
                'Seal-stone. Harrow will know what to do with it.')],
          ('Give her the seal-stone',
           'A piece of the boundary marker.',
           'She turns it in the forge light. «Good.» She sets it on the '
           'anvil like something asleep. «This one will not crack.»'),
          'Bring Harrow a piece of the broken boundary marker'),

    quest('oak_marks', 'The Marks on the Oak', 'z_03_ravencrest', T1,
          'npc_003_aldus', ['aldus_told_burials'], 15, 'minor',
          ('Ask if he can read the marks on the oak',
           'There are marks scored into the old oak at Ravencrest.',
           '«Marks?» He looks up sharply. «Bring me a rubbing of them, or '
           'the bark itself if it comes away. I would know whose hand that '
           'is.»'),
          [item('RF_002_OakGrove', 'A Strip of Scored Bark',
                'A strip of bark has come away from the largest oak, the '
                'scored marks still clear on it.',
                'Bark scored from inside the ring, facing out, in a hand '
                'that was not looking at what it wrote.',
                'It comes away in one long strip, and the oak does not seem '
                'to mind.',
                'These marks were made from inside the ring.')],
          ('Show him the bark',
           'The marks from the oak.',
           'He reads them twice, moving his lips. «It is the old rite,» he '
           'says, «written backwards. Somebody was teaching it to the '
           'tree.»'),
          'Bring Brother Aldus the marks from the old oak'),

    quest('drovers_road', 'The Drovers\' Road', 'z_02_whisperwood', T1,
          'npc_002_marta', ['met_marta'], 20, 'moderate',
          ('Ask why the drovers stopped coming',
           'Nobody seems to come out to the farm.',
           '«The drovers will not come through the wood with those things '
           'walking it.» She looks at her empty yard. «If the deep wood '
           'were clear, they would come. I could sell the hay.»'),
          [fight('cleared_whisperwood_thralls',
                 'Clear the thralls out of the deep wood')],
          ('Tell her the wood is clear',
           'The deep wood is clear. The drovers can come.',
           '«Then I will send word to the drovers.» She is already reaching '
           'for her shawl. «Thank you. You do not know what it is to have '
           'nobody come.»'),
          'Clear the deep wood so the drovers come back to Ravencrest'),

    quest('tollgate_pass', 'A Pass for the Tollgate', 'z_01_proper', T1,
          'npc_009_jory', ['jory_told_of_the_road'], 10, 'minor',
          ('Ask if he wants a word put in for him',
           'Would a word with the Captain help you?',
           '«A word!» He brightens. «Ask him for a pedlar\'s pass for the '
           'tollgate. Just for me. I will be no trouble on the road. I am '
           'never any trouble anywhere.»'),
          [word('npc_001_thorne', 'Ask him for a pass for Jory',
                'Jory Tallow wants a pass through the tollgate.',
                '«Tallow.» He sighs, and writes something on a slip of '
                'card, and stamps it. «Tell him the road is still shut. This '
                'is for when it is not.»')],
          ('Give Jory the pass',
           'A pass, for when the road opens.',
           '«For when it opens.» He pins it to his hat next to the other '
           'stamp. «That is the nicest thing anybody has given me all '
           'year.»'),
          'Get Captain Thorne to write Jory a tollgate pass'),

    quest('mill_bell', 'The Mill Bell', 'z_07_mere_road', T1,
          'npc_001_thorne', ['deception_revealed_mere_road'], 25,
          'moderate',
          ('Ask about the bell you heard at the mill',
           'We heard a bell ring at the drowned mill.',
           '«The mill bell.» His face goes still. «It rang for the hangings, '
           'when there were hangings. Bring me the clapper and it will '
           'never ring for anybody again.»'),
          [item('MR_003_DrownedMill', 'The Mill Bell\'s Clapper',
                'Hanging from a rotten beam over the race, the old mill '
                'bell has lost its rope. Its clapper lies below, green with '
                'weed.',
                'An iron clapper as long as a forearm, weed-grown and cold.',
                'You pull it out of the weed. Up on the beam the bell '
                'shifts, and is silent.',
                'Nobody will ring this for anyone again.')],
          ('Give him the clapper',
           'The clapper from the mill bell.',
           'He weighs it in his hand, then drops it into the strongbox '
           'under his desk and locks it. «Good,» he says. «Good.»'),
          'Bring Captain Thorne the mill bell\'s clapper'),

    quest('watch_crate', 'The Lost Crate', 'z_07_mere_road', T1,
          'npc_019_rook', ['met_rook', 'heard_of_the_mere_road'], 30,
          'moderate',
          ('Ask what the Watch has lost on the Mere',
           'Has the Watch lost anything out on the Mere?',
           '«A crate of frost vials.» She checks the ledger. «It went in the '
           'reeds when the drowned came up at the patrol. Clear the reeds '
           'and bring it back, and it is yours to keep half of.»'),
          [fight('cleared_reed_beds', 'Clear the drowned out of the reeds'),
           item('MR_002_ReedBeds', 'A Watch Stores Crate',
                'Half sunk in the reeds is a straw-packed crate stencilled '
                'WATCH STORES, its lid still nailed down.',
                'A crate of frost vials, every one of them unbroken, which '
                'is a small miracle.',
                'You lift it out very carefully. Frost blooms on the wood '
                'where your hands were.',
                'Watch stores, still nailed shut. Rook will be pleased.')],
          ('Give her the crate',
           'Your crate of frost vials, Sergeant.',
           '«Unbroken!» She signs it back in, and counts out coin for '
           'half. «You are wasted on adventure.»'),
          'Bring the Watch crate back from the Reed Beds'),

    quest('altar_coal', 'Altar-Coal', 'z_01_proper', T1, 'npc_004_harrow',
          ['met_harrow', 'cleared_whisperwood_thralls'], 10, 'minor',
          ('Ask what she needs for the forge',
           'Is there anything the forge needs?',
           '«Coal from the temple altar.» She does not look embarrassed. '
           '«The old smiths quenched against the dark in blessed fire. '
           'Ask the Brother. He will give it to you before he gives it to '
           'me.»'),
          [word('npc_003_aldus', 'Ask him for coal from the altar fire',
                'Harrow asks for coal from the altar fire.',
                '«Harrow asks?» He smiles, and scoops a coal into a little '
                'iron box. «Tell her Ashkyr does not mind where his fire '
                'goes, as long as it goes somewhere useful.»')],
          ('Give her the altar-coal',
           'Coal from the temple altar.',
           'She tips it into the forge. The fire goes white for a moment, '
           'and every blade on the rack rings very faintly. «Huh,» she '
           'says.'),
          'Fetch Harrow coal from the temple altar'),

    # --- Valorheim -------------------------------------------------------------
    quest('crown_picks', 'The Crown\'s Picks', 'z_05_bloodstone_mines', TT2,
          'npc_020_venn', ['met_venn'], 300, 'moderate',
          ('Ask what the Crown is missing',
           'Is the Crown short of anything besides coin?',
           '«Forty picks.» She chalks it on a slate. «Lent to the Bloodstone '
           'mine and never returned. The mine head will have the loan '
           'ledger. Bring it, and I will have them back.»'),
          [item('BM_001_Entrance', 'The Mine\'s Loan Ledger',
                'On a nail by the tally board hangs a loan ledger, its '
                'cover stamped with the Crown.',
                'Forty picks lent, forty picks signed for, and nothing '
                'written in the column for their return.',
                'You take it down from the nail. Nobody stops you.',
                'Forty picks. Venn will want every one.')],
          ('Give her the loan ledger',
           'The mine\'s loan ledger.',
           '«Forty.» She runs a finger down the column. «And not one '
           'returned. The Crown will be writing a stern letter.»'),
          'Find the mine\'s loan ledger for Quartermaster Venn'),

    quest('requisitions', 'Forged Requisitions', 'z_04_palace_district',
          TT2, 'npc_020_venn', ['met_venn'], 250, 'minor',
          ('Ask about the requisitions on her slate',
           'Those requisitions you rubbed out. Forged?',
           '«Signed by a clerk who does not exist.» She lowers her voice. '
           '«The Keeper at the library knows every clerk\'s hand in the '
           'city. Ask him whose this is.»'),
          [word('npc_008_hale', 'Ask him whose hand signs the forged '
                'requisitions', 'Whose hand is this, on the Crown '
                'requisitions?',
                'He looks at it for a long moment. «Nobody\'s,» he says. «It '
                'is a copy of the Queen\'s secretary\'s hand. A good copy. '
                'Made by somebody who has seen a great deal of it.»')],
          ('Tell her whose hand it is',
           'It copies the Queen\'s secretary\'s hand.',
           'She sets down the chalk. «Then I will stop filling them,» she '
           'says, «and I will start keeping them.»'),
          'Find out who signs the forged requisitions'),

    quest('cut_pages', 'The Cut Pages', 'z_08_under_archive', TT2,
          'npc_008_hale', ['met_hale', 'heard_of_the_under_archive'], 400,
          'moderate',
          ('Ask about the books with pages cut out',
           'Somebody has been cutting pages out of the seal books.',
           '«I know.» He does not meet your eye. «They went down. Into the '
           'stacks. If they are still there, I would have them back, '
           'whatever is on them.»'),
          [item('UA_001_SealedStacks', 'A Bundle of Cut Pages',
                'Tucked behind a shelf in the sealed stacks is a bundle of '
                'pages, cut cleanly from their books and tied with red '
                'thread.',
                'Every page shows the same seal, drawn from a different '
                'side.',
                'The thread is the Covenant\'s red. You do not untie it.',
                'Every one of these is a seal, drawn from the wrong side.')],
          ('Give him the cut pages',
           'The pages from the seal books.',
           'He unties the thread with shaking fingers and lays the pages '
           'out. «Every seal in the valley,» he says. «Every one.»'),
          'Bring the cut pages back up out of the Under-Archive'),

    quest('prayer_beads', 'The Reader\'s Beads', 'z_08_under_archive', TT2,
          'npc_003_aldus', [T2, 'heard_of_the_under_archive'], 350,
          'moderate',
          ('Ask what is buried under the capital library',
           'There are dead under the Grand Library, Brother.',
           '«The readers.» He nods slowly. «Ashkyr\'s first scribes. They '
           'were buried with their beads. If one string came back up, I '
           'could say the rite over it here, for all of them.»'),
          [item('UA_002_OssuaryStair', 'A String of Prayer-Beads',
                'On a step of the ossuary stair, a string of wooden '
                'prayer-beads lies coiled as if somebody had just put it '
                'down.',
                'Ashkyr\'s beads, worn smooth by a reader\'s fingers, every '
                'bead a small carved sheaf.',
                'You pick it up, and somewhere below, something that was '
                'climbing the stair stops.',
                'A reader\'s beads. Aldus can say the rite over these.')],
          ('Give him the prayer-beads',
           'A reader\'s beads, from the ossuary stair.',
           'He says the rite there and then, kneeling, the beads wound '
           'round his hand. When he stands, he looks ten years younger.'),
          'Bring Brother Aldus a string of the readers\' beads'),

    quest('canary', 'The Canary Cage', 'z_05_bloodstone_mines', TT2,
          'npc_009_jory', [T2, 'met_jory'], 300, 'moderate',
          ('Ask about his cousin in the mines',
           'You mentioned a cousin in the capital.',
           '«Pell. In the Bloodstone mine.» He fidgets. «He keeps the '
           'canary for the deep shaft. If the canary is still alive, so is '
           'Pell. Would you look?»'),
          [item('BM_002_DeepMine', 'A Canary Cage',
                'Hung from a pit-prop in the deep workings is a little '
                'brass cage. The canary in it is very much alive, and very '
                'angry.',
                'A miner\'s canary in a brass cage, singing furiously.',
                'You unhook the cage. The canary bites you through the '
                'bars.',
                'Alive. So, probably, is Pell.')],
          ('Give him the canary',
           'Pell\'s canary. Alive and furious.',
           '«Then Pell is alive!» Jory takes the cage and the canary bites '
           'him too. «Family,» he says, beaming.'),
          'Find out if Jory\'s cousin\'s canary still sings'),

    quest('crimson_banner', 'The Crimson Banner', 'z_06_thornhaven', TT2,
          'npc_001_thorne', [T2, 'met_thorne'], 600, 'moderate',
          ('Ask what he would have from Thornhaven',
           'Is there anything you want from Thornhaven, Captain?',
           '«Their banner.» He does not smile. «The Covenant flies it over '
           'the gate like they won something. Bring it down, and bring it '
           'here, and I will burn it in the square.»'),
          [fight('thornhaven_watch_broken', 'Break the watch on Thornhaven\'s '
                 'gate'),
           item('TH_001_Gates', 'The Crimson Banner',
                'Above the broken gate, the Covenant\'s crimson banner '
                'still hangs, ragged at the edges.',
                'Crimson silk, knotted the Covenant\'s way at every corner.',
                'You cut it down. It falls slowly, like something much '
                'heavier than silk.',
                'Thorne wants to watch this burn.')],
          ('Give him the banner',
           'The Covenant\'s banner, from Thornhaven\'s gate.',
           'He carries it out to the square himself, and the whole town '
           'watches it burn. Nobody cheers. Everybody stays until it is '
           'ash.'),
          'Bring Captain Thorne the banner from Thornhaven\'s gate'),

    quest('brazier_ash', 'Cold Ash', 'z_06_thornhaven', TT2,
          'npc_003_aldus', ['boss_defeated_malachai_vex'], 500, 'moderate',
          ('Ask what should be done with the ritual chamber',
           'Malachai is dead. What happens to the chamber?',
           '«Bring me ash from the brazier.» He does not hesitate. «Whoever '
           'burned in it deserves a grave, even if all that is left of them '
           'is ash.»'),
          [item('TH_002_RitualChamber', 'A Jar of Cold Ash',
                'The great brazier at the chamber\'s heart has gone cold. A '
                'clay jar stands beside it, as if somebody had meant to '
                'gather the ash and never did.',
                'Grey ash in a clay jar, finer than any fire should leave.',
                'You fill the jar and stopper it. The chamber is quieter '
                'when you have.',
                'Whoever this was, they are going home.')],
          ('Give him the ash',
           'Ash from the ritual chamber\'s brazier.',
           'He buries it himself, in the temple yard, under a stone with '
           'no name on it. «Ashkyr knows who they were,» he says.'),
          'Bring Brother Aldus the ash from the ritual chamber'),

    quest('warden_keystone', 'The Warden\'s Keystone',
          'z_08_under_archive', TT2, 'npc_008_hale',
          ['met_hale', 'heard_of_the_under_archive'], 600, 'moderate',
          ('Ask about the thing that guards the stacks',
           'Something guards the sealed stacks.',
           '«The Archive Warden.» He swallows. «Built to keep the stacks, '
           'and now it keeps them from us. There is a keystone in its '
           'chest. Stop it, and bring me the stone.»'),
          [fight('cleared_sealed_stacks', 'Stop the Archive Warden'),
           item('UA_001_SealedStacks', 'The Warden\'s Keystone',
                'Among the Archive Warden\'s broken plates lies a keystone '
                'of white marble, still faintly warm.',
                'A marble keystone carved with the library\'s mark, warm '
                'as a hand.',
                'You lift it from the wreck, and every lamp in the stacks '
                'goes out and comes on again.',
                'The keystone. Hale wanted this.')],
          ('Give him the keystone',
           'The Warden\'s keystone.',
           'He sets it on his desk and lays both hands on it. «Then the '
           'stacks are ours again,» he says. «Whatever is left in them.»'),
          'Bring Master Hale the Archive Warden\'s keystone'),

    quest('crown_debt', 'The Crown\'s Debt', 'z_04_palace_district', TT2,
          'npc_020_venn', ['met_venn'], 250, 'minor',
          ('Ask what the Crown owes',
           'Does the Crown owe anybody besides you?',
           '«Millhaven.» She taps a slate. «The Watch there has not been '
           'paid since spring. Ask their Captain the sum. I will see it '
           'paid, if I have to sell every sword on this table.»'),
          [word('npc_001_thorne', 'Ask him what the Crown owes the Watch',
                'What does the Crown owe the Millhaven Watch?',
                '«Since spring?» He laughs without much in it. «Two hundred '
                'and twelve gold. Ten men. Nine, now. Ten again,» he '
                'corrects himself.')],
          ('Tell her the sum',
           'Two hundred and twelve gold, since spring.',
           '«Then it will be two hundred and twelve gold by the next '
           'post.» She writes it on the slate and underlines it twice.'),
          'Find out what the Crown owes the Millhaven Watch'),

    quest('red_ore', 'Red-Veined Ore', 'z_05_bloodstone_mines', TT2,
          'npc_004_harrow', [T2, 'met_harrow'], 400, 'moderate',
          ('Ask what she knows of bloodstone',
           'Have you ever worked bloodstone?',
           '«No, and I would like to know why nobody will.» She sets down '
           'the hammer. «Bring me a lump of the red ore from the deep '
           'workings. I will find out what it does in a fire.»'),
          [item('BM_002_DeepMine', 'A Lump of Red-Veined Ore',
                'In a cart abandoned in the deep workings, the ore is '
                'veined with red that seems to move when you look away.',
                'Bloodstone ore. The veins are warm, and very slightly '
                'wet.',
                'You take a lump. It is warmer than your hand, and stays '
                'that way.',
                'Harrow wants to know what this does in a fire. So do I.')],
          ('Give her the ore',
           'A lump of bloodstone ore.',
           'She puts it in the fire and watches. The red veins crawl '
           'toward the edge of the coal, away from the heat. She takes it '
           'out with the tongs and drops it in the quench. «No,» she says. '
           '«Nobody is working that.»'),
          'Bring Harrow a lump of bloodstone ore'),

    # --- the Sundering ----------------------------------------------------------
    quest('rift_patrol', 'The Armoury Patrol', 'z_09_the_sundering', TT3,
          'npc_020_venn', [T3, 'met_venn'], 2000, 'moderate',
          ('Ask about the patrol she sent into the Rift',
           'Did the Crown send anybody into the Rift?',
           '«Six from the armoury, the night it opened.» Her hands are '
           'still. «I signed their kit out myself. If you go down, bring '
           'back a tag. Any tag.»'),
          [fight('cleared_the_rift', 'Clear the mouth of the Rift'),
           item('SD_001_Rift', 'An Armoury Tag',
                'On the lip of the Rift, a brass armoury tag hangs from a '
                'broken spear-haft driven into the rock.',
                'A Crown armoury tag, number forty-one, on a cut thong.',
                'You work it free of the haft. The spear stays where it '
                'is, driven in to the socket.',
                'Number forty-one. Venn will know whose it was.')],
          ('Give her the tag',
           'Tag forty-one, from the lip of the Rift.',
           '«Forty-one. Corporal Asha Venn.» She closes her hand on it. '
           '«My niece,» she says, when she can.'),
          'Bring back a tag from the armoury patrol in the Rift'),

    quest('house_deeds', 'The Deeds of the Buried Street', 'z_09_the_sundering',
          TT3, 'npc_008_hale', [T3, 'met_hale'], 1500, 'minor',
          ('Ask what was lost in the Buried Street',
           'What was on the street the earthquake swallowed?',
           '«The Registry of Deeds.» He is already writing a list. «Every '
           'house in the lower city. Without the deeds, the Crown can say '
           'the land is the Crown\'s. Find the deed-box.»'),
          [item('SD_002_BuriedStreet', 'The Registry Deed-Box',
                'Under a fallen lintel carved REGISTRY lies an iron-bound '
                'deed-box, its lock still shut.',
                'Every deed in the lower city, dry inside the box.',
                'You drag it out from under the lintel. The street groans, '
                'and settles.',
                'Every house in the lower city. Hale will want this.')],
          ('Give him the deed-box',
           'The Registry\'s deed-box.',
           '«Every one.» He opens it and lifts out the first deed as if it '
           'might break. «Nobody is taking these houses now.»'),
          'Find the Registry\'s deed-box in the Buried Street'),

    quest('silenced_bell', 'The Silenced Bell', 'z_09_the_sundering', TT3,
          'npc_003_aldus', [T3, 'met_aldus'], 2500, 'moderate',
          ('Ask about the temple under the city',
           'There is a temple to the Unmaking under the capital.',
           '«It was Ashkyr\'s once.» His voice is very quiet. «They took '
           'its bell and silenced it. Bring it back to the light, and I '
           'will hang it here.»'),
          [fight('cleared_unmaking_temple', 'Cleanse the temple of '
                 'Unmaking'),
           item('SD_003_UnmakingTemple', 'Ashkyr\'s Silenced Bell',
                'Stripped of its clapper and wound in black cloth, a small '
                'temple bell lies on the altar of the Unmaking.',
                'A bronze bell cast with Ashkyr\'s sheaf, wound in black.',
                'You unwind the cloth. The bell has no clapper, and rings '
                'anyway, once.',
                'Aldus will hang this where it belongs.')],
          ('Give him the bell',
           'Ashkyr\'s bell, from under the capital.',
           'He hangs it over the temple door with Harrow\'s help. It has '
           'no clapper. It rings every morning at dawn anyway.'),
          'Bring Ashkyr\'s bell up from the temple of the Unmaking'),

    quest('signet', 'The King\'s Signet', 'z_09_the_sundering', TT3,
          'npc_012_aldric', [T3, 'met_aldric'], 2000, 'moderate',
          ('Ask what he lost when the city fell',
           'Did you lose anything when the city fell, Majesty?',
           '«My signet.» He looks at his bare hand. «I threw it down at the '
           'guard post, the night I was not myself. If it is still there, '
           'I would wear it again, and mean it this time.»'),
          [item('SD_004_GuardPost', 'The King\'s Signet',
                'Among the rubble of the fallen guard post, a gold signet '
                'ring glints in the dust.',
                'The royal signet, heavy, cut with the crowned tower.',
                'You pick it out of the dust. It is warm, as if somebody had '
                'only just taken it off.',
                'The King\'s ring. He wants to mean it this time.')],
          ('Give him the signet',
           'Your signet, Majesty.',
           'He puts it on slowly. «I will try to deserve it,» he says, to '
           'nobody in particular.'),
          'Find King Aldric\'s signet at the fallen guard post'),

    quest('name_stone', 'A Name-Stone', 'z_10_quiet_court', TT3,
          'npc_012_aldric', [T3, 'met_aldric'], 3000, 'moderate',
          ('Ask about the Causeway of Names',
           'What is the Causeway of Names, Majesty?',
           '«Every king of Valorheim, written in stone, and then '
           'forgotten.» He frowns. «Bring me one of the stones. And ask the '
           'Brother at Millhaven how a name is given back. He will know the '
           'rite.»'),
          [item('QK_001_CausewayOfNames', 'A Name-Stone',
                'One of the causeway\'s name-stones has worked loose. The '
                'name cut in it has been scratched out.',
                'A grey stone with a scratched-out name, heavy with the '
                'weight of not being remembered.',
                'You lift it. For a moment you almost know the name.',
                'A king nobody remembers. Aldric wants him back.'),
           word('npc_003_aldus', 'Ask him how a name is given back',
                'How is a name given back, Brother?',
                '«You say it,» he says simply. «Out loud, where the dead '
                'can hear. If you do not know it, you say that you would '
                'have known it, and Ashkyr fills in the rest.»')],
          ('Give him the name-stone, and the rite',
           'A name-stone from the causeway, and the rite to give it back.',
           'He holds the stone and says, out loud, that he would have '
           'known the name. The scratches in the stone seem, for a moment, '
           'shallower.'),
          'Bring King Aldric a name-stone and the rite of naming'),

    quest('iron_crown', 'The Iron Crown', 'z_10_quiet_court', TT3,
          'npc_020_venn', [T3, 'met_venn'], 3500, 'moderate',
          ('Ask what the Crown wants from the Quiet Court',
           'Is there anything in the Quiet Court the Crown would want?',
           '«The iron crowns the courtiers wear.» She has gone pale. «They '
           'were made in our armoury, eight hundred years ago. I want one '
           'back on the inventory, so I can strike it off.»'),
          [fight('cleared_quiet_court', 'Silence the Quiet Court'),
           item('QK_002_QuietCourt', 'A Courtier\'s Iron Crown',
                'Fallen beside an empty throne-chair, a plain crown of '
                'black iron lies on the flagstones.',
                'Black iron, stamped inside with the armoury\'s mark and a '
                'date eight hundred years gone.',
                'You lift it. It is very cold, and fits your hand like it '
                'wants to fit your head.',
                'Armoury work. Venn wants to strike it off the books.')],
          ('Give her the iron crown',
           'A courtier\'s crown, from the Quiet Court.',
           'She checks the stamp against a ledger older than she is, then '
           'draws a single line through an entry. «Returned,» she says. '
           '«At last.»'),
          'Bring Quartermaster Venn a courtier\'s iron crown'),

    quest('seal_water', 'Water from the Well of Seals', 'z_10_quiet_court',
          TT3, 'npc_003_aldus', [T3, 'met_aldus'], 2500, 'minor',
          ('Ask what the temple needs for the end',
           'Is there anything the temple needs, before the end?',
           '«Water from the Well of Seals.» He holds out an empty flask. '
           '«Every seal in the valley was blessed with it. If there is any '
           'left, we can bless new ones.»'),
          [item('QK_003_WellOfSeals', 'A Flask of Seal-Water',
                'At the lip of the well, a stone cup still holds a little '
                'water, clear as air.',
                'Water from the Well of Seals, perfectly still even when '
                'the flask is shaken.',
                'You fill the flask. The water in it does not slosh.',
                'Enough to bless one seal. Maybe two.')],
          ('Give him the seal-water',
           'Water from the Well of Seals.',
           '«Enough for one seal.» He holds the flask to the light. «Then '
           'we will make one, and set it where it is needed most.»'),
          'Bring Brother Aldus water from the Well of Seals'),

    quest('true_history', 'The True History', 'z_10_quiet_court', TT3,
          'npc_009_jory', [T3, 'met_jory'], 3000, 'moderate',
          ('Ask what a pedlar wants at the end of the world',
           'What does a pedlar want at the end of the world?',
           '«A story to sell after it.» He grins. «The true one. Get the '
           'Keeper at the library to tell you how the seals were made, and '
           'go and see the causeway for yourself, and I will sell it in '
           'every market from here to the sea.»'),
          [word('npc_008_hale', 'Ask him for the true history of the seals',
                'How were the seals really made, Master Hale?',
                '«By people.» He takes off his spectacles. «Not by kings or '
                'gods. A smith, a priest, a clerk and a soldier, who were '
                'too stubborn to let the world end. Nobody wrote their '
                'names down. That is how they wanted it.»'),
           fight('cleared_causeway', 'Cross the Causeway of Names')],
          ('Tell Jory the true history',
           'A smith, a priest, a clerk and a soldier. That is the story.',
           '«A smith, a priest, a clerk and a soldier.» He is quiet for a '
           'long moment. «I am not going to sell that,» he says. «I am '
           'going to tell it.»'),
          'Bring Jory the true history of the seals'),
]

assert len(QUESTS) == 30, len(QUESTS)


def flags(q):
    """The quest's start flag, each objective's condition, and the done
    flag, in order."""
    key = q['key']
    conditions = []
    for i, (kind, data) in enumerate(q['objectives']):
        if kind == 'fight':
            conditions.append(data['flag'])
        else:
            conditions.append(f'sq_{key}_{kind}{i + 1}')
    return f'sq_{key}_taken', conditions, f'sq_{key}_done'


def item_id(q, index):
    return f'i_sq_{q["key"]}_{index + 1}'


def task_for(q, index):
    kind, data = q['objectives'][index]
    if kind == 'fight':
        return data['task']
    if kind == 'word':
        return f'Ask {NAMES[data["npc"]]}'
    return f'Find {data["name"][0].lower()}{data["name"][1:]}'
