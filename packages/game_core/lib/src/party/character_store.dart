import 'package:pf2e_core/pf2e_core.dart';

import 'character_revision.dart';
import 'party.dart';
import 'party_member.dart';

/// How sure the store is that an import is a character the party already has.
enum MatchConfidence {
  /// Nothing in the party looks like this character.
  none,

  /// Name, ancestry and class all match an existing member.
  likely,

  /// The same Pathbuilder export code was used before.
  exact,
}

/// What an import would do, before it does it.
///
/// Imports are never applied silently. A re-import after a level-up should
/// update a member, a genuinely new character should join, and the difference
/// between the two is a judgement the player makes — the store only proposes.
class ImportProposal {
  const ImportProposal({
    required this.payload,
    required this.imported,
    required this.revision,
    required this.confidence,
    this.match,
    this.changes = const [],
    this.warnings = const [],
  });

  final String payload;

  /// The parsed character, with the importer's own notes attached.
  final ImportResult imported;

  /// The revision that would be recorded.
  final CharacterRevision revision;

  /// The member this appears to be, when one was found.
  final PartyMember? match;
  final MatchConfidence confidence;

  /// Human-readable differences from the matched member, e.g. `level 6 -> 7`.
  final List<String> changes;

  /// Things worth showing the player before they confirm.
  final List<String> warnings;

  bool get isNewCharacter => match == null;

  ImportedCharacter get character => imported.character;

  @override
  String toString() => isNewCharacter
      ? 'new character: ${character.name}'
      : 'update ${match!.name} (${confidence.name}): ${changes.join(', ')}';
}

/// Manages a party's imported characters and their history.
class CharacterStore {
  CharacterStore({
    required this.party,
    String Function()? idGenerator,
    DateTime Function()? clock,
  })  : _idGenerator = idGenerator ?? _defaultIdGenerator,
        _clock = clock ?? DateTime.now;

  final Party party;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  static int _counter = 0;
  static String _defaultIdGenerator() =>
      'pc-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  /// Reads [payload] and works out what importing it would mean.
  ///
  /// Throws [PathbuilderImportException] if the payload cannot be read at all.
  ImportProposal prepare(String payload, {String? buildCode}) {
    final imported = const PathbuilderImporter().importJson(payload);
    final character = imported.character;

    final revision = CharacterRevision(
      importedAt: _clock(),
      payload: payload,
      level: character.level,
      className: character.className,
      buildCode: buildCode,
    );

    final match = _findMatch(character, buildCode);
    final warnings = <String>[
      for (final note in imported.report.warnings) note.message,
    ];

    if (match == null) {
      if (party.isFull) {
        warnings.add('${party.name} is full at ${party.maxMembers} members; '
            'remove one before adding another.');
      }
      return ImportProposal(
        payload: payload,
        imported: imported,
        revision: revision,
        confidence: MatchConfidence.none,
        warnings: warnings,
      );
    }

    final confidence = _confidenceFor(match.member, buildCode);
    final changes = _changesBetween(match.member, character);
    if (character.level < match.member.level) {
      warnings.add('This import is level ${character.level}, lower than the '
          'stored level ${match.member.level}.');
    }

    return ImportProposal(
      payload: payload,
      imported: imported,
      revision: revision,
      match: match.member,
      confidence: confidence,
      changes: changes,
      warnings: warnings,
    );
  }

  /// Applies [proposal]: updating the matched member, or adding a new one.
  ///
  /// Updating appends a revision; nothing is discarded.
  PartyMember commit(ImportProposal proposal) {
    final match = proposal.match;
    if (match == null) return commitAsNew(proposal);
    match.addRevision(proposal.revision);
    return match;
  }

  /// Adds [proposal] as a separate member even if it matched an existing one.
  ///
  /// Twins happen: two players at the same table can build the same ancestry
  /// and class and give them the same name.
  PartyMember commitAsNew(ImportProposal proposal) {
    final member = PartyMember.fromImport(
      id: _idGenerator(),
      revision: proposal.revision,
    );
    party.add(member);
    return member;
  }

  /// Convenience for the common path: prepare and immediately commit.
  ///
  /// Use [prepare] wherever the player should confirm first, which is anywhere
  /// a match was found.
  PartyMember importDirect(String payload, {String? buildCode}) =>
      commit(prepare(payload, buildCode: buildCode));

  ({PartyMember member, bool byBuildCode})? _findMatch(
      ImportedCharacter character, String? buildCode) {
    if (buildCode != null) {
      for (final member in party.members) {
        for (final revision in member.revisions) {
          if (revision.buildCode == buildCode) {
            return (member: member, byBuildCode: true);
          }
        }
      }
    }
    final found = party.findByFingerprint(PartyMember.fingerprintOf(character));
    return found == null ? null : (member: found, byBuildCode: false);
  }

  MatchConfidence _confidenceFor(PartyMember member, String? buildCode) {
    if (buildCode != null) {
      for (final revision in member.revisions) {
        if (revision.buildCode == buildCode) return MatchConfidence.exact;
      }
    }
    return MatchConfidence.likely;
  }

  List<String> _changesBetween(PartyMember member, ImportedCharacter next) {
    final current = member.character;
    final changes = <String>[];

    void compare(String label, Object? before, Object? after) {
      final a = before?.toString().trim() ?? '';
      final b = after?.toString().trim() ?? '';
      if (a != b) changes.add('$label $a -> $b');
    }

    compare('name', current.name, next.name);
    compare('level', current.level, next.level);
    compare('class', current.className, next.className);
    compare('dual class', current.dualClassName ?? 'none',
        next.dualClassName ?? 'none');
    compare('ancestry', current.ancestry, next.ancestry);
    compare('heritage', current.heritage, next.heritage);
    compare('background', current.background, next.background);

    final beforeFeats = {for (final f in current.feats) f.name};
    final afterFeats = {for (final f in next.feats) f.name};
    final gained = afterFeats.difference(beforeFeats);
    final lost = beforeFeats.difference(afterFeats);
    if (gained.isNotEmpty) {
      changes.add('gained ${gained.length} feat(s): ${gained.join(', ')}');
    }
    if (lost.isNotEmpty) {
      changes.add('lost ${lost.length} feat(s): ${lost.join(', ')}');
    }

    return changes;
  }
}
