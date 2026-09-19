# Game

A text-first Pathfinder 2e RPG for phones, tablets, and the browser, built
around importing a character you already play.

## The idea

You export your character from [Pathbuilder 2e](https://pathbuilder2e.com/) and
play *that* character — not a generic one. The pitch is the gap between table
sessions: short, no GM needed, and it feeds the campaign rather than competing
with it. Phone-shaped first, but a text log and an input bar scale up to a
tablet or a desktop browser far more gracefully than a tactical grid would.

## Design decisions so far

**Text-first, MUD-flavoured.** The character's identity lives in its skill
choices, not its attack bonus. Korash — the reference build — has Lore: Undead
at +14, Deception and Diplomacy at +13, and Religion at untrained +0. A text
game where skills open doors makes every one of those choices load-bearing; a
tactical combat sim reduces him to "+15 to hit" and the import becomes
decoration.

It also collapses the largest cost. No sprites, tilesets, or animation means
effort goes into the rules engine, and world content becomes data rather than
level design.

Three amendments to the 90s inspiration:

- **Tap-composed commands, not a typed parser.** Verbs and targets as chips
  that assemble the same grammar underneath. The log reads like a MUD; the
  input does not fight a touchscreen. Because both forms compile to the same
  grammar, the typed parser comes back for free wherever there is a real
  keyboard — the web and tablet builds can offer it as a power-user path while
  phones stay on chips.
- **Zones, not a flat world.** PF2e is more spatial than it looks — flanking,
  reach, and reactions are core. Abstract positions (engaged / near / far)
  preserve that without a grid.
- **MUD as presentation, not architecture.** The persistent shared world is
  what the later multiplayer layer becomes, not a launch requirement.

**A party of four.** PF2e is balanced for four PCs, so importing four and
running them together means published encounter budgets work as written,
with no invented scaling. Dual Class stays an optional toggle rather than a
load-bearing fix.

**Solo first, async-ready.** One device to start, with state modelled so
asynchronous multiplayer drops in later. Async also keeps a larger group
viable: turn latency is fatal to a shared tactical grid and harmless to text.

**Flutter + Dart**, which reaches Android, iOS, tablets, and the web from one
codebase, with the rules engine as a pure package carrying no Flutter
dependency, so it stays headlessly testable and the UI stays swappable.

Targeting the browser is not free, and it constrains the engine rather than
just the UI. Dart integers are 64-bit when compiled natively but are backed by
doubles on the web, exact only to 2^53. Any arithmetic that relies on 64-bit
wraparound would therefore give different answers in a browser than on a
phone — which for dice means a replayed turn diverging between a PC and a
phone. The dice roller is built inside that bound deliberately; see
`packages/pf2e_core/lib/src/rules/dice.dart`.

## Layout

```
packages/
  pf2e_core/     Rules engine and Pathbuilder importer (pure Dart, no Flutter)
  game_core/     Scene engine and session state (depends on pf2e_core)
```

The Flutter app is not started yet, and deliberately so: the game is playable
in a terminal first. A text log with an input bar *is* the product, so proving
the loop costs a CLI rather than an app shell. If it is not good in a terminal,
a UI will not save it.

`pf2e_core` proves that a Pathbuilder export contains enough to rebuild a full
character sheet. `game_core` proves the loop on top of it.

## Status

`pf2e_core` imports a real export, reproduces its sheet exactly, and resolves
checks against it. Every sheet value is pinned against the Pathbuilder display
for build 472704:

```
$ dart run pf2e_core:sheet packages/pf2e_core/test/fixtures/korash.json

Korash Blackearth - Magus/Necromancer 6
Orc Dragonblood | Undertaker | Medium
Str 19 (+4), Dex 10 (+0), Con 14 (+2), Int 18 (+4), Wis 10 (+0), Cha 16 (+3)
AC 25  HP 70  Speed 20ft  Class DC 22
Fortitude +12 (E)  Reflex +10 (E)  Will +10 (E)
```

Check resolution covers the four degrees of success and the natural 20/1
shifts, driven by a seeded roller whose sequence is fixed by its seed and can
be snapshotted mid-turn — which is what makes an asynchronous turn replayable
on someone else's device.

**The game is playable.** A short adventure ships as data, and the menu makes
the whole design argument on its own:

```
$ dart run game_core:play --seed=12 --choices=examine-body,descend

  1. Examine the body properly  [Lore: Undead +14 vs DC 18]
  2. Recite the funeral rites over him  [Religion +0 vs DC 15]
  3. Offer the widow your condolences  [Diplomacy +13 vs DC 20]
  4. Collect your fee and go

> examine-body

  ~ Lore: Undead: d20(16) +14 = 30 vs DC 18 -> Critical Success
```

The same character is expert at reading a corpse and untrained at reciting
over it. In a combat sim both collapse to "+15 to hit"; here they are the
content.

## Next

The gap between importing a character and *running* one is the real work. A
level 6 character references roughly 80 distinct rules elements — feats, class
features, spells, focus spells — and implementing those, not parsing them, is
the bulk of the project. Near-term order:

1. Character store: import, re-import on level-up without losing history, party
   of four.
2. Zone-based encounters over the derived statblock.
4. Feat and spell effects, as a growing set with explicit gaps surfaced to the
   player rather than silently ignored. These live in a separate content
   package: rules *text and names* are licensed material, rules *arithmetic* is
   not, so keeping them apart scopes the licence obligation to one place. See
   [NOTICE.md](NOTICE.md).

Re-import has to be non-destructive. The character levels up at the table, in
Pathbuilder; if this app grants its own XP the two copies drift and the thing
that made it *their* character quietly breaks.

## Development

```
cd packages/pf2e_core
dart pub get
dart test
dart analyze
```

## Licence and attribution

**Not distributable yet.** This project implements Pathfinder 2e rules
mechanics, which Paizo publishes under the ORC License. That licence requires
the distributed work to carry the licence text and an attribution notice, and
neither is complete here — `LICENSES/ORC_LICENSE.txt` is a placeholder.

See [NOTICE.md](NOTICE.md) for what is outstanding, what must never be included
(trademarks, Golarion setting material, adventure content, art), and why the
licence boundary and the engine/content boundary should be the same line.

"Pathfinder" is a trademark of Paizo Inc. This project is unaffiliated with
Paizo and with Pathbuilder. None of this is legal advice.
