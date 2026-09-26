"""Writes conversations.json for Campaign I: Shattered Seals.

Speech is written «like this» here and becomes straight double quotes in the
output, so the prose can be read without a thicket of escapes.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import house_json as h  # noqa: E402

os.chdir(os.path.dirname(HERE))


# --- builders ----------------------------------------------------------------

def out(text, go=None, sets=(), clears=()):
    o = {'text': text}
    if go:
        o['goTo'] = go
    if sets:
        o['setFlags'] = list(sets)
    if clears:
        o['clearFlags'] = list(clears)
    return o


def _gate(requires, unless):
    g = {}
    if requires:
        g['flags'] = list(requires)
    if unless:
        g['notFlags'] = list(unless)
    return g


def opt(id, label, text, go=None, say=None, sets=(), clears=(),
        requires=(), unless=()):
    """An option with no roll. With [say] it is speech; without, an action."""
    o = {'id': id, 'label': label}
    if say:
        o['say'] = say
    o['outcome'] = out(text, go, sets, clears)
    g = _gate(requires, unless)
    if g:
        o['requires'] = g
    return o


def roll(id, label, say, stat, dc, requires=(), unless=(), **degrees):
    """An option decided by a check. Degrees: crit, success, failure, fumble."""
    names = {'crit': 'criticalSuccess', 'success': 'success',
             'failure': 'failure', 'fumble': 'criticalFailure'}
    o = {'id': id, 'label': label, 'say': say,
         'check': {'stat': stat, 'dc': dc},
         'outcomes': {names[k]: v for k, v in degrees.items()}}
    g = _gate(requires, unless)
    if g:
        o['requires'] = g
    return o


def scene(id, title, body, *options, ending=False):
    s = {'id': id, 'title': title, 'body': body}
    if options:
        s['options'] = list(options)
    if ending:
        s['isEnding'] = True
    return s


def entry(scene_id, requires=(), unless=()):
    e = {'scene': scene_id}
    if requires:
        e['requires'] = list(requires)
    if unless:
        e['unless'] = list(unless)
    return e


def conversation(npc, entries, scenes):
    return {'npc': npc, 'entries': entries, 'scenes': scenes}


def quoted(value):
    if isinstance(value, str):
        return value.replace('«', '"').replace('»', '"')
    if isinstance(value, list):
        return [quoted(v) for v in value]
    if isinstance(value, dict):
        return {k: quoted(v) for k, v in value.items()}
    return value


# --- Captain Thorne Ironhelm -------------------------------------------------

T = 'Captain Thorne Ironhelm'


def _thorne_stone(back):
    return [
        opt('show_stone', 'Show him the drowning-stone',
            '«That\'s one of ours.» He turns it to the light, and his thumb '
            'finds the mark without looking for it: a tower over three lines '
            'of water. «The Watch\'s mark. They\'re drowning-stones, from '
            'when Millhaven did its hanging in the mere, a hundred years back. '
            'There\'s a cellar full of them under this hall, and nobody\'s '
            'opened it since my grandfather.» He goes to look at the cellar '
            'door. He looks at the lock for a long time, and comes back '
            'without saying anything, and then says: «Somebody\'s been in.»',
            go=back,
            say='This came up out of the mere, tied to somebody\'s ankle.',
            sets=['thorne_knew_the_stone'],
            requires=['item_acquired_drowning_stone'],
            unless=['thorne_knew_the_stone']),
    ]
thorne = conversation('npc_001_thorne', [
    entry('thorne_after', requires=['boss_defeated_hollow_avatar']),
    entry('thorne_mere_road', requires=['deception_revealed_mere_road'],
          unless=['thorne_asked_about_mere_road']),
    entry('thorne_again', requires=['met_thorne']),
    entry('thorne_open'),
], [
    scene('thorne_open', T,
          'Captain Thorne looks up from a map of the valley pinned flat with '
          'daggers. «Well met. If you\'re seeking work, you\'ve come at the '
          'right time. Dark times are falling on Millhaven.»',
          opt('ask_quest', 'Ask what has happened',
              '«The roads are unsafe. Caravans vanish, and young Elara Whitmore '
              'was taken three days ago.» He taps the map west of the town, '
              'where somebody has shaded the Whisperwood in charcoal and then, '
              'it seems, thought better of it and tried to rub it out.',
              go='thorne_case', say='What kind of dark times?',
              sets=['met_thorne', 'keyword_quest_unlocked']),
          opt('leave', 'Leave',
              '«Don\'t go far,» he says, not looking up.',
              go='thorne_bye', sets=['met_thorne'])),

    scene('thorne_case', T,
          '«Her mother\'s Marta, out at Ravencrest Farm, north past the '
          'treeline. She\'s said everything she\'s going to say to me twice.» '
          'He rubs his eyes. «Council\'s put up fifty gold. I know how that '
          'sounds.»',
          opt('ask_elara', 'Ask about the girl',
              '«Nine years old. Plays in the old oak ring behind the farm, '
              'which every child in the valley has done and every mother has '
              'told them not to. Went out on Tuesday with her doll and didn\'t '
              'come back for supper.» He says it the way people say things '
              'they have said a great many times this week.',
              go='thorne_case', say='Tell me about Elara.',
              sets=['thorne_told_elara'], unless=['thorne_told_elara']),
          opt('ask_creatures', 'Ask about the creatures',
              '«Farmers speak of shadows moving. Animals found dead, or '
              'worse... corrupted.» He looks at the door as if he expects '
              'someone to be listening at it. «Brother Aldus believes it\'s '
              'dark magic. He\'s buried four people this week, so I\'m '
              'inclined to let him believe what he likes.»',
              go='thorne_case', say="What's been getting at the livestock?",
              sets=['thorne_told_creatures'],
              unless=['thorne_told_creatures']),
          roll('haggle', '[Diplomacy] Ask for more money',
               'Fifty gold is what you pay to find a lost goat, Captain.',
               'diplomacy', 16, unless=['thorne_haggled'],
               crit=out('He looks at you for a long moment. «A hundred,» he '
                        'says finally. «If you bring her back breathing, a '
                        'hundred, and I\'ll find the rest somewhere.»',
                        go='thorne_case',
                        sets=['thorne_haggled', 'thorne_reward_doubled']),
               success=out('He looks at you, then at the map, then back. '
                           '«Seventy-five. The rest comes out of my own '
                           'purse, and if the council asks, you found her '
                           'for fifty.»',
                           go='thorne_case',
                           sets=['thorne_haggled', 'thorne_reward_raised']),
               failure=out('«It\'s what the council gave,» he says flatly. '
                           '«You can take it or leave it, and I\'ve men out '
                           'on those roads doing it for nothing.»',
                           go='thorne_case', sets=['thorne_haggled']),
               fumble=out('His face shuts like a door. «Get out of my hall.» '
                          'He means it for about a minute, and then he '
                          'doesn\'t, but the offer does not improve.',
                          go='thorne_case',
                          sets=['thorne_haggled', 'thorne_offended'])),
          *_thorne_stone('thorne_case'),
          opt('ask_who', 'Ask who else might know something',
              '«Marta, first. Brother Aldus at the temple — he\'s been burying '
              'what we find, so he\'s seen more of it than I have. Harrow at '
              'the forge, if you can get her to put the hammer down.» He '
              'almost smiles. «And Wendel Pike at the Sparrow hears '
              'everything, though I\'d not swear he understands half of it.»',
              go='thorne_case', say='Who else should we talk to?',
              sets=['thorne_told_who'], unless=['thorne_told_who']),
          opt('leave', 'Leave',
              '«See that you do,» he says. «And come back and tell me, either '
              'way. I\'d rather know.»',
              go='thorne_bye', say="We'll find her.")),

    scene('thorne_again', T,
          'Thorne glances up from the map. «Anything?»',
          opt('talk', 'Go over it again', '«Go on, then.»',
              go='thorne_case', say='Not yet. Tell me again how it stands.'),
          opt('leave', 'Leave', 'He nods and goes back to the map.',
              go='thorne_bye', say='Not yet.')),

    scene('thorne_mere_road', T,
          'Thorne is on his feet before you reach the desk. «You went down '
          'the Mere Road.» It isn\'t a question; you are wet to the knee. «On '
          'whose word?»',
          opt('name_confessed', 'Tell him Wendel has confessed',
              'Thorne says nothing at all for a while. Then he takes his sword '
              'belt down off its peg. «I\'ve drunk in that man\'s house for '
              'twenty years.» He goes out past you without another word, and '
              'by evening the Drowned Sparrow is shut, with a guard on the '
              'door.',
              go='thorne_gone',
              say="Wendel Pike's. He's admitted it — the Covenant pays him "
                  'to send people south.',
              sets=['thorne_asked_about_mere_road', 'wendel_reported',
                    'wendel_arrested'],
              requires=['wendel_confessed']),
          opt('name_suspected', 'Tell him it was Wendel',
              '«Wendel.» Thorne sits back down, slowly. «Pike\'s lived here his '
              'whole life.» He looks at the red cord in your hand for a long '
              'time. «I can\'t hang a man on a bit of string. But I can watch '
              'him. And I will.»',
              go='thorne_bye',
              say="Wendel Pike's. He sent us down there, and somebody was "
                  'waiting for us.',
              sets=['thorne_asked_about_mere_road', 'wendel_reported'],
              unless=['wendel_confessed']),
          opt('keep_quiet', 'Keep it to yourself',
              '«It matters to me,» he says. But he lets it go.',
              go='thorne_bye', say="Doesn't matter whose. We're back.",
              sets=['thorne_asked_about_mere_road'])),

    scene('thorne_after', T,
          'Thorne stands when you come in, which he has not done before. '
          '«Marta\'s got her girl back,» he says. «She came in this morning to '
          'tell me herself, and she brought bread, and I\'ve not the faintest '
          'idea what to do with it.»',
          opt('paid_double', 'Collect the reward',
              '«A hundred,» he says, and counts it out, and it is a hundred, in '
              'coin that has been several different people\'s savings.',
              go='thorne_after', say="The council's gold, Captain.",
              sets=['thorne_paid', 'thorne_paid_hundred'],
              requires=['thorne_reward_doubled'], unless=['thorne_paid']),
          opt('paid_raised', 'Collect the reward',
              'Seventy-five, counted out twice, the second time more slowly.',
              go='thorne_after', say="The council's gold, Captain.",
              sets=['thorne_paid', 'thorne_paid_seventy_five'],
              requires=['thorne_reward_raised'], unless=['thorne_paid']),
          opt('paid_base', 'Collect the reward',
              '«Fifty, as promised.» He pushes the purse across. «It\'s not '
              'enough. It never was.»',
              go='thorne_after', say="The council's gold, Captain.",
              sets=['thorne_paid', 'thorne_paid_fifty'],
              unless=['thorne_paid', 'thorne_reward_raised',
                      'thorne_reward_doubled']),
          opt('ask_next', 'Ask what comes next',
              '«Now?» He unrolls a second map, older, of the whole kingdom. '
              '«Now the tollgate on the capital road opens again, and every '
              'merchant who\'s been sitting in the Sparrow waiting on it goes '
              'home. And you, if you\'ve any sense, go with them.» He taps the '
              'capital. «Whatever that thing in the wood was, it didn\'t start '
              'here. Things like that come from money.»',
              go='thorne_after', say='What happens now?',
              sets=['thorne_pointed_to_capital'],
              unless=['thorne_pointed_to_capital']),
          *_thorne_stone('thorne_after'),
          opt('leave', 'Leave',
              '«Millhaven owes you,» he says. «It won\'t remember for long. I '
              'will.»',
              go='thorne_bye', say='Look after them, Captain.')),

    scene('thorne_gone', T,
          'The Guard Hall is empty behind him, the map still pinned to the '
          'desk with its daggers.',
          ending=True),
    scene('thorne_bye', T, 'Thorne goes back to his map.', ending=True),
])


# --- Marta Whitmore ------------------------------------------------------------

M = 'Marta Whitmore'
marta = conversation('npc_002_marta', [
    entry('marta_home', requires=['boss_defeated_hollow_avatar']),
    entry('marta_doll', requires=['item_acquired_elaras_doll'],
          unless=['marta_saw_doll']),
    entry('marta_again', requires=['met_marta']),
    entry('marta_open'),
], [
    scene('marta_open', M,
          'Marta Whitmore doesn\'t turn from the fence. «Are you from the '
          'Captain?» Her voice is steady in the way of someone holding it '
          'steady. «Have you— no. You\'d have said.»',
          opt('gentle', 'Answer her gently',
              'She nods at the treeline, which is easier than nodding at you. '
              '«Ask, then. I\'ve told it so many times it doesn\'t sound like '
              'her any more.»',
              go='marta_ask',
              say="Not yet. But we're looking, and we'd like your help.",
              sets=['met_marta']),
          opt('blunt', 'Get straight to it',
              '«Out the back. Toward the oaks.» She points without looking: '
              'east, past the barn, to a dark ring of trees on the rise. '
              '«She\'s not meant to go there.»',
              go='marta_ask', say='Where was she last seen?',
              sets=['met_marta', 'marta_told_of_the_grove']),
          opt('leave', 'Leave her be',
              'She doesn\'t watch you go. She is watching the trees.',
              go='marta_bye')),

    scene('marta_ask', M, '«What do you want to know?»',
          opt('ask_grove', 'Ask about the oak ring',
              '«Nine oaks. Been there longer than the farm. Every child in the '
              'valley plays in it, and every mother tells them not to, and the '
              'mothers played there too.» She is quiet a moment. «She took her '
              'doll. She always takes the doll. I found her shoe by the gate, '
              'and I took it to the temple, because I didn\'t know what else '
              'to do with it.»',
              go='marta_ask', say='Tell us about the grove.',
              sets=['marta_asked_grove', 'marta_told_of_the_grove'],
              unless=['marta_asked_grove']),
          opt('ask_strangers', 'Ask about strangers',
              '«Tinkers. A priest, once, not ours — red cord on his wrist. '
              'Asked for water and didn\'t drink it.» She frowns. «And Wendel '
              'Pike from the Sparrow, all the way out here, asking had we seen '
              'anything. That was after she went. Kind of him, I thought.»',
              go='marta_ask', say='Anyone odd come by, before she went?',
              sets=['marta_asked_strangers', 'marta_mentioned_wendel'],
              unless=['marta_asked_strangers']),
          opt('ask_scarecrow', 'Ask about the empty pole in the field',
              '«Is it?» She looks past you at the field, and her face goes '
              'very still. «It went the night she did. I thought somebody\'d '
              'had it for the coat. It was my father\'s coat.» A long pause. '
              '«Elara tied her ribbon on its wrist. So it would keep the crows '
              'off her.»',
              go='marta_ask', say='Your scarecrow is gone off its pole.',
              sets=['marta_told_of_the_scarecrow'],
              unless=['marta_told_of_the_scarecrow']),
          opt('scarecrow_done', 'Tell her about the scarecrow',
              'Marta nods for a long time. «Good,» she says. «Good.» And then, '
              'because she is who she is: «Did you save the coat?» You did '
              'not. She laughs, which surprises both of you.',
              go='marta_ask',
              say="It was standing in the oak ring. It's ash now.",
              sets=['marta_scarecrow_settled'],
              requires=['scarecrow_burned'],
              unless=['marta_scarecrow_settled']),
          roll('remember', '[Diplomacy] Help her remember',
               'Take your time. Anything at all — a sound, a smell, the dog '
               'barking at nothing.',
               'diplomacy', 15, unless=['marta_pressed', 'marta_remembered'],
               crit=out('She closes her eyes. «The night before... the stock '
                        'wouldn\'t settle. And there was a smell off the wood '
                        'like a cold hearth, like the Brother\'s temple. I '
                        'thought it was the rain coming.» Her eyes open. «And '
                        'singing. Very faint. From the west, from the deep '
                        'wood. I told myself I dreamed it.»',
                        go='marta_ask',
                        sets=['marta_remembered', 'marta_heard_singing_west']),
               success=out('She closes her eyes. «The night before... the '
                           'stock wouldn\'t settle. And there was a smell off '
                           'the wood like a cold hearth, like the Brother\'s '
                           'temple.» Her eyes open. «I thought it was the rain '
                           'coming. It wasn\'t raining yet.»',
                           go='marta_ask', sets=['marta_remembered']),
               failure=out('«I don\'t know. I don\'t know. I\'ve gone over it '
                           'and over it.» She grips the fence rail. «I\'m '
                           'sorry.»',
                           go='marta_ask', sets=['marta_pressed'])),
          opt('leave', 'Leave',
              '«Don\'t promise me that,» she says. «Just go and look.»',
              go='marta_bye', say="We'll bring her home.")),

    scene('marta_again', M, 'Marta is still at the fence.',
          opt('ask', 'Ask her something',
              'She turns, a little, to listen.',
              go='marta_ask', say='Marta. A few more questions.'),
          opt('leave', 'Leave her be', 'She goes back to watching the trees.',
              go='marta_bye')),

    scene('marta_doll', M,
          'Marta sees what you are carrying before you say anything, and '
          'takes the doll from you with both hands.',
          opt('tell_dry', 'Tell her how you found it',
              '«Dry.» She turns it over. «Then somebody\'s been keeping it for '
              'her.» It is the first thing anyone has said in three days that '
              'has made her face do anything but hold still, and you are not '
              'sure it is hope.',
              go='marta_doll_after',
              say='It was lying in the grove. It was dry, after three days of '
                  'rain.',
              sets=['marta_saw_doll']),
          opt('silent', 'Say nothing',
              'She holds it against her for a long time.',
              go='marta_doll_after', sets=['marta_saw_doll'])),

    scene('marta_doll_after', M,
          'She gives it back. «Take it with you. She\'ll want it.»',
          opt('promise', 'Promise her',
              'She doesn\'t tell you not to, this time.',
              go='marta_bye', say="She'll have it back. From us."),
          opt('go', 'Go', 'She is already watching the trees again.',
              go='marta_bye')),

    scene('marta_home', M,
          'Elara is sitting on the fence rail where her mother stood, '
          'swinging her feet, the doll in her lap. Marta is inside. You can '
          'hear her singing, badly, through the open kitchen window.',
          opt('talk_elara', 'Talk to Elara',
              '«Mum says you\'re the ones.» She considers you with a '
              'nine-year-old\'s total seriousness. «The tall man in the grove '
              'was very cold, and he knew all our names. He said he was '
              'keeping us for somebody.» She hugs the doll. «He said *us*.»',
              go='marta_home', say='Hello, Elara.',
              sets=['elara_spoke_of_us'], unless=['elara_spoke_of_us']),
          opt('elara_scarecrow', 'Ask Elara what she keeps looking at',
              '«The scarecrow.» She points up at the oak ring on the rise. '
              '«It\'s up there now. It waves at me.» She does not sound '
              'frightened, which is worse. «It\'s still got my ribbon.»',
              go='marta_home', say='What are you watching, Elara?',
              sets=['marta_told_of_the_scarecrow'],
              unless=['marta_told_of_the_scarecrow']),
          opt('scarecrow_done', 'Tell Elara about the scarecrow',
              'Elara thinks about this seriously. «Did it mind?» You tell her '
              'you don\'t think so. «Good. It was only trying to keep the crows '
              'off.» She goes back to swinging her feet.',
              go='marta_home',
              say="The scarecrow's gone, Elara. We burned it.",
              sets=['marta_scarecrow_settled'],
              requires=['scarecrow_burned'],
              unless=['marta_scarecrow_settled']),
          opt('leave', 'Leave them to it',
              'Elara waves until you are out of sight.',
              go='marta_home_bye')),

    scene('marta_home_bye', M,
          'Behind you, through the kitchen window, somebody is still singing.',
          ending=True),
    scene('marta_bye', M, 'The farm is quiet behind you.', ending=True),
])


# --- Brother Aldus -------------------------------------------------------------

A = 'Brother Aldus'


def _aldus_errands(back):
    return [
        opt('give_names', 'Give him the name-tokens',
            'He takes the twine in both hands and reads every token, moving '
            'his lips. «Tessaly. Orrin. Beck. Hal.» He stops at the fifth. «I '
            'buried four of these. The rest I\'ve been waiting for.» He hangs '
            'them on the altar rail one at a time. «They\'ll have their names '
            'said, at least. Which is more than whoever took these off their '
            'doors meant for them.»',
            go=back,
            say='These were on the thralls in the wood. Door-tokens. Their '
                'names.',
            sets=['aldus_took_the_names'],
            requires=['item_acquired_name_tokens'],
            unless=['aldus_took_the_names']),
        opt('bless_drowned', 'Ask him to say the words for the drowned',
            '«For hanged men?» Aldus is quiet. «Nobody said them at the time, '
            'I expect. That was rather the point of the mere.» He takes his '
            'book down from the shelf, and his coat from the peg. «Tonight. '
            'Somebody should walk out on that causeway and say them, and it '
            'had better be somebody who isn\'t frightened of what comes up.»',
            go=back,
            say='The drowned in the mere. The Captain says the Watch put them '
                'there. Will you say the words for them?',
            sets=['aldus_blessed_the_drowned'],
            requires=['thorne_knew_the_stone'],
            unless=['aldus_blessed_the_drowned']),
    ]
aldus = conversation('npc_003_aldus', [
    entry('aldus_after', requires=['boss_defeated_hollow_avatar']),
    entry('aldus_again', requires=['met_aldus']),
    entry('aldus_open'),
], [
    scene('aldus_open', A,
          'Brother Aldus sets a loaf aside and gets up off his knees, one at a '
          'time. «Ashkyr keep you. If you\'ve come to leave something, there '
          'is room on the step. If you\'ve come to ask something, I\'d sooner '
          'you asked it than left it.»',
          opt('ask_burials', 'Ask about the burials',
              '«Four this week.» He does not need to count. «Two farmhands, a '
              'drover, and old Tessaly who kept the bees. Each of them had been '
              'dead longer than they\'d been missing, if you follow me. And '
              'each of them came to me with their eyes full of earth.»',
              go='aldus_ask',
              say="The Captain says you've been burying what they find.",
              sets=['met_aldus', 'aldus_told_burials']),
          opt('ask_shoe', 'Ask about the child\'s shoe on the step',
              '«Elara Whitmore\'s. Her mother brought it in.» He looks at it '
              'rather than at you. «I keep meaning to give it back, and I keep '
              'not being able to decide whether that would be a kindness.»',
              go='aldus_ask', say='Whose is the shoe?',
              sets=['met_aldus', 'aldus_told_shoe']),
          opt('leave', 'Leave him to his work',
              '«Ashkyr keep you,» he says again, and kneels.',
              go='aldus_bye', sets=['met_aldus'])),

    scene('aldus_ask', A, 'Aldus waits, hands folded into his sleeves.',
          opt('ask_burials', 'Ask about the burials',
              '«Four this week. Each dead longer than they\'d been missing, and '
              'each with their eyes full of earth.»',
              go='aldus_ask', say='Tell us about the dead.',
              sets=['aldus_told_burials'], unless=['aldus_told_burials']),
          opt('ask_what', 'Ask what he thinks is doing it',
              '«Honestly? Something that wants the dead and has learned to ask '
              'nicely.» He glances west, toward the forge and the wood beyond '
              'it. «It came out of the Whisperwood. Somebody\'s driven iron '
              'nails into the trees along the edge to keep it in there. They\'re '
              'new, and I didn\'t put them there, and neither did anyone who '
              'will admit to it.»',
              go='aldus_ask', say="What's doing this, Brother? Honestly.",
              sets=['aldus_pointed_west'], unless=['aldus_pointed_west']),
          roll('rite', '[Religion] Ask about the earth in their eyes',
               "Earth packed into the eyes. That's a rite, isn't it?",
               'religion', 16,
               unless=['aldus_explained_the_rite', 'aldus_rite_asked'],
               success=out('He looks at you properly for the first time. «It '
                           'is. An old burial rite, older than Ashkyr in this '
                           'valley — you pack the eyes so the dead can\'t find '
                           'their way home.» His mouth tightens. «Or so '
                           'something else can find its way in. Whoever\'s '
                           'doing this knows the old rites, and knows them from '
                           'the wrong side.»',
                           go='aldus_ask', sets=['aldus_explained_the_rite']),
               failure=out('«It\'s a sign of something,» he says. «I\'d hoped '
                           'you might know what.»',
                           go='aldus_ask', sets=['aldus_rite_asked'])),
          opt('ask_mere', 'Ask about the Mere Road',
              '«The Mere Road.» Aldus frowns. «Nobody\'s used that causeway '
              'since the mill drowned. I bury from that end of the parish, and '
              'there\'s been nothing from it to bury.» He hesitates. «Wendel\'s '
              'a good man for a rumour. I\'d not say he was a good man for a '
              'fact.»',
              go='aldus_ask',
              say='Wendel Pike says they took her south, down the Mere Road.',
              sets=['aldus_doubted_the_mere'],
              requires=['heard_of_the_mere_road'],
              unless=['aldus_doubted_the_mere',
                      'deception_revealed_mere_road']),
          *_aldus_errands('aldus_ask'),
          opt('leave', 'Leave',
              '«I always do,» he says, and goes back to the bread.',
              go='aldus_bye', say='Keep a lamp lit, Brother.')),

    scene('aldus_again', A, 'Aldus looks up from the altar. «Back again?»',
          opt('ask', 'Ask him something', '«Ask.»',
              go='aldus_ask', say='A few more questions, Brother.'),
          opt('leave', 'Leave him to his work', 'He nods, and kneels.',
              go='aldus_bye')),

    scene('aldus_after', A,
          'The child\'s shoe is gone from the step. «Marta came by,» Aldus '
          'says. «She didn\'t need it after all.» He smiles, which changes his '
          'whole face. «Ashkyr keep you. I mean it rather more than usual.»',
          opt('ask_over', 'Ask if it is over',
              '«The thing in the grove is over. Whoever taught it that rite is '
              'not, and they didn\'t learn it here.» He looks east, toward the '
              'capital road. «I\'d want to know who pays for a thing like '
              'that.»',
              go='aldus_after', say='Is it over?',
              sets=['aldus_warned_of_teacher'],
              unless=['aldus_warned_of_teacher']),
          *_aldus_errands('aldus_after'),
          opt('leave', 'Leave', 'He goes back to his altar, humming.',
              go='aldus_bye')),

    scene('aldus_bye', A, 'The temple smells of cold ash and new bread.',
          ending=True),
])


# --- Ada Harrow ----------------------------------------------------------------

H = 'Ada Harrow'
harrow = conversation('npc_004_harrow', [
    entry('harrow_after', requires=['boss_defeated_hollow_avatar']),
    entry('harrow_again', requires=['met_harrow']),
    entry('harrow_open'),
], [
    scene('harrow_open', H,
          'The hammer stops. Ada Harrow does not put it down. «If you want a '
          'horse shod, it\'ll be a week. If you want anything else, it\'ll be '
          'longer.»',
          opt('commissions', 'Ask about the unclaimed work',
              '«Hinges for a man who\'s dead. Plough-share for a man who\'s '
              'dead. That\'s a cradle-hook for a family that went to their '
              'sister\'s in Thornhaven and hasn\'t written.» She sets the '
              'hammer down, finally. «Four this week. I stack them in the '
              'order I heard.»',
              go='harrow_ask', say="That's a lot of work nobody's collected.",
              sets=['met_harrow']),
          opt('nails', 'Ask about the nails in the trees',
              'Her face does nothing at all, which is a great deal for a face '
              'to do.',
              go='harrow_nails',
              say="Somebody's been driving iron into the trees along the "
                  'Whisperwood.',
              sets=['met_harrow']),
          opt('leave', 'Leave', 'The hammer starts again before you reach the '
              'door.', go='harrow_bye', sets=['met_harrow'])),

    scene('harrow_nails', H, '«Is that so,» says Harrow.',
          roll('persuade', '[Diplomacy] Tell her you are on the same side',
               "Whoever's doing it is the only one in this town trying to keep "
               "something in that wood. I'd like to help them.",
               'diplomacy', 17,
               unless=['harrow_admitted_the_nails', 'harrow_refused'],
               crit=out('She looks at you a long while. Then she opens a '
                        'drawer under the bench, and it is full of nails, '
                        'square-cut, each with a mark scratched into its head. '
                        '«My grandmother did it the last time. I\'ve her book. '
                        'Iron and a name, one for every soul in the parish, so '
                        'it knows who\'s spoken for.» She scoops up a handful, '
                        'binds them in waxed thread, and puts them in your '
                        'hand. «If you\'re going in there, you\'ll want to be '
                        'spoken for.»',
                        go='harrow_ask',
                        sets=['harrow_admitted_the_nails',
                              'loot_g_003_charm_of_iron_nails']),
               success=out('She looks at you a long while. Then she opens a '
                           'drawer under the bench, and it is full of nails, '
                           'square-cut, each with a mark scratched into its '
                           'head. «My grandmother did it the last time. I\'ve '
                           'her book. Iron and a name, one for every soul in '
                           'the parish, so it knows who\'s spoken for.» She '
                           'shuts the drawer. «I\'ve run out of names I know. '
                           'I\'ve started on the ones in the ledger.»',
                           go='harrow_ask',
                           sets=['harrow_admitted_the_nails']),
               failure=out('«I\'m a smith,» she says. «I make nails. People '
                           'buy them.» She picks the hammer back up.',
                           go='harrow_ask', sets=['harrow_refused'])),
          roll('lean', '[Intimidation] Lean on her',
               'You know exactly who. Say it.',
               'intimidation', 19,
               unless=['harrow_admitted_the_nails', 'harrow_refused'],
               success=out('«Fine. Me.» She says it the way you would drop '
                           'something heavy. «And if you tell the council, '
                           'they\'ll make me stop, and then there\'ll be '
                           'nothing between Millhaven and that wood but you.»',
                           go='harrow_ask',
                           sets=['harrow_admitted_the_nails',
                                 'harrow_resents_you']),
               failure=out('Harrow looks at you, and then at the hammer, and '
                           'then at you again, and you find you have taken a '
                           'step back without deciding to.',
                           go='harrow_ask', sets=['harrow_refused'])),
          opt('drop', 'Let it go', '«Good,» she says.', go='harrow_ask',
              say='Never mind.')),

    scene('harrow_ask', H, '«Well?» says Harrow.',
          opt('ask_ledger', 'Show her the undertaker\'s ledger',
              '«Not mine. It came in with the undertaker\'s hinges, and I\'ve '
              'been meaning to walk it back.» She runs a thumb down the page. '
              '«Four marks, four burials — the four the Brother\'s had. That\'s '
              'not the undertaker\'s hand.» She taps one. «That\'s somebody '
              'counting.»',
              go='harrow_ask',
              say='This ledger was on your bench. Who marked it?',
              sets=['harrow_read_the_ledger'],
              requires=['item_acquired_harrow_ledger'],
              unless=['harrow_read_the_ledger']),
          opt('ask_maul', 'Ask about the maul on the wall',
              '«Seal-stone. A broken one, off the old boundary marker at the '
              'end of the Mere causeway.» She doesn\'t take it down. «I made '
              'three. I finished one. The other two cracked in the quench, and '
              'I don\'t know why, and I don\'t like not knowing why.»',
              go='harrow_ask',
              say="That maul's head — is that stone set into the iron?",
              sets=['harrow_told_of_the_maul'],
              unless=['harrow_told_of_the_maul']),
          opt('ask_nails', 'Ask about the nails in the trees',
              'Her face does nothing at all.',
              go='harrow_nails',
              say="About the nails along the Whisperwood.",
              unless=['harrow_admitted_the_nails', 'harrow_refused']),
          opt('leave', 'Leave', 'The hammer starts again before you reach the '
              'door.', go='harrow_bye')),

    scene('harrow_again', H, 'The hammer stops. «You again.»',
          opt('talk', 'Talk', '«Go on.»', go='harrow_ask',
              say='A word, if you can spare it.'),
          opt('leave', 'Leave', 'The hammer starts again.', go='harrow_bye')),

    scene('harrow_after', H,
          'The commissions along the back wall have been collected, all but '
          'the cradle-hook. Harrow is working, and for the first time since '
          'you came to Millhaven the hammer does not stop when you walk in.',
          opt('quiet', 'Tell her the wood is quiet',
              '«For now.» She holds up a nail between two fingers without '
              'looking round. «I\'m not pulling them out.»',
              go='harrow_bye', say="The wood's quiet."),
          opt('leave', 'Leave her to it', 'She lifts a hand without turning.',
              go='harrow_bye')),

    scene('harrow_bye', H, 'The forge is loud behind you.', ending=True),
])


# --- Wendel Pike ---------------------------------------------------------------

W = 'Wendel Pike'
cornered_options = [
    roll('lean', '[Intimidation] Make him tell you where she really is',
         'Where is she? The truth, this time, or I stop being polite.',
         'intimidation', 17, unless=['wendel_stonewalled', 'wendel_confessed'],
         crit=out('«The Hollow Grove!» It comes out of him all at once. «West, '
                  'through the Whisperwood, past where the trees stop having '
                  'birds. They said nobody would be hurt. They said she\'d be '
                  'kept, not— they said *kept*.» He is crying now, which does '
                  'not make you like him any better.',
                  go='wendel_broken',
                  sets=['wendel_confessed', 'wendel_named_the_grove']),
         success=out('«West.» He can\'t hold your eye. «The Whisperwood, the '
                     'grove at the heart of it. They pay me to send people '
                     'south, and I send them south, and I don\'t ask what\'s '
                     'west.»',
                     go='wendel_broken',
                     sets=['wendel_confessed', 'wendel_named_the_grove']),
         failure=out('«I don\'t know what you\'re talking about,» he says, and '
                     'walks into the back, and bolts the door. A moment later '
                     'the lamp on the back stair goes out.',
                     go='wendel_bolted', sets=['wendel_fled'])),
    roll('coax', '[Diplomacy] Give him a way out',
         "Whatever they've got on you, Wendel, we can help. But not while "
         "you're lying to us.",
         'diplomacy', 17, unless=['wendel_stonewalled', 'wendel_confessed'],
         success=out('He sits down on the nearest bench as if his legs have '
                     'been cut. «They\'ve got my boy,» he says. «Not— not '
                     'like that. He\'s with them. He went to Thornhaven for '
                     'work and came back with a red cord on his wrist, and '
                     'he\'s so *happy*, and they said if I did as I was told '
                     'he\'d stay happy.» A long breath. «The Hollow Grove. '
                     'West, through the wood. That\'s where they\'re keeping '
                     'her.»',
                     go='wendel_broken',
                     sets=['wendel_confessed', 'wendel_named_the_grove',
                           'wendel_spoke_of_his_son']),
         failure=out('«I\'ve done nothing I need a way out of,» he says, and '
                     'turns his back on you to serve somebody who isn\'t '
                     'there.',
                     go='wendel_bye', sets=['wendel_stonewalled'])),
    opt('leave', 'Leave him', 'He does not watch you go, which is how you know '
        'he wants to.', go='wendel_bye'),
]

wendel = conversation('npc_007_wendel', [
    entry('wendel_arrested', requires=['wendel_arrested']),
    entry('wendel_gone', requires=['wendel_fled']),
    entry('wendel_ashamed', requires=['wendel_confessed']),
    entry('wendel_caught', requires=['deception_revealed_mere_road']),
    entry('wendel_again', requires=['met_wendel']),
    entry('wendel_open'),
], [
    scene('wendel_open', W,
          '«Welcome to the Sparrow!» The landlord is at your elbow before you '
          'have the door shut behind you, cloth over his shoulder, smile '
          'ready. «Sit anywhere but by the door — there\'s a draught. You\'re '
          'the ones the Captain\'s sent after the Whitmore girl, aren\'t you? '
          'Terrible thing. Terrible.»',
          opt('ask_elara', 'Ask what he has heard',
              'Wendel lowers his voice, though there is nobody near. «More '
              'than heard.»',
              go='wendel_story',
              say='You hear everything in here, they say. What have you heard '
                  'about Elara?',
              sets=['met_wendel']),
          opt('small_talk', 'Order a drink', '«Coming up!»',
              go='wendel_bar', say="Whatever's good.", sets=['met_wendel'])),

    scene('wendel_bar', W,
          'Wendel leans on the bar, cloth in hand. At the back of the room a '
          'lamp burns on the stair in the middle of the day. «What\'ll it '
          'be?»',
          opt('ask_elara', 'Ask what he has heard about Elara',
              'Wendel lowers his voice, though there is nobody near. «More '
              'than heard.»',
              go='wendel_story', say='What have you heard about the Whitmore '
              'girl?',
              unless=['heard_of_the_mere_road']),
          opt('ask_lamp', 'Ask about the lamp on the stair',
              '«For the late ones,» he says easily. «Nobody wants to break '
              'their neck on the stair in the dark.» It is broad daylight '
              'through every window in the room.',
              go='wendel_bar', say="Why's there a lamp lit on the stair at "
              'noon?',
              sets=['asked_wendel_lamp'], unless=['asked_wendel_lamp']),
          opt('ask_news', 'Ask for the news',
              '«Tollgate on the capital road\'s shut till the Captain says '
              'otherwise, so half the county\'s drinking my cellar dry waiting '
              'on it.» He beams. «Ill wind.»',
              go='wendel_bar', say="What's the talk in here?",
              sets=['asked_wendel_news'], unless=['asked_wendel_news']),
          opt('doubt', 'Tell him what Brother Aldus said',
              '«Well, somebody has,» Wendel says, a shade too quickly. «Two '
              'somebodies, carrying a third.» He picks up a cup that is '
              'already clean and cleans it.',
              go='wendel_bar',
              say="Brother Aldus says nobody's used the Mere Road in years.",
              sets=['caught_wendel_lying'],
              requires=['aldus_doubted_the_mere'],
              unless=['caught_wendel_lying', 'deception_revealed_mere_road']),
          opt('pedlar', 'Tell him what the pedlar said',
              'Wendel laughs, and it comes out wrong. «Sal Mercy? She\'d sell '
              'you your own boots.» His eyes go to the lamp on the back stair, '
              'and come back, and he sees you watching them do it.',
              go='wendel_bar',
              say="Sal Mercy says the men on the Mere Road are paid in here.",
              sets=['caught_wendel_lying'],
              requires=['sal_warned_of_the_mere', 'heard_of_the_mere_road'],
              unless=['caught_wendel_lying', 'deception_revealed_mere_road']),
          opt('confront', 'Tell him you know he is lying',
              'The cloth stops moving on the bar.',
              go='wendel_cornered',
              say='You told that story like a man reading it off a card. Who '
                  'wrote it for you?',
              requires=['caught_wendel_lying'],
              unless=['deception_revealed_mere_road', 'wendel_stonewalled']),
          opt('leave', 'Leave', '«Mind the draught!»', go='wendel_bye')),

    scene('wendel_story', W,
          '«I saw them,» Wendel says. «Three nights back, closing up, I\'m out '
          'the back with the slops and there\'s two men going past the temple '
          'wall, south, carrying something the size of a child wrapped in '
          'sacking. Down the Mere Road, toward the old drowned mill.» He '
          'shakes his head. «I told the Captain. He said I\'d had a drink. '
          'Well — I had. But I know what I saw.»',
          opt('believe', 'Thank him',
              '«Least I can do.» He squeezes your arm. «South past the temple '
              'and over the causeway. Mind how you go on it — it floods.»',
              go='wendel_bye',
              say="That's the first real lead anyone's given us. Thank you.",
              sets=['heard_of_the_mere_road', 'believed_wendel']),
          roll('watch', '[Perception] Watch him while he tells it again',
               'Say it again. Slowly. What exactly did you see?',
               'perception', 19,
               crit=out('He tells it again, word for word — exactly word for '
                        'word, the same pauses in the same places, like a man '
                        'reciting. And when he says *south*, his eyes go, just '
                        'for a moment, to the lamp burning on the back stair.'
                        '\n\nHe is lying, and lying to send you south, which '
                        'means whatever he is covering for is somewhere else. '
                        'The Whisperwood is west.',
                        go='wendel_bye',
                        sets=['heard_of_the_mere_road', 'caught_wendel_lying',
                              'wendel_looked_at_the_lamp']),
               success=out('He tells it again, and it comes out the same — too '
                           'much the same, the same pauses in the same places, '
                           'like a man reciting something he has practised. He '
                           'is lying to you. You are not sure yet why.',
                           go='wendel_bye',
                           sets=['heard_of_the_mere_road',
                                 'caught_wendel_lying']),
               failure=out('He tells it again. It is a good story, and he '
                           'tells it like a man who has been telling it all '
                           'week to anybody who would listen, which is '
                           'probably exactly what he has been doing.',
                           go='wendel_bye',
                           sets=['heard_of_the_mere_road', 'believed_wendel']),
               fumble=out('He tells it again, better, with the weight of the '
                          'bundle and the sound their boots made on the '
                          'causeway. You find you are leaning in.',
                          go='wendel_bye',
                          sets=['heard_of_the_mere_road', 'believed_wendel']))),

    scene('wendel_again', W,
          '«Back again!» Wendel wipes the bar in front of you. «What\'ll it '
          'be?»',
          opt('bar', 'Lean on the bar', 'He waits, smiling.', go='wendel_bar',
              say='A word, landlord.'),
          opt('leave', 'Leave', '«Mind the draught!»', go='wendel_bye')),

    scene('wendel_caught', W,
          'Wendel sees the red cord in your hand from across the room, and '
          'for a moment his face isn\'t doing anything at all. Then the smile '
          'comes back, a little too wide. «You\'re back! Any luck?»',
          opt('cord', 'Put the red cord on the bar',
              'He looks at it. He doesn\'t touch it.',
              go='wendel_cornered',
              say='Stones in a sack, Wendel. And this, knotted the Covenant '
                  'way.'),
          opt('leave', 'Leave him wondering', 'The smile follows you to the '
              'door.', go='wendel_bye')),

    scene('wendel_cornered', W,
          '«Anyone can tie a knot,» Wendel says. His hands have gone flat on '
          'the bar.',
          *cornered_options),

    scene('wendel_ashamed', W,
          'Wendel won\'t look at you. He keeps polishing the same cup, and '
          'the lamp on the back stair is cold.',
          ending=True),
    scene('wendel_gone', W,
          'Wendel isn\'t behind the bar. The pot-boy says he\'s gone to his '
          'sister\'s in the capital, and doesn\'t believe it either. The lamp '
          'on the back stair has been put out.',
          ending=True),
    scene('wendel_arrested', W,
          'The Sparrow is shut. Through the window you can see Wendel sitting '
          'alone at a table, a guard on a stool by the door, the lamp on the '
          'back stair cold.',
          ending=True),
    scene('wendel_broken', W,
          'Wendel stays where he is. Nobody else in the Sparrow looks at him, '
          'or at you.',
          ending=True),
    scene('wendel_bolted', W,
          'Somewhere below, a yard door bangs. By the time anyone thinks to '
          'go after him, the lane behind the Sparrow is empty.',
          ending=True),
    scene('wendel_bye', W,
          'Wendel goes back to his bar. The lamp on the back stair burns on in '
          'the daylight.',
          ending=True),
])


# --- Queen Liora ---------------------------------------------------------------

L = 'Queen Liora'
liora = conversation('npc_005_queen_liora', [
    entry('liora_gone', requires=['boss_defeated_malachai_vex']),
    entry('liora_exposed', requires=['deception_revealed_under_archive'],
          unless=['liora_confronted']),
    entry('liora_again', requires=['met_liora']),
    entry('liora_open'),
], [
    scene('liora_open', L,
          'Queen Liora does not rise. «Ah, the heroes of Millhaven. How '
          'quaint.» A servant is already pouring. «Perhaps you might join us '
          'for wine?»',
          opt('accept', 'Accept the wine',
              'The wine is very good, and she watches you drink it with the '
              'attention of someone checking a recipe.',
              go='liora_court', say='Thank you, Majesty.',
              sets=['met_liora', 'drank_with_liora']),
          opt('decline', 'Decline',
              '«How careful.» The smile does not move at all. «Careful people '
              'live such long, dull lives.»',
              go='liora_court', say="We'll stay thirsty, Majesty.",
              sets=['met_liora']),
          roll('protocol', '[Society] Greet her with full court protocol',
               'Your Majesty honours us. We come at the commendation of the '
               'Captain of Millhaven, to offer the Crown our service.',
               'society', 28,
               success=out('The courtiers along the wall stop whispering. '
                           '«Someone has taught you manners,» Liora says. «How '
                           'unexpected. Sit.»',
                           go='liora_court',
                           sets=['met_liora', 'liora_respects_you']),
               failure=out('A courtier laughs behind his hand at something in '
                           'the phrasing, and Liora lets him. «Charming,» she '
                           'says.',
                           go='liora_court', sets=['met_liora']))),

    scene('liora_court', L,
          '«The King is resting,» Liora says, before you can ask. «The King is '
          'always resting now. You will address yourselves to me.»',
          opt('ask_king', 'Ask after the King',
              '«The King is adjusting to recent pressures. His paranoia is '
              'tiresome, but I remain steadfast.» She turns her cup a quarter '
              'turn on the arm of the throne. «He sees shadows in the corners '
              'of rooms. One would think a king would be used to that.»',
              go='liora_court', say='What ails the King?',
              sets=['liora_asked_king'], unless=['liora_asked_king']),
          opt('ask_covenant', 'Ask about the Crimson Covenant',
              '«Ah, you know. How delightful.» She says it the way other '
              'people say *good morning*. «We are not murderers. We are '
              'gravediggers for a dead world.» A pause, while the courtiers '
              'along the wall find somewhere else to look. «I speak '
              'figuratively, of course.»',
              go='liora_court',
              say='What does Your Majesty know of the Crimson Covenant?',
              sets=['liora_asked_covenant'],
              requires=['liora_asked_king'], unless=['liora_asked_covenant']),
          opt('ask_corruption', 'Ask about the corruption',
              '«Such an ugly word. I call it *transformation*.» She leans '
              'forward, and for the first time looks interested. «The shadow '
              'will purge the weak. The question every sensible person in this '
              'kingdom is asking is which side of that sentence they intend to '
              'be on.»',
              go='liora_court',
              say='The corruption in this city — the red grain in the stone, '
                  'the lamps, the shadows. What is it?',
              sets=['liora_asked_corruption'],
              unless=['liora_asked_corruption']),
          opt('ask_mines', 'Ask about the Bloodstone mines',
              '«Rock,» she says. «Men. Accidents.» She sets the cup down. «I '
              'would not go down the mines, if I were you. I would go home to '
              'Millhaven and be thanked by farmers.» It is the first thing she '
              'has said that sounds like advice, and the first that sounds '
              'like a threat.',
              go='liora_court', say="The Bloodstone mines. What's down there?",
              sets=['liora_warned_of_mines'],
              requires=['liora_asked_corruption'],
              unless=['liora_warned_of_mines']),
          roll('turncoat', '[Deception] Let her think you want to join',
               'Suppose someone wanted to be on the right side of that '
               'sentence, Majesty.',
               'deception', 28,
               requires=['liora_asked_covenant'],
               unless=['liora_sent_you_to_hale', 'liora_saw_through_you'],
               success=out('«Then someone would visit the Grand Library,» she '
                           'says slowly, «and ask Master Hale for the old '
                           'records of the seals. He is very helpful to people '
                           'I send.» She smiles. «Tell him I sent you.»',
                           go='liora_court', sets=['liora_sent_you_to_hale']),
               failure=out('«No,» she says pleasantly. «You don\'t.» And that '
                           'is the end of that.',
                           go='liora_court', sets=['liora_saw_through_you'])),
          opt('take_leave', 'Take your leave',
              '«I have, haven\'t I.» She lifts two fingers, and the audience is '
              'over. As the doors close behind you, you hear her laugh — not '
              'at you, you think, but at something she has just decided.',
              go='liora_bye',
              say='Your Majesty has been generous with her time.',
              sets=['dialogue_complete_queen_liora'],
              requires=['liora_asked_king', 'liora_asked_covenant',
                        'liora_asked_corruption']),
          opt('walk_out', 'Walk out',
              '«Have you,» she says, to your back.',
              go='liora_bye', say="We've heard enough.")),

    scene('liora_again', L,
          'Queen Liora regards you over the rim of her cup. «Again? The court '
          'will talk.»',
          opt('audience', 'Ask for an audience', '«Well?»', go='liora_court',
              say='A few more questions, Majesty.'),
          opt('leave', 'Bow and leave', 'She does not watch you go.',
              go='liora_bye')),

    scene('liora_exposed', L,
          'You lay the letter on the arm of her throne. Liora reads her own '
          'handwriting without any change of expression at all. «Hale always '
          'did keep everything,» she says.',
          roll('demand', "[Intimidation] Demand the archivist's daughter",
               "The archivist's girl. Where is she?",
               'intimidation', 30,
               success=out('For a moment the smile goes away entirely, and '
                           'what is underneath it is only tired. «Thornhaven,» '
                           'she says. «With the others. Malachai likes to keep '
                           'the families close.» The smile comes back. «You\'ll '
                           'be going there anyway, I expect.»',
                           go='liora_bye',
                           sets=['liora_confronted', 'liora_named_thornhaven']),
               failure=out('«Guards,» says Liora, without raising her voice, '
                           'and you are escorted from the throne room with '
                           'great courtesy and no discussion.',
                           go='liora_bye',
                           sets=['liora_confronted', 'liora_had_you_removed'])),
          opt('accuse', 'Accuse her before the court',
              'Nobody along the wall moves. Nobody along the wall looks at '
              'you. Liora lets the silence go on until it is embarrassing for '
              'everyone except her. «The kingdom has heard you,» she says. '
              '«The kingdom is not interested.»',
              go='liora_bye',
              say="Your Queen sends honest men's children to Thornhaven to "
                  'keep their fathers quiet.',
              sets=['liora_confronted', 'liora_accused_publicly']),
          opt('leave', 'Take the letter back and go',
              '«Do keep it,» she says. «I have the original.»',
              go='liora_bye')),

    scene('liora_gone', L,
          'The throne is empty. A servant tells you the Queen has retired to '
          'the country for her health, and does not say which country.',
          ending=True),
    scene('liora_bye', L, 'The doors of the throne room close behind you.',
          ending=True),
])


# --- Master Archivist Oswin Hale ------------------------------------------------

O = 'Master Archivist Oswin Hale'
hale_daybook = opt(
    'give_daybook', 'Give him the Reader\'s day-book',
    '«Pell,» he says. He opens it at the flyleaf and reads the names crossed '
    'out there, one after another, in an ink he must have bought himself. «I '
    'told their families the provinces. I was told to say the provinces.» He '
    'closes it very gently. «I\'ll write to them. Properly, this time. Every '
    'one.»',
    go='hale_daybook_bye',
    say='This was on one of the things on your stair. We think it was his.',
    sets=['hale_given_the_daybook'],
    requires=['item_acquired_readers_daybook'],
    unless=['hale_given_the_daybook'])
hale_confront = [
    roll('coax', '[Diplomacy] Tell him you know about his daughter',
         'We read the letter. We know what she is holding over you.',
         'diplomacy', 26, unless=['hale_stonewalled', 'hale_confessed'],
         success=out('«Her name is Wenna,» Hale says. «She\'s eleven. They '
                     'took her to Thornhaven for her schooling, the Queen '
                     'said, a great honour.» He wipes his eyes with an '
                     'ink-stained cuff. «The mines. It\'s the mines, it was '
                     'always the mines. There\'s a geode at the bottom of the '
                     'deep workings that the whole city is drinking from, and '
                     'while it stands, what\'s in Thornhaven can\'t be '
                     'stopped.»',
                     go='hale_bye',
                     sets=['hale_confessed', 'hale_named_the_geode']),
         failure=out('«You don\'t know anything,» Hale says, too loudly for a '
                     'library, and then, in a whisper: «Please go away.»',
                     go='hale_bye', sets=['hale_stonewalled'])),
    roll('threaten', '[Intimidation] Tell him the next lie will cost him',
         'You sent us to die under your floor. Give me one reason not to '
         'return the favour.',
         'intimidation', 26, unless=['hale_stonewalled', 'hale_confessed'],
         success=out('«Because I\'m the only one who\'ll tell you the '
                     'truth!» He is on his feet and shaking. «The mines. The '
                     'geode in the deep workings. Break it and Thornhaven\'s '
                     'gates can be opened — he can\'t hold the ritual without '
                     'it.» He sits back down. «She has my daughter.»',
                     go='hale_bye',
                     sets=['hale_confessed', 'hale_named_the_geode']),
         failure=out('Hale flinches, and then — to his own evident surprise — '
                     'doesn\'t. «There is nothing you can do to me that she '
                     'hasn\'t already,» he says, quite calmly.',
                     go='hale_bye', sets=['hale_stonewalled'])),
    hale_daybook,
    opt('leave', 'Leave him', 'He does not look up as you go.', go='hale_bye'),
]

hale = conversation('npc_008_hale', [
    entry('hale_home', requires=['boss_defeated_malachai_vex']),
    entry('hale_ashamed', requires=['hale_confessed']),
    entry('hale_caught', requires=['deception_revealed_under_archive']),
    entry('hale_again', requires=['met_hale']),
    entry('hale_open'),
], [
    scene('hale_open', O,
          'The archivist looks up from the catalogue. «Quietly, please.» He '
          'takes in your road-dirt and your weapons, and something in his '
          'face settles, the way a face settles when a thing that has been '
          'dreaded for a long time finally arrives. «You\'ll be the ones from '
          'Millhaven.»',
          opt('ask_missing', 'Ask about the empty sections',
              '«Removed for conservation,» Hale says. «By order of the Crown.» '
              'He does not look at the catalogue, which still lists every '
              'missing volume in his own neat hand.',
              go='hale_desk', say='Whole sections of your shelves are empty.',
              sets=['met_hale', 'hale_asked_missing']),
          opt('ask_seals', 'Ask about the seals',
              'Hale is quiet for a moment. Then he closes the catalogue.',
              go='hale_story',
              say='We need to know about the seals the Covenant is breaking.',
              sets=['met_hale']),
          opt('queen_sent', 'Tell him the Queen sent you',
              'Something crosses Hale\'s face and is put away. «Then I shall '
              'be,» he says, and closes the catalogue.',
              go='hale_story',
              say="The Queen sent us. She says you're very helpful.",
              sets=['met_hale', 'hale_knows_the_queen_sent_you'],
              requires=['liora_sent_you_to_hale'])),

    scene('hale_desk', O,
          'Hale waits with his hands folded on the closed catalogue.',
          opt('ask_seals', 'Ask about the seals',
              'Hale is quiet for a moment. «Not in front of the shelves,» he '
              'says, and lowers his voice.',
              go='hale_story',
              say='The seals the Covenant is breaking. Tell us.',
              unless=['heard_of_the_under_archive']),
          opt('ask_missing', 'Ask about the empty sections',
              '«Removed for conservation. By order of the Crown.»',
              go='hale_desk', say='Where did the missing books go?',
              sets=['hale_asked_missing'], unless=['hale_asked_missing']),
          opt('confront', 'Tell him you know he lied',
              'His hands press flat on the catalogue.',
              go='hale_cornered',
              say='The stair under your desk. You were lying about it, and we '
                  'both know it.',
              requires=['caught_hale_lying'],
              unless=['deception_revealed_under_archive', 'hale_stonewalled']),
          hale_daybook,
          opt('leave', 'Leave', '«Quietly, please,» he says, to nobody.',
              go='hale_bye')),

    scene('hale_story', O,
          '«You\'ll have been told the mines,» Hale says, low. «Everyone is '
          'told the mines. The Queen wants you told the mines.» He glances '
          'across the plaza toward the throne room. «They are a feint — a red '
          'grain in the rock to draw the eye. The seal they are really '
          'working is beneath this library. I hear the chanting through the '
          'floor at night. There is a stair behind this desk, and I can give '
          'you the key.»',
          opt('take_key', 'Take the key',
              'He puts an iron key on the desk and doesn\'t take his hand off '
              'it quite as quickly as he should. «Behind the catalogue, and '
              'down. Be careful. Nobody has been below the stacks since my '
              'predecessor.»',
              go='hale_bye', say='Show us the stair.',
              sets=['heard_of_the_under_archive', 'believed_hale']),
          roll('watch', '[Perception] Watch his hands while he answers',
               "You've heard chanting. Through the floor. How often?",
               'perception', 28,
               crit=out('«Most nights,» he says, and his hands, which have been '
                        'still on the catalogue, press down flat as if to hold '
                        'it shut. He isn\'t lying about the chanting. He is '
                        'lying about everything around it. And when he says '
                        '*the mines are a feint*, he looks, for a fraction of a '
                        'second, like a man who badly wants to be contradicted.',
                        go='hale_bye',
                        sets=['heard_of_the_under_archive', 'caught_hale_lying',
                              'hale_wants_to_be_stopped']),
               success=out('«Most nights,» he says, and his hands press flat on '
                           'the catalogue as if to hold it shut. The story is '
                           'good. The man telling it is terrified. He is lying '
                           'to you.',
                           go='hale_bye',
                           sets=['heard_of_the_under_archive',
                                 'caught_hale_lying']),
               failure=out('«Most nights,» he says. «Low. In a language I can '
                           'read but have never heard spoken.» He is afraid, '
                           'but everyone in this city is afraid, and he has '
                           'more reason than most.',
                           go='hale_bye',
                           sets=['heard_of_the_under_archive',
                                 'believed_hale'])),
          opt('mines_first', 'Tell him you will try the mines first',
              '«Of course,» says Hale, and looks as though someone has taken '
              'one weight off him and put a different one on.',
              go='hale_bye',
              say="Then we'll look at the mines first, and come back to your "
                  'stair.',
              sets=['heard_of_the_under_archive'])),

    scene('hale_again', O, 'Hale looks up from the catalogue. «Yes?»',
          opt('desk', 'Speak with him', 'He closes the catalogue.',
              go='hale_desk', say='A word, Master Hale.'),
          opt('leave', 'Leave', '«Quietly, please.»', go='hale_bye')),

    scene('hale_caught', O,
          'Hale sees the letter in your hand, and all the air goes out of him. '
          'He sits down behind the catalogue desk as if someone has cut a '
          'string.',
          *hale_confront),

    scene('hale_cornered', O,
          '«I don\'t know what you mean,» says Hale. He is looking at the '
          'door behind his desk.',
          *hale_confront),

    scene('hale_daybook_bye', O,
          'When you look back from the door, Hale has a fresh sheet in front '
          'of him and has not yet written a word.',
          ending=True),

    scene('hale_ashamed', O,
          'Hale won\'t look up from the catalogue. «Find her,» he says, to the '
          'page. «Please.»',
          hale_daybook,
          opt('leave', 'Go and find her', 'He does not watch you go.',
              go='hale_bye')),
    scene('hale_home', O,
          'Hale is not at the catalogue desk. A girl of about eleven is '
          'sitting in his chair with her feet not touching the floor, reading, '
          'and when you come in she says, without looking up, «Quietly, '
          'please.»',
          opt('give_daybook', 'Give Hale the Reader\'s day-book',
              '«Father,» the girl calls, still without looking up, and Hale '
              'comes out of the stacks wiping his hands. He sees the binding '
              'and stops. «Pell,» he says. He reads the names crossed out on '
              'the flyleaf, one after another. «I told their families the '
              'provinces.» His daughter turns a page. «I\'ll write to them. '
              'Properly, this time.»',
              go='hale_daybook_bye',
              say='This was on one of the things on your stair. We think it '
                  'was his.',
              sets=['hale_given_the_daybook'],
              requires=['item_acquired_readers_daybook'],
              unless=['hale_given_the_daybook']),
          opt('leave', 'Leave them be',
              'Somewhere in the stacks, Hale is humming.',
              go='hale_bye')),
    scene('hale_bye', O, 'The library\'s silence closes over you again.',
          ending=True),
])


# --- Malachai Vex ----------------------------------------------------------------

V = 'Malachai Vex'
malachai = conversation('npc_006_malachai', [
    entry('malachai_after', requires=['boss_defeated_malachai_vex']),
    entry('malachai_open'),
], [
    scene('malachai_open', V,
          'Malachai Vex does not stand. He gestures to the chair across from '
          'him, just inside the outermost circle. «At last we meet. Sit with '
          'me. Let us discuss the world as it truly is.»',
          opt('sit', 'Sit',
              'You sit. The circle is warm through the chair, the way a hearth '
              'is warm after the fire has gone out.',
              go='malachai_talk', say='Talk, then.',
              sets=['sat_with_malachai']),
          opt('stand', 'Stay standing',
              '«As you like.» He seems, if anything, pleased. «The last ones '
              'sat.»',
              go='malachai_talk', say="We'll stand.")),

    scene('malachai_talk', V, 'Vex waits, patient as a stone.',
          opt('vision', 'Ask what he is doing',
              '«The old order is a fossil,» he says. «This kingdom was built on '
              'a people who understood entropy, and buried them, and put seals '
              'on the grave, and has spent a thousand years pretending the '
              'grave isn\'t there. We will be perfected through the shadow.»',
              go='malachai_talk', say='What is it you think you\'re doing?',
              sets=['malachai_spoke_of_the_vision'],
              unless=['malachai_spoke_of_the_vision']),
          opt('shadow', 'Ask what the shadow is',
              '«Shadow is entropy — the natural force of ending. It grants '
              'clarity and power.» He opens his hand, and the dark in the palm '
              'of it is darker than the room. «Everything ends. I have simply '
              'stopped pretending otherwise.»',
              go='malachai_talk', say='And the shadow? What is it, really?',
              sets=['malachai_spoke_of_the_shadow'],
              unless=['malachai_spoke_of_the_shadow']),
          opt('ascension', 'Ask what becomes of him',
              '«I am a Vessel.» He says it as simply as a man giving his trade. '
              '«Soon I will be consumed, and the true god will wear this '
              'flesh.» A pause. «You are wondering whether I mind. That is the '
              'most interesting question anyone has asked me this year.»',
              go='malachai_talk',
              say='What happens to you, at the end of all this?',
              sets=['malachai_spoke_of_the_ascension'],
              unless=['malachai_spoke_of_the_ascension']),
          opt('children', 'Ask where the children are',
              '«Upstairs. Asleep. Well fed.» He sounds faintly offended. «I am '
              'ending the world, not being *cruel*.» He glances at the '
              'ceiling. «When I am finished, it will not matter where anybody '
              'is.»',
              go='malachai_talk',
              say="Where are the children? Hale's daughter. The others.",
              sets=['malachai_told_of_the_children'],
              requires=['hale_confessed'],
              unless=['malachai_told_of_the_children']),
          roll('name_him', '[Religion] Tell him what he is',
               "A Vessel doesn't choose. You're not a prophet. You're a jar.",
               'religion', 30,
               requires=['malachai_spoke_of_the_ascension'],
               unless=['malachai_shaken', 'malachai_unshaken'],
               success=out('For the first time something in Vex\'s face moves '
                           'without his permission. «...Yes,» he says, after a '
                           'while. «Yes. That is exactly right.» He stands. '
                           '«Thank you. I had wondered whether anyone would '
                           'say it.»',
                           go='malachai_rise', sets=['malachai_shaken']),
               failure=out('«Of course I am a jar,» he says kindly. «So are '
                           'you. The difference is that I know what I am '
                           'for.»',
                           go='malachai_talk', sets=['malachai_unshaken'])),
          opt('enough', 'End it',
              '«Yes,» says Vex. «I suppose it is.»',
              go='malachai_rise', say='Enough talk.')),

    scene('malachai_rise', V,
          'He closes the ledger, sets it down with care, and stands. The two '
          'acolytes move to the edges of the circle without being told.',
          ending=True),
    scene('malachai_after', V,
          'Nothing of Malachai Vex remains in the chamber but the ledger, '
          'closed, and a shadow on the floor that does not belong to anything '
          'still standing.',
          ending=True),
])


# --- Jory Tallow ----------------------------------------------------------------

J = 'Jory Tallow'
jory_talk_options = [
    opt('ask_road', 'Ask why he is stuck here',
        '«Tollgate\'s shut. Captain\'s orders, till the roads are safe — and '
        'the roads are not safe, so here I sit.» He waves at the cart. «Stock '
        'I bought for the capital, selling to farmers. You can imagine how '
        'that\'s going.»',
        go='jory_talk',
        say="Why's a Crown-road pedlar selling out of a market square?",
        sets=['jory_told_of_the_road'], unless=['jory_told_of_the_road']),
    roll('haggle', '[Diplomacy] Talk his prices down',
         'Nobody in Millhaven can afford capital prices. We can — if they '
         'come down.',
         'diplomacy', 16, unless=['jory_haggled'],
         crit=out('«...You know, I like you.» He writes something on the back '
                  'of his broadsheet and underlines it twice. «Two in ten off, '
                  'for you. Don\'t tell the farmers.»',
                  go='jory_talk',
                  sets=['jory_haggled', 'jory_discount_large']),
         success=out('He sucks his teeth, looks at the cart, looks at the '
                     'empty square. «One in ten off. Because you\'re the only '
                     'people who\'ve asked.»',
                     go='jory_talk', sets=['jory_haggled', 'jory_discount']),
         failure=out('«My prices are my prices,» he says, cheerfully enough.',
                     go='jory_talk', sets=['jory_haggled']),
         fumble=out('«Well,» he says, a good deal less cheerfully, «now '
                    'they\'re a little higher.»',
                    go='jory_talk', sets=['jory_haggled', 'jory_offended'])),
    opt('ask_talk', 'Ask what he has heard on the road',
        '«That the road\'s shut, mostly.» He lowers his voice. «And that '
        'nobody in this town will buy iron nails from me. Plenty of call for '
        'nails — every tree on the Whisperwood side has a row of them. Nobody '
        'buys mine. Somebody local\'s selling them cheaper, and I\'d dearly '
        'like to know who.»',
        go='jory_talk', say="You're a travelling man. What's the talk?",
        sets=['jory_mentioned_the_nails'],
        unless=['jory_mentioned_the_nails']),
    opt('ask_rare', 'Ask if he has anything special',
        '«If I had anything you couldn\'t get in the capital, I\'d be in the '
        'capital selling it.» He grins. «The things worth having out here '
        'don\'t come off a cart. They come off whatever was carrying them. '
        'Bring me those and I\'ll give you half what they\'re worth, which is '
        'more than they\'re worth to a corpse.»',
        go='jory_talk',
        say="Anything under the counter? Something the capital doesn't have?",
        sets=['jory_asked_rare'], unless=['jory_asked_rare']),
    opt('leave', 'Leave',
        '«Look all you like. Buying\'s where the joy is.»',
        go='jory_bye', say="We'll have a look."),
]

jory = conversation('npc_009_jory', [
    entry('jory_wagon', requires=['Unlock_Travel_to_Valorheim'],
          unless=['jory_saw_the_wagon']),
    entry('jory_again', requires=['met_jory']),
    entry('jory_open'),
], [
    scene('jory_open', J,
          '«Customers!» The pedlar folds his broadsheet away. «Actual '
          'customers. Jory Tallow — licensed to the Crown road, and currently '
          'licensed to this fountain.» He taps a tollgate stamp pinned to his '
          'hatband like a medal.',
          opt('ask_road', 'Ask why he is stuck here',
              '«Tollgate\'s shut. Captain\'s orders, till the roads are safe — '
              'and the roads are not safe, so here I sit.» He waves at the '
              'cart. «Stock I bought for the capital, selling to farmers. You '
              'can imagine how that\'s going.»',
              go='jory_talk',
              say="Why's a Crown-road pedlar selling out of a market square?",
              sets=['met_jory', 'jory_told_of_the_road']),
          opt('look', 'Ask to see his stock',
              '«Everything a sensible adventurer needs, and several things '
              'nobody does.» He props the second shutter open with a '
              'flourish.',
              go='jory_talk', say='What have you got?', sets=['met_jory']),
          opt('leave', 'Leave',
              '«Mind how you go. Come back richer.»',
              go='jory_bye', sets=['met_jory'])),

    scene('jory_talk', J, 'Jory leans on the cart wheel. «What else?»',
          *jory_talk_options),

    scene('jory_again', J,
          'Jory looks up from his broadsheet. «Back for more?»',
          opt('talk', 'Talk', '«Always.»', go='jory_talk',
              say='A word, Jory.'),
          opt('leave', 'Leave', 'He goes back to the broadsheet.',
              go='jory_bye')),

    scene('jory_wagon', J,
          "Jory's cart has doubled overnight: a second wagon stands behind it, "
          'still dusty from the capital road, and he is unpacking it with the '
          'air of a man whose luck has finally turned. «Road\'s open! And look '
          'what came down it.»',
          opt('ask_new', 'Ask what came in',
              '«Capital stock. Proper armour, proper blades, and a mining pick '
              'I\'d not touch myself, but somebody will.» He lowers his voice. '
              '«Some of it was cheap for reasons I didn\'t ask about. You\'d be '
              'surprised what a dead man\'s quartermaster will part with.»',
              go='jory_talk', say="What's new?",
              sets=['met_jory', 'jory_saw_the_wagon']),
          opt('leave', 'Leave',
              '«Don\'t be long! It won\'t last.»',
              go='jory_bye', sets=['met_jory', 'jory_saw_the_wagon'])),

    scene('jory_bye', J, 'Jory goes back to his broadsheet.', ending=True),
])


# --- Sal Mercy --------------------------------------------------------------------

SM = 'Sal Mercy'
sal_options = [
    opt('ask_road', 'Ask where she travels',
        '«Wherever there\'s somebody with coin and a reason not to go to town '
        'for it.» She jerks her chin at the mule. «Patience and I don\'t stay '
        'anywhere long. Stand still in this country and something comes up out '
        'of the ground to see why.»',
        go='sal_talk', say='Where do your roads go?',
        sets=['sal_told_of_the_roads'], unless=['sal_told_of_the_roads']),
    opt('ask_stock', 'Ask what she is carrying',
        '«Today? Whatever didn\'t sell yesterday.» She slaps a pannier. «Things '
        'a town merchant won\'t carry and a few he\'s never heard of. '
        'Different every time you find me — if you find me.»',
        go='sal_talk', say="What's on the mule today?",
        sets=['sal_told_of_her_stock'], unless=['sal_told_of_her_stock']),
    roll('rumour', '[Diplomacy] Ask what she has heard on the roads',
         "You've been on every road in the valley. What's worth knowing?",
         'diplomacy', 15, unless=['sal_rumoured'],
         success=out('«That the Mere Road\'s got a bell on it that rings for '
                     'nobody, and the men who wait by it are paid in the '
                     'Sparrow.» She taps the side of her nose. «And that '
                     'nothing that goes south from Millhaven is carrying a '
                     'child. Whatever took the Whitmore girl went west, into '
                     'the trees.»',
                     go='sal_talk',
                     sets=['sal_rumoured', 'sal_warned_of_the_mere']),
         failure=out('«That it costs to know things,» she says, «and you '
                     'aren\'t buying.»',
                     go='sal_talk', sets=['sal_rumoured'])),
    opt('ask_bounty', 'Ask who is sending things after you',
        '«Oh, you\'re on the board.» She says it the way you would tell '
        'somebody their collar was turned up. «Counting-house on Tithe Street '
        'in the capital. The Covenant keeps a book of what everybody\'s worth, '
        'and when a name in it gets heavy enough, they post it with a figure '
        'next to it. Every cutpurse and worse from here to the mines reads '
        'that board.» She looks at your packs. «Spend it, give it away, or get '
        'used to company.»',
        go='sal_talk',
        say='Something keeps finding us on the road. Something that knows '
            'what we carry.',
        sets=['sal_named_the_broker'],
        requires=['hunted_first'], unless=['sal_named_the_broker']),
    opt('leave', 'Leave', '«There aren\'t any,» says Sal Mercy, cheerfully.',
        go='sal_bye', say='Safe roads.'),
]

sal = conversation('npc_010_sal', [
    entry('sal_again', requires=['met_sal']),
    entry('sal_open'),
], [
    scene('sal_open', SM,
          'The woman with the mule looks you over the way a buyer looks over '
          'a horse. «Mercy\'s the name,» she says, «and it\'s the only thing I '
          'give away.»',
          opt('greet', 'Ask her business',
              '«Selling. Buying, if it\'s worth it. Listening, always.» The mule '
              'shifts, and its bell clanks once.',
              go='sal_talk', say='What brings you out here?',
              sets=['met_sal']),
          opt('leave', 'Leave her be', 'She is already counting again.',
              go='sal_bye', sets=['met_sal'])),
    scene('sal_talk', SM, 'Sal waits, one hand on the mule\'s neck.',
          *sal_options),
    scene('sal_again', SM,
          'Sal Mercy squints at you. «You again. Anyone would think you were '
          'following me.»',
          opt('talk', 'Talk', '«Go on, then.»', go='sal_talk',
              say='Just passing, same as you.'),
          opt('leave', 'Leave', 'The mule\'s bell clanks as you go.',
              go='sal_bye')),
    scene('sal_bye', SM, 'The mule\'s bell clanks as she shifts her weight.',
          ending=True),
])


# --- Foreman Ruel Brask ------------------------------------------------------------

B = 'Foreman Ruel Brask'
brask = conversation('npc_011_brask', [
    entry('brask_home', requires=['brask_given_the_tallies']),
    entry('brask_tallies', requires=['item_acquired_shift_tallies']),
    entry('brask_again', requires=['met_brask']),
    entry('brask_open'),
], [
    scene('brask_open', B,
          'The foreman looks up from the brass token he is turning over. «If '
          'you\'re from the Crown, the answer\'s still no. If you\'re not, '
          'mind the shaft. It\'s further down than it looks.»',
          opt('ask_board', 'Ask about the tally board',
              '«Nine went down on the last shift.» He does not look at the '
              'board. He does not need to. «A token each at the top of the '
              'shaft, and the token back at the end, and that\'s how I know '
              'who\'s still below. I\'ve had nine tokens out for a month.» '
              'He turns the one in his fingers. «This one\'s mine. I was sick '
              'that day.»',
              go='brask_talk', say="Your tally board doesn't add up.",
              sets=['met_brask', 'brask_asked_after_the_shift']),
          opt('leave', 'Mind the shaft',
              '«Most don\'t,» he says.',
              go='brask_bye', sets=['met_brask'])),

    scene('brask_talk', B, 'Brask waits, turning the token.',
          opt('ask_board', 'Ask about the shift',
              '«Nine men. A token each. None of them back.»',
              go='brask_talk', say='Tell us about the shift.',
              sets=['brask_asked_after_the_shift'],
              unless=['brask_asked_after_the_shift']),
          opt('ask_down', 'Ask what is down there',
              '«Picks. I can hear them, nights, when the winch is still. Same '
              'rhythm as a working shift.» He finally puts the token away. '
              '«Crown\'s men put a guard on the deep workings, on account of '
              'something at the bottom they wanted kept. Then the guard '
              'stopped coming up and all.»',
              go='brask_talk', say="What's down in the deep workings?",
              sets=['brask_heard_the_picks'],
              unless=['brask_heard_the_picks']),
          opt('leave', 'Leave',
              '«If you go down,» he says, «bring me their tokens. I\'ll not '
              'wipe that board till I have them.»',
              go='brask_bye', say="We'll look.")),

    scene('brask_again', B, 'Brask is on the ore cart by the board.',
          opt('talk', 'Talk to him', '«Well?»', go='brask_talk',
              say='A word, Foreman.'),
          opt('leave', 'Leave', 'He goes back to the token.', go='brask_bye')),

    scene('brask_tallies', B,
          'Brask sees the tokens in your hand, and stands up off the cart.',
          opt('give', 'Give him the tallies',
              'He counts them. He counts them again, the way you did. Then he '
              'goes to the board with a rag and wipes the chalk off it, line '
              'by line, and hangs the nine tokens on their nine hooks. «Paid '
              'off,» he says, to the board. «Shift\'s done.»',
              go='brask_bye',
              say="They were still working when we found them. They aren't "
                  'now.',
              sets=['brask_given_the_tallies']),
          opt('leave', 'Not yet', 'He sits back down, slowly.',
              go='brask_bye')),

    scene('brask_home', B,
          'The tally board is clean, and every hook on it is full. Brask nods '
          'to you and goes on with his work.',
          ending=True),
    scene('brask_bye', B, 'The winch creaks in the wind above the shaft.',
          ending=True),
])


# Side quests follow from what already happens in the story, so these flags
# are derived rather than written by hand at every outcome that earns them:
# whatever uncovers a lie, and whatever settles the liar, says so.
DERIVED = [
    ({'caught_wendel_lying'}, 'wendel_lie_uncovered'),
    ({'wendel_confessed', 'wendel_fled', 'wendel_reported'}, 'wendel_dealt_with'),
    ({'caught_hale_lying'}, 'hale_lie_uncovered'),
    ({'hale_confessed', 'hale_stonewalled'}, 'hale_confronted'),
]


def derive(value):
    if isinstance(value, dict):
        flags = value.get('setFlags')
        if flags:
            for sources, derived in DERIVED:
                if sources & set(flags) and derived not in flags:
                    flags.append(derived)
        for v in value.values():
            derive(v)
    elif isinstance(value, list):
        for v in value:
            derive(v)


document = {'conversations': [
    thorne, marta, aldus, harrow, wendel, liora, hale, malachai, jory,
    sal, brask,
]}
derive(document)
h.save('conversations.json', quoted(document))
print(f"{len(document['conversations'])} conversations, "
      f"{sum(len(c['scenes']) for c in document['conversations'])} scenes, "
      f"{sum(len(s.get('options', [])) for c in document['conversations'] for s in c['scenes'])} choices")
