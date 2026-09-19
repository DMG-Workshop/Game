# Notices and attribution

## Status: incomplete

This project implements Pathfinder Second Edition rules mechanics. Paizo
publishes the Pathfinder Second Edition Remaster rules under the **ORC License**
(Open RPG Creative License), which requires a distributed work to include the
licence text and an attribution notice identifying the Licensed Material it
draws on.

Neither is complete here yet:

- `LICENSES/ORC_LICENSE.txt` is a placeholder, not the licence.
- The attribution notice below is a scaffold with unfilled fields.

Both must be finished before anything is distributed. The exact required
wording and notice format have to come from the licence text itself — they are
not reproduced from memory anywhere in this repository.

## Attribution notice (to be completed)

```
ATTRIBUTION NOTICE

Licensed Material: <the Paizo works this project draws mechanics from,
                    e.g. Pathfinder Player Core, Pathfinder GM Core,
                    Pathfinder Monster Core — list each edition and year>

Copyright Notice:  <as stated in each source work>

Licensor:          Paizo Inc.

Reserved Material: <as designated by each Licensor in its own notice>
```

Fill each field from the notice printed in the source works themselves, not
from summaries. If any mechanics are drawn from **pre-Remaster** Pathfinder 2e
content, that material is under the OGL 1.0a rather than ORC and needs its own
separate Section 15 notice — the two licences do not substitute for one another.

## What this project must never include

Open rules mechanics are not the same thing as Paizo's protected material. The
following stay out regardless of licence:

- **Trademarks and logos.** "Pathfinder" is a trademark of Paizo Inc. The app
  must not be named or branded to use it or to imply endorsement.
- **Setting material.** Golarion, its deities, nations, organisations, and
  cosmology. One example already in this repository: the reference character
  has `Lore: First World`, and the First World is Golarion cosmology rather
  than generic rules content.
- **Adventure content**, adventure paths, and published scenarios.
- **Iconic characters** and any Paizo artwork.
- Anything a Licensor designates as **Reserved Material** in its own notice.

Paizo's **Community Use Policy** is a separate permission from ORC and is
explicitly non-commercial. It does not cover a paid application, so it is not
a fallback here.

## Licensed material in this repository today

- `packages/pf2e_core/test/fixtures/korash.json` — a real Pathbuilder export.
  It names roughly eighty Paizo rules elements (class features, feats, spells,
  focus spells, heritages, a background). This is the largest concentration of
  licensed expression currently in the tree.
- `packages/pf2e_core/lib/src/model/skill.dart` — the sixteen core skill names,
  needed to map Pathbuilder's proficiency keys.

Everything else in `pf2e_core` is arithmetic and schema handling.

## Why that distinction drives the architecture

Game mechanics and systems are not themselves copyrightable; their expression
is. `10 + level + proficiency + ability` is a method of operation. "Arcane
Cascade", "Spellstrike", "Bon Mot" and the rules text describing them are
expression, and a database of them is exactly what the licence governs.

So the licence boundary and the engineering boundary should be the same line:

- **Engine** (`pf2e_core` and successors) — resolution, arithmetic, degrees of
  success, the turn model. Original work, no licence obligation attached.
- **Content** (a separate package, not yet written) — feat, spell, and feature
  names and their rules text. Licensed material, carrying its own attribution
  notice.

Keeping content in one swappable package scopes the obligation to a single
place instead of smearing it through the codebase, makes attribution mechanical
rather than a manual audit, and leaves the engine shippable with different
content entirely.

The test fixture is the one deliberate exception: it is licensed material
sitting inside the engine package because pinning the importer against a real
export is worth more than a synthetic one. If that ever becomes awkward, the
fix is to move fixtures into the content package rather than to fake the data.

## Pathbuilder

Pathbuilder 2e is a third-party application by Redrazors, unaffiliated with
Paizo and with this project. Its JSON schema is Redrazors' work, not Paizo's,
and is a separate consideration from the ORC obligations above. No Pathbuilder
data is bundled or scraped here; users supply their own export. Pathbuilder's
export dialog advertises the Pathmuncher Foundry VTT module, so third-party
import is a sanctioned use of that export.

## Project code

No licence has been chosen for this project's own source. That is a deliberate
gap, not an oversight: a commercial game generally should not carry a
permissive open-source licence, and the choice is the owner's to make.

## Not legal advice

The above is engineering guidance for keeping the obligations tractable. Have
the licence notices reviewed by a lawyer before any commercial release.
