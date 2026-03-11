import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/tree_node.dart';

class NodePosition {
  final TreeNode node;
  double x;
  double y;
  final int level;

  NodePosition({
    required this.node,
    required this.x,
    required this.y,
    required this.level,
  });
}

class TreeLayoutResult {
  final List<NodePosition> positions;
  final Size canvasSize;

  TreeLayoutResult({
    required this.positions,
    required this.canvasSize,
  });
}

class TidyTreeLayout {
  static const double nodeWidth = 120.0;
  static const double nodeHeight = 140.0;

  // تقليل التمدد الأفقي
  static const double siblingGap = 22.0;
  static const double verticalGap = 105.0;
  static const double rootGap = 70.0;
  static const double padding = 90.0;

  static TreeLayoutResult layout(List<TreeNode> roots) {
    if (roots.isEmpty) {
      return TreeLayoutResult(
        positions: [],
        canvasSize: const Size(400, 400),
      );
    }

    final subtreeWidth = <String, double>{};
    final orderedChildren = <String, List<TreeNode>>{};

    int countVisibleDescendants(TreeNode n) {
      if (n.isCollapsed || n.children.isEmpty) return 0;
      int count = n.children.length;
      for (final c in n.children) {
        count += countVisibleDescendants(c);
      }
      return count;
    }

    double calcWidth(TreeNode n) {
      if (n.children.isEmpty || n.isCollapsed) {
        subtreeWidth[n.id] = nodeWidth;
        orderedChildren[n.id] = const [];
        return nodeWidth;
      }

      // نحسب عرض كل ابن أولًا
      for (final c in n.children) {
        calcWidth(c);
      }

      final kids = List<TreeNode>.from(n.children);

      // أهم فرع يكون هو "الساق الرئيسية" العمودية
      kids.sort((a, b) {
        final da = countVisibleDescendants(a);
        final db = countVisibleDescendants(b);
        if (da != db) return db.compareTo(da);

        final wa = subtreeWidth[a.id] ?? nodeWidth;
        final wb = subtreeWidth[b.id] ?? nodeWidth;
        if (wa != wb) return wb.compareTo(wa);

        return a.name.compareTo(b.name);
      });

      orderedChildren[n.id] = kids;

      final trunk = kids.first;
      final trunkWidth = subtreeWidth[trunk.id] ?? nodeWidth;

      double sideWidth = 0;
      for (int i = 1; i < kids.length; i++) {
        sideWidth += subtreeWidth[kids[i].id] ?? nodeWidth;
        if (i != kids.length - 1) {
          sideWidth += siblingGap;
        }
      }

      final total = kids.length == 1
          ? math.max(nodeWidth, trunkWidth)
          : math.max(nodeWidth, trunkWidth + siblingGap + sideWidth);

      subtreeWidth[n.id] = total;
      return total;
    }

    for (final r in roots) {
      calcWidth(r);
    }

    final positions = <NodePosition>[];
    final posById = <String, NodePosition>{};

    void place(TreeNode n, double leftX, int level) {
      final y = padding + level * (nodeHeight + verticalGap);

      final selfPos = NodePosition(
        node: n,
        x: leftX,
        y: y,
        level: level,
      );

      positions.add(selfPos);
      posById[n.id] = selfPos;

      if (n.children.isEmpty || n.isCollapsed) return;

      final kids = orderedChildren[n.id] ?? const <TreeNode>[];
      if (kids.isEmpty) return;

      // الابن الأول = الساق العمودية
      final trunk = kids.first;
      place(trunk, leftX, level + 1);

      // بقية الأبناء يتوزعون يمينًا
      double sideLeft =
          leftX + math.max(nodeWidth, subtreeWidth[trunk.id] ?? nodeWidth) + siblingGap;

      for (int i = 1; i < kids.length; i++) {
        final child = kids[i];
        place(child, sideLeft, level + 1);
        sideLeft += (subtreeWidth[child.id] ?? nodeWidth) + siblingGap;
      }
    }

    // نبقي ترتيب الجذور كما هو بدل الترتيب حسب العرض
    double currentLeft = padding;
    for (final r in roots) {
      place(r, currentLeft, 0);
      currentLeft += (subtreeWidth[r.id] ?? nodeWidth) + rootGap;
    }

    final ordered = <NodePosition>[];

    void addOrdered(TreeNode n) {
      final p = posById[n.id];
      if (p != null) ordered.add(p);

      if (!n.isCollapsed) {
        final kids = orderedChildren[n.id] ?? const <TreeNode>[];
        for (final c in kids) {
          addOrdered(c);
        }
      }
    }

    for (final r in roots) {
      addOrdered(r);
    }

    double maxX = 0;
    double maxY = 0;

    for (final p in ordered) {
      maxX = math.max(maxX, p.x + nodeWidth);
      maxY = math.max(maxY, p.y + nodeHeight);
    }

    return TreeLayoutResult(
      positions: ordered,
      canvasSize: Size(maxX + padding, maxY + padding),
    );
  }
}