"""The words around every fixed fight, and every creature's voice.

A scene's lines are {"enemy": ...}, {"pc": ...} or {"text": ...}. Enemy lines
go to whichever of them can talk; for the mindless there is nobody, so their
fights are written with "text" where another fight would have "enemy".
{enemy} and {pc} become names at the table.
"""


def E(t):
    return {'enemy': t}


def P(t):
    return {'pc': t}


def T(t):
    return {'text': t}


FIGHTS = {
    'e_whisperwood_thralls': {
        'setting': (
            'A week ago these were Millhaven people: a drover, a farmhand, '
            'somebody who kept bees. Whatever raised them walked them out '
            'into the wood and left them to keep it.'),
        'ambiance': [
            'Leaves come down in the still air, a few at a time.',
            'Somewhere behind you, a third set of footsteps starts, and stops.',
            'The thralls make no sound at all, not even breathing.',
        ],
        'opening': [
            T('The nearer one turns its head toward you the way a sleeper '
              'turns toward a voice. Its boots are still laced.'),
            P('Whoever you were, I am sorry. Stay down this time.'),
        ],
        'first_down': [
            P('That one had a name. Remember it was somebody.'),
        ],
        'victory': [
            T('They lie in the leaves as if they had only sat down to rest.'),
            P('Aldus will want to know. He will want their names.'),
        ],
        'defeat': [
            T('The last thing you see is a pair of good boots, standing '
              'patiently by your head, waiting for instructions.'),
        ],
        'flee': [
            P('Back! Back to the track!'),
            T('They do not follow past the nails. Not yet.'),
        ],
    },
    'e_hollow_grove': {
        'setting': (
            'The heart of it. Elara is somewhere under that turned earth, '
            'kept, and the thing standing over the grave has been waiting '
            'for somebody to come for her.'),
        'ambiance': [
            'The trees lean in a little further, as if to watch.',
            'The turned earth in the centre heaves once, like breath.',
            'Every shadow in the clearing points toward the Avatar, whatever '
            'the light says.',
        ],
        'opening': [
            E('You are not the one I kept her for. Still. You will do to '
              'begin with.'),
            P('She is going home. Stand aside or be put aside.'),
            E('Home. I remember home. It was cold there too.'),
        ],
        'bloodied': [
            P('It can be hurt. Keep on it!'),
        ],
        'first_down': [
            P('One less of its puppets. The strings are next.'),
        ],
        'victory': [
            T('The shadows in the clearing let go of the Avatar all at once, '
              'and there is nothing inside them.'),
            T('Under the turned earth, very faintly, a child is crying.'),
            P('Dig. Carefully. She is alive.'),
        ],
        'defeat': [
            E('Lie down with the others. I will keep you too.'),
        ],
        'flee': [
            E('Run, then. The wood is mine to the nails, and the nails are '
              'coming out.'),
        ],
    },
    'e_ritual_chamber': {
        'setting': (
            'The top of Thornhaven, with the city burning below the windows. '
            'Every circle on the floor is drawn to open something, and '
            'Malachai has been drawing them for years.'),
        'ambiance': [
            'The circles on the floor brighten, dim, brighten, like a pulse.',
            'Below the windows the city burns without a sound reaching up here.',
            'Something under the floor answers every word Malachai says.',
        ],
        'opening': [
            E('Ah. The farmers\' friends. You broke the geode; I felt it. '
              'You have no idea what you let out doing it.'),
            P('Then tell us, Vex. You like talking.'),
            E('I do. I shall talk the whole time I am killing you.'),
        ],
        'bloodied': [
            P('He bleeds like anyone. Keep him off the circles!'),
        ],
        'first_down': [
            E('Acolytes are cheap. Faith is not. Do not flatter yourselves.'),
            P('Your turn next.'),
        ],
        'victory': [
            T('The circles go out one ring at a time, from the outside in, '
              'and the thing under the floor stops answering.'),
            P('It is over. It is actually over.'),
        ],
        'defeat': [
            E('Lie still. You will want to be facing the right way when it '
              'opens.'),
        ],
        'flee': [
            E('Go. Tell them what you saw. Fear makes such a good congregation.'),
        ],
    },
    'e_mere_road_cutthroats': {
        'setting': (
            'The Mere Road was never a road anyone used. Somebody wanted you '
            'on it anyway, and paid these two to be waiting when you came.'),
        'ambiance': [
            'The black water on either side of the causeway does not move.',
            'A bell rings once, far out on the mere, for nobody.',
            'Reeds hiss in a wind you cannot feel.',
        ],
        'opening': [
            E('Wendel said you\'d be along. Said you\'d have a look about you. '
              'You do.'),
            P('Wendel said a lot of things. How much did he get for us?'),
            E('More than you\'ll be worth by teatime.'),
        ],
        'bloodied': [
            E('This isn\'t what we were paid for.'),
        ],
        'first_down': [
            P('Your friend\'s done. You can still walk away.'),
        ],
        'victory': [
            T('Red cord on both their wrists. Covenant money, paid in the '
              'Sparrow.'),
            P('Wendel sent us down here to die. I want to hear him explain it.'),
        ],
        'defeat': [
            E('Take their purses. Leave them for the mere. Wendel owes us a '
              'drink.'),
        ],
        'flee': [
            E('That\'s it, run home! Tell Wendel we said hello!'),
        ],
    },
    'e_reed_beds_drowned': {
        'setting': (
            'The mere keeps what goes into it. These went in with stones on '
            'their ankles, a long time ago, and somebody has asked them back '
            'up.'),
        'ambiance': [
            'Water runs off them in sheets and never stops running.',
            'The reeds close behind you. There is no path now but through.',
            'A stone on a rope drags across the causeway, grinding.',
        ],
        'opening': [
            T('They come up out of the water without a ripple, stones still '
              'swinging from their ankles, and walk toward you on the bottom '
              'of the shallows.'),
            P('Stay on the causeway. Whatever you do, stay out of the water.'),
        ],
        'first_down': [
            P('It went back down. Let it stay there.'),
        ],
        'victory': [
            T('The water takes them back. The ropes go down last.'),
            P('Somebody tied those stones on. Somebody in Millhaven.'),
        ],
        'defeat': [
            T('Cold water closes over your face, and a hand holds you under, '
              'patiently, the way it was once held under itself.'),
        ],
        'flee': [
            P('North! Get back up the causeway!'),
            T('They wade after you a little way, and then stand in the '
              'shallows, watching, water running off them.'),
        ],
    },
    'e_drowned_mill': {
        'setting': (
            'The end of the Mere Road. Nobody ever took Elara down here, and '
            'the people waiting in the mill have known that all along.'),
        'ambiance': [
            'The locked wheel creaks against the weed, trying to turn.',
            'Water drips from the millstone dais onto the dry floor, and dries.',
            'The sacking bundle in the corner is exactly the size of a child.',
        ],
        'opening': [
            E('Didn\'t think you\'d make it past the reeds. Wendel owes me '
              'two silver.'),
            P('Where is the girl?'),
            E('Girl? Never was a girl. Just a bundle of sacking and a story '
              'for fools.'),
        ],
        'bloodied': [
            E('Get it up out of the water! Get it on them!'),
        ],
        'first_down': [
            P('Talk, and you live. Who paid you?'),
        ],
        'victory': [
            T('The last of them goes into the mere and does not come up.'),
            P('A decoy. The whole road was a decoy. She was never here.'),
        ],
        'defeat': [
            E('Wrap them in the sacking. Wendel can have them for his next '
              'story.'),
        ],
        'flee': [
            E('Go on, then! It\'s a long road back, and it\'s filling up '
              'behind you.'),
        ],
    },
    'e_sealed_stacks_warden': {
        'setting': (
            'Under the Grand Library, where the missing books went. The '
            'warden was set to walk these stacks before the library had its '
            'name, and no one has told it to stop.'),
        'ambiance': [
            'The key in the warden\'s back turns, click, click, click.',
            'Empty shelves go back into the dark further than any lamp.',
            'Dust falls from the ceiling at every step the warden takes.',
        ],
        'opening': [
            T('The warden stops mid-patrol. The helm turns toward you with a '
              'grinding of old iron, and the halberd comes down level.'),
            P('Get behind it. The key. Somebody get to the key.'),
        ],
        'bloodied': [
            P('It is slowing. The key is winding down!'),
        ],
        'first_down': [
            P('Down. Pull the key before it gets up.'),
        ],
        'victory': [
            T('The key stops turning. The armour stands a moment longer on '
              'nothing, then comes apart like a dropped tray of cutlery.'),
            P('Hale knew this was down here. He sent us anyway.'),
        ],
        'defeat': [
            T('The warden resumes its patrol, stepping over you on the second '
              'pass as carefully as it steps over the fallen shelves.'),
        ],
        'flee': [
            P('Up! Up the stair!'),
            T('It does not follow. Its patrol does not go that way.'),
        ],
    },
    'e_ossuary_readers': {
        'setting': (
            'The Readers were archivists once, sent down to catalogue the '
            'sealed stacks and kept down here since. They have been fed '
            'just enough.'),
        'ambiance': [
            'Skulls in the wall seem to turn a little further as you pass.',
            'One of the Readers licks ink from its knuckles.',
            'Somewhere below, pages turn in the dark.',
        ],
        'opening': [
            E('Shh. Quiet in the stacks. Quiet.'),
            P('You were people. Archivists. Do you remember?'),
            E('We remember hunger. Hunger is quieter than you.'),
        ],
        'bloodied': [
            P('They feel it. Keep them off the stair!'),
        ],
        'first_down': [
            E('Pell. Pell is gone. More for us.'),
        ],
        'victory': [
            T('The last one folds over itself on the stair with a sound like '
              'a book being closed.'),
            P('Somebody sent them down here and told their families a story.'),
        ],
        'defeat': [
            E('Quiet now. Quiet. We will catalogue you.'),
        ],
        'flee': [
            E('Come back. Come back when you are hungrier.'),
        ],
    },
    'e_false_seal': {
        'setting': (
            'The seal at the bottom of the stair is painted plaster. '
            'Everything about the Under-Archive was a lie to keep you busy, '
            'and these are the people told to keep it.'),
        'ambiance': [
            'Brush strokes show in the painted seal when the light moves.',
            'Up the stair behind you, small sounds, getting closer.',
            'The kneeling mats are still warm.',
        ],
        'opening': [
            E('You were meant to stay below longer. The Queen will be so '
              'disappointed.'),
            P('The Queen can tell us herself.'),
            E('Oh, she will. She always does.'),
        ],
        'bloodied': [
            E('Hold them here! Hold them as long as you can!'),
        ],
        'first_down': [
            P('Holding us here for what? What are we missing up there?'),
        ],
        'victory': [
            T('The satchel by the mats is still open, and there is a letter '
              'in it under a black wax seal.'),
            P('A painted seal. We have been digging in the wrong place.'),
        ],
        'defeat': [
            E('Keep them below. As long as they are willing to stay.'),
        ],
        'flee': [
            E('Run upstairs, then. It is all the same to us. You are late '
              'either way.'),
        ],
    },
    'e_oak_grove_scarecrow': {
        'setting': (
            'Marta\'s scarecrow, walked three fields off its pole into the oak '
            'ring the night Elara went, and standing guard over nothing '
            'since. Whatever took the girl passed close enough to wake it.'),
        'ambiance': [
            'Straw sifts out of the old coat with every movement.',
            'A crow lands on an oak branch, looks at the scarecrow, and leaves '
            'in a hurry.',
            'Elara\'s ribbon flutters at its wrist.',
        ],
        'opening': [
            T('Its arms come down from their crucifix stretch, slowly, and '
              'the turnip head tilts at you, as if you were a crow.'),
            P('It is only trying to keep the birds off. We are the birds.'),
        ],
        'first_down': [
            P('Get the ribbon. Elara will want it back.'),
        ],
        'victory': [
            T('It goes up like a bonfire, all at once, and the coat last.'),
            P('Save the ribbon. Leave the rest to burn.'),
        ],
        'defeat': [
            T('The scarecrow stands over you with its arms out, keeping you '
              'from the crows until morning.'),
        ],
        'flee': [
            T('It does not chase. It goes back to the middle of the ring and '
              'puts its arms out again.'),
        ],
    },
    'e_lost_shift': {
        'setting': (
            'The last shift down the Bloodstone mine: nine men, a token each. '
            'The red grain got into them the way it gets into the rock, and '
            'they have been working the face ever since.'),
        'ambiance': [
            'The picks ring on the beat, the way a shift keeps time.',
            'Red light pulses in the veins of the walls, and in theirs.',
            'Somewhere up the shaft, the shift bell rings for nobody.',
        ],
        'opening': [
            T('Two of them turn from the face together, on the beat, and '
              'bring their picks round.'),
            P('Brask is waiting for you up top. We are taking you home.'),
        ],
        'bloodied': [
            T('Red light leaks from the wound instead of blood.'),
        ],
        'first_down': [
            P('Get its token. Brask counts every one.'),
        ],
        'victory': [
            T('The picks stop. For the first time in a month there is '
              'silence at the face.'),
            P('Nine tokens. Brask will want to count them himself.'),
        ],
        'defeat': [
            T('The shift goes back to the face, and the rhythm picks up where '
              'it left off, as if you had never interrupted.'),
        ],
        'flee': [
            P('Up the shaft! Go!'),
            T('Behind you the picks start again, on the beat.'),
        ],
    },
    'e_thornhaven_watch': {
        'setting': (
            'The gatehouse at Thornhaven holds the families Malachai keeps to '
            'buy obedience: servants\' children, a clerk\'s wife, an '
            'archivist\'s daughter. Two wardens stand between them and you.'),
        'ambiance': [
            'Behind the gatehouse door, somebody is being hushed.',
            'The gravel of the drive has been raked into perfect lines.',
            'Crimson lacquer flakes from the wardens\' plate as they move.',
        ],
        'opening': [
            E('Visiting hours are over. They are always over.'),
            P('Open that door, and you can walk away.'),
            E('We are paid to stand here. We have not been paid to walk.'),
        ],
        'bloodied': [
            E('Hold the door! Whatever happens, hold the door!'),
        ],
        'first_down': [
            P('One down. The door is next.'),
        ],
        'victory': [
            T('Behind the gatehouse door, the hushing stops. Somebody knocks, '
              'very quietly, from the inside.'),
            P('We are here. We are getting you out.'),
        ],
        'defeat': [
            E('Put them in with the others. Vex likes a full house.'),
        ],
        'flee': [
            E('Come back with more friends. The door is not going anywhere.'),
        ],
    },
}


