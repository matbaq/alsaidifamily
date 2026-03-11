import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/tree_node.dart';

enum TreeVerticalDirection {
  topToBottom,
  bottomToTop,
}

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

class TreeLayoutConfig {
  final double nodeWidth;
  final double nodeHeight;
  final double siblingGap;
  final double rootGap;
  final double levelGap;
  final double padding;
  final TreeVerticalDirection direction;

  const TreeLayoutConfig({
    this.nodeWidth = 120,
    this.nodeHeight = 140,
    this.siblingGap = 22,
    this.rootGap = 52,
    this.levelGap = 92,
    this.padding = 72,
    this.direction = TreeVerticalDirection.bottomToTop,
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
  static TreeLayoutResult layout(
    List<TreeNode> roots, {
    TreeLayoutConfig config = const TreeLayoutConfig(),
  }) {
    if (roots.isEmpty) {
      return TreeLayoutResult(
        positions: const [],
        canvasSize: const Size(400, 400),
      );
    }

    final subtreeWidth = <String, double>{};
    final orderedChildren = <String, List<TreeNode>>{};

    double calcSubtreeWidth(TreeNode node) {
      if (node.isCollapsed || node.children.isEmpty) {
        orderedChildren[node.id] = const [];
        subtreeWidth[node.id] = config.nodeWidth;
        return config.nodeWidth;
      }

      final kids = List<TreeNode>.from(node.children)
        ..sort((a, b) => a.name.compareTo(b.name));

      orderedChildren[node.id] = kids;

      double childrenBand = 0;
      for (int i = 0; i < kids.length; i++) {
        childrenBand += calcSubtreeWidth(kids[i]);
        if (i != kids.length - 1) childrenBand += config.siblingGap;
      }

      final width = math.max(config.nodeWidth, childrenBand);
      subtreeWidth[node.id] = width;
      return width;
    }

    for (final root in roots) {
      calcSubtreeWidth(root);
    }

    final positions = <NodePosition>[];

    void place(TreeNode node, double leftX, int level) {
      final width = subtreeWidth[node.id] ?? config.nodeWidth;
      final nodeX = leftX + (width - config.nodeWidth) / 2;
      final nodeY = config.padding + level * (config.nodeHeight + config.levelGap);

      positions.add(
        NodePosition(node: node, x: nodeX, y: nodeY, level: level),
      );

      if (node.isCollapsed || node.children.isEmpty) return;

      final kids = orderedChildren[node.id] ?? const <TreeNode>[];
      double childLeft = leftX;
      for (int i = 0; i < kids.length; i++) {
        final c = kids[i];
        place(c, childLeft, level + 1);
        childLeft += (subtreeWidth[c.id] ?? config.nodeWidth) + config.siblingGap;
      }
    }

    double rootsLeft = config.padding;
    for (int i = 0; i < roots.length; i++) {
      final root = roots[i];
      place(root, rootsLeft, 0);
      rootsLeft += (subtreeWidth[root.id] ?? config.nodeWidth) + config.rootGap;
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;

    for (final p in positions) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x + config.nodeWidth);
      maxY = math.max(maxY, p.y + config.nodeHeight);
    }

    final normalized = positions
        .map(
          (p) => NodePosition(
            node: p.node,
            x: p.x - minX + config.padding,
            y: p.y - minY + config.padding,
            level: p.level,
          ),
        )
        .toList();

    final height = (maxY - minY) + config.padding * 2;

    if (config.direction == TreeVerticalDirection.bottomToTop) {
      for (final p in normalized) {
        p.y = height - p.y - config.nodeHeight;
      }
    }

    return TreeLayoutResult(
      positions: normalized,
      canvasSize: Size(
        (maxX - minX) + config.padding * 2,
        height,
      ),
    );
  }
}
