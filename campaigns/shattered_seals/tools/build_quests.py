"""Writes the thirty side quests in side_quests.py into the campaign:
each as an arc in campaign_arcs.json, and whatever is to be found as an
object in world_items.json, there only once the quest is taken.

What this script owns it removes and writes again, so it can be run any
number of times; everything else in those files is left alone. The asking
and the handing-in are conversation, and build_conversations.py writes
those.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import house_json as h  # noqa: E402
from side_quests import NAMES, QUESTS, flags, item_id  # noqa: E402

os.chdir(os.path.dirname(HERE))


def _find(name):
    for article in ('A ', 'An ', 'The '):
        if name.startswith(article):
            return f'Find {article.lower()}{name[len(article):]}'
    return f'Find {name}'


def arc(q):
    taken, conditions, done = flags(q)
    objectives = []
    for i, ((kind, data), condition) in enumerate(
            zip(q['objectives'], conditions)):
        if len(q['objectives']) == 1:
            task = q['task']
        elif kind == 'fight':
            task = data['task']
        elif kind == 'word':
            task = f'Ask {NAMES[data["npc"]]}'
        else:
            task = _find(data['name'])
        objectives.append({'id': i + 1, 'task': task,
                           'condition': condition})
    objectives.append({'id': len(objectives) + 1,
                       'task': f'Go back to {NAMES[q["giver"]]}',
                       'condition': done})
    return {
        'arc_id': f'side_sq_{q["key"]}',
        'name': q['name'],
        'kind': 'side',
        'zone': q['zone'],
        'reward': {'gp': q['gp'], 'xp': q['xp']},
        'levels': q['levels'],
        'start_trigger': taken,
        'objectives': objectives,
    }


def objects(q):
    taken, conditions, _ = flags(q)
    out = []
    for i, ((kind, data), condition) in enumerate(
            zip(q['objectives'], conditions)):
        if kind != 'item':
            continue
        out.append({
            'item_id': item_id(q, i),
            'name': data['name'],
            'location': data['room'],
            'in_room': data['in_room'],
            'description': data['description'],
            'takeable': True,
            'hidden_until': [taken],
            'acquire_flags': [condition],
            'on_take': data['on_take'],
            'say_on_take': data['say'],
        })
    return out


arcs = [arc(q) for q in QUESTS]
items = [o for q in QUESTS for o in objects(q)]

doc = h.load('campaign_arcs.json')
mine = {a['arc_id'] for a in arcs}
doc['arcs'] = [a for a in doc['arcs'] if a['arc_id'] not in mine] + arcs
h.save('campaign_arcs.json', doc)

doc = h.load('world_items.json')
mine = {i['item_id'] for i in items}
doc['items'] = [i for i in doc['items'] if i['item_id'] not in mine] + items
h.save('world_items.json', doc)

print(f'{len(arcs)} side quests, {len(items)} things to find')
