"""Pathfinder's creature-building tables, and a statblock built from them.

Moderate AC, HP and saves, and high or moderate Strike attack and damage,
indexed from level -1, so everything written from here sits on one curve.
Kept apart from any one script so every creature is built the same way.
"""

# Index = level + 1, levels -1..24.
AC = [14, 15, 15, 17, 18, 20, 21, 23, 24, 26, 27, 29, 30, 32, 33, 35, 36, 38,
      39, 41, 42, 44, 45, 47, 48, 50]
HP = [7, 15, 20, 30, 45, 60, 75, 95, 115, 135, 155, 175, 195, 215, 235, 255,
      275, 295, 315, 335, 355, 375, 400, 430, 460, 500]
ATTACK_HIGH = [8, 8, 9, 11, 12, 14, 15, 17, 18, 20, 21, 23, 24, 26, 27, 29,
               30, 32, 33, 35, 36, 38, 39, 41, 42, 44]
ATTACK_MOD = [6, 6, 7, 9, 10, 12, 13, 15, 16, 18, 19, 21, 22, 24, 25, 27, 28,
              30, 31, 33, 34, 36, 37, 39, 40, 42]
DAMAGE_HIGH = ['1d4+1', '1d6+2', '1d6+3', '1d10+4', '1d10+6', '2d8+5',
               '2d8+7', '2d8+9', '2d10+9', '2d10+11', '2d10+13', '2d12+13',
               '2d12+15', '3d10+14', '3d10+16', '3d10+18', '3d12+17',
               '3d12+18', '3d12+19', '3d12+20', '4d10+20', '4d10+22',
               '4d10+24', '4d10+26', '4d12+24', '4d12+26']
DAMAGE_MOD = ['1d4', '1d4+2', '1d6+2', '1d8+4', '1d8+6', '2d6+5', '2d6+6',
              '2d6+8', '2d8+8', '2d8+9', '2d8+11', '2d10+11', '2d10+12',
              '3d8+12', '3d8+14', '3d8+15', '3d10+14', '3d10+15', '3d10+16',
              '3d10+17', '4d8+17', '4d8+19', '4d8+20', '4d8+22', '4d10+20',
              '4d10+22']
SAVE_MOD = [5, 6, 7, 8, 9, 11, 12, 14, 15, 16, 18, 19, 21, 22, 23, 25, 26, 28,
            29, 30, 32, 33, 35, 36, 37, 38]
SAVE_HIGH = [8, 9, 10, 11, 12, 14, 15, 17, 18, 19, 21, 22, 24, 25, 26, 28, 29,
             30, 32, 33, 35, 36, 38, 39, 40, 42]
SAVE_LOW = [2, 3, 4, 5, 6, 8, 9, 11, 12, 13, 15, 16, 18, 19, 20, 22, 23, 25,
            26, 27, 29, 30, 32, 33, 34, 36]

SAVES = {'high': SAVE_HIGH, 'moderate': SAVE_MOD, 'low': SAVE_LOW}


def statblock(cid, name, level, *, style, saves, description, traits,
              attacks, specials, speed=25):
    i = level + 1
    ac = AC[i]
    hp = HP[i]
    if style == 'brute':
        ac -= 2
        hp = round(hp * 1.25)
    elif style == 'skirmisher':
        ac += 1
        hp = round(hp * 0.85)
    fort, ref, will = (SAVES[s][i] for s in saves)
    out_attacks = []
    for a in attacks:
        primary = a.get('primary', False)
        entry = {
            'name': a['name'],
            'bonus': ATTACK_HIGH[i] if primary else ATTACK_MOD[i],
            'damage': DAMAGE_HIGH[i] if primary else DAMAGE_MOD[i],
            'damage_type': a['type'],
            'reach': a.get('reach', 'engaged'),
        }
        if a.get('traits'):
            entry['traits'] = a['traits']
        if a.get('on_critical'):
            entry['on_critical'] = a['on_critical']
        out_attacks.append(entry)
    return {
        'creature_id': cid,
        'name': name,
        'level': level,
        'description': description,
        'ac': ac,
        'hp': hp,
        'perception': SAVE_MOD[i] + (2 if style == 'skirmisher' else 0),
        'fortitude': fort,
        'reflex': ref,
        'will': will,
        'speed': speed,
        'traits': traits,
        'attacks': out_attacks,
        'specials': specials,
    }
