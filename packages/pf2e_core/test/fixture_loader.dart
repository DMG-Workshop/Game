import 'dart:io';

import 'package:pf2e_core/pf2e_core.dart';

/// Loads a Pathbuilder fixture from `test/fixtures`.
ImportResult loadFixture(String name) {
  final file = File('test/fixtures/$name.json');
  if (!file.existsSync()) {
    throw StateError('Missing fixture: ${file.path}');
  }
  return const PathbuilderImporter().importJson(file.readAsStringSync());
}

/// Mira Quell, a Human Wizard/Witch 6 with Free Archetype and Ancestry
/// Paragon. Written by hand in Pathbuilder 2e's export format, with the
/// quirks real exports have: a name with a leading space, "Not set"
/// sentinels, spell lists out of rank order, feats granted through parent
/// and child choices, a Starfinder skill or two. The expected values in
/// these tests are worked out from the rules, line by line.
ImportResult loadMira() => loadFixture('mira');
