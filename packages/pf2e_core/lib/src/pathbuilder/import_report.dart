/// How much a note should worry the caller.
enum ImportSeverity {
  /// Worth surfacing, but the import is faithful.
  info,

  /// The import succeeded but something was dropped, guessed, or looked wrong.
  warning,

  /// The payload could not be read.
  error,
}

/// One observation made while importing.
class ImportNote {
  const ImportNote(this.severity, this.code, this.message);

  const ImportNote.info(String code, String message)
      : this(ImportSeverity.info, code, message);
  const ImportNote.warning(String code, String message)
      : this(ImportSeverity.warning, code, message);
  const ImportNote.error(String code, String message)
      : this(ImportSeverity.error, code, message);

  final ImportSeverity severity;

  /// Stable machine-readable identifier, e.g. `unknown_proficiency`.
  final String code;
  final String message;

  @override
  String toString() => '[${severity.name}] $code: $message';
}

/// Everything the importer noticed about one payload.
///
/// Pathbuilder's schema carries legacy fields, cross-system leakage, and
/// unfinished builds, so a silent import is the wrong default: anything
/// dropped or guessed is recorded here for the caller to show the player.
class ImportReport {
  ImportReport();

  final List<ImportNote> notes = [];

  void add(ImportNote note) => notes.add(note);

  void info(String code, String message) =>
      notes.add(ImportNote.info(code, message));
  void warn(String code, String message) =>
      notes.add(ImportNote.warning(code, message));
  void error(String code, String message) =>
      notes.add(ImportNote.error(code, message));

  Iterable<ImportNote> bySeverity(ImportSeverity s) =>
      notes.where((n) => n.severity == s);

  List<ImportNote> get warnings =>
      bySeverity(ImportSeverity.warning).toList(growable: false);
  List<ImportNote> get errors =>
      bySeverity(ImportSeverity.error).toList(growable: false);

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;

  bool hasCode(String code) => notes.any((n) => n.code == code);

  @override
  String toString() => notes.isEmpty
      ? 'clean import'
      : notes.map((n) => n.toString()).join('\n');
}

/// Thrown when a payload cannot be read at all.
class PathbuilderImportException implements Exception {
  PathbuilderImportException(this.message, [this.report]);

  final String message;
  final ImportReport? report;

  @override
  String toString() => 'PathbuilderImportException: $message';
}
