import 'package:pf2e_core/pf2e_core.dart';

/// A character taking part in a session.
///
/// Deliberately lighter than a `PartyMember`: a session needs a name, a sheet
/// and an id, not an import history. Keeping the scene engine independent of
/// the store means a session can be run from a roster, from a single imported
/// character, or from a fixture, without either layer knowing about the other.
class SessionActor {
  SessionActor({required this.id, required this.character});

  final String id;
  final ImportedCharacter character;

  DerivedStats? _stats;

  /// The derived sheet, computed once per actor.
  DerivedStats get stats => _stats ??= DerivedStats(character);

  String get name => character.name;

  /// This actor's bonus for [statKey], or null when they have no such
  /// statistic at all — an absent Lore is not the same as an untrained skill.
  CheckValue? statFor(String statKey) => stats.statByKey(statKey);

  @override
  String toString() => '$name (${character.className} ${character.level})';
}

/// One actor's standing to attempt a particular check.
typedef ActorCandidate = ({SessionActor actor, CheckValue stat});
