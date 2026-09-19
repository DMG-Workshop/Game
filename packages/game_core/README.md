# game_core

The scene engine and session state for the text-first Pathfinder 2e RPG.

Pure Dart, no I/O and no UI: a client renders `currentScene` and
`availableOptions()`, then calls `choose()`. The same loop drives the terminal
build, the phone, the tablet, and the browser.

It depends on `pf2e_core` for the character and the check resolution, and
knows nothing about Pathfinder rules itself. That split is deliberate: rules
are one problem, narrative is another.

## Playing

```
dart run game_core:play
dart run game_core:play --seed=12 --choices=examine-body,descend,read-ledger
```

`--choices` plays a scripted sequence instead of reading stdin, which makes a
playthrough reproducible and testable. With a fixed `--seed`, the same choices
always produce the same rolls.

## Content is data

Adventures are JSON, so scenes can be written, reviewed, and shipped without a
rebuild:

```json
{
  "id": "examine-body",
  "label": "Examine the body properly",
  "check": { "stat": "lore:undead", "dc": 18 },
  "outcomes": {
    "criticalSuccess": { "text": "...", "setFlags": ["knows-thrall"] },
    "success":         { "text": "...", "setFlags": ["suspicious"] },
    "failure":         { "text": "..." },
    "criticalFailure": { "text": "...", "setFlags": ["alarmed"] }
  }
}
```

`stat` is any key `DerivedStats.statByKey` understands — a core skill, a Lore
subskill (`lore:local undead`), a save, or `perception`.

Options can be gated on flags or on a minimum proficiency rank:

```json
"requires": {
  "flags": ["suspicious"],
  "notFlags": ["alarmed"],
  "minProficiency": { "stat": "lore:undead", "rank": "expert" }
}
```

A gated option is hidden rather than shown-and-refused, so the menu reflects
what this particular character can actually do. Only an expert in the dead is
offered the chance to unpick a binding by hand.

Authors may write only `success` and `failure`; a critical then falls back to
its ordinary counterpart rather than dropping the player into silence.

## Validation

`AdventureLoader` refuses to load content that would strand a player: a
transition to a scene that does not exist, a duplicate id, a dead end not
marked as an ending, an option with neither a check nor an outcome, or a check
with no outcomes at all.

Stat keys are checked separately via `unresolvableStats`, because a typo like
`lore:undad` is only detectable against a real character sheet.

## Sessions are replayable

`GameSession.snapshot()` captures the current scene, the flags, and the dice
roller's exact position. Restoring from it continues the session without
changing any future roll — which is what an asynchronous turn needs in order
to be verified on someone else's device.

## The sample adventure

`assets/adventures/the_quiet_wake.json` is a short original scene set written
to exercise one character's asymmetry: Korash reads a corpse at +14 and
recites over it at +0, and the menu shows both. It is original fiction and
carries no Paizo setting material — see `NOTICE.md` at the repository root.
