import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:pf2e_core/pf2e_core.dart';
import 'package:test/test.dart';

String korashPayload() =>
    File('../pf2e_core/test/fixtures/korash.json').readAsStringSync();

String selaPayload() => File('test/fixtures/sela.json').readAsStringSync();

/// Korash's payload with its level raised, standing in for a level-up at the
/// table followed by a fresh export.
String korashAtLevel(int level) {
  final json = jsonDecode(korashPayload()) as Map<String, Object?>;
  (json['build']! as Map)['level'] = level;
  return jsonEncode(json);
}

/// Korash's payload with an extra feat, standing in for a rebuild.
String korashWithFeat(String featName) {
  final json = jsonDecode(korashPayload()) as Map<String, Object?>;
  final build = json['build']! as Map;
  (build['feats']! as List).add([featName, null, 'Skill Feat', 6]);
  return jsonEncode(json);
}

CharacterStore newStore({int maxMembers = Party.defaultMaxMembers}) {
  var n = 0;
  return CharacterStore(
    party: Party(id: 'p1', name: 'The Table', maxMembers: maxMembers),
    idGenerator: () => 'pc-${++n}',
    clock: () => DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('first import', () {
    test('adds a new member', () {
      final store = newStore();
      final proposal = store.prepare(korashPayload());
      expect(proposal.isNewCharacter, isTrue);
      expect(proposal.confidence, MatchConfidence.none);

      final member = store.commit(proposal);
      expect(member.id, 'pc-1');
      expect(member.name, 'Korash Blackearth');
      expect(member.level, 6);
      expect(store.party.size, 1);
      expect(member.revisions, hasLength(1));
    });

    test('surfaces the importer\'s own warnings for the player to see', () {
      final store = newStore();
      final proposal = store.prepare(korashPayload());
      // Korash's export has an unresolved Free Archetype choice.
      expect(proposal.warnings, isNotEmpty);
      expect(proposal.warnings.join(' '), contains('Basic Maneuver'));
    });

    test('propagates an unreadable payload', () {
      expect(() => newStore().prepare('not json'),
          throwsA(isA<PathbuilderImportException>()));
    });
  });

  group('re-import after levelling', () {
    test('matches the existing member and lists what changed', () {
      final store = newStore();
      store.importDirect(korashPayload());

      final proposal = store.prepare(korashAtLevel(7));
      expect(proposal.isNewCharacter, isFalse);
      expect(proposal.confidence, MatchConfidence.likely);
      expect(proposal.changes, contains('level 6 -> 7'));
    });

    test('appends a revision rather than overwriting', () {
      final store = newStore();
      final member = store.importDirect(korashPayload());
      expect(member.level, 6);

      store.importDirect(korashAtLevel(7));
      expect(store.party.size, 1, reason: 'should update, not duplicate');
      expect(member.revisions, hasLength(2));
      expect(member.level, 7);
      // The earlier state is still readable.
      expect(member.history, hasLength(1));
      expect(member.history.first.level, 6);
      expect(member.revisions.first.reimport().character.level, 6);
    });

    test('reports feats gained between imports', () {
      final store = newStore();
      store.importDirect(korashPayload());
      final proposal = store.prepare(korashWithFeat('Battle Medicine'));
      expect(proposal.changes.join(' '), contains('Battle Medicine'));
      expect(proposal.changes.join(' '), contains('gained 1 feat'));
    });

    test('matches exactly when the same build code is reused', () {
      final store = newStore();
      store.importDirect(korashPayload(), buildCode: '472704');
      final proposal = store.prepare(korashAtLevel(7), buildCode: '472704');
      expect(proposal.confidence, MatchConfidence.exact);
    });

    test('warns when an import would lower the stored level', () {
      final store = newStore();
      store.importDirect(korashAtLevel(7));
      final proposal = store.prepare(korashPayload());
      expect(proposal.warnings.join(' '), contains('lower than the stored'));
    });

    test('can be forced to add a twin instead of updating', () {
      final store = newStore();
      store.importDirect(korashPayload());
      final proposal = store.prepare(korashPayload());
      expect(proposal.isNewCharacter, isFalse);

      store.commitAsNew(proposal);
      expect(store.party.size, 2);
    });
  });

  group('history', () {
    test('reverting appends rather than truncating', () {
      final store = newStore();
      final member = store.importDirect(korashPayload());
      store.importDirect(korashAtLevel(9));
      expect(member.level, 9);

      member.revertTo(0);
      expect(member.level, 6);
      expect(member.revisions, hasLength(3),
          reason: 'a revert is itself reversible');
      expect(member.current.note, contains('reverted'));
    });

    test('rejects an out-of-range revision', () {
      final member = newStore().importDirect(korashPayload());
      expect(() => member.revertTo(5), throwsRangeError);
      expect(() => member.revertTo(-1), throwsRangeError);
    });

    test('a member cannot exist with no imports', () {
      expect(
          () => PartyMember(id: 'x', revisions: const []), throwsArgumentError);
    });
  });

  group('roster', () {
    test('holds four by default and refuses a fifth', () {
      final store = newStore();
      for (var i = 0; i < 4; i++) {
        store.commitAsNew(store.prepare(korashPayload()));
      }
      expect(store.party.isFull, isTrue);
      expect(() => store.commitAsNew(store.prepare(korashPayload())),
          throwsA(isA<PartyException>()));
    });

    test('warns on a full party before the attempt fails', () {
      final store = newStore(maxMembers: 1);
      store.importDirect(korashPayload());
      final proposal = store.prepare(selaPayload());
      expect(proposal.isNewCharacter, isTrue);
      expect(proposal.warnings.join(' '), contains('is full'));
    });

    test('removes by id', () {
      final store = newStore();
      final member = store.importDirect(korashPayload());
      expect(store.party.remove(member.id), same(member));
      expect(store.party.isEmpty, isTrue);
      expect(store.party.remove('nope'), isNull);
    });

    test('refuses a duplicate id', () {
      final party = Party(id: 'p', name: 'P');
      final revision = CharacterRevision(
        importedAt: DateTime.utc(2026),
        payload: korashPayload(),
        level: 6,
        className: 'Magus',
      );
      party.add(PartyMember.fromImport(id: 'same', revision: revision));
      expect(
          () =>
              party.add(PartyMember.fromImport(id: 'same', revision: revision)),
          throwsA(isA<PartyException>()));
    });
  });

  group('picking who rolls', () {
    test('finds the best member for a statistic', () {
      final store = newStore();
      store.importDirect(korashPayload());
      store.importDirect(selaPayload());

      // Sela is an expert sneak with +4 Dex; Korash is untrained at +0.
      final stealth = store.party.bestFor('stealth')!;
      expect(stealth.member.name, 'Sela Finch');
      expect(stealth.stat.total, 14);

      // Korash knows the dead; Sela has no Lore: Undead at all.
      final lore = store.party.bestFor('lore:undead')!;
      expect(lore.member.name, 'Korash Blackearth');
      expect(lore.stat.total, 14);
    });

    test('ranks the whole party, best first', () {
      final store = newStore();
      store.importDirect(korashPayload());
      store.importDirect(selaPayload());

      final ranked = store.party.rankedFor('perception');
      expect(ranked, hasLength(2));
      expect(ranked.first.member.name, 'Sela Finch'); // +12 vs Korash's +8
      expect(ranked.first.stat.total, 12);
      expect(ranked.last.stat.total, 8);
    });

    test('skips members who cannot resolve the statistic at all', () {
      final store = newStore();
      store.importDirect(selaPayload());
      // Only Korash has Lore: Undead, and he is not in this party.
      expect(store.party.bestFor('lore:undead'), isNull);
      expect(store.party.rankedFor('lore:undead'), isEmpty);
    });

    test('returns null for an unknown statistic', () {
      final store = newStore();
      store.importDirect(korashPayload());
      expect(store.party.bestFor('basketweaving'), isNull);
    });
  });

  group('persistence', () {
    test('a party round-trips through JSON with its history intact', () {
      final store = newStore();
      store.importDirect(korashPayload(), buildCode: '472704');
      store.importDirect(korashAtLevel(8), buildCode: '472704');
      store.importDirect(selaPayload());

      final restored = Party.fromJson(
          jsonDecode(jsonEncode(store.party.toJson())) as Map<String, Object?>);

      expect(restored.id, 'p1');
      expect(restored.maxMembers, 4);
      expect(restored.size, 2);

      final korash = restored.members.first;
      expect(korash.name, 'Korash Blackearth');
      expect(korash.level, 8);
      expect(korash.revisions, hasLength(2));
      expect(korash.revisions.first.level, 6);
      expect(korash.revisions.first.buildCode, '472704');

      // The derived sheet survives the round trip because the raw payload did.
      expect(korash.stats.statByKey('lore:undead')!.total, 16); // level 8 now
    });
  });
}
