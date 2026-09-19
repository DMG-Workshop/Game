/// One entry from the Pathbuilder `feats` array.
///
/// Entries are positional tuples of *variable length*: most carry seven
/// elements, but background-granted feats carry only four. Anything past
/// index 3 must be treated as optional.
///
///   `[name, choice, type, level, source, choiceKind, parentKey]`
class ImportedFeat {
  const ImportedFeat({
    required this.name,
    required this.choice,
    required this.type,
    required this.level,
    required this.source,
    required this.choiceKind,
    required this.parentKey,
  });

  /// Feat name, e.g. `Assurance`.
  final String name;

  /// The feat's own selected option, e.g. `Medicine` for Assurance. Null when
  /// the feat takes no choice.
  final String? choice;

  /// Pathbuilder's category label, e.g. `Skill Feat`, `Ancestry Feat`.
  final String type;

  /// Character level at which the feat was taken.
  final int level;

  /// Free-text slot label, e.g. `Magus Feat 6`, `Free Archetype 2`. Doubles as
  /// this feat's key when other feats name it as their parent.
  final String? source;

  /// One of `standardChoice`, `parentChoice`, `childChoice`.
  final String? choiceKind;

  /// The `source` of this feat's parent, for feats granted by another feat.
  ///
  /// These keys are built by string concatenation with no delimiter, e.g.
  /// `"Reincarnation Feat" + "Ancestry Paragon 3"`, so they can only be
  /// matched whole against a parent's [source] — never parsed apart.
  final String? parentKey;

  bool get isParent => choiceKind == 'parentChoice';
  bool get isChild => choiceKind == 'childChoice';

  @override
  String toString() =>
      choice == null ? '$name (L$level)' : '$name [$choice] (L$level)';
}
