import 'package:pf2e_core/pf2e_core.dart';

import 'character_revision.dart';

/// One character in a party, with every import ever taken of it.
///
/// A member is never overwritten by a re-import: a new [CharacterRevision] is
/// appended and becomes current, and the earlier ones stay readable. The
/// character belongs to the table, not to this app — it levels up in
/// Pathbuilder and arrives here again — so losing the previous state would
/// quietly break the thing that made it theirs.
class PartyMember {
  PartyMember({
    required this.id,
    required List<CharacterRevision> revisions,
  }) : _revisions = List.of(revisions) {
    if (_revisions.isEmpty) {
      throw ArgumentError.value(
          revisions, 'revisions', 'a member needs at least one import');
    }
  }

  /// Creates a member from its first import.
  factory PartyMember.fromImport({
    required String id,
    required CharacterRevision revision,
  }) =>
      PartyMember(id: id, revisions: [revision]);

  /// Stable local identifier. Pathbuilder payloads carry no id of their own,
  /// so identity is ours to assign and keep.
  final String id;

  final List<CharacterRevision> _revisions;

  /// Imports oldest first.
  List<CharacterRevision> get revisions => List.unmodifiable(_revisions);

  /// The import currently in play.
  CharacterRevision get current => _revisions.last;

  /// Every import before the current one, newest first.
  List<CharacterRevision> get history =>
      _revisions.reversed.skip(1).toList(growable: false);

  ImportedCharacter? _cached;
  String? _cachedPayload;

  /// The character as of [current], parsed once and reused.
  ImportedCharacter get character {
    if (_cached == null || _cachedPayload != current.payload) {
      _cached = current.reimport().character;
      _cachedPayload = current.payload;
    }
    return _cached!;
  }

  DerivedStats get stats => DerivedStats(character);

  String get name => character.name;
  int get level => current.level;

  /// Appends [revision] and makes it current.
  void addRevision(CharacterRevision revision) => _revisions.add(revision);

  /// Restores an earlier revision by appending a copy of it.
  ///
  /// Reverting adds to the history rather than truncating it, so an accidental
  /// revert is itself reversible.
  CharacterRevision revertTo(int index, {DateTime? at}) {
    if (index < 0 || index >= _revisions.length) {
      throw RangeError.index(index, _revisions, 'index');
    }
    final source = _revisions[index];
    final restored = CharacterRevision(
      importedAt: at ?? DateTime.now(),
      payload: source.payload,
      level: source.level,
      className: source.className,
      buildCode: source.buildCode,
      note: 'reverted to import ${index + 1} of ${_revisions.length}',
    );
    _revisions.add(restored);
    return restored;
  }

  /// A loose identity fingerprint, used to spot a re-import of this character.
  ///
  /// Name, ancestry and class are the fields that survive levelling; level,
  /// feats and gear all change and are useless for matching.
  static String fingerprintOf(ImportedCharacter character) => [
        character.name.trim().toLowerCase(),
        character.ancestry.trim().toLowerCase(),
        character.className.trim().toLowerCase(),
      ].join('|');

  String get fingerprint => fingerprintOf(character);

  Map<String, Object?> toJson() => {
        'id': id,
        'revisions': [for (final r in _revisions) r.toJson()],
      };

  static PartyMember fromJson(Map<String, Object?> json) => PartyMember(
        id: json['id']!.toString(),
        revisions: [
          for (final r in (json['revisions'] as List))
            CharacterRevision.fromJson((r as Map).cast<String, Object?>()),
        ],
      );

  @override
  String toString() => '$name ($className $level)';

  String get className => current.className;
}
