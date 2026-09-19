# Game

A text-first Pathfinder 2e RPG for Android and iOS, built around importing a
character you already play.

## The idea

You export your character from [Pathbuilder 2e](https://pathbuilder2e.com/) and
play *that* character — not a generic one. The pitch is the gap between table
sessions: short, phone-shaped, no GM needed, and it feeds the campaign rather
than competing with it.

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
  input does not fight a touchscreen.
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

**Flutter + Dart**, with the rules engine as a pure package carrying no
Flutter dependency, so it stays headlessly testable and the UI stays
swappable.

## Layout

```
packages/
  pf2e_core/     Rules engine and Pathbuilder importer (pure Dart, no Flutter)
```

The Flutter app is not started yet. `pf2e_core` is the foundation: it proves
the riskiest assumption — that a Pathbuilder export contains enough to rebuild
a full character sheet — before any UI exists.

## Status

`pf2e_core` imports a real export and reproduces its sheet exactly. Every
value is pinned against the Pathbuilder display for build 472704:

```
$ dart run pf2e_core:sheet packages/pf2e_core/test/fixtures/korash.json

Korash Blackearth - Magus/Necromancer 6
Orc Dragonblood | Undertaker | Medium
Str 19 (+4), Dex 10 (+0), Con 14 (+2), Int 18 (+4), Wis 10 (+0), Cha 16 (+3)
AC 25  HP 70  Speed 20ft  Class DC 22
Fortitude +12 (E)  Reflex +10 (E)  Will +10 (E)
```

## Next

The gap between importing a character and *running* one is the real work. A
level 6 character references roughly 80 distinct rules elements — feats, class
features, spells, focus spells — and implementing those, not parsing them, is
the bulk of the project. Near-term order:

1. Character store: import, re-import on level-up without losing history, party
   of four.
2. Skill checks and degrees of success — the smallest complete game loop.
3. Zone-based encounters over the derived statblock.
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
