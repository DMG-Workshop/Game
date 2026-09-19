/// A pure-Dart Pathfinder 2e rules core and Pathbuilder 2e character importer.
///
/// This package has no Flutter dependency and no I/O: it takes a Pathbuilder
/// export and produces a character plus every derived number on its sheet, so
/// the rules can be tested headlessly and reused behind any UI.
library;

export 'src/model/ability.dart';
export 'src/model/character.dart';
export 'src/model/feat.dart';
export 'src/model/gear.dart';
export 'src/model/proficiency.dart';
export 'src/model/skill.dart';
export 'src/model/spellcasting.dart';
export 'src/model/variant_rules.dart';
export 'src/pathbuilder/import_report.dart';
export 'src/pathbuilder/pathbuilder_importer.dart';
export 'src/rules/check_resolver.dart';
export 'src/rules/degree_of_success.dart';
export 'src/rules/derived_stats.dart';
export 'src/rules/dice.dart';
