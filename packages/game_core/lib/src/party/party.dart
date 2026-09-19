import 'package:pf2e_core/pf2e_core.dart';

import 'party_member.dart';

/// Thrown when a roster change would break the party's rules.
class PartyException implements Exception {
  PartyException(this.message);

  final String message;

  @override
  String toString() => 'PartyException: $message';
}

/// A roster of imported characters.
///
/// The default cap is four because Pathfinder 2e's encounter budgets assume
/// four player characters. Importing four and running them together means
/// published encounter maths works as written, with no invented scaling — it
/// is the reason the party exists at all, rather than a single hero.
class Party {
  Party({
    required this.id,
    required this.name,
    List<PartyMember>? members,
    this.maxMembers = defaultMaxMembers,
  }) : _members = List.of(members ?? const []) {
    if (maxMembers < 1) {
      throw ArgumentError.value(maxMembers, 'maxMembers', 'must be at least 1');
    }
    if (_members.length > maxMembers) {
      throw PartyException(
          'A party of $maxMembers cannot hold ${_members.length} members.');
    }
  }

  /// The party size Pathfinder 2e encounter budgets are written for.
  static const int defaultMaxMembers = 4;

  final String id;
  final String name;
  final int maxMembers;

  final List<PartyMember> _members;

  List<PartyMember> get members => List.unmodifiable(_members);

  int get size => _members.length;
  bool get isFull => _members.length >= maxMembers;
  bool get isEmpty => _members.isEmpty;

  PartyMember? memberById(String id) {
    for (final member in _members) {
      if (member.id == id) return member;
    }
    return null;
  }

  /// Adds [member], refusing to exceed [maxMembers] or repeat an id.
  void add(PartyMember member) {
    if (isFull) {
      throw PartyException(
          '$name already has $maxMembers members; remove one first.');
    }
    if (memberById(member.id) != null) {
      throw PartyException('Member "${member.id}" is already in the party.');
    }
    _members.add(member);
  }

  /// Removes a member by id, returning it, or null when it was not present.
  ///
  /// Removing a member drops its import history with it, so callers that mean
  /// "bench for now" should keep the member and track that separately.
  PartyMember? remove(String id) {
    for (var i = 0; i < _members.length; i++) {
      if (_members[i].id == id) return _members.removeAt(i);
    }
    return null;
  }

  /// A member whose loose identity fingerprint matches [fingerprint].
  PartyMember? findByFingerprint(String fingerprint) {
    for (final member in _members) {
      if (member.fingerprint == fingerprint) return member;
    }
    return null;
  }

  /// The member with the best bonus for [statKey], and that bonus.
  ///
  /// This is what a party-wide skill check needs: when the group wants someone
  /// to read a corpse, it matters that one of them is an expert and the rest
  /// are untrained. Returns null when no member can resolve the statistic.
  ({PartyMember member, CheckValue stat})? bestFor(String statKey) {
    PartyMember? bestMember;
    CheckValue? bestStat;
    for (final member in _members) {
      final stat = member.stats.statByKey(statKey);
      if (stat == null) continue;
      if (bestStat == null || stat.total > bestStat.total) {
        bestMember = member;
        bestStat = stat;
      }
    }
    if (bestMember == null || bestStat == null) return null;
    return (member: bestMember, stat: bestStat);
  }

  /// Every member's bonus for [statKey], best first.
  List<({PartyMember member, CheckValue stat})> rankedFor(String statKey) {
    final rows = <({PartyMember member, CheckValue stat})>[];
    for (final member in _members) {
      final stat = member.stats.statByKey(statKey);
      if (stat != null) rows.add((member: member, stat: stat));
    }
    rows.sort((a, b) => b.stat.total.compareTo(a.stat.total));
    return rows;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'maxMembers': maxMembers,
        'members': [for (final m in _members) m.toJson()],
      };

  static Party fromJson(Map<String, Object?> json) => Party(
        id: json['id']!.toString(),
        name: json['name']!.toString(),
        maxMembers: (json['maxMembers'] as num?)?.toInt() ?? defaultMaxMembers,
        members: [
          for (final m in (json['members'] as List? ?? const []))
            PartyMember.fromJson((m as Map).cast<String, Object?>()),
        ],
      );

  @override
  String toString() => '$name ($size/$maxMembers)';
}
