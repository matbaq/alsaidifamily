import 'family_graph.dart';

/// Resolved V2 tree selection state after query/focus/collapse rules are applied.
class FamilyGraphSelection {
  FamilyGraphSelection({
    required this.graph,
    required this.focusPersonId,
    required Set<String> matchedPersonIds,
    required Set<String> collapsedFamilyUnitIds,
    required this.query,
  })  : matchedPersonIds = Set.unmodifiable(matchedPersonIds),
        collapsedFamilyUnitIds = Set.unmodifiable(collapsedFamilyUnitIds);

  final FamilyGraph graph;
  final String? focusPersonId;
  final Set<String> matchedPersonIds;
  final String query;
  final Set<String> collapsedFamilyUnitIds;

  bool get hasQuery => query.trim().isNotEmpty;
  bool get hasMatches => matchedPersonIds.isNotEmpty;
  bool isFamilyCollapsed(String familyUnitId) =>
      collapsedFamilyUnitIds.contains(familyUnitId);
}
