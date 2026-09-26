"""Runs the content scripts in order, rewriting what they own.

    python3 regenerate.py          rewrite the campaign's data from the scripts
    python3 regenerate.py --check  change nothing; fail if the scripts and the
                                   committed data disagree

The order matters: the hunt and weather scripts rewrite the hunters and the
weather wholesale, and the scenes script then puts their words back on them.
CI runs --check, so an edit made by hand to anything a script owns fails there
instead of being quietly undone the next time the scripts run.
"""
import difflib
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CAMPAIGN = os.path.dirname(HERE)

ORDER = [
    'build_hunt.py',
    'build_weather.py',
    'build_scenes.py',
    'build_conversations.py',
]


def run(campaign):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    for script in ORDER:
        subprocess.run([sys.executable, os.path.join(campaign, 'tools', script)],
                       check=True, env=env)


def data_files(campaign):
    return sorted(f for f in os.listdir(campaign) if f.endswith('.json'))


def check():
    with tempfile.TemporaryDirectory() as tmp:
        copy = os.path.join(tmp, 'campaign')
        shutil.copytree(CAMPAIGN, copy,
                        ignore=shutil.ignore_patterns('__pycache__'))
        run(copy)
        stale = []
        for name in data_files(CAMPAIGN):
            with open(os.path.join(CAMPAIGN, name), encoding='utf-8') as f:
                committed = f.read()
            with open(os.path.join(copy, name), encoding='utf-8') as f:
                written = f.read()
            if committed != written:
                stale.append(name)
                diff = difflib.unified_diff(
                    committed.splitlines(), written.splitlines(),
                    f'{name} (committed)', f'{name} (from the scripts)',
                    lineterm='', n=1)
                print('\n'.join(list(diff)[:40]))
    if stale:
        print(f'\nThe scripts and the data disagree about {", ".join(stale)}. '
              'Make the edit in the script that owns it, then run '
              'regenerate.py.')
        return 1
    print(f'The scripts reproduce all {len(data_files(CAMPAIGN))} data files.')
    return 0


if __name__ == '__main__':
    if sys.argv[1:] == ['--check']:
        sys.exit(check())
    if sys.argv[1:]:
        sys.exit(__doc__)
    run(CAMPAIGN)
