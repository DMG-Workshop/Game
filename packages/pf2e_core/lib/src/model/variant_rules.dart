/// Optional PF2e rules detected on an imported build.
///
/// Only Dual Class has a dedicated field in the Pathbuilder payload. Free
/// Archetype and Ancestry Paragon are inferable *only* from the free-text
/// source labels attached to feats (`"Free Archetype 4"`, `"Ancestry Paragon
/// 3"`), so detection here is necessarily heuristic.
class VariantRules {
  const VariantRules({
    this.dualClass = false,
    this.freeArchetype = false,
    this.ancestryParagon = false,
  });

  final bool dualClass;
  final bool freeArchetype;
  final bool ancestryParagon;

  bool get any => dualClass || freeArchetype || ancestryParagon;

  List<String> get active => [
        if (dualClass) 'Dual Class',
        if (freeArchetype) 'Free Archetype',
        if (ancestryParagon) 'Ancestry Paragon',
      ];

  @override
  String toString() => active.isEmpty ? 'none' : active.join(', ');
}
