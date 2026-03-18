import '../models/family_graph.dart';
import '../models/family_unit.dart';
import '../models/person.dart';

class FamilyGraphBuildRequest {
  const FamilyGraphBuildRequest({
    required this.persons,
    required this.familyUnits,
    this.focusPersonId,
    this.mode = FamilyTreeDisplayMode.full,
    this.searchQuery,
    this.matchedPersonIds = const <String>{},
    this.includeSiblingsForContext = true,
  });

  final List<Person> persons;
  final List<FamilyUnit> familyUnits;
  final String? focusPersonId;
  final FamilyTreeDisplayMode mode;
  final String? searchQuery;
  final Set<String> matchedPersonIds;
  final bool includeSiblingsForContext;
}

class FamilyGraphBuilder {
  const FamilyGraphBuilder();

  FamilyGraph build(FamilyGraphBuildRequest request) {
    final personById = <String, Person>{
      for (final person in request.persons) person.id: person,
    };

    final sanitizedFamilyUnits = _sanitizeFamilyUnits(
      request.familyUnits,
      personById,
    );

    final allGraph = _buildFullGraph(
      personById: personById,
      familyUnits: sanitizedFamilyUnits,
    );

    final includedPersonIds = _selectVisiblePersonIds(allGraph, request);
    final includedFamilyUnitIds = _selectVisibleFamilyUnits(
      allGraph,
      includedPersonIds,
    );

    return _createSubgraph(
      fullGraph: allGraph,
      includedPersonIds: includedPersonIds,
      includedFamilyUnitIds: includedFamilyUnitIds,
    );
  }

  List<FamilyUnit> _sanitizeFamilyUnits(
    List<FamilyUnit> units,
    Map<String, Person> personById,
  ) {
    final byId = <String, FamilyUnit>{};

    for (final unit in units) {
      final children = unit.childrenIds.where(personById.containsKey).toSet();
      final husbandId = personById.containsKey(unit.husbandId)
          ? unit.husbandId
          : null;
      final wifeId = personById.containsKey(unit.wifeId) ? unit.wifeId : null;

      if (husbandId == null && wifeId == null && children.isEmpty) {
        continue;
      }

      byId[unit.id] = FamilyUnit(
        id: unit.id,
        husbandId: husbandId,
        wifeId: wifeId,
        childrenIds: List.unmodifiable(children),
      );
    }

    return byId.values.toList(growable: false);
  }

  FamilyGraph _buildFullGraph({
    required Map<String, Person> personById,
    required List<FamilyUnit> familyUnits,
  }) {
    final nodes = <String, FamilyGraphNode>{
      for (final person in personById.values)
        person.id: FamilyGraphNode.person(person),
    };
    final unitsById = <String, FamilyUnit>{};
    final edges = <FamilyGraphEdge>[];
    final familyUnitsByPersonId = <String, Set<String>>{};
    final familyUnitByChildId = <String, String>{};
    final childrenByParentId = <String, Set<String>>{};
    final spouseIdsByPersonId = <String, Set<String>>{};
    final parentIdsByPersonId = <String, Set<String>>{};
    final siblingIdsByPersonId = <String, Set<String>>{};

    for (final unit in familyUnits) {
      unitsById[unit.id] = unit;
      nodes[unit.id] = FamilyGraphNode.familyUnit(unit);

      final spouseIds = <String>{
        if (unit.husbandId != null) unit.husbandId!,
        if (unit.wifeId != null) unit.wifeId!,
      };

      for (final spouseId in spouseIds) {
        familyUnitsByPersonId.putIfAbsent(spouseId, () => <String>{}).add(unit.id);
        edges.add(FamilyGraphEdge(
          fromId: spouseId,
          toId: unit.id,
          type: FamilyGraphEdgeType.personToFamilyUnit,
        ));
      }

      if (unit.husbandId != null && unit.wifeId != null) {
        spouseIdsByPersonId.putIfAbsent(unit.husbandId!, () => <String>{}).add(unit.wifeId!);
        spouseIdsByPersonId.putIfAbsent(unit.wifeId!, () => <String>{}).add(unit.husbandId!);
      }

      final parentIds = spouseIds;
      final childIds = unit.childrenIds.toSet();

      for (final childId in childIds) {
        familyUnitByChildId[childId] = unit.id;
        familyUnitsByPersonId.putIfAbsent(childId, () => <String>{}).add(unit.id);
        edges.add(FamilyGraphEdge(
          fromId: unit.id,
          toId: childId,
          type: FamilyGraphEdgeType.familyUnitToChild,
        ));

        for (final parentId in parentIds) {
          childrenByParentId.putIfAbsent(parentId, () => <String>{}).add(childId);
          parentIdsByPersonId.putIfAbsent(childId, () => <String>{}).add(parentId);
        }
      }

      for (final childId in childIds) {
        final siblings = childIds.where((candidate) => candidate != childId);
        siblingIdsByPersonId.putIfAbsent(childId, () => <String>{}).addAll(siblings);
      }
    }

    return FamilyGraph(
      persons: personById,
      familyUnits: unitsById,
      nodes: nodes,
      edges: edges,
      familyUnitsByPersonId: familyUnitsByPersonId,
      familyUnitByChildId: familyUnitByChildId,
      childrenByParentId: childrenByParentId,
      spouseIdsByPersonId: spouseIdsByPersonId,
      parentIdsByPersonId: parentIdsByPersonId,
      siblingIdsByPersonId: siblingIdsByPersonId,
    );
  }

