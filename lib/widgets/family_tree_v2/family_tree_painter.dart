import 'package:flutter/material.dart';

import '../../models/family_graph.dart';
import '../../models/family_tree_layout_result.dart';

/// Paints relationship edges for the V2 tree using layout-engine output only.
class FamilyTreeV2Painter extends CustomPainter {
  const FamilyTreeV2Painter({
    required this.layout,
    required this.canvasOffset,
    this.focusedNodeId,
  });

  final FamilyTreeLayoutResult layout;
  final Offset canvasOffset;
  final String? focusedNodeId;

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.edges.isEmpty) {
      return;
    }

    for (final edge in layout.edges) {
      if (edge.points.length < 2) {
        continue;
      }

      final isHighlighted = edge.fromId == focusedNodeId || edge.toId == focusedNodeId;
      final strokeColor = _colorForEdge(edge.type, isHighlighted);
      final glowColor = strokeColor.withValues(alpha: isHighlighted ? 0.18 : 0.08);

      final shiftedPoints = edge.points
          .map((point) => point.translate(canvasOffset.dx, canvasOffset.dy))
          .toList(growable: false);

      final path = Path()..moveTo(shiftedPoints.first.dx, shiftedPoints.first.dy);
      for (final point in shiftedPoints.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }

      final glowPaint = Paint()
        ..color = glowColor
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = isHighlighted ? 7 : 4;

      final strokePaint = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = isHighlighted ? 2.8 : 1.8;

      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, strokePaint);

      final endPoint = shiftedPoints.last;
      canvas.drawCircle(
        endPoint,
        isHighlighted ? 2.8 : 2.1,
        Paint()..color = strokeColor,
      );
    }
  }

  Color _colorForEdge(FamilyGraphEdgeType type, bool isHighlighted) {
    switch (type) {
      case FamilyGraphEdgeType.personToFamilyUnit:
        return isHighlighted
            ? const Color(0xFFFFC857)
            : const Color(0xFF7C8AA5);
      case FamilyGraphEdgeType.familyUnitToChild:
        return isHighlighted
            ? const Color(0xFF69A9FF)
            : const Color(0xFF90A4C2);
    }
  }

  @override
  bool shouldRepaint(covariant FamilyTreeV2Painter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.canvasOffset != canvasOffset ||
        oldDelegate.focusedNodeId != focusedNodeId;
  }
}
