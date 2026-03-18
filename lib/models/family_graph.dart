import 'person.dart';
import 'family_unit.dart';

enum FamilyTreeDisplayMode { focused, ancestors, descendants, full }

enum FamilyGraphNodeType { person, familyUnit }

enum FamilyGraphEdgeType {
  personToFamilyUnit,
  familyUnitToChild,
}

class FamilyGraphNode {
  const FamilyGraphNode._({
    required this.id,
    required this.type,
    this.person,
    this.familyUnit,
  });

  factory FamilyGraphNode.person(Person person) {
    return FamilyGraphNode._(
      id: person.id,
      type: FamilyGraphNodeType.person,
      person: person,
    );
  }

  factory FamilyGraphNode.familyUnit(FamilyUnit familyUnit) {
    return FamilyGraphNode._(
      id: familyUnit.id,
      type: FamilyGraphNodeType.familyUnit,
      familyUnit: familyUnit,
    );
  }

  final String id;
  final FamilyGraphNodeType type;
  final Person? person;
  final FamilyUnit? familyUnit;

  bool get isPerson => type == FamilyGraphNodeType.person;
  bool get isFamilyUnit => type == FamilyGraphNodeType.familyUnit;
}

class FamilyGraphEdge {
  const FamilyGraphEdge({
    required this.fromId,
    required this.toId,
    required this.type,
  });

  final String fromId;
  final String toId;
  final FamilyGraphEdgeType type;
}

class FamilyGraph {
  FamilyGraph({
    required Map<String, Person> persons,
    required Map<String, FamilyUnit> familyUnits,
    required Map<String, FamilyGraphNode> nodes,
    required List<FamilyGraphEdge> edges,
    required Map<String, Set<String>> familyUnitsByPersonId,
    required Map<String, String> familyUnitByChildId,
    required Map<String, Set<String>> childrenByParentId,
    required Map<String, Set<String>> spouseIdsByPersonId,
    required Map<String, Set<String>> parentIdsByPersonId,
    required Map<String, Set<String>> siblingIdsByPersonId,
  })  : persons = Map.unmodifiable(persons),
        familyUnits = Map.unmodifiable(familyUnits),
        nodes = Map.unmodifiable(nodes),
        edges = List.unmodifiable(edges),
        familyUnitsByPersonId = _freezeNestedMap(familyUnitsByPersonId),
        familyUnitByChildId = Map.unmodifiable(familyUnitByChildId),
        childrenByParentId = _freezeNestedMap(childrenByParentId),
        spouseIdsByPersonId = _freezeNestedMap(spouseIdsByPersonId),
        parentIdsByPersonId = _freezeNestedMap(parentIdsByPersonId),
        siblingIdsByPersonId = _freezeNestedMap(siblingIdsByPersonId);

  final Map<String, Person> persons;
  final Map<String, FamilyUnit> familyUnits;
  final Map<String, FamilyGraphNode> nodes;
  final List<FamilyGraphEdge> edges;

  /// A person can belong to multiple family units as spouse or child context.
  final Map<String, Set<String>> familyUnitsByPersonId;

  /// A child belongs to at most one origin family unit in this graph.
  final Map<String, String> familyUnitByChildId;

  final Map<String, Set<String>> childrenByParentId;
  final Map<String, Set<String>> spouseIdsByPersonId;
  final Map<String, Set<String>> parentIdsByPersonId;
  final Map<String, Set<String>> siblingIdsByPersonId;

  Iterable<Person> get rootPersons sync* {
    for (final person in persons.values) {
      if ((parentIdsByPersonId[person.id] ?? const <String>{}).isEmpty) {
        yield person;
      }
    }
  }

  Set<String> familyUnitsForPerson(String personId) =>
      familyUnitsByPersonId[personId] ?? const <String>{};

  String? familyUnitForChild(String childId) => familyUnitByChildId[childId];

  Set<String> childrenOf(String personId) =>
      childrenByParentId[personId] ?? const <String>{};

  Set<String> spousesOf(String personId) =>
      spouseIdsByPersonId[personId] ?? const <String>{};

  Set<String> parentsOf(String personId) =>
      parentIdsByPersonId[personId] ?? const <String>{};

  Set<String> siblingsOf(String personId) =>
      siblingIdsByPersonId[personId] ?? const <String>{};

  static Map<String, Set<String>> _freezeNestedMap(
    Map<String, Set<String>> source,
  ) {
    return Map.unmodifiable({
      for (final entry in source.entries)
        entry.key: Set.unmodifiable(entry.value),
    });
  }
}
