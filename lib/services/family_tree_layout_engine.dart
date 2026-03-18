import 'dart:math' as math;
import 'dart:ui';

import '../models/family_graph.dart';
import '../models/family_tree_layout_result.dart';
import '../models/family_unit.dart';

class FamilyTreeLayoutConfig {
  const FamilyTreeLayoutConfig({
    this.personNodeSize = const Size(168, 96),
    this.familyUnitNodeSize = const Size(44, 28),
    this.spouseGap = 32,
    this.siblingGap = 28,
    this.familyGap = 56,
    this.generationGap = 124,
    this.canvasPadding = const EdgeInsets.all(48),
  });

  final Size personNodeSize;
  final Size familyUnitNodeSize;
  final double spouseGap;
  final double siblingGap;
  final double familyGap;
  final double generationGap;
  final EdgeInsets canvasPadding;

  double get coupleWidth =>
      (personNodeSize.width * 2) + spouseGap;

  double get childStep => personNodeSize.width + siblingGap;

  double get familyBlockStep => coupleWidth + familyGap;
}

class FamilyTreeLayoutRequest {
  const FamilyTreeLayoutRequest({
    required this.graph,
    this.focusPersonId,
    this.config = const FamilyTreeLayoutConfig(),
  });

  final FamilyGraph graph;
  final String? focusPersonId;
  final FamilyTreeLayoutConfig config;
}

/// Production-oriented, family-aware layout engine for V2.
///
/// Core ideas:
/// 1. Compute explicit generation lanes from family relationships.
/// 2. Lay out person and family-unit nodes independently.
/// 3. Keep spouses side-by-side around the family-unit center.
/// 4. Center children under their family unit instead of under one father.
/// 5. Iterate top-down to stabilize child groups while preserving readable gaps.
class FamilyTreeLayoutEngine {
  const FamilyTreeLayoutEngine();

  FamilyTreeLayoutResult layout(FamilyTreeLayoutRequest request) {
    final graph = request.graph;
    final config = request.config;

    if (graph.nodes.isEmpty) {
      return FamilyTreeLayoutResult(
        nodes: const <String, FamilyTreeLayoutNode>{},
        edges: const <FamilyTreeLayoutEdge>[],
        generations: const <FamilyTreeGenerationLayout>[],
        bounds: Rect.fromLTWH(0, 0, 0, 0),
      );
    }

    final personGenerations = _computePersonGenerations(graph, request.focusPersonId);
    final familyGenerations = _computeFamilyGenerations(graph, personGenerations);

    final personX = _initialPersonSlots(graph, personGenerations, request.focusPersonId, config);

    for (var pass = 0; pass < 3; pass++) {
      _alignFamiliesToPeople(graph, familyGenerations, personX, config);
      _alignChildrenToFamilies(graph, familyGenerations, personGenerations, personX, config);
      _resolveGenerationCollisions(graph, personGenerations, personX, config);
    }

    final familyX = _familyCentersFromPeople(graph, familyGenerations, personX);
    final nodes = _buildNodes(
      graph: graph,
      personGenerations: personGenerations,
      familyGenerations: familyGenerations,
      personX: personX,
      familyX: familyX,
      config: config,
    );
    final edges = _buildEdges(graph, nodes);
    final generations = _buildGenerationMetadata(nodes);
    final bounds = _calculateBounds(nodes.values, config.canvasPadding);

    return FamilyTreeLayoutResult(
      nodes: nodes,
      edges: edges,
      generations: generations,
      bounds: bounds,
    );
  }

