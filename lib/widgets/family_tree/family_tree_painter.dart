import 'package:flutter/material.dart';

import 'tidy_tree_layout.dart';

class FamilyTreePainter extends CustomPainter {
  final List<NodePosition> positions;
  final String? selectedNodeId;
  final Set<String> visibleIds;

  static const double nodeWidth = 120.0;
  static const double nodeHeight = 140.0;
  static const double toggleBtnOffset = 14.0;

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

      for (final child in p.node.children) {
        final childPos = posById[child.id];
        if (childPos == null || !visibleIds.contains(child.id)) continue;

        final isHighlighted = selectedNodeId != null &&
            (p.node.id == selectedNodeId || child.id == selectedNodeId);

        final parentColor = p.node.branchColor;
        final childColor = child.branchColor;

        final parentCenter = Offset(p.x + nodeWidth / 2, p.y + nodeHeight / 2);
        final childCenter = Offset(childPos.x + nodeWidth / 2, childPos.y + nodeHeight / 2);

        final parentAboveChild = parentCenter.dy < childCenter.dy;

        final from = Offset(
          parentCenter.dx,
          parentAboveChild ? p.y + nodeHeight - toggleBtnOffset : p.y,
        );
        final to = Offset(
          childCenter.dx,
          parentAboveChild ? childPos.y : childPos.y + nodeHeight - toggleBtnOffset,
        );

        final midY = (from.dy + to.dy) / 2;
        final dx = to.dx - from.dx;
        final dy1 = midY - from.dy;
        final dy2 = to.dy - midY;

        const maxCornerRadius = 15.0;
        final cornerRadius = [
          maxCornerRadius,
          dx.abs() / 2,
          dy1.abs(),
          dy2.abs(),
        ].reduce((a, b) => a < b ? a : b);

        final path = Path()..moveTo(from.dx, from.dy);

        if (cornerRadius <= 0.01 || dx.abs() <= 0.01) {
          path
            ..lineTo(from.dx, midY)
            ..lineTo(to.dx, midY)
            ..lineTo(to.dx, to.dy);
        } else {
          final xDir = dx.isNegative ? -1.0 : 1.0;
          final y1Dir = dy1.isNegative ? -1.0 : 1.0;
          final y2Dir = dy2.isNegative ? -1.0 : 1.0;

          path
            ..lineTo(from.dx, midY - y1Dir * cornerRadius)
            ..quadraticBezierTo(
              from.dx,
              midY,
              from.dx + xDir * cornerRadius,
              midY,
            )
            ..lineTo(to.dx - xDir * cornerRadius, midY)
            ..quadraticBezierTo(
              to.dx,
              midY,
              to.dx,
              midY + y2Dir * cornerRadius,
            )
            ..lineTo(to.dx, to.dy);
        }

        final rect = Rect.fromPoints(from, to);
        final safeRect = rect.width < 1 || rect.height < 1
            ? Rect.fromCenter(
                center: rect.center,
                width: rect.width.clamp(2, 9999),
                height: rect.height.clamp(2, 9999),
              )
            : rect;

        final glowPaint = Paint()
          ..color = parentColor.withValues(alpha: isHighlighted ? 0.18 : 0.10)
          ..strokeWidth = isHighlighted ? 7.0 : 5.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        final linePaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              parentColor.withValues(alpha: isHighlighted ? 0.96 : 0.72),
              childColor.withValues(alpha: isHighlighted ? 0.92 : 0.46),
            ],
          ).createShader(safeRect)
          ..strokeWidth = isHighlighted ? 3.0 : 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, linePaint);

        if (isHighlighted) {
          canvas.drawCircle(
            from,
            4.2,
            Paint()..color = parentColor.withValues(alpha: 0.95),
          );
          canvas.drawCircle(
            to,
            4.2,
            Paint()..color = childColor.withValues(alpha: 0.95),
          );
        }
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
