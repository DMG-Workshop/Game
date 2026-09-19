import 'dart:convert';
import 'dart:io';

import 'package:pf2e_core/pf2e_core.dart';

/// Renders a Pathbuilder export as a plain-text character sheet.
///
///   dart run pf2e_core:sheet path/to/build.json
///   cat build.json | dart run pf2e_core:sheet --report
Future<void> main(List<String> args) async {
  final showReport = args.contains('--report');
  final paths = args.where((a) => !a.startsWith('--')).toList();

  final String payload;
  if (paths.isEmpty) {
    if (stdin.hasTerminal) {
      stderr
        ..writeln('usage: sheet [--report] <build.json>')
        ..writeln('       cat build.json | sheet');
      exitCode = 64;
      return;
    }
    payload = await stdin.transform(utf8.decoder).join();
  } else {
    final file = File(paths.first);
    if (!file.existsSync()) {
      stderr.writeln('No such file: ${paths.first}');
      exitCode = 66;
      return;
    }
    payload = file.readAsStringSync();
  }

  if (payload.trim().isEmpty) {
    stderr.writeln('No input received.');
    exitCode = 65;
    return;
  }

  final ImportResult result;
  try {
    result = const PathbuilderImporter().importJson(payload);
  } on PathbuilderImportException catch (e) {
    stderr.writeln('Import failed: ${e.message}');
    exitCode = 65;
    return;
  }

  stdout.write(DerivedStats(result.character).renderSheet());

  final notes = result.report.notes;
  if (notes.isEmpty) return;
  if (showReport) {
    stdout.writeln('--- Import report ---');
    for (final note in notes) {
      stdout.writeln('  $note');
    }
  } else {
    stdout.writeln('${notes.length} import note(s), '
        '${result.report.warnings.length} warning(s). '
        'Re-run with --report for detail.');
  }
}
