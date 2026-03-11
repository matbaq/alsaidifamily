import 'package:flutter/material.dart';

import 'tidy_tree_layout.dart';

class FamilyTreePainter extends CustomPainter {
  final List<NodePosition> positions;
  final String? selectedNodeId;
  final Set<String> visibleIds;

  static const double nodeWidth = 120.0;
  static const double nodeHeight = 140.0;
  static const double toggleBtnOffset = 14.0;
  static const double _minLinkDistanceSquared = 0.5;
  static const double _junctionGap = 30.0;

  FamilyTreePainter({
    required this.positions,
    required this.visibleIds,
    this.selectedNodeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;

    final posById = <String, NodePosition>{
      for (final p in positions) p.node.id: p,
    };

    for (final p in positions) {
      if (!visibleIds.contains(p.node.id)) continue;

      final visibleChildren = p.node.children
          .map((child) => posById[child.id])
          .whereType<NodePosition>()
          .where((childPos) => visibleIds.contains(childPos.node.id))
          .toList();

      if (visibleChildren.isEmpty) continue;

      final parentColor = p.node.branchColor;
      final parentCenterX = p.x + nodeWidth / 2;
      final parentCenterY = p.y + nodeHeight / 2;
      final parentAboveChild = parentCenterY <
          visibleChildren.first.y + nodeHeight / 2;

      final parentJoin = Offset(
        parentCenterX,
        parentAboveChild ? p.y + nodeHeight - toggleBtnOffset : p.y,
      );

      final junctionY = parentAboveChild
          ? parentJoin.dy + _junctionGap
          : parentJoin.dy - _junctionGap;

      final childJoints = visibleChildren
          .map(
            (childPos) => Offset(
              childPos.x + nodeWidth / 2,
              parentAboveChild
                  ? childPos.y
                  : childPos.y + nodeHeight - toggleBtnOffset,
            ),
          )
          .toList();

      double minChildX = childJoints.first.dx;
      double maxChildX = childJoints.first.dx;
      for (final c in childJoints.skip(1)) {
        if (c.dx < minChildX) minChildX = c.dx;
        if (c.dx > maxChildX) maxChildX = c.dx;
      }

      final anyHighlighted = selectedNodeId != null &&
          (p.node.id == selectedNodeId ||
              visibleChildren.any((c) => c.node.id == selectedNodeId));

      final paintGlow = Paint()
        ..color = parentColor.withValues(alpha: anyHighlighted ? 0.20 : 0.11)
        ..strokeWidth = anyHighlighted ? 7.2 : 5.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final paintLine = Paint()
        ..color = parentColor.withValues(alpha: anyHighlighted ? 0.95 : 0.78)
        ..strokeWidth = anyHighlighted ? 3.2 : 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      if ((parentJoin - Offset(parentJoin.dx, junctionY)).distanceSquared >=
          _minLinkDistanceSquared) {
        canvas.drawLine(parentJoin, Offset(parentJoin.dx, junctionY), paintGlow);
        canvas.drawLine(parentJoin, Offset(parentJoin.dx, junctionY), paintLine);
      }

      if ((maxChildX - minChildX).abs() > 0.1) {
        canvas.drawLine(
          Offset(minChildX, junctionY),
          Offset(maxChildX, junctionY),
          paintGlow,
        );
        canvas.drawLine(
          Offset(minChildX, junctionY),
          Offset(maxChildX, junctionY),
          paintLine,
        );
      }

      for (int i = 0; i < childJoints.length; i++) {
        final childJoint = childJoints[i];
        final childNode = visibleChildren[i].node;
        final isHighlighted = selectedNodeId != null &&
            (p.node.id == selectedNodeId || childNode.id == selectedNodeId);

        final childLine = Paint()
          ..color = childNode.branchColor
              .withValues(alpha: isHighlighted ? 0.95 : 0.74)
          ..strokeWidth = isHighlighted ? 3.0 : 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        final childGlow = Paint()
          ..color = parentColor.withValues(alpha: isHighlighted ? 0.18 : 0.10)
          ..strokeWidth = isHighlighted ? 6.8 : 4.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        final from = Offset(childJoint.dx, junctionY);
        if ((from - childJoint).distanceSquared < _minLinkDistanceSquared) {
          continue;
        }

        canvas.drawLine(from, childJoint, childGlow);
        canvas.drawLine(from, childJoint, childLine);

        if (isHighlighted) {
          canvas.drawCircle(
            childJoint,
            3.8,
            Paint()..color = childNode.branchColor.withValues(alpha: 0.95),
          );
        }
      }

      if (anyHighlighted) {
        canvas.drawCircle(
          parentJoin,
          4.2,
          Paint()..color = parentColor.withValues(alpha: 0.96),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant FamilyTreePainter old) {
    return old.positions != positions ||
        old.selectedNodeId != selectedNodeId ||
        old.visibleIds != visibleIds;
  }
}
