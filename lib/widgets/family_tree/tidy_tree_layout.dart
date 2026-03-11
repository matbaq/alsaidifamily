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
    this.siblingGap = 20,
    this.rootGap = 28,
    this.levelGap = 68,
    this.padding = 16,
    this.direction = TreeVerticalDirection.topToBottom,
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

class _TidyNode {
  final TreeNode treeNode;
  final int depth;
  final _TidyNode? parent;
  final List<_TidyNode> children;
  _TidyNode? thread;
  _TidyNode? ancestor;
  double prelim = 0;
  double modifier = 0;
  double change = 0;
  double shift = 0;
  final int number;

  _TidyNode({
    required this.treeNode,
    required this.depth,
    required this.parent,
    required this.children,
    required this.number,
  }) {
    ancestor = this;
  }

  _TidyNode? get leftSibling {
    if (parent == null || number == 0) return null;
    return parent!.children[number - 1];
  }

  _TidyNode? get leftMostChild => children.isEmpty ? null : children.first;
  _TidyNode? get rightMostChild => children.isEmpty ? null : children.last;
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

    final positions = <NodePosition>[];

    final horizontalUnit = config.nodeWidth + config.siblingGap;
    final rootUnitGap = config.rootGap + config.nodeWidth;
    double forestOffsetUnits = 0;

    for (final root in roots) {
      final tidyRoot = _buildTidyTree(root, null, 0, 0);
      _firstWalk(tidyRoot);
      _secondWalk(
        tidyRoot,
        config,
        positions,
        forestOffsetUnits,
        horizontalUnit,
      );

      final extent = _measureSubtreeExtentUnits(tidyRoot);
      forestOffsetUnits += extent + (rootUnitGap / horizontalUnit);
    }

