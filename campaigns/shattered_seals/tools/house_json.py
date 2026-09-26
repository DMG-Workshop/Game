"""JSON in the campaign's house style: objects expanded, scalar arrays and
short scalar maps kept on one line."""
import json


def _scalar(v):
    return not isinstance(v, (dict, list))


def dumps(obj, indent=0, width=100):
    pad = '  ' * indent
    inner = '  ' * (indent + 1)
    if isinstance(obj, dict):
        if not obj:
            return '{}'
        if all(_scalar(v) for v in obj.values()):
            one = '{ ' + ', '.join(f'{json.dumps(k, ensure_ascii=False)}: '
                                   f'{json.dumps(v, ensure_ascii=False)}'
                                   for k, v in obj.items()) + ' }'
            if len(one) + len(pad) <= width and len(obj) <= 6:
                return one
        items = [f'{inner}{json.dumps(k, ensure_ascii=False)}: {dumps(v, indent + 1, width)}'
                 for k, v in obj.items()]
        return '{\n' + ',\n'.join(items) + '\n' + pad + '}'
    if isinstance(obj, list):
        if not obj:
            return '[]'
        # Identifiers and numbers sit on one line; sentences get one each.
        if all(_scalar(v) and not (isinstance(v, str) and len(v) > 40)
               for v in obj):
            return '[' + ', '.join(json.dumps(v, ensure_ascii=False) for v in obj) + ']'
        items = [f'{inner}{dumps(v, indent + 1, width)}' for v in obj]
        return '[\n' + ',\n'.join(items) + '\n' + pad + ']'
    return json.dumps(obj, ensure_ascii=False)


def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def save(path, obj):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(dumps(obj) + '\n')
