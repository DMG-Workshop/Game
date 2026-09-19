# pf2e_core

A pure-Dart Pathfinder 2e rules core and Pathbuilder 2e character importer.

No Flutter dependency, no I/O in the library: it takes a Pathbuilder export and
produces a character plus every derived number on its sheet. That keeps the
rules testable headlessly and reusable behind any UI.

## Usage

```dart
import 'package:pf2e_core/pf2e_core.dart';

final result = const PathbuilderImporter().importJson(payload);
final stats = DerivedStats(result.character);

print(stats.armorClass);                       // 25
print(stats.skill(CoreSkill.deception)!.total); // 13
print(stats.lore('Undead')!.total);             // 14

for (final note in result.report.notes) {
  print(note); // anything dropped, guessed, or inconsistent
}
```

There is a CLI for eyeballing an import against Pathbuilder's own display:

```
dart run pf2e_core:sheet test/fixtures/korash.json --report
cat build.json | dart run pf2e_core:sheet
```

## Getting a payload

Pathbuilder's **Export JSON** dialog gives a numeric build code, which the web
endpoint serves as `{"success": true, "build": {...}}`. The in-app file export
may hand you the bare build object instead, so the importer accepts both.

Note that Pathbuilder's *share* links (`launch.html?build=...`) appear to use a
different ID space from the JSON export codes — a share ID is not necessarily a
valid export ID, and the two should not be used interchangeably.

## Schema notes

The export format carries a decade of accumulated legacy. Everything below is
handled by the importer and pinned by a test; the reference payload is
`test/fixtures/korash.json`, an Orc Magus/Necromancer 6.

| Trap | Handling |
| --- | --- |
| `name` can carry leading whitespace | Trimmed |
| `"Not set"` sentinel for gender/age/deity | Mapped to null |
| `alignment` persists post-Remaster | Kept, flagged, unused |
| `weapons[].str` is the **striking rune**, `abilities.str` is Strength | Separate types |
| `feats` tuples vary in length (4 or 7 elements) | Bounds-checked accessors |
| Feat parent keys are concatenated with no delimiter | Matched whole, never parsed apart |
| `specials` and `feats` overlap (e.g. Reactive Strike) | De-duplicated, reported |
| Free Archetype / Ancestry Paragon have no field | Inferred from feat source labels |
| `spells` arrives out of rank order (0, 3, 2, 1) | Sorted by `spellLevel`, never by index |
| `prepared` may repeat a spell | Kept: it is a slot list, not a set |
| `focusPoints` exists twice with different values | Top-level pool is authoritative |
| `piloting` / `computers` are Starfinder 2e skills | Ignored; flagged if ranked |
| `proficiencies` values are bonuses (0/2/4/6/8), not ordinals | `Proficiency` enum |

## The one rule that matters most

A check is the ability modifier plus the proficiency term, where the
proficiency term is the rank bonus **plus the character's level** — unless
untrained, which contributes nothing at all.

Getting that exception wrong inflates every untrained skill by the character's
level, and it is the most common porting bug. Korash's Crafting is `+4` (bare
Intelligence), not `+10`.

## Licence

Pathfinder 2e rules mechanics are published by Paizo under the ORC License
(Remaster) and the OGL 1.0a (pre-Remaster). This package implements rules
mechanics only. It ships no Paizo trademarks, setting material, adventure
content, or art, and it is not affiliated with or endorsed by Paizo or with
Pathbuilder. Any distributed build must carry the appropriate licence notice —
get that reviewed before shipping commercially.