  Set<String> _selectVisiblePersonIds(
    FamilyGraph graph,
    FamilyGraphBuildRequest request,
  ) {
    if (request.mode == FamilyTreeDisplayMode.full &&
        request.focusPersonId == null &&
        request.matchedPersonIds.isEmpty) {
      return graph.persons.keys.toSet();
    }

    final seeds = <String>{
      if (request.focusPersonId != null) request.focusPersonId!,
      ...request.matchedPersonIds,
    }..removeWhere((id) => !graph.persons.containsKey(id));

    if (seeds.isEmpty) {
      return graph.persons.keys.toSet();
    }

    final visible = <String>{};

    for (final seed in seeds) {
      visible.add(seed);

      switch (request.mode) {
        case FamilyTreeDisplayMode.focused:
          _collectFocusedContext(
            graph: graph,
            personId: seed,
            visible: visible,
            includeSiblings: request.includeSiblingsForContext,
          );
          break;
        case FamilyTreeDisplayMode.ancestors:
          _collectAncestors(graph, seed, visible);
          _collectSpouses(graph, seed, visible);
          _collectParentsForVisible(graph, visible);
          break;
        case FamilyTreeDisplayMode.descendants:
          _collectDescendants(graph, seed, visible);
          _collectSpouses(graph, seed, visible);
          break;
        case FamilyTreeDisplayMode.full:
          visible.addAll(graph.persons.keys);
          break;
      }
    }

    if (request.matchedPersonIds.isNotEmpty) {
      for (final personId in request.matchedPersonIds) {
        _collectFocusedContext(
          graph: graph,
          personId: personId,
          visible: visible,
          includeSiblings: request.includeSiblingsForContext,
        );
      }
    }

    return visible;
  }

  Set<String> _selectVisibleFamilyUnits(
    FamilyGraph graph,
    Set<String> visiblePersonIds,
  ) {
    final familyUnitIds = <String>{};

    for (final personId in visiblePersonIds) {
      familyUnitIds.addAll(graph.familyUnitsForPerson(personId));
    }

    familyUnitIds.removeWhere((unitId) {
      final unit = graph.familyUnits[unitId];
      if (unit == null) return true;

      final relatedPeople = <String>{
        if (unit.husbandId != null) unit.husbandId!,
        if (unit.wifeId != null) unit.wifeId!,
        ...unit.childrenIds,
      };

      return relatedPeople.intersection(visiblePersonIds).isEmpty;
    });

    return familyUnitIds;
  }

