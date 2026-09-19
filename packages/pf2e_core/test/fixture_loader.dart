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

/// Korash Blackearth, an Orc Magus/Necromancer 6 exported from Pathbuilder
/// build 472704. Every expected value in these tests was read off the
/// Pathbuilder character sheet for this build, not computed by this package.
ImportResult loadKorash() => loadFixture('korash');
