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

    final posById = <String, NodePosition>{};
    for (final p in positions) {
      posById[p.node.id] = p;
    }

    for (final p in positions) {
      if (!visibleIds.contains(p.node.id)) continue;

      for (final child in p.node.children) {
        final childPos = posById[child.id];
        if (childPos == null) continue;
        if (!visibleIds.contains(child.id)) continue;

        final isHighlighted = selectedNodeId != null &&
            (p.node.id == selectedNodeId || child.id == selectedNodeId);

        final parentColor = p.node.branchColor;
        final childColor = child.branchColor;

        final parentCX = p.x + nodeWidth / 2;
        final childCX = childPos.x + nodeWidth / 2;

        // الجد أسفل - الأبناء فوق
        final parentTopY = p.y;
        final childBotY = childPos.y + nodeHeight - toggleBtnOffset;

        final midY = (parentTopY + childBotY) / 2;

        // مسار أنظف: عمودي ثم أفقي ثم عمودي
        final path = Path()
          ..moveTo(parentCX, parentTopY)
          ..lineTo(parentCX, midY)
          ..quadraticBezierTo(
            parentCX,
            childBotY,
            childCX,
            childBotY,
          );

        final rect = Rect.fromLTRB(
          parentCX < childCX ? parentCX : childCX,
          childBotY < parentTopY ? childBotY : parentTopY,
          parentCX > childCX ? parentCX : childCX,
          childBotY > parentTopY ? childBotY : parentTopY,
        );

        final safeRect = rect.width < 1 || rect.height < 1
            ? Rect.fromCenter(
          center: rect.center,
          width: 2,
          height: rect.height.clamp(2, 9999),
        )
            : rect;

        final shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            parentColor.withValues(alpha: isHighlighted ? 0.95 : 0.65),
            childColor.withValues(alpha: isHighlighted ? 0.85 : 0.35),
          ],
        ).createShader(safeRect);

        final paint = Paint()
          ..shader = shader
          ..strokeWidth = isHighlighted ? 3.2 : 2.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        canvas.drawPath(path, paint);

        if (isHighlighted) {
          canvas.drawCircle(
            Offset(parentCX, parentTopY),
            4.5,
            Paint()..color = parentColor.withValues(alpha: 0.9),
          );
          canvas.drawCircle(
            Offset(childCX, childBotY),
            4.5,
            Paint()..color = childColor.withValues(alpha: 0.9),
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