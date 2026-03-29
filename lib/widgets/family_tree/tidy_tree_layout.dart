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
  static const double siblingGap = 35.0;
  static const double verticalGap = 120.0;
  static const double rootGap = 100.0;
  static const double padding = 100.0;

  static TreeLayoutResult layout(List<TreeNode> roots) {
    if (roots.isEmpty) {
      return TreeLayoutResult(
        positions: [],
        canvasSize: const Size(400, 400),
      );
    }

    final subtreeWidth = <String, double>{};

    double calcWidth(TreeNode node) {
      if (node.children.isEmpty || node.isCollapsed) {
        subtreeWidth[node.id] = nodeWidth;
        return nodeWidth;
      }

      double totalWidth = 0;
      for (int i = 0; i < node.children.length; i++) {
        totalWidth += calcWidth(node.children[i]);
        if (i != node.children.length - 1) {
          totalWidth += siblingGap;
        }
      }

      totalWidth = math.max(totalWidth, nodeWidth);
      subtreeWidth[node.id] = totalWidth;
      return totalWidth;
    }

    for (final root in roots) {
      calcWidth(root);
    }

    final positions = <NodePosition>[];
    final nodeXCenter = <String, double>{};

    void place(TreeNode node, double leftX, int level) {
      final y = padding + level * (nodeHeight + verticalGap);

      if (node.children.isEmpty || node.isCollapsed) {
        final centerX = leftX + nodeWidth / 2;
        nodeXCenter[node.id] = centerX;
        positions.add(
          NodePosition(
            node: node,
            x: leftX,
            y: y,
            level: level,
          ),
        );
        return;
      }

      double childLeft = leftX;
      for (final child in node.children) {
        place(child, childLeft, level + 1);
        childLeft += (subtreeWidth[child.id] ?? nodeWidth) + siblingGap;
      }

      final firstCenter = nodeXCenter[node.children.first.id]!;
      final lastCenter = nodeXCenter[node.children.last.id]!;
      final parentCenter = (firstCenter + lastCenter) / 2;

      nodeXCenter[node.id] = parentCenter;

      positions.add(
        NodePosition(
          node: node,
          x: parentCenter - nodeWidth / 2,
          y: y,
          level: level,
        ),
      );
    }

    final sortedRoots = List<TreeNode>.from(roots)
      ..sort(
            (a, b) =>
            (subtreeWidth[a.id] ?? 0).compareTo(subtreeWidth[b.id] ?? 0),
      );

    double currentLeft = padding;
    for (final root in sortedRoots) {
      place(root, currentLeft, 0);
      currentLeft += (subtreeWidth[root.id] ?? nodeWidth) + rootGap;
    }

    final posById = <String, NodePosition>{};
    for (final pos in positions) {
      posById[pos.node.id] = pos;
    }

    final ordered = <NodePosition>[];

    void addOrdered(TreeNode node) {
      final pos = posById[node.id];
      if (pos != null) {
        ordered.add(pos);
      }

      if (!node.isCollapsed) {
        for (final child in node.children) {
          addOrdered(child);
        }
      }
    }

    for (final root in sortedRoots) {
      addOrdered(root);
    }

    double maxX = 0;
    double maxY = 0;

    for (final pos in ordered) {
      maxX = math.max(maxX, pos.x + nodeWidth);
      maxY = math.max(maxY, pos.y + nodeHeight);
    }

    return TreeLayoutResult(
      positions: ordered,
      canvasSize: Size(maxX + padding, maxY + padding),
    );
  }
}