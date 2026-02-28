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
  TreeLayoutResult({required this.positions, required this.canvasSize});
}

class TidyTreeLayout {
  static const double nodeWidth   = 120.0;
  static const double nodeHeight  = 140.0;
  static const double siblingGap  = 28.0;
  static const double verticalGap = 70.0;
  static const double rootGap     = 60.0;
  static const double padding     = 60.0;

  static TreeLayoutResult layout(List<TreeNode> roots) {
    if (roots.isEmpty) {
      return TreeLayoutResult(positions: [], canvasSize: const Size(400, 400));
    }

    final subtreeWidth = <String, double>{};

    double calcWidth(TreeNode n) {
      if (n.children.isEmpty) {
        subtreeWidth[n.id] = nodeWidth;
        return nodeWidth;
      }
      double sum = 0;
      for (int i = 0; i < n.children.length; i++) {
        sum += calcWidth(n.children[i]);
        if (i != n.children.length - 1) sum += siblingGap;
      }
      sum = math.max(sum, nodeWidth);
      subtreeWidth[n.id] = sum;
      return sum;
    }

    for (final r in roots) calcWidth(r);

    final positions   = <NodePosition>[];
    final nodeXCenter = <String, double>{};

    void place(TreeNode n, double leftX, int level) {
      final y = padding + level * (nodeHeight + verticalGap);

      if (n.children.isEmpty) {
        final cx = leftX + nodeWidth / 2;
        nodeXCenter[n.id] = cx;
        positions.add(NodePosition(node: n, x: leftX, y: y, level: level));
        return;
      }

      double childLeft = leftX;
      for (final c in n.children) {
        place(c, childLeft, level + 1);
        childLeft += (subtreeWidth[c.id] ?? nodeWidth) + siblingGap;
      }

      // الأب فوق مركز أبنائه المباشرين
      final firstCX = nodeXCenter[n.children.first.id]!;
      final lastCX  = nodeXCenter[n.children.last.id]!;
      final parentCX = (firstCX + lastCX) / 2;
      nodeXCenter[n.id] = parentCX;
      positions.add(NodePosition(node: n, x: parentCX - nodeWidth / 2, y: y, level: level));
    }

    // ترتيب الجذور: الأصغر أولاً
    final sortedRoots = List<TreeNode>.from(roots)
      ..sort((a, b) => (subtreeWidth[a.id] ?? 0).compareTo(subtreeWidth[b.id] ?? 0));

    double currentLeft = padding;
    for (final r in sortedRoots) {
      place(r, currentLeft, 0);
      currentLeft += (subtreeWidth[r.id] ?? nodeWidth) + rootGap;
    }

    // إعادة ترتيب: الأب قبل أبنائه للـ painter
    final posById = <String, NodePosition>{};
    for (final p in positions) posById[p.node.id] = p;

    final ordered = <NodePosition>[];
    void addOrdered(TreeNode n) {
      final p = posById[n.id];
      if (p != null) ordered.add(p);
      for (final c in n.children) addOrdered(c);
    }
    for (final r in sortedRoots) addOrdered(r);

    double maxX = 0, maxY = 0;
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