import 'package:flutter/material.dart';
import 'node_widget.dart';
import 'tidy_tree_layout.dart';

class FamilyTreePainter extends CustomPainter {
  final List<NodePosition> positions;
  final String? selectedNodeId;

  static const double nodeWidth  = 120.0;
  static const double nodeHeight = 140.0;
  static const double toggleBtnOffset = 14.0;

  FamilyTreePainter({required this.positions, this.selectedNodeId});

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;

    final posById = <String, NodePosition>{};
    for (final p in positions) posById[p.node.id] = p;

    for (final p in positions) {
      for (final child in p.node.children) {
        final childPos = posById[child.id];
        if (childPos == null) continue;

        final isHighlighted = selectedNodeId != null &&
            (p.node.id == selectedNodeId || child.id == selectedNodeId);

        final parentLevel = p.level;
        final childLevel  = childPos.level;

        final parentColor = GenerationPalette.primaryForLevel(parentLevel);
        final childColor  = GenerationPalette.primaryForLevel(childLevel);

        final parentCX = p.x + nodeWidth / 2;
        final childCX  = childPos.x + nodeWidth / 2;

        // الشجرة مقلوبة: الجد أسفل، الأبناء فوقه
        final parentTopY  = p.y;
        final childBotY   = childPos.y + nodeHeight - toggleBtnOffset;

        final ctrl = (parentTopY - childBotY).abs() * 0.5;

        final path = Path()
          ..moveTo(parentCX, parentTopY)
          ..cubicTo(
            parentCX, parentTopY - ctrl,
            childCX,  childBotY  + ctrl,
            childCX,  childBotY,
          );

        final rect = Rect.fromLTRB(
          parentCX < childCX ? parentCX : childCX,
          childBotY < parentTopY ? childBotY : parentTopY,
          parentCX > childCX ? parentCX : childCX,
          childBotY > parentTopY ? childBotY : parentTopY,
        );

        final safeRect = rect.width < 1 || rect.height < 1
            ? Rect.fromCenter(center: rect.center, width: 2, height: rect.height.clamp(2, 9999))
            : rect;

        final shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            parentColor.withValues(alpha: isHighlighted ? 0.9 : 0.5),
            childColor.withValues(alpha: isHighlighted ? 0.7 : 0.25),
          ],
        ).createShader(safeRect);

        final paint = Paint()
          ..shader = shader
          ..strokeWidth = isHighlighted ? 3.0 : 1.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        canvas.drawPath(path, paint);

        if (isHighlighted) {
          canvas.drawCircle(
            Offset(parentCX, parentTopY), 4.5,
            Paint()..color = parentColor.withValues(alpha: 0.85),
          );
          canvas.drawCircle(
            Offset(childCX, childBotY), 4.5,
            Paint()..color = childColor.withValues(alpha: 0.85),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant FamilyTreePainter old) =>
      old.positions != positions || old.selectedNodeId != selectedNodeId;
}