  FamilyGraph _createSubgraph({
    required FamilyGraph fullGraph,
    required Set<String> includedPersonIds,
    required Set<String> includedFamilyUnitIds,
  }) {
    final persons = <String, Person>{
      for (final id in includedPersonIds)
        if (fullGraph.persons.containsKey(id)) id: fullGraph.persons[id]!,
    };

    final familyUnits = <String, FamilyUnit>{
      for (final id in includedFamilyUnitIds)
        if (fullGraph.familyUnits.containsKey(id)) id: fullGraph.familyUnits[id]!,
    };

    final nodes = <String, FamilyGraphNode>{
      for (final id in persons.keys) id: fullGraph.nodes[id]!,
      for (final id in familyUnits.keys) id: fullGraph.nodes[id]!,
    };

    final edges = fullGraph.edges.where((edge) {
      final fromVisible = nodes.containsKey(edge.fromId);
      final toVisible = nodes.containsKey(edge.toId);
      return fromVisible && toVisible;
    }).toList(growable: false);

    final familyUnitsByPersonId = <String, Set<String>>{};
    final familyUnitByChildId = <String, String>{};
    final childrenByParentId = <String, Set<String>>{};
    final spouseIdsByPersonId = <String, Set<String>>{};
    final parentIdsByPersonId = <String, Set<String>>{};
    final siblingIdsByPersonId = <String, Set<String>>{};

    for (final personId in persons.keys) {
      final visibleFamilyUnits = fullGraph
          .familyUnitsForPerson(personId)
          .where(familyUnits.containsKey)
          .toSet();
      if (visibleFamilyUnits.isNotEmpty) {
        familyUnitsByPersonId[personId] = visibleFamilyUnits;
      }

      final visibleChildren =
          fullGraph.childrenOf(personId).where(persons.containsKey).toSet();
      if (visibleChildren.isNotEmpty) {
        childrenByParentId[personId] = visibleChildren;
      }

      final visibleSpouses =
          fullGraph.spousesOf(personId).where(persons.containsKey).toSet();
      if (visibleSpouses.isNotEmpty) {
        spouseIdsByPersonId[personId] = visibleSpouses;
      }

      final visibleParents =
          fullGraph.parentsOf(personId).where(persons.containsKey).toSet();
      if (visibleParents.isNotEmpty) {
        parentIdsByPersonId[personId] = visibleParents;
      }

      final visibleSiblings =
          fullGraph.siblingsOf(personId).where(persons.containsKey).toSet();
      if (visibleSiblings.isNotEmpty) {
        siblingIdsByPersonId[personId] = visibleSiblings;
      }
    }

    for (final entry in familyUnits.entries) {
      for (final childId in entry.value.childrenIds) {
        if (persons.containsKey(childId)) {
          familyUnitByChildId[childId] = entry.key;
        }
      }
    }

    return FamilyGraph(
      persons: persons,
      familyUnits: familyUnits,
      nodes: nodes,
      edges: edges,
      familyUnitsByPersonId: familyUnitsByPersonId,
      familyUnitByChildId: familyUnitByChildId,
      childrenByParentId: childrenByParentId,
      spouseIdsByPersonId: spouseIdsByPersonId,
      parentIdsByPersonId: parentIdsByPersonId,
      siblingIdsByPersonId: siblingIdsByPersonId,
    );
  }

  void _collectFocusedContext({
    required FamilyGraph graph,
    required String personId,
    required Set<String> visible,
    required bool includeSiblings,
  }) {
    visible.add(personId);
    _collectParents(graph, personId, visible);
    _collectSpouses(graph, personId, visible);
    _collectChildren(graph, personId, visible);

    if (includeSiblings) {
      visible.addAll(graph.siblingsOf(personId));
    }

    for (final spouseId in graph.spousesOf(personId)) {
      _collectChildren(graph, spouseId, visible);
    }
  }

  void _collectAncestors(FamilyGraph graph, String personId, Set<String> visible) {
    if (!visible.add(personId) && visible.containsAll(graph.parentsOf(personId))) {
      return;
    }

    for (final parentId in graph.parentsOf(personId)) {
      _collectAncestors(graph, parentId, visible);
      _collectSpouses(graph, parentId, visible);
    }
  }

  void _collectDescendants(FamilyGraph graph, String personId, Set<String> visible) {
    if (!visible.add(personId)) {
      return;
    }

    _collectSpouses(graph, personId, visible);

    for (final childId in graph.childrenOf(personId)) {
      _collectDescendants(graph, childId, visible);
    }
  }

  void _collectParents(FamilyGraph graph, String personId, Set<String> visible) {
    visible.addAll(graph.parentsOf(personId));
  }

  void _collectChildren(FamilyGraph graph, String personId, Set<String> visible) {
    visible.addAll(graph.childrenOf(personId));
  }

  void _collectSpouses(FamilyGraph graph, String personId, Set<String> visible) {
    visible.addAll(graph.spousesOf(personId));
  }

  void _collectParentsForVisible(FamilyGraph graph, Set<String> visible) {
    final snapshot = visible.toList(growable: false);
    for (final personId in snapshot) {
      visible.addAll(graph.parentsOf(personId));
    }
  }
}
