import '../scene/scene.dart';

/// Where a conversation opens, depending on how far the story has got.
///
/// Somebody you have already spoken to should not introduce themselves again,
/// and somebody you have caught lying should not greet you as a stranger.
/// Entries are tried in order and the first whose conditions hold wins.
class ConversationEntry {
  const ConversationEntry({
    required this.sceneId,
    this.requiredFlags = const [],
    this.forbiddenFlags = const [],
  });

  final String sceneId;
  final List<String> requiredFlags;
  final List<String> forbiddenFlags;

  bool opensFor(Set<String> flags) =>
      requiredFlags.every(flags.contains) &&
      !forbiddenFlags.any(flags.contains);

  @override
  String toString() => sceneId;
}

/// Everything an NPC says when properly talked to, as opposed to asked about
/// a single word.
///
/// The dialogue is an ordinary scene graph: each scene is what the NPC says,
/// and each option is what the party says back. That buys skill checks,
/// degrees of success, flags and validation from the engine that already
/// runs adventures, instead of a second, weaker one for talking.
class Conversation {
  const Conversation({
    required this.npcId,
    required this.entries,
    required this.adventure,
  });

  final String npcId;
  final List<ConversationEntry> entries;
  final Adventure adventure;

  /// The scene it opens on for [flags], or null when nothing matches.
  String? openingFor(Set<String> flags) {
    for (final entry in entries) {
      if (entry.opensFor(flags)) return entry.sceneId;
    }
    return null;
  }

  /// Every flag any line of this conversation can set.
  Set<String> get producibleFlags => {
        for (final scene in adventure.scenes.values)
          for (final option in scene.options) ...[
            ...?option.automatic?.setFlags,
            for (final outcome in option.outcomes.values) ...outcome.setFlags,
          ],
      };

  @override
  String toString() => '$npcId (${adventure.scenes.length} lines)';
}

/// The campaign's conversations, one per NPC at most.
class Conversations {
  Conversations(List<Conversation> conversations)
      : _byNpc = {for (final c in conversations) c.npcId: c};

  final Map<String, Conversation> _byNpc;

  List<Conversation> get all => List.unmodifiable(_byNpc.values);
  int get length => _byNpc.length;

  Conversation? forNpc(String npcId) => _byNpc[npcId];

  Set<String> get producibleFlags => {
        for (final conversation in _byNpc.values)
          ...conversation.producibleFlags,
      };

  /// Conversations written for somebody the campaign does not have.
  List<Conversation> orphanedFrom(Set<String> knownNpcIds) => [
        for (final conversation in _byNpc.values)
          if (!knownNpcIds.contains(conversation.npcId)) conversation,
      ];

  @override
  String toString() => '$length conversations';
}
