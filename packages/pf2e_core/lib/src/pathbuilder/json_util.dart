/// Pathbuilder's sentinel for an unset free-text field.
const pathbuilderUnsetSentinel = 'Not set';

/// Reads a string, trimming whitespace and mapping Pathbuilder's `"Not set"`
/// sentinel and empty strings to null.
///
/// Exported names can carry leading whitespace — the reference payload's name
/// is `" Korash Blackearth"` — so trimming is not optional.
String? readOptionalString(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  if (value.isEmpty || value == pathbuilderUnsetSentinel) return null;
  return value;
}

/// Reads a required string, falling back to [fallback] when absent.
String readString(Object? raw, {String fallback = ''}) =>
    readOptionalString(raw) ?? fallback;

/// Reads an int from a value that may arrive as int, double, or string.
int readInt(Object? raw, {int fallback = 0}) {
  if (raw is int) return raw;
  if (raw is double) return raw.round();
  if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

int? readOptionalInt(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is double) return raw.round();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

bool readBool(Object? raw, {bool fallback = false}) {
  if (raw is bool) return raw;
  if (raw is String) return raw.trim().toLowerCase() == 'true';
  return fallback;
}

/// Reads a list, returning an empty list for null or a non-list value.
List<Object?> readList(Object? raw) => raw is List ? raw : const [];

/// Reads a string list, trimming and dropping empties.
List<String> readStringList(Object? raw) => [
      for (final item in readList(raw))
        if (readOptionalString(item) case final s?) s,
    ];

/// Reads a map, returning an empty map for null or a non-map value.
Map<String, Object?> readMap(Object? raw) =>
    raw is Map ? raw.cast<String, Object?>() : const {};

/// Element [index] of a positional tuple, or null when the tuple is shorter.
///
/// Pathbuilder's `feats` entries vary in length — background-granted feats
/// carry four elements where selected feats carry seven — so every access
/// past index 3 has to tolerate a short tuple.
Object? tupleAt(List<Object?> tuple, int index) =>
    index < tuple.length ? tuple[index] : null;