def mute(taunts, hurt, dying):
    return {'speaks': False, 'taunts': taunts, 'hurt': hurt, 'dying': dying}


def says(taunts, hurt, dying):
    return {'taunts': taunts, 'hurt': hurt, 'dying': dying}


VOICES = {
    'c_hollow_thrall': mute(
        ['The thrall leans in close, its jaw working without a sound.'],
        ['The thrall looks down at the wound as if it belonged to someone '
         'else.'],
        ['The thrall sits down in the leaves, carefully, and is still.']),
    'c_hollow_avatar': says(
        ['Cold, isn\'t it? It gets colder.', 'I will keep you. I keep '
         'everything.'],
        ['You... take from me? From ME?'],
        ['Tell him... tell him I kept them... for him...']),
    'c_covenant_acolyte': says(
        ['For the Vessel!', 'You see? You see what faith can do?'],
        ['This was not in the catechism.'],
        ['I was promised... I was promised...']),
    'c_malachai_vex': says(
        ['Did that hurt? It will stop. Everything stops.',
         'Such a small life, and so much of it on the floor.'],
        ['Interesting. Truly. Do that again.'],
        ['You have... only... postponed... it...']),
    'c_covenant_cutthroat': says(
        ['Should have stayed in the Sparrow.', 'Nothing personal. It\'s paid.'],
        ['Not paid enough for this. Not near enough.'],
        ['Tell Wendel... tell him he still owes me...']),
    'c_mere_drowned': mute(
        ['The drowned thing drags you toward the water\'s edge.'],
        ['Black water pours from the wound, and keeps pouring.'],
        ['It goes back into the mere, and the stone on its rope pulls it '
         'down.']),
    'c_archive_warden': mute(
        ['The warden\'s halberd comes round on its patrol, and you are in '
         'the way.'],
        ['Something inside the warden\'s armour grinds and slips a gear.'],
        ['The key in its back stops turning.']),
    'c_ossuary_reader': says(
        ['Quiet. Quiet. Quiet.', 'Mmm. Fresh margins.'],
        ['Hurts. Hurts like paper cuts.'],
        ['Shelve me... shelve me... in the... right... place...']),
    'c_ravencrest_scarecrow': mute(
        ['The scarecrow swings its stuffed arms, and there is something '
         'hard inside the straw.'],
        ['Straw bursts out of the coat, and it does not seem to notice.'],
        ['The scarecrow falls back into its crucifix stretch and topples '
         'over, stiff as a post.']),
    'c_red_veined_miner': mute(
        ['The miner\'s pick comes down on the beat, and you are the face.'],
        ['Red light bleeds from the miner instead of blood.'],
        ['The miner stops mid-swing, and the red goes out of its eyes.']),
    'c_thornhaven_warden': says(
        ['Back from the door.', 'Vex pays for every one of you we drop.'],
        ['Hold. Hold, damn it.'],
        ['Should have... walked away... myself...']),
    'c_hunt_copper_rat': mute(
        ['The rat gets its teeth into your belt pouch and worries it.'],
        ['The rat squeals, and three more squeals answer from the ditch.'],
        ['The rat drops, with a copper penny still in its teeth.']),
    'c_hunt_hedge_footpad': says(
        ['Purses. Now.', 'I did say nobody needed to be brave.'],
        ['This was meant to be easy!'],
        ['My sister-in-law... wants her hatchet back...']),
    'c_hunt_tithe_taker': says(
        ['Tithe paid in part.', 'The Covenant is patient. I am not.'],
        ['You will be charged for that.'],
        ['The account... is not... closed...']),
    'c_hunt_gilt_harpy': says(
        ['Pretty rings. Pretty fingers.', 'Sing with me! Sing!'],
        ['My feathers! You will pay in gold for my feathers!'],
        ['My nest... my shining nest...']),
    'c_hunt_hoard_wight': says(
        ['Mine.', 'Mine. Mine. Mine.'],
        ['You cannot take it with you. I tried.'],
        ['Was it... ever... mine...']),
    'c_hunt_ash_ogre': says(
        ['In the sack you go!', 'Shiny things for the sack!'],
        ['Ow! Ow! Not the sack!'],
        ['Sack... was... nearly... full...']),
    'c_hunt_cinder_drake': mute(
        ['The drake snaps, and sparks shower off its teeth.'],
        ['The drake hisses, and the air around the wound shimmers with heat.'],
        ['The drake\'s fire goes out, and it cools to ash in front of you.']),
    'c_hunt_red_vein_stalker': mute(
        ['The stalker\'s fist comes down like a hammer on an anvil.'],
        ['A crack runs through the stalker, and the red light in it '
         'flickers.'],
        ['The stalker comes apart into ore, and the red goes out of it.']),
    'c_hunt_crimson_inquisitor': says(
        ['Recorded.', 'You are worth less already.'],
        ['That will be entered in the ledger against you.'],
        ['Balance... carried... forward...']),
    'c_hunt_tithe_knight': says(
        ['Monies owed.', 'The Crown will be paid.'],
        ['Obstruction of a collector. Noted.'],
        ['Account... settled...']),
    'c_hunt_vessel_hound': mute(
        ['The hound\'s bite leaves no mark, and the gold at your belt goes '
         'dull.'],
        ['The hound flickers, like a shadow when a lamp gutters.'],
        ['The hound lies down, and there is only a shadow on the ground, '
         'and then not even that.']),
    'c_hunt_hoardmother': says(
        ['Tribute. At last.', 'Kneel, and I may leave you your teeth.'],
        ['You scratched me. Nobody has scratched me in four hundred years.'],
        ['Valorheim... owes me... still...']),
}
