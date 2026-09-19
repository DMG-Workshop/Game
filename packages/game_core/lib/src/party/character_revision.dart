import 'package:pf2e_core/pf2e_core.dart';

/// One import of a character, kept forever.
///
/// The raw payload is stored rather than only the parsed result. A character
/// levels up at the table, in Pathbuilder, and is re-imported here; keeping
/// every payload means an earlier state can always be re-derived, and means a
/// later improvement to the importer can be applied retroactively to imports
/// taken before it existed.
class CharacterRevision {
  const CharacterRevision({
    required this.importedAt,
    required this.payload,
    required this.level,
    required this.className,
    this.buildCode,
    this.note,
  });

  final DateTime importedAt;

  /// The exact Pathbuilder JSON this revision came from.
  final String payload;

  /// Level at the time of import, denormalised so a history can be listed
  /// without re-parsing every payload.
  final int level;
  final String className;

  /// Pathbuilder export code, when the import came from one.
  final String? buildCode;

  /// Optional free-text note, e.g. "after the Harrow job".
  final String? note;

  /// Re-derives the character this revision recorded.
  ImportResult reimport() => const PathbuilderImporter().importJson(payload);

  Map<String, Object?> toJson() => {
        'importedAt': importedAt.toUtc().toIso8601String(),
        'payload': payload,
        'level': level,
        'className': className,
        if (buildCode != null) 'buildCode': buildCode,
        if (note != null) 'note': note,
      };

  static CharacterRevision fromJson(Map<String, Object?> json) =>
      CharacterRevision(
        importedAt: DateTime.parse(json['importedAt']!.toString()),
        payload: json['payload']!.toString(),
        level: (json['level'] as num).toInt(),
        className: json['className']!.toString(),
        buildCode: json['buildCode']?.toString(),
        note: json['note']?.toString(),
      );

  @override
  String toString() => '$className $level @ ${importedAt.toIso8601String()}';
}