  Map<String, int> _computePersonGenerations(
    FamilyGraph graph,
    String? focusPersonId,
  ) {
    final generations = <String, int>{};
    final queue = <String>[];

    final roots = graph.rootPersons.map((person) => person.id).toList(growable: true)
      ..sort();

    if (focusPersonId != null && graph.persons.containsKey(focusPersonId)) {
      roots.remove(focusPersonId);
      roots.insert(0, focusPersonId);
    }

    if (roots.isEmpty) {
      roots.addAll(graph.persons.keys.toList()..sort());
    }

    for (final rootId in roots) {
      generations.putIfAbsent(rootId, () => 0);
      queue.add(rootId);
    }

    while (queue.isNotEmpty) {
      final personId = queue.removeAt(0);
      final baseGeneration = generations[personId] ?? 0;

      for (final childId in graph.childrenOf(personId)) {
        final nextGeneration = baseGeneration + 1;
        final current = generations[childId];
        if (current == null || nextGeneration > current) {
          generations[childId] = nextGeneration;
          queue.add(childId);
        }
      }

      for (final spouseId in graph.spousesOf(personId)) {
        final spouseGeneration = generations[spouseId];
        if (spouseGeneration == null || spouseGeneration != baseGeneration) {
          generations[spouseId] = baseGeneration;
          queue.add(spouseId);
        }
      }
    }

    for (final personId in graph.persons.keys) {
      generations.putIfAbsent(personId, () {
        final parents = graph.parentsOf(personId);
        if (parents.isEmpty) return 0;
        final parentGeneration = parents
            .map((parentId) => generations[parentId] ?? 0)
            .fold<int>(0, math.max);
        return parentGeneration + 1;
      });
    }

    return generations;
  }

  Map<String, int> _computeFamilyGenerations(
    FamilyGraph graph,
    Map<String, int> personGenerations,
  ) {
    final generations = <String, int>{};

    for (final entry in graph.familyUnits.entries) {
      final family = entry.value;
      final spouseGenerations = <int>{
        if (family.husbandId != null) personGenerations[family.husbandId!] ?? 0,
        if (family.wifeId != null) personGenerations[family.wifeId!] ?? 0,
      };

      if (spouseGenerations.isNotEmpty) {
        generations[entry.key] = spouseGenerations.reduce(math.max);
        continue;
      }

      if (family.childrenIds.isNotEmpty) {
        final childGeneration = family.childrenIds
            .map((childId) => personGenerations[childId] ?? 1)
            .reduce(math.min);
        generations[entry.key] = math.max(0, childGeneration - 1);
        continue;
      }

      generations[entry.key] = 0;
    }

    return generations;
  }

  Map<String, double> _initialPersonSlots(
    FamilyGraph graph,
    Map<String, int> personGenerations,
    String? focusPersonId,
    FamilyTreeLayoutConfig config,
  ) {
    final grouped = <int, List<String>>{};
    for (final entry in personGenerations.entries) {
      grouped.putIfAbsent(entry.value, () => <String>[]).add(entry.key);
    }

    final positions = <String, double>{};

    for (final generation in grouped.keys.toList()..sort()) {
      final ids = grouped[generation]!..sort((a, b) {
        if (a == focusPersonId) return -1;
        if (b == focusPersonId) return 1;

        final aParents = graph.parentsOf(a).toList()..sort();
        final bParents = graph.parentsOf(b).toList()..sort();
        final parentCompare = aParents.join(',').compareTo(bParents.join(','));
        if (parentCompare != 0) return parentCompare;

        return a.compareTo(b);
      });

      for (var index = 0; index < ids.length; index++) {
        positions[ids[index]] = index * config.childStep;
      }
    }

    return positions;
  }

  void _alignFamiliesToPeople(
    FamilyGraph graph,
    Map<String, int> familyGenerations,
    Map<String, double> personX,
    FamilyTreeLayoutConfig config,
  ) {
    final families = graph.familyUnits.values.toList()
      ..sort((a, b) {
        final generationCompare =
            (familyGenerations[a.id] ?? 0).compareTo(familyGenerations[b.id] ?? 0);
        if (generationCompare != 0) return generationCompare;
        return a.id.compareTo(b.id);
      });

    for (final family in families) {
      final coupleCenter = _targetFamilyCenter(graph, family, personX);
      final (husbandX, wifeX) = _spousePositionsFromCenter(coupleCenter, config);

      if (family.husbandId != null) {
        personX[family.husbandId!] = husbandX;
      }
      if (family.wifeId != null) {
        personX[family.wifeId!] = wifeX;
      }
    }
  }

