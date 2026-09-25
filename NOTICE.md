# Notices and attribution

This project implements Pathfinder Second Edition rules mechanics. Paizo
publishes the Remaster rules under the **ORC License**, whose Section III makes
the grant conditional on four notice statements. Each is given below.

The licence itself is committed at `LICENSES/ORC_License.pdf`, unaltered. See
`LICENSES/README.md` for why no text transcription accompanies it.

---

## (a) ORC Notice

> This product is licensed under the ORC License located at the Library of
> Congress at TX 9-307-067 and available online at various locations. All
> warranties are disclaimed as set forth therein.

This statement is quoted from Section III.a and must appear verbatim in any
distributed build.

## (b) Attribution Notice

**Licensed Material this project is based on:**

```
[Title of Work], [Copyright Notice], [Author Credit Information]
```

One line per Paizo work whose Licensed Material is actually Used — in practice
the Remaster core volumes. **Copy each line from the notice printed in that
book**, not from memory, a wiki, or a summary: the licence asks for the credit
"worded in any accurate and reasonable manner so requested by such parties",
and only the book states how Paizo asks to be credited.

Section III.b.i also requires crediting **all upstream licensors** named in
Paizo's own attribution notice, not only Paizo. Those names are listed in the
same place, and are easy to miss.

**How this project wishes to be credited** (Section III.b.ii):

```
Marching Order, [Copyright Notice], DMG Workshop
```

Only the copyright line is still outstanding, and it needs a year and a
holder rather than a guess.

## (c) Reserved Material Notice

The following are this project's **Reserved Material** and are not offered
under the ORC License:

- The campaign **Shattered Seals** and its title.
- The world of **Valorheim**, its history, factions, and cosmology, including
  the Crimson Covenant, the Shadow Vessel, and the seals.
- All regions, towns, zones, and rooms: Millhaven, Ravencrest, Whisperwood,
  Valorheim Capital, Thornhaven, the Bloodstone Mines, and every location
  within them.
- All characters: Captain Thorne Ironhelm, Queen Liora, Malachai Vex, Elara
  and Marta Whitmore, Brother Aldus, King Aldric, and the rest of the cast.
- All narrative prose, dialogue, room descriptions, ambiance and weather text.
- Named unique items: the Shadowbane Dagger, the Monarch's Vestment, Shadow
  Ripper, and similar.
- The software in this repository, including the rules engine, the importer,
  and the scene engine.

This designation costs nothing and protects the setting, so it is worth
keeping current as content is written. Note the licence's own caveat: where a
designation conflicts with the definition of Licensed Material, the definition
controls — declaring a game mechanic Reserved does not make it so.

## (d) Expressly Designated Licensed Material

None. No element of this project's Reserved Material is offered to prospective
licensees under the ORC License.

Change this only deliberately: it is a one-way door, and the grant is
irrevocable.

---

## What stays out regardless of licence

Open mechanics are not the same as Paizo's protected material:

- **Trademarks and logos.** "Pathfinder" is a trademark of Paizo Inc. The
  product must not be named or branded to use it, or to imply endorsement.
- **Setting material.** Golarion, its deities, nations, organisations and
  cosmology. Watch for this leaking in through mechanics: a Pathbuilder export
  can carry `Lore: First World`, and the First World is Golarion cosmology
  rather than generic rules content.
- **Adventure content**, adventure paths, and published scenarios.
- **Iconic characters** and any Paizo artwork.
- Anything a Licensor designates as **Reserved Material** in its own notice.

Paizo's **Community Use Policy** is a separate permission from the ORC License
and is explicitly non-commercial. It does not cover a paid application, so it
is not a fallback here.

## Pre-Remaster material

Pre-Remaster Pathfinder 2e content is under the **OGL 1.0a**, not the ORC
License, and needs its own separate Section 15 notice. The two do not
substitute for one another. A character import can mix both eras without
saying so, so this is worth checking per source rather than assuming.

## Where licensed expression sits in this repository

- `packages/pf2e_core/test/fixtures/` — real Pathbuilder exports naming Paizo
  rules elements (class features, feats, spells, heritages, backgrounds).
  These are test fixtures, not characters in the game.
- `packages/pf2e_core/lib/src/model/skill.dart` — the sixteen core skill
  names, needed to map Pathbuilder's proficiency keys.

Everything else in `pf2e_core` is arithmetic and schema handling, and
everything in `game_core` is original.

## Why that distinction drives the architecture

Game mechanics and systems are not themselves copyrightable; their expression
is. `10 + level + proficiency + ability` is a method of operation. "Arcane
Cascade", "Spellstrike", "Bon Mot" and the rules text describing them are
expression, and a database of them is exactly what the licence governs.

So the licence boundary and the engineering boundary are the same line:

- **Engine** (`pf2e_core`, `game_core`) — resolution, arithmetic, degrees of
  success, the turn model, the scene graph. Original work.
- **Content** — feat, spell and feature names with their rules text. Licensed
  material, belonging in its own package with its own attribution.

Keeping content in one swappable package scopes the obligation to a single
place instead of smearing it through the codebase, makes attribution
mechanical rather than a manual audit, and leaves the engine shippable with
different content entirely.

Campaign content — Valorheim, its rooms, NPCs and prose — is original and
carries no ORC obligation. It is Reserved Material under (c) above.

## Pathbuilder

Pathbuilder 2e is a third-party application by Redrazors, unaffiliated with
Paizo and with this project. Its JSON schema is Redrazors' work, not Paizo's,
and is a separate consideration from the ORC obligations above. No Pathbuilder
data is bundled or scraped here; users supply their own export. Pathbuilder's
export dialog advertises the Pathmuncher Foundry VTT module, so third-party
import is a sanctioned use of that export.

## Project source licence

No licence has been chosen for this project's own source. That is a deliberate
gap, not an oversight: a commercial game generally should not carry a
permissive open-source licence, and the choice is the owner's to make.

## Not legal advice

The above is engineering guidance for keeping the obligations tractable, and
the bracketed fields in (b) are the parts a lawyer should see filled in. Have
the notices reviewed before any commercial release.
