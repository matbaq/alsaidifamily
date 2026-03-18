import 'dart:ui';

import 'family_graph.dart';

/// Immutable node position produced by the V2 layout engine.
///
/// The renderer should consume these coordinates directly rather than
/// attempting to infer placement from parent ids or list order.
class FamilyTreeLayoutNode {
  const FamilyTreeLayoutNode({
    required this.id,
    required this.type,
    required this.center,
    required this.size,
    required this.generation,
  });

  final String id;
  final FamilyGraphNodeType type;
  final Offset center;
  final Size size;
  final int generation;

  double get left => center.dx - (size.width / 2);
  double get top => center.dy - (size.height / 2);
  double get right => center.dx + (size.width / 2);
  double get bottom => center.dy + (size.height / 2);

  Rect get rect => Rect.fromCenter(
        center: center,
        width: size.width,
        height: size.height,
      );
}

/// A polyline edge that can be rendered with orthogonal segments.
class FamilyTreeLayoutEdge {
  const FamilyTreeLayoutEdge({
    required this.fromId,
    required this.toId,
    required this.type,
    required this.points,
  });

  final String fromId;
  final String toId;
  final FamilyGraphEdgeType type;
  final List<Offset> points;
}

/// Generation-level metrics are useful for debugging and future UI features
/// such as jump-to-generation, sticky headers, or minimaps.
class FamilyTreeGenerationLayout {
  const FamilyTreeGenerationLayout({
    required this.generation,
    required this.top,
    required this.bottom,
    required this.nodeIds,
  });

  final int generation;
  final double top;
  final double bottom;
  final List<String> nodeIds;
}

class FamilyTreeLayoutResult {
  FamilyTreeLayoutResult({
    required Map<String, FamilyTreeLayoutNode> nodes,
    required List<FamilyTreeLayoutEdge> edges,
    required List<FamilyTreeGenerationLayout> generations,
    required Rect bounds,
  })  : nodes = Map.unmodifiable(nodes),
        edges = List.unmodifiable(edges),
        generations = List.unmodifiable(generations),
        bounds = bounds;

  final Map<String, FamilyTreeLayoutNode> nodes;
  final List<FamilyTreeLayoutEdge> edges;
  final List<FamilyTreeGenerationLayout> generations;
  final Rect bounds;

  FamilyTreeLayoutNode? nodeFor(String nodeId) => nodes[nodeId];
}
