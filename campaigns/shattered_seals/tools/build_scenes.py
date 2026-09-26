"""Writes the words around every fight and interaction into the campaign.

Run after build_hunt.py and build_weather.py, which rewrite the hunters and
the weather these attach to; regenerate.py runs them in that order.
Idempotent.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import house_json as h  # noqa: E402
from scenes_fights import FIGHTS, VOICES  # noqa: E402
from scenes_world import (HUNTER_SCENES, ITEM_LINES, NPC_BARKS,  # noqa: E402
                          REST_LINES, ROOM_AMBIANCE, SHOP_LINES,
                          WEATHER_REMARKS)

os.chdir(os.path.dirname(HERE))


def attach(items, key, field, table):
    missing = set(table)
    for item in items:
        if item[key] in table:
            item[field] = table[item[key]]
            missing.discard(item[key])
    assert not missing, f'nothing to attach {field} to: {sorted(missing)}'


best = h.load('bestiary.json')
attach(best['encounters'], 'encounter_id', 'scene', FIGHTS)
attach(best['creatures'], 'creature_id', 'voice', VOICES)
h.save('bestiary.json', best)

hunt = h.load('hunt.json')
attach(hunt['hunters'], 'creature', 'scene', HUNTER_SCENES)
h.save('hunt.json', hunt)

locations = h.load('locations.json')
attach(locations['rooms'], 'room_id', 'ambiance', ROOM_AMBIANCE)
h.save('locations.json', locations)

items = h.load('world_items.json')
for item in items['items']:
    for field, line in ITEM_LINES.get(item['item_id'], {}).items():
        item[field] = line
h.save('world_items.json', items)

npcs = h.load('npcs_and_dialogue.json')
attach(npcs['npcs'], 'npc_id', 'barks', NPC_BARKS)
h.save('npcs_and_dialogue.json', npcs)

economy = h.load('economy.json')
attach(economy['shops'], 'shop_id', 'lines', SHOP_LINES)
h.save('economy.json', economy)

weather = h.load('weather.json')
for w in weather['weather']:
    w['remark'] = WEATHER_REMARKS[w['id']]
weather['rest'] = REST_LINES
h.save('weather.json', weather)

lines = (
    sum(len(s.get(k, [])) for s in FIGHTS.values()
        for k in ('ambiance', 'opening', 'bloodied', 'first_down', 'victory',
                  'defeat', 'flee')) + len(FIGHTS)
    + sum(len(s.get(k, [])) for s in HUNTER_SCENES.values()
          for k in ('ambiance', 'opening', 'victory', 'defeat', 'flee'))
    + len(HUNTER_SCENES)
    + sum(len(v[k]) for v in VOICES.values()
          for k in ('taunts', 'hurt', 'dying'))
    + sum(len(v) for v in ROOM_AMBIANCE.values())
    + sum(len(v) for v in ITEM_LINES.values())
    + sum(len(v) for s in SHOP_LINES.values() for v in s.values())
    + len(WEATHER_REMARKS)
    + sum(len(v) for v in REST_LINES.values())
    + sum(len(v) for v in NPC_BARKS.values())
)
print(f'{len(FIGHTS)} fights, {len(HUNTER_SCENES)} hunters, {len(VOICES)} '
      f'voices, {len(ROOM_AMBIANCE)} rooms, {len(ITEM_LINES)} objects, '
      f'{len(SHOP_LINES)} shops: {lines} lines')