  void _alignChildrenToFamilies(
    FamilyGraph graph,
    Map<String, int> familyGenerations,
    Map<String, int> personGenerations,
    Map<String, double> personX,
    FamilyTreeLayoutConfig config,
  ) {
    final families = graph.familyUnits.values.toList()
      ..sort((a, b) {
        final generationCompare =
            (familyGenerations[a.id] ?? 0).compareTo(familyGenerations[b.id] ?? 0);
        if (generationCompare != 0) return generationCompare;
        return a.id.compareTo(b.id);
      });

    for (final family in families) {
      if (family.childrenIds.isEmpty) {
        continue;
      }

      final centerX = _targetFamilyCenter(graph, family, personX);
      final orderedChildren = family.childrenIds.toList()
        ..sort((a, b) {
          final generationCompare =
              (personGenerations[a] ?? 0).compareTo(personGenerations[b] ?? 0);
          if (generationCompare != 0) return generationCompare;
          return a.compareTo(b);
        });

      final startX = centerX - (((orderedChildren.length - 1) * config.childStep) / 2);
      for (var index = 0; index < orderedChildren.length; index++) {
        final childId = orderedChildren[index];
        final proposedX = startX + (index * config.childStep);
        personX[childId] = (personX[childId] == null)
            ? proposedX
            : (personX[childId]! + proposedX) / 2;
      }
    }
  }

  void _resolveGenerationCollisions(
    FamilyGraph graph,
    Map<String, int> personGenerations,
    Map<String, double> personX,
    FamilyTreeLayoutConfig config,
  ) {
    final grouped = <int, List<String>>{};
    for (final entry in personGenerations.entries) {
      grouped.putIfAbsent(entry.value, () => <String>[]).add(entry.key);
    }

    for (final generation in grouped.keys.toList()..sort()) {
      final ids = grouped[generation]!..sort((a, b) {
        final ax = personX[a] ?? 0;
        final bx = personX[b] ?? 0;
        if (ax == bx) return a.compareTo(b);
        return ax.compareTo(bx);
      });

      double? previousX;
      for (final personId in ids) {
        final currentX = personX[personId] ?? 0;
        if (previousX == null) {
          previousX = currentX;
          continue;
        }

        final minX = previousX + config.childStep;
        if (currentX < minX) {
          personX[personId] = minX;
          previousX = minX;
        } else {
          previousX = currentX;
        }
      }
    }

    _pullSinglePeopleTowardFamilies(graph, personX);
  }

  void _pullSinglePeopleTowardFamilies(
    FamilyGraph graph,
    Map<String, double> personX,
  ) {
    for (final personId in graph.persons.keys) {
      final familyIds = graph.familyUnitsForPerson(personId);
      if (familyIds.isEmpty) {
        continue;
      }

      final targetCenters = familyIds
          .map((familyId) => graph.familyUnits[familyId])
          .whereType<FamilyUnit>()
          .map((family) => _targetFamilyCenter(graph, family, personX))
          .toList(growable: false);
      if (targetCenters.isEmpty) {
        continue;
      }

      final target =
          targetCenters.reduce((a, b) => a + b) / targetCenters.length;
      final current = personX[personId] ?? target;
      personX[personId] = (current + target) / 2;
    }
  }

  Map<String, double> _familyCentersFromPeople(
    FamilyGraph graph,
    Map<String, int> familyGenerations,
    Map<String, double> personX,
  ) {
    final centers = <String, double>{};

    final families = graph.familyUnits.values.toList()
      ..sort((a, b) {
        final generationCompare =
            (familyGenerations[a.id] ?? 0).compareTo(familyGenerations[b.id] ?? 0);
        if (generationCompare != 0) return generationCompare;
        return a.id.compareTo(b.id);
      });

    for (final family in families) {
      centers[family.id] = _targetFamilyCenter(graph, family, personX);
    }

    return centers;
  }

  double _targetFamilyCenter(
    FamilyGraph graph,
    FamilyUnit family,
    Map<String, double> personX,
  ) {
    final spouseCenters = <double>[
      if (family.husbandId != null && personX[family.husbandId!] != null)
        personX[family.husbandId!]!,
      if (family.wifeId != null && personX[family.wifeId!] != null)
        personX[family.wifeId!]!,
    ];

    if (spouseCenters.isNotEmpty) {
      return spouseCenters.reduce((a, b) => a + b) / spouseCenters.length;
    }

    final childCenters = family.childrenIds
        .map((childId) => personX[childId])
        .whereType<double>()
        .toList(growable: false);
    if (childCenters.isNotEmpty) {
      return childCenters.reduce((a, b) => a + b) / childCenters.length;
    }

    return 0;
  }

