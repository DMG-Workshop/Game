# Pathfinder Remaster content

This directory is the project's **content package**: the part that is
Licensed Material under the ORC License, kept apart from the engine as the
root `NOTICE.md` describes. Everything here is swappable; the engine in
`packages/` runs on whatever tables this directory holds, or on none.

## What is here

- `spells.json` — for each spell, its name (to match a Pathbuilder export)
  and the numbers needed to resolve it in a fight: rank, what it is rolled
  against, range, damage, and how the damage grows when heightened. No rules
  text is stored, and effects the engine cannot run (persistent damage,
  conditions) are left out.

## Before release

- **Check every number against Player Core.** These were written from memory
  of the Remaster rules, not copied from the book.
- **Attribution.** The ORC Attribution Notice line for each Paizo work used
  must be copied from the notice printed in that book; see the root
  `NOTICE.md`, section (b). It is still outstanding.