    return _normalizeAndBuildCanvas(positions, config);
  }

  static _TidyNode _buildTidyTree(
    TreeNode node,
    _TidyNode? parent,
    int depth,
    int number,
  ) {
    final children = node.isCollapsed
        ? const <TreeNode>[]
        : (List<TreeNode>.from(node.children)
          ..sort((a, b) => a.name.compareTo(b.name)));

    final tidy = _TidyNode(
      treeNode: node,
      depth: depth,
      parent: parent,
      children: <_TidyNode>[],
      number: number,
    );

    for (int i = 0; i < children.length; i++) {
      tidy.children.add(_buildTidyTree(children[i], tidy, depth + 1, i));
    }

    return tidy;
  }

  static void _firstWalk(_TidyNode v) {
    if (v.children.isEmpty) {
      final left = v.leftSibling;
      v.prelim = left == null ? 0 : left.prelim + 1;
      return;
    }

    _TidyNode defaultAncestor = v.children.first;
    for (final child in v.children) {
      _firstWalk(child);
      defaultAncestor = _apportion(child, defaultAncestor);
    }

    _executeShifts(v);

    final midpoint =
        (v.children.first.prelim + v.children.last.prelim) / 2.0;

    final left = v.leftSibling;
    if (left != null) {
      v.prelim = left.prelim + 1;
      v.modifier = v.prelim - midpoint;
    } else {
      v.prelim = midpoint;
    }
  }

  static _TidyNode _apportion(_TidyNode v, _TidyNode defaultAncestor) {
    final leftSibling = v.leftSibling;
    if (leftSibling == null) return defaultAncestor;

    _TidyNode vir = v;
    _TidyNode vor = v;
    _TidyNode vil = leftSibling;
    _TidyNode vol = v.parent!.children.first;

    double sir = vir.modifier;
    double sor = vor.modifier;
    double sil = vil.modifier;
    double sol = vol.modifier;

    while (_nextRight(vil) != null && _nextLeft(vir) != null) {
      vil = _nextRight(vil)!;
      vir = _nextLeft(vir)!;
      vol = _nextLeft(vol)!;
      vor = _nextRight(vor)!;
      vor.ancestor = v;

      final shift = (vil.prelim + sil) - (vir.prelim + sir) + 1.0;
      if (shift > 0) {
        final a = _ancestor(vil, v, defaultAncestor);
        _moveSubtree(a, v, shift);
        sir += shift;
        sor += shift;
      }

      sil += vil.modifier;
      sir += vir.modifier;
      sol += vol.modifier;
      sor += vor.modifier;
    }

    if (_nextRight(vil) != null && _nextRight(vor) == null) {
      vor.thread = _nextRight(vil);
      vor.modifier += sil - sor;
    }

    if (_nextLeft(vir) != null && _nextLeft(vol) == null) {
      vol.thread = _nextLeft(vir);
      vol.modifier += sir - sol;
      defaultAncestor = v;
    }

    return defaultAncestor;
  }

  static void _moveSubtree(_TidyNode wl, _TidyNode wr, double shift) {
    final subtrees = (wr.number - wl.number).toDouble();
    if (subtrees <= 0) return;

    wr.change -= shift / subtrees;
    wr.shift += shift;
    wl.change += shift / subtrees;
    wr.prelim += shift;
    wr.modifier += shift;
  }

  static void _executeShifts(_TidyNode v) {
    double shift = 0;
    double change = 0;

    for (int i = v.children.length - 1; i >= 0; i--) {
      final w = v.children[i];
      w.prelim += shift;
      w.modifier += shift;
      change += w.change;
      shift += w.shift + change;
    }
  }

  static _TidyNode _ancestor(_TidyNode vil, _TidyNode v, _TidyNode defaultAncestor) {
    if (vil.ancestor != null && vil.ancestor!.parent == v.parent) {
      return vil.ancestor!;
    }
    return defaultAncestor;
  }

  static _TidyNode? _nextLeft(_TidyNode v) => v.leftMostChild ?? v.thread;
  static _TidyNode? _nextRight(_TidyNode v) => v.rightMostChild ?? v.thread;

  static void _secondWalk(
    _TidyNode v,
    TreeLayoutConfig config,
    List<NodePosition> out,
    double forestOffsetUnits,
    double horizontalUnit,
    [double modifierSum = 0],
  ) {
    final xUnits = v.prelim + modifierSum + forestOffsetUnits;
    final y = v.depth * (config.nodeHeight + config.levelGap);

    out.add(
      NodePosition(
        node: v.treeNode,
        x: xUnits * horizontalUnit,
        y: y,
        level: v.depth,
      ),
    );

    for (final child in v.children) {
      _secondWalk(
        child,
        config,
        out,
        forestOffsetUnits,
        horizontalUnit,
        modifierSum + v.modifier,
      );
    }
  }

  static double _measureSubtreeExtentUnits(_TidyNode root) {
    double minX = double.infinity;
    double maxX = -double.infinity;

    void visit(_TidyNode n, [double mod = 0]) {
      final x = n.prelim + mod;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      for (final c in n.children) {
        visit(c, mod + n.modifier);
      }
    }

    visit(root);
    if (!minX.isFinite || !maxX.isFinite) return 1;
    return (maxX - minX) + 1;
  }

  static TreeLayoutResult _normalizeAndBuildCanvas(
    List<NodePosition> positions,
    TreeLayoutConfig config,
  ) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;

    for (final p in positions) {
      final left = p.x - config.nodeWidth / 2;
      final top = p.y;
      final right = left + config.nodeWidth;
      final bottom = top + config.nodeHeight;
      minX = math.min(minX, left);
      minY = math.min(minY, top);
      maxX = math.max(maxX, right);
      maxY = math.max(maxY, bottom);
    }

    final width = (maxX - minX) + config.padding * 2;
    final height = (maxY - minY) + config.padding * 2;

    final normalized = positions
        .map((p) {
          final centeredX = p.x - config.nodeWidth / 2;
          final normX = centeredX - minX + config.padding;
          final normY = p.y - minY + config.padding;
          return NodePosition(node: p.node, x: normX, y: normY, level: p.level);
        })
        .toList();

    if (config.direction == TreeVerticalDirection.bottomToTop) {
      for (final p in normalized) {
        p.y = height - p.y - config.nodeHeight;
      }
    }

    return TreeLayoutResult(
      positions: normalized,
      canvasSize: Size(width, height),
    );
  }
}