  (double, double) _spousePositionsFromCenter(
    double centerX,
    FamilyTreeLayoutConfig config,
  ) {
    final offset = (config.personNodeSize.width + config.spouseGap) / 2;
    return (centerX - offset, centerX + offset);
  }

  Map<String, FamilyTreeLayoutNode> _buildNodes({
    required FamilyGraph graph,
    required Map<String, int> personGenerations,
    required Map<String, int> familyGenerations,
    required Map<String, double> personX,
    required Map<String, double> familyX,
    required FamilyTreeLayoutConfig config,
  }) {
    final nodes = <String, FamilyTreeLayoutNode>{};

    for (final person in graph.persons.values) {
      final generation = personGenerations[person.id] ?? 0;
      final y = _generationToY(generation, config);
      nodes[person.id] = FamilyTreeLayoutNode(
        id: person.id,
        type: FamilyGraphNodeType.person,
        center: Offset(personX[person.id] ?? 0, y),
        size: config.personNodeSize,
        generation: generation,
      );
    }

    for (final family in graph.familyUnits.values) {
      final generation = familyGenerations[family.id] ?? 0;
      final y = _generationToY(generation, config) +
          ((config.personNodeSize.height + config.familyUnitNodeSize.height) / 2) -
          14;
      nodes[family.id] = FamilyTreeLayoutNode(
        id: family.id,
        type: FamilyGraphNodeType.familyUnit,
        center: Offset(familyX[family.id] ?? 0, y),
        size: config.familyUnitNodeSize,
        generation: generation,
      );
    }

    return nodes;
  }

  List<FamilyTreeLayoutEdge> _buildEdges(
    FamilyGraph graph,
    Map<String, FamilyTreeLayoutNode> nodes,
  ) {
    final result = <FamilyTreeLayoutEdge>[];

    for (final edge in graph.edges) {
      final from = nodes[edge.fromId];
      final to = nodes[edge.toId];
      if (from == null || to == null) {
        continue;
      }

      final start = Offset(from.center.dx, from.bottom);
      final end = Offset(to.center.dx, to.top);
      final middleY = start.dy + ((end.dy - start.dy) / 2);

      result.add(
        FamilyTreeLayoutEdge(
          fromId: edge.fromId,
          toId: edge.toId,
          type: edge.type,
          points: <Offset>[
            start,
            Offset(start.dx, middleY),
            Offset(end.dx, middleY),
            end,
          ],
        ),
      );
    }

    return result;
  }

  List<FamilyTreeGenerationLayout> _buildGenerationMetadata(
    Map<String, FamilyTreeLayoutNode> nodes,
  ) {
    final grouped = <int, List<FamilyTreeLayoutNode>>{};
    for (final node in nodes.values) {
      grouped.putIfAbsent(node.generation, () => <FamilyTreeLayoutNode>[]).add(node);
    }

    final result = <FamilyTreeGenerationLayout>[];
    for (final generation in grouped.keys.toList()..sort()) {
      final generationNodes = grouped[generation]!;
      final top = generationNodes.map((node) => node.top).reduce(math.min);
      final bottom = generationNodes.map((node) => node.bottom).reduce(math.max);
      final ids = generationNodes.map((node) => node.id).toList()..sort();

      result.add(
        FamilyTreeGenerationLayout(
          generation: generation,
          top: top,
          bottom: bottom,
          nodeIds: ids,
        ),
      );
    }

    return result;
  }

  Rect _calculateBounds(
    Iterable<FamilyTreeLayoutNode> nodes,
    EdgeInsets padding,
  ) {
    if (nodes.isEmpty) {
      return Rect.fromLTWH(0, 0, 0, 0);
    }

    final left = nodes.map((node) => node.left).reduce(math.min) - padding.left;
    final top = nodes.map((node) => node.top).reduce(math.min) - padding.top;
    final right = nodes.map((node) => node.right).reduce(math.max) + padding.right;
    final bottom = nodes.map((node) => node.bottom).reduce(math.max) + padding.bottom;

    return Rect.fromLTRB(left, top, right, bottom);
  }

  double _generationToY(int generation, FamilyTreeLayoutConfig config) {
    return generation * (config.personNodeSize.height + config.generationGap);
  }
}
