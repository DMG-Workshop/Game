# Content scripts

Part of Shattered Seals' data is written by these scripts rather than by hand,
because it is easier to write prose, tables and statblocks in Python than in
escaped JSON. The JSON beside this folder is still what the game loads. The
scripts own the parts listed below, and CI checks that the two agree.

```
python3 tools/regenerate.py          # rewrite the data from the scripts
python3 tools/regenerate.py --check  # change nothing; fail if they disagree
```

Plain Python 3, no packages. They can be run from anywhere.

## What each script owns

| Script | Writes |
| --- | --- |
| `build_hunt.py` | `hunt.json`, and the hunters' statblocks (`c_hunt_*`) in `bestiary.json` |
| `build_weather.py` | `weather.json`, which rooms have a roof, and how long the library stair takes |
| `build_scenes.py` | every fight's scene, creature voices, the hunters' scenes, room ambiance, what objects say when taken or broken, NPC barks, shop lines, weather remarks and rest lines. Lines live in `scenes_fights.py` and `scenes_world.py` |
| `build_conversations.py` | `conversations.json`, every NPC's conversation |

`regenerate.py` runs them in that order. The hunt and weather scripts rewrite
their parts wholesale, and the scenes script then puts the words back on them.

Everything else — rooms, NPCs, items, gear, shops, quests — is edited by hand
in the JSON. A hand edit to something a script owns fails `--check`: make the
edit in the script instead and regenerate.

`house_json.py` is the formatter the scripts save with: objects spread over
lines, short lists and small flat objects kept on one line. Use it for any
data edit made from Python, so the diff shows only what changed.
`gear.json` and `campaign_arcs.json` keep a hand layout it does not
reproduce; edit those as text.

## `applied/`

One-time patches that have already been run, kept as the record of what they
added: the Mere Road and Under-Archive wrong turns and their cast
(`build_world.py`), and the side quests for every region
(`build_side_quests.py`). Both refuse to run a second time.

Like the data they write, these scripts are Reserved Material: see
[NOTICE.md](../../../NOTICE.md).
