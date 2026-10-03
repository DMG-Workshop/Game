"""Writes the arms and alchemy into gear.json and economy.json.

Fifty weapons, fifty things to use up (bombs, elixirs, scrolls), and the
wands and staffs, with the shops that sell them and the bosses that drop the
best of them. Everything this script owns it removes and writes again, so it
can be run any number of times; everything else in those files is left as
it is.

The numbers are Pathfinder's (Player Core and GM Core, Remaster), written
from memory and to be checked against the books, as the content package's
NOTICE says. Where the engine cannot run part of an item — persistent
damage, a weapon's trip or shove — the item still says what it is, and the
numbers the engine does use are the ones in the book.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import house_json as h  # noqa: E402

os.chdir(os.path.dirname(HERE))

# The story's three tiers, as the flags that open each.
T2 = ['Unlock_Travel_to_Valorheim']
T3 = ['Trigger_Sundering_Earthquake_Event']


def tier(level):
    return [] if level <= 5 else T2 if level <= 12 else T3


# --- weapons -----------------------------------------------------------------
#
# (id, name, category, die, damage type, traits, price in gp, description).
# Level 0, as Pathfinder has them: anyone can buy a sword.

PLAIN = [
    ('w_101_dagger', 'Dagger', 'simple', 'd4', 'agile finesse thrown versatile-s',
     0.2, 'A plain double-edged knife with a leather grip, balanced for '
     'throwing as well as for everything else.'),
    ('w_102_shortsword', 'Shortsword', 'martial', 'd6',
     'agile finesse versatile-s', 0.9,
     'A short, broad thrusting blade of the kind the Watch issues and nobody '
     'gives back.'),
    ('w_103_rapier', 'Rapier', 'martial', 'd6', 'deadly-d8 disarm finesse', 2,
     'A long, narrow blade with a swept hilt: a duellist\'s weapon, and a '
     'capital fashion.'),
    ('w_104_longsword', 'Longsword', 'martial', 'd8', 'versatile-p', 1,
     'A knight\'s sword, or a farmer\'s grandfather\'s: straight, plain, and '
     'heavier than it looks.'),
    ('w_105_greatsword', 'Greatsword', 'martial', 'd12', 'versatile-p', 2,
     'Five feet of steel that wants both hands and most of the room.'),
    ('w_106_battle_axe', 'Battle Axe', 'martial', 'd8', 'sweep', 1,
     'A broad-bladed axe on a hickory haft, made for people, not wood.'),
    ('w_107_greataxe', 'Greataxe', 'martial', 'd12', 'sweep', 2,
     'A crescent head the width of a man\'s chest on a haft as long as a '
     'leg.'),
    ('w_108_warhammer', 'Warhammer', 'martial', 'd8', 'shove', 1,
     'A square-headed hammer with a spike behind, for armour that will not '
     'be cut.'),
    ('w_109_maul', 'Maul', 'martial', 'd12', 'shove', 3,
     'A sledge with ambitions. It does not so much hit as arrive.'),
    ('w_110_spear', 'Spear', 'simple', 'd6', 'thrown', 0.1,
     'An ash pole and a leaf-shaped head. Every farm in the valley has one '
     'behind the door.'),
    ('w_111_glaive', 'Glaive', 'martial', 'd8', 'deadly-d8 forceful reach', 1,
     'A long blade on a longer pole, for keeping something at arm\'s length '
     'and then some.'),
    ('w_112_halberd', 'Halberd', 'martial', 'd10', 'reach versatile-s', 2,
     'Axe, spike and hook on one pole: the Crown guard\'s answer to '
     'everything.'),
    ('w_113_mace', 'Mace', 'simple', 'd6', 'shove', 1,
     'A flanged iron head on a short haft. Priests like them; so do bailiffs.'),
    ('w_114_morningstar', 'Morningstar', 'simple', 'd6', 'versatile-p', 1,
     'A spiked ball on a stout handle, as subtle as it looks.'),
    ('w_115_light_hammer', 'Light Hammer', 'martial', 'd6', 'agile thrown', 0.3,
     'A smith\'s hammer that has been told it is a weapon, and believed it.'),
    ('w_116_bo_staff', 'Bo Staff', 'martial', 'd8', 'monk parry reach trip',
     0.2, 'Six feet of seasoned oak, iron-shod at both ends.'),
    ('w_117_scimitar', 'Scimitar', 'martial', 'd6', 'forceful sweep', 1,
     'A curved blade from somewhere south, made for cutting from horseback.'),
    ('w_118_flail', 'Flail', 'martial', 'd6', 'disarm sweep trip', 0.8,
     'A spiked head on a chain on a handle. The chain is the point.'),
    ('w_119_falchion', 'Falchion', 'martial', 'd10', 'forceful', 3,
     'A heavy, single-edged blade that widens toward the tip like a '
     'cleaver.'),
    ('w_120_bastard_sword', 'Bastard Sword', 'martial', 'd8', 'two-hand-d12',
     4, 'A sword long enough for two hands and light enough for one, if the '
     'one is strong.'),
    ('w_121_kukri', 'Kukri', 'martial', 'd6', 'agile finesse trip', 0.6,
     'A forward-curved knife, heavy at the tip. It chops like a hatchet.'),
    ('w_122_whip', 'Whip', 'martial', 'd4', 'disarm finesse nonlethal reach '
     'trip', 0.1, 'A drover\'s whip, plaited leather with a lead-weighted '
     'tail.'),
    ('w_123_javelin', 'Javelin', 'simple', 'd6', 'thrown', 0.1,
     'A light throwing spear, sold in bundles to people who expect to miss.'),
    ('w_124_shortbow', 'Shortbow', 'martial', 'd6', 'ranged deadly-d10', 3,
     'A hunter\'s bow, short enough to draw in a hedge.'),
    ('w_125_longbow', 'Longbow', 'martial', 'd8', 'ranged deadly-d10 volley',
     6, 'A yew bow as tall as the archer, and a good deal more patient.'),
    ('w_126_composite_shortbow', 'Composite Shortbow', 'martial', 'd6',
     'ranged deadly-d10 propulsive', 14,
     'Horn, wood and sinew glued in layers: a short bow that pulls like a '
     'long one, and lets a strong arm tell.'),
    ('w_127_composite_longbow', 'Composite Longbow', 'martial', 'd8',
     'ranged deadly-d10 propulsive volley', 20,
     'A recurved war bow of horn and sinew. The strong get more out of it.'),
    ('w_128_crossbow', 'Crossbow', 'simple', 'd8', 'ranged reload-1', 3,
     'A stirrup crossbow. Anyone can shoot one; the trick is the reloading.'),
    ('w_129_heavy_crossbow', 'Heavy Crossbow', 'simple', 'd10',
     'ranged reload-2', 4, 'A windlass crossbow for walls and gates, '
     'brought down to the road.'),
    ('w_130_hand_crossbow', 'Hand Crossbow', 'simple', 'd6', 'ranged reload-1',
     3, 'A crossbow small enough to hold in one hand and hide in a sleeve.'),
]

# (id, name, level, base weapon id, potency, striking, rarity, description,
#  special). The level band sets the runes: +1 from 2, striking from 4, +2
# from 10, greater striking from 12, +3 from 16, major striking from 19.
MAGIC = [
    ('w_131_watchmans_spear', 'Watchman\'s Spear', 2, 'w_110_spear', 1, '',
     'common', 'A Millhaven Watch spear, the haft burned with the tower-and-'
     'water mark and the head kept bright by somebody who cared.', None),
    ('w_132_reedcutter_shortbow', 'Reedcutter Shortbow', 2, 'w_124_shortbow',
     1, '', 'common', 'Strung by a fowler from the Mere and waxed against '
     'the damp. It has never once warped, which the fowler takes personally.',
     None),
    ('w_133_fenward_axe', 'Fenward Axe', 3, 'w_106_battle_axe', 1, '',
     'common', 'An old Fenward family axe with a new edge and an older '
     'rune, still keen after three generations of being lent out.', None),
    ('w_134_duellists_rapier', 'Duellist\'s Rapier', 4, 'w_103_rapier', 1,
     'striking', 'common', 'A capital rapier with a cup hilt and a crest '
     'filed off it. Whoever it belonged to left town owing Harrow money.',
     None),
    ('w_135_tollgate_arbalest', 'Tollgate Arbalest', 5,
     'w_129_heavy_crossbow', 1, 'striking', 'common', 'One of the heavy '
     'crossbows from the king\'s road tollgate, sold off when the gate shut, '
     'its windlass oiled and its sights true.', None),
    ('w_136_bridgeguard_glaive', 'Bridgeguard Glaive', 6, 'w_111_glaive', 1,
     'striking', 'common', 'Carried on the Valorheim bridges by guards who '
     'were never once called on to use it, until this year.', None),
    ('w_137_greywood_longbow', 'Greywood Longbow', 7,
     'w_127_composite_longbow', 1, 'striking', 'common', 'A war bow backed '
     'with grey horn, from the royal bowyers. The string hums a long time '
     'after the arrow has gone.', None),
    ('w_138_archive_kukri', 'Archive Kukri', 8, 'w_121_kukri', 1, 'striking',
     'uncommon', 'Issued to the Grand Library\'s night porters, which tells '
     'you something about the night porters, or about the library.', None),
    ('w_139_minebreaker_axe', 'Minebreaker Axe', 9, 'w_107_greataxe', 1,
     'striking', 'common', 'A greataxe forged from a mine-gate bar. The '
     'dwarves who made it say it remembers the weight of the mountain.',
     None),
    ('w_140_knight_captains_sword', 'Knight-Captain\'s Sword', 10,
     'w_104_longsword', 2, 'striking', 'common', 'A Crown officer\'s sword, '
     'plain where a courtier\'s would be gilded, and sharper for it.', None),
    ('w_141_palace_halberd', 'Palace Halberd', 11, 'w_112_halberd', 2,
     'striking', 'common', 'Black-lacquered and silver-chased, from the '
     'palace stair. The lacquer is for show; the edge is not.', None),
    ('w_142_whisper_blade', 'Whisper Blade', 12, 'w_102_shortsword', 2,
     'greaterStriking', 'uncommon', 'A short, matt-grey blade that makes no '
     'sound leaving the scabbard and very little going in.', None),
    ('w_143_seal_masons_maul', 'Seal-Mason\'s Maul', 13, 'w_109_maul', 2,
     'greaterStriking', 'uncommon', 'The maul the old seal-masons used to '
     'set boundary stones. Its head is the same stone as the seals.', None),
    ('w_144_quiet_court_crossbow', 'Quiet Court Crossbow', 14,
     'w_128_crossbow', 2, 'greaterStriking', 'uncommon', 'Taken from the '
     'Quiet Court\'s gate. Its bolts are stamped with names nobody in '
     'Valorheim remembers.', None),
    ('w_145_riftwalker_scimitar', 'Riftwalker Scimitar', 15, 'w_117_scimitar',
     2, 'greaterStriking', 'uncommon', 'Carried up out of the Rift by somebody '
     'who did not carry anything else up. The blade is cold in summer.',
     None),
    ('w_146_cradle_breaker', 'Cradle-Breaker', 16, 'w_105_greatsword', 3,
     'greaterStriking', 'rare', 'A greatsword the Quiet Court\'s courtiers '
     'carry and never draw, until the Cradle is threatened. It is heavier '
     'than steel ought to be.', None),
    ('w_147_last_light_longbow', 'Last Light Longbow', 17, 'w_125_longbow', 3,
     'greaterStriking', 'uncommon', 'A longbow cut from the last tree to stand '
     'on the Causeway of Names. Its arrows burn faintly in the dark.', None),
    ('w_148_unmaking_ward_flail', 'Unmaking-Ward Flail', 18, 'w_118_flail', 3,
     'greaterStriking', 'rare', 'The hierophants\' own flail, its chain '
     'links each stamped with a seal-sign, turned now against whatever '
     'wields the Unmaking.', None),
    ('w_149_quietus', 'Quietus', 19, 'w_103_rapier', 3, 'majorStriking',
     'unique', 'The rapier of the last seal-breaker, so fine it bends in the '
     'wind and so sharp it does not need to be swung hard.', None),
    ('w_150_hammer_of_the_first_seal', 'Hammer of the First Seal', 20,
     'w_108_warhammer', 3, 'majorStriking', 'unique', 'The hammer that set '
     'the first seal in the valley, a thousand years before Millhaven. The '
     'Last Quiet King kept it to make sure nobody would set another.', None),
]

# Who has the best of them: (item, creature, chance).
DROPS = {
    'w_146_cradle_breaker': ('c_quiet_courtier', 20),
    'w_148_unmaking_ward_flail': ('c_entropy_hierophant', 30),
    'w_149_quietus': ('c_last_seal_breaker', 50),
    'w_150_hammer_of_the_first_seal': ('c_quiet_king', 100),
}


def _traits(spec):
    return [t.replace('-', ' ') for t in spec.split()]


def plain_weapons():
    out = []
    for (iid, name, category, die, traits, price, text) in PLAIN:
        out.append({
            'item_id': iid,
            'name': name,
            'level': 0,
            'type': 'weapon',
            'price': price,
            'traits': [category, *_traits(traits)],
            'description': text,
            'stats': {'damage': f'1{die}', 'bonus': 0, 'magic': False},
        })
    return out


def magic_weapons():
    base = {w[0]: w for w in PLAIN}
    out = []
    for (iid, name, level, of, potency, striking, rarity, text,
         special) in MAGIC:
        b = base[of]
        rune = {'': '', 'striking': ' striking',
                'greaterStriking': ' greater striking',
                'majorStriking': ' major striking'}[striking]
        item = {
            'item_id': iid,
            'name': name,
            'level': level,
            'type': 'weapon',
        }
        if rarity != 'common':
            item['rarity'] = rarity
        item['traits'] = [b[2], 'magical', *_traits(b[4])]
        item['description'] = text
        stats = {'damage': f'1{b[3]}', 'bonus': potency, 'magic': True}
        if striking:
            stats['striking'] = striking
        item['stats'] = stats
        dice = {'': 'one', 'striking': 'two', 'greaterStriking': 'three',
                'majorStriking': 'four'}[striking]
        item['special'] = special or (
            f'{"A potency rune" if not rune else f"Potency and{rune} runes"}: '
            f'a +{potency} item bonus to attack rolls with it, and {dice} '
            f'damage {"die" if dice == "one" else "dice"}.')
        if iid in DROPS:
            creature, chance = DROPS[iid]
            item['drops'] = [{'from': creature, 'chance': chance}]
        out.append(item)
    return out


# --- bombs ---------------------------------------------------------------------
#
# Lesser, moderate, greater and major: Pathfinder's four grades, at levels 1,
# 3, 11 and 17, for 3, 10, 250 and 3000 gp, with +0 to +3 to hit and a die
# and a point of splash more at each.

GRADES = [('Lesser', 1, 3, 0), ('Moderate', 3, 10, 1), ('Greater', 11, 250, 2),
          ('Major', 17, 3000, 3)]

BOMBS = [
    ('alchemists_fire', 'Alchemist\'s Fire', 'd8', 'fire',
     'A clay flask of something that catches the moment air reaches it and '
     'keeps burning on whatever it lands on.'),
    ('acid_flask', 'Acid Flask', 'd6', 'acid',
     'A stoppered flask of green acid, wrapped in straw so it does not eat '
     'the pack on the way.'),
    ('frost_vial', 'Frost Vial', 'd6', 'cold',
     'A thin glass vial, frosted on the outside, that bursts into a cloud '
     'of rime.'),
    ('bottled_lightning', 'Bottled Lightning', 'd6', 'electricity',
     'A copper-capped bottle full of a storm, crackling faintly against the '
     'glass.'),
    ('thunderstone', 'Thunderstone', 'd4', 'sonic',
     'A stone the size of an egg that goes off like a thunderclap where it '
     'lands.'),
    ('blight_bomb', 'Blight Bomb', 'd6', 'poison',
     'A fragile gourd of yellow spores that bursts into choking dust.'),
]


def bombs():
    out = []
    n = 200
    for key, name, die, energy, text in BOMBS:
        for grade, level, price, bonus in GRADES:
            n += 1
            dice = GRADES.index((grade, level, price, bonus)) + 1
            splash = dice
            item = {
                'item_id': f'b_{n}_{key}_{grade.lower()}',
                'name': f'{grade} {name}',
                'level': level,
                'type': 'bomb',
                'price': price,
                'traits': ['consumable', 'alchemical', 'bomb', energy,
                           'splash'],
                'description': text,
                'stats': {'magic': False},
                'special': (f'Thrown, for 1 action, at an enemy no further '
                            f'than near: {dice}{die} {energy} damage on a '
                            f'hit, double on a critical, and {splash} splash '
                            f'damage even on a miss'
                            f'{f", with a +{bonus} item bonus to the attack roll" if bonus else ""}.'),
                'use': {'bomb': f'{dice}{die}', 'splash': splash},
            }
            if bonus:
                item['use']['bonus'] = bonus
            out.append(item)
    return out


# --- elixirs of life -----------------------------------------------------------

ELIXIRS = [
    ('Minor', 1, 3, '1d6'),
    ('Lesser', 5, 30, '3d6+6'),
    ('Moderate', 9, 150, '5d6+12'),
    ('Greater', 13, 600, '7d6+18'),
    ('Major', 15, 1500, '8d6+21'),
    ('True', 19, 30000, '10d6+27'),
]


def elixirs():
    out = []
    for i, (grade, level, price, heal) in enumerate(ELIXIRS):
        out.append({
            'item_id': f'e_{231 + i}_elixir_of_life_{grade.lower()}',
            'name': f'{grade} Elixir of Life',
            'level': level,
            'type': 'elixir',
            'price': price,
            'traits': ['consumable', 'alchemical', 'elixir', 'healing'],
            'description': 'A red, faintly fizzing draught that tastes of iron '
                           'and pepper and knits flesh as it goes down.',
            'stats': {'magic': False},
            'special': f'Drink it, or get it into somebody within reach, for '
                       f'1 action: it restores {heal} Hit Points, and gets '
                       f'somebody who is down back on their feet.',
            'use': {'heal': heal},
        })
    return out


# --- scrolls, wands and staffs -------------------------------------------------

SCROLL_GP = {1: 4, 2: 12, 3: 30, 4: 70, 5: 150, 6: 300, 7: 600, 8: 1300,
             9: 3000}

SCROLLS = [
    ('Heal', 1), ('Heal', 3), ('Heal', 5), ('Heal', 7), ('Heal', 9),
    ('Fireball', 3), ('Fireball', 5), ('Fireball', 7), ('Fireball', 9),
    ('Lightning Bolt', 3), ('Lightning Bolt', 6),
    ('Breathe Fire', 1), ('Breathe Fire', 2),
    ('Chilling Spray', 1),
    ('Acid Grip', 2), ('Acid Grip', 4),
    ('Horizon Thunder Sphere', 2),
    ('Cone of Cold', 5),
    ('Eclipse Burst', 7),
    ('Polar Ray', 8),
]

WANDS = [
    ('Heal', 1), ('Heal', 3), ('Heal', 5), ('Heal', 7),
    ('Fireball', 3), ('Fireball', 5), ('Fireball', 9),
    ('Lightning Bolt', 3), ('Lightning Bolt', 6),
    ('Breathe Fire', 1), ('Breathe Fire', 2),
    ('Chilling Spray', 1),
    ('Horizon Thunder Sphere', 2),
    ('Acid Grip', 2),
    ('Cone of Cold', 5),
    ('Eclipse Burst', 7),
    ('Polar Ray', 8),
]

# What a scroll or a wand of each looks like.
LOOKS = {
    'Heal': 'pale vellum, the words in the gold ink of Ashkyr\'s temples',
    'Fireball': 'scorched at the edges before anyone has read it',
    'Lightning Bolt': 'that makes the hair on your arm stand up',
    'Breathe Fire': 'that smells of a blown-out lamp',
    'Chilling Spray': 'cold to the touch, with frost in the creases',
    'Acid Grip': 'whose ink has eaten little holes in the page',
    'Horizon Thunder Sphere': 'that hums when it is unrolled',
    'Cone of Cold': 'stiff with frost that never melts',
    'Eclipse Burst': 'written in silver on black, hard to look at for long',
    'Polar Ray': 'blue-white, and so cold it burns',
}

WAND_LOOKS = {
    'Heal': 'pale ash wood bound in gold wire, warm in the hand',
    'Fireball': 'blackened oak with a red stone set in its tip',
    'Lightning Bolt': 'copper-banded, with a spark that jumps to your rings',
    'Breathe Fire': 'charred at one end, as if it had been used as a poker',
    'Chilling Spray': 'white birch, rimed with frost',
    'Acid Grip': 'green glass in a pitted silver sleeve',
    'Horizon Thunder Sphere': 'brass, humming faintly',
    'Cone of Cold': 'bone-white and so cold it sticks to the skin',
    'Eclipse Burst': 'jet, swallowing the light around it',
    'Polar Ray': 'a rod of clear ice that does not melt',
}

ORDINAL = {1: '1st', 2: '2nd', 3: '3rd'}


def _rank(r):
    return ORDINAL.get(r, f'{r}th')


def scrolls():
    out = []
    for i, (spell, rank) in enumerate(SCROLLS):
        key = spell.lower().replace(' ', '_')
        out.append({
            'item_id': f'sc_{241 + i}_scroll_{key}_{rank}',
            'name': f'Scroll of {spell} ({_rank(rank)} rank)',
            'level': rank * 2 - 1,
            'type': 'scroll',
            'price': SCROLL_GP[rank],
            'traits': ['consumable', 'magical', 'scroll'],
            'description': f'A scroll {LOOKS[spell]}.',
            'stats': {'magic': True},
            'special': f'Casts {spell} at {_rank(rank)} rank once, and '
                       f'crumbles. A caster casts it with their own spell '
                       f'attack and DC, anyone else with the scroll\'s.',
            'use': {'spell': spell, 'rank': rank},
        })
    return out


def wands():
    out = []
    for i, (spell, rank) in enumerate(WANDS):
        key = spell.lower().replace(' ', '_')
        out.append({
            'item_id': f'wd_{261 + i}_wand_of_{key}_{rank}',
            'name': f'Wand of {spell} ({_rank(rank)} rank)',
            'level': rank * 2 + 1,
            'type': 'wand',
            'traits': ['magical', 'wand'],
            'description': f'A wand of {WAND_LOOKS[spell]}.',
            'stats': {'magic': True},
            'special': f'Casts {spell} at {_rank(rank)} rank once a day, and '
                       f'is ready again after a night\'s rest. A caster '
                       f'casts it with their own spell attack and DC, anyone '
                       f'else with the wand\'s.',
            'use': {'spell': spell, 'rank': rank, 'per_day': 1},
        })
    return out


# (id, name, level, rarity, [(spell, rank)], charges, description).
STAFFS = [
    ('st_281_staff_of_fire', 'Staff of Fire', 3, 'common',
     [('Ignition', 0), ('Breathe Fire', 1)], 2,
     'A blackened oak staff, its head carved like a candle flame and always '
     'warm.'),
    ('st_282_greater_staff_of_fire', 'Greater Staff of Fire', 8, 'common',
     [('Ignition', 0), ('Breathe Fire', 2), ('Fireball', 3)], 4,
     'The same blackened oak, bound in red iron, with a coal that never goes '
     'out set in the flame.'),
    ('st_283_major_staff_of_fire', 'Major Staff of Fire', 12, 'common',
     [('Ignition', 0), ('Fireball', 3), ('Fireball', 5)], 6,
     'An iron staff with a living flame caged in its head. It singes the '
     'ceiling of any room it is kept in.'),
    ('st_284_staff_of_healing', 'Staff of Healing', 4, 'common',
     [('Heal', 1)], 2,
     'A shepherd\'s crook of pale ash, carved with Ashkyr\'s sheaf, worn '
     'smooth by hands that were not the healer\'s.'),
    ('st_285_greater_staff_of_healing', 'Greater Staff of Healing', 8,
     'common', [('Heal', 1), ('Heal', 3)], 4,
     'The temple\'s own crook, gold-capped, lent out to those who will '
     'bring it back.'),
    ('st_286_major_staff_of_healing', 'Major Staff of Healing', 12, 'common',
     [('Heal', 3), ('Heal', 5)], 6,
     'A tall staff of white wood that puts out green shoots in spring, '
     'wherever it is.'),
    ('st_287_true_staff_of_healing', 'True Staff of Healing', 16, 'uncommon',
     [('Heal', 5), ('Heal', 7)], 8,
     'The crook of the first sister of Ashkyr in the valley. The dying who '
     'touch it say they hear bread being broken.'),
    ('st_288_stormwardens_staff', 'Stormwarden\'s Staff', 10, 'uncommon',
     [('Electric Arc', 0), ('Lightning Bolt', 3), ('Lightning Bolt', 4)], 5,
     'A copper-shod staff of lightning-struck oak, carried by the wardens '
     'who keep the capital\'s roofs from burning in the summer storms.'),
    ('st_289_rimewood_staff', 'Rimewood Staff', 14, 'uncommon',
     [('Chilling Spray', 2), ('Cone of Cold', 5), ('Cone of Cold', 6)], 7,
     'White wood from a tree that grew in the Rift, cold enough to ache. '
     'Frost spreads from wherever its foot is set down.'),
    ('st_290_staff_of_the_unmaking', 'Staff of the Unmaking', 18, 'rare',
     [('Eclipse Burst', 7), ('Polar Ray', 8)], 9,
     'The hierophants\' rod of office: black, smooth, and hard to see the '
     'end of, as if it went on somewhere you could not.'),
]

STAFF_DROPS = {
    'st_290_staff_of_the_unmaking': ('c_entropy_hierophant', 25),
}


def staffs():
    out = []
    for iid, name, level, rarity, spells, charges, text in STAFFS:
        listed = ', '.join(
            f'{s} (cantrip)' if r == 0 else f'{s} ({_rank(r)})'
            for s, r in spells)
        item = {
            'item_id': iid,
            'name': name,
            'level': level,
            'type': 'staff',
        }
        if rarity != 'common':
            item['rarity'] = rarity
        item.update({
            'traits': ['magical', 'staff'],
            'description': text,
            'stats': {'magic': True},
            'special': f'Holds {listed}. {charges} charges a day, back after '
                       f'a night\'s rest: a spell costs as many as its rank, '
                       f'a cantrip none.',
            'use': {
                'spells': [{'spell': s, 'rank': r} for s, r in spells],
                'charges': charges,
            },
        })
        if iid in STAFF_DROPS:
            creature, chance = STAFF_DROPS[iid]
            item['drops'] = [{'from': creature, 'chance': chance}]
        out.append(item)
    return out


# --- who sells what --------------------------------------------------------------

def line(item, requires=()):
    entry = {'item': item['item_id']}
    if requires:
        entry['requires'] = list(requires)
    return entry


def stocked(items):
    return [line(i, tier(i['level'])) for i in items]


def shops(items):
    by = {i['item_id']: i for i in items}
    melee = [by[w[0]] for w in PLAIN if 'ranged' not in w[4]]
    ranged = [by[w[0]] for w in PLAIN if 'ranged' in w[4]]
    magic = {m[0]: by[m[0]] for m in MAGIC}
    bomb = [i for i in items if i['type'] == 'bomb']
    elixir = [i for i in items if i['type'] == 'elixir']
    scroll = [i for i in items if i['type'] == 'scroll']
    wand = [i for i in items if i['type'] == 'wand']
    staff = {i['item_id']: i for i in items if i['type'] == 'staff'}

    def healing(i):
        return 'Heal' in i['name']

    harrow = {
        'shop_id': 's_004_harrows_forge',
        'name': 'Harrow\'s Forge',
        'keeper': 'npc_004_harrow',
        'location': 'MH_005_Forge',
        # Harrow's own work, and the fletcher's on consignment.
        'stock': stocked(melee + ranged + [
            magic['w_131_watchmans_spear'],
            magic['w_132_reedcutter_shortbow'],
            magic['w_133_fenward_axe'],
            magic['w_134_duellists_rapier'],
            magic['w_135_tollgate_arbalest'],
        ]),
    }
    temple = {
        'shop_id': 's_005_temple_alms_table',
        'name': 'The Temple Alms-Table',
        'keeper': 'npc_003_aldus',
        'location': 'MH_004_Temple',
        'stock': stocked(elixir + [s for s in scroll if healing(s)]
                         + [w for w in wand if healing(w)]
                         + [staff['st_284_staff_of_healing'],
                            staff['st_285_greater_staff_of_healing'],
                            staff['st_286_major_staff_of_healing']]),
    }
    watch = {
        'shop_id': 's_006_watch_stores',
        'name': 'The Watch Stores',
        'keeper': 'npc_019_rook',
        'location': 'MH_002_GuardHall',
        'stock': stocked(bomb),
    }
    armoury = {
        'shop_id': 's_007_crown_armoury',
        'name': 'The Crown Armoury',
        'keeper': 'npc_020_venn',
        'location': 'VC_001_Plaza',
        'stock': stocked(
            [magic[k] for k in ('w_136_bridgeguard_glaive',
                                'w_137_greywood_longbow',
                                'w_138_archive_kukri',
                                'w_139_minebreaker_axe',
                                'w_140_knight_captains_sword',
                                'w_141_palace_halberd',
                                'w_142_whisper_blade',
                                'w_143_seal_masons_maul',
                                'w_144_quiet_court_crossbow')]
            + [w for w in wand if not healing(w)]
            + [staff['st_281_staff_of_fire'],
               staff['st_282_greater_staff_of_fire'],
               staff['st_283_major_staff_of_fire'],
               staff['st_288_stormwardens_staff'],
               staff['st_289_rimewood_staff']]),
    }
    # The library's copying desk, the cart and the mule are written by hand
    # in economy.json; these are what this script adds to them.
    extra = {
        's_002_mercys_mule': [
            line(magic['w_145_riftwalker_scimitar'], T3),
            line(magic['w_147_last_light_longbow'], T3),
            line(staff['st_287_true_staff_of_healing'], T3),
        ],
        's_003_library_copying_desk': stocked(
            [s for s in scroll if not healing(s)]),
    }
    return [harrow, temple, watch, armoury], extra


# --- writing it ----------------------------------------------------------------

items = (plain_weapons() + magic_weapons() + bombs() + elixirs() + scrolls()
         + wands() + staffs())
owned = {i['item_id'] for i in items}
assert len(owned) == len(items), 'duplicate item ids'

gear = h.load('gear.json')
gear['gear'] = [i for i in gear['gear'] if i['item_id'] not in owned] + items
h.save('gear.json', gear)

new_shops, extra = shops(items)
economy = h.load('economy.json')
mine = {s['shop_id'] for s in new_shops}
kept = [s for s in economy['shops'] if s['shop_id'] not in mine]
for shop in kept:
    shop['stock'] = [s for s in shop['stock'] if s['item'] not in owned]
    shop['stock'].extend(extra.get(shop['shop_id'], []))
economy['shops'] = kept + new_shops
h.save('economy.json', economy)

weapons = [i for i in items if i['type'] == 'weapon']
used = [i for i in items if i['type'] in ('bomb', 'elixir', 'scroll')]
print(f'{len(weapons)} weapons, {len(used)} consumables, '
      f'{len(wands())} wands, {len(staffs())} staffs, '
      f'{len(new_shops)} new shops')
