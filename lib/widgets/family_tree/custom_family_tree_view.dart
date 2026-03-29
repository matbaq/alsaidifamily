import 'dart:math' as math;
import 'package:flutter/material.dart';

// ✅ تم ضبط المسار الصحيح للموديل الخاص بك
import '../../models/tree_node.dart';

class NodePosition {
  final TreeNode node;
  final double x;
  final double y;
  final int level;

  NodePosition({
    required this.node,
    required this.x,
    required this.y,
    required this.level,
  });
}

class CustomFamilyTreeView extends StatefulWidget {
  final List<TreeNode> roots;
  final Function(TreeNode)? onNodeTap;
  final String? selectedNodeId;

  // ✅ الخصائص المطلوبة للتحكم من خارج الشجرة (من صفحة family_tree_page)
  final TransformationController? externalController;
  final Function(String)? onToggleChildren;
  final Function(Map<String, Offset>, Rect, Size)? onLayoutReady;

  const CustomFamilyTreeView({
    super.key,
    required this.roots,
    this.onNodeTap,
    this.selectedNodeId,
    this.externalController,
    this.onToggleChildren,
    this.onLayoutReady,
  });

  @override
  State<CustomFamilyTreeView> createState() => _CustomFamilyTreeViewState();
}

class _LayoutNode {
  final TreeNode data;
  final List<_LayoutNode> children;
  _LayoutNode? parent;

  double prelim = 0;
  double mod = 0;
  double change = 0;
  double shift = 0;
  _LayoutNode? thread;
  _LayoutNode? ancestor;
  int number = 1;

  double x = 0;
  double y = 0;
  int depth = 0;

  _LayoutNode(this.data, this.children) {
    for (final c in children) {
      c.parent = this;
    }
    ancestor = this;
  }

  _LayoutNode? leftMostChild() => children.isEmpty ? null : children.first;
  _LayoutNode? rightMostChild() => children.isEmpty ? null : children.last;

  _LayoutNode? leftSibling() {
    if (parent == null) return null;
    final siblings = parent!.children;
    final idx = siblings.indexOf(this);
    if (idx <= 0) return null;
    return siblings[idx - 1];
  }

  _LayoutNode? rightSibling() {
    if (parent == null) return null;
    final siblings = parent!.children;
    final idx = siblings.indexOf(this);
    if (idx < 0 || idx + 1 >= siblings.length) return null;
    return siblings[idx + 1];
  }

  _LayoutNode? nextLeft() => children.isNotEmpty ? children.first : thread;
  _LayoutNode? nextRight() => children.isNotEmpty ? children.last : thread;
}

class _CustomFamilyTreeViewState extends State<CustomFamilyTreeView> {
  late TransformationController _controller;
  final List<NodePosition> _positions = [];
  Size _treeSize = Size.zero;

  static const double nodeWidth = 140.0;
  static const double nodeHeight = 160.0;
  static const double siblingGap = 20.0;
  static const double verticalGap = 80.0;
  static const double rootGap = 60.0;
  static const double padding = 40.0;

  static const double minScale = 0.05;
  static const double maxScale = 5.0;
  static const double initialScale = 0.6;

  @override
  void initState() {
    super.initState();
    // استخدام المتحكم الخارجي القادم من الصفحة
    _controller = widget.externalController ?? TransformationController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuild();
      if (widget.externalController == null) {
        _setInitialZoom();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CustomFamilyTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roots != widget.roots) _rebuild();
  }

  void _setInitialZoom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;

      final screen = MediaQuery.of(context).size;
      final scaledW = _treeSize.width * initialScale;

      final dx = (scaledW - screen.width) / 2;
      final dy = -40.0;

      _controller.value = Matrix4.identity()
        ..scale(initialScale)
        ..translate(-dx / initialScale, -dy / initialScale);
    });
  }

  void _rebuild() {
    _positions.clear();

    if (widget.roots.isEmpty) {
      setState(() => _treeSize = const Size(400, 400));
      widget.onLayoutReady?.call({}, Rect.zero, _treeSize);
      return;
    }

    final layoutRoots = <_LayoutNode>[];
    for (final r in widget.roots) {
      layoutRoots.add(_buildLayoutTree(r));
    }

    double cursorX = padding;

    for (final root in layoutRoots) {
      _assignNumbers(root);

      _firstWalk(root, 0);
      _secondWalk(root, 0, 0);

      final bounds = _boundsOf(root);
      final minX = bounds.$1;
      final maxX = bounds.$2;
      final minY = bounds.$3;

      final shiftX = cursorX - minX;
      final shiftY = padding - minY;

      final collected = <_LayoutNode>[];
      _collect(root, collected);

      for (final n in collected) {
        n.x += shiftX;
        n.y += shiftY;
      }

      final width = (maxX - minX) + nodeWidth;
      cursorX += width + rootGap;
    }

    double maxXAll = 0;
    double maxYAll = 0;
    final allNodes = <_LayoutNode>[];

    for (final root in layoutRoots) {
      _collect(root, allNodes);
    }

    for (final n in allNodes) {
      maxXAll = math.max(maxXAll, n.x + nodeWidth);
      maxYAll = math.max(maxYAll, n.y + nodeHeight);
    }

    final totalHeight = maxYAll + padding;

    final centers = <String, Offset>{};
    double calcMinX = double.infinity, calcMinY = double.infinity;
    double calcMaxX = -double.infinity, calcMaxY = -double.infinity;

    for (final n in allNodes) {
      // ✅ قلب الـ Y-Axis لتبدأ الشجرة من الأسفل وتتجه للأعلى
      final flippedY = totalHeight - nodeHeight - n.y;

      _positions.add(
        NodePosition(
          node: n.data,
          x: n.x,
          y: flippedY,
          level: n.depth,
        ),
      );

      centers[n.data.id] = Offset(n.x + nodeWidth / 2, flippedY + nodeHeight / 2);

      calcMinX = math.min(calcMinX, n.x);
      calcMinY = math.min(calcMinY, flippedY);
      calcMaxX = math.max(calcMaxX, n.x + nodeWidth);
      calcMaxY = math.max(calcMaxY, flippedY + nodeHeight);
    }

    final computedBounds = Rect.fromLTRB(
      calcMinX == double.infinity ? 0 : calcMinX,
      calcMinY == double.infinity ? 0 : calcMinY,
      calcMaxX == -double.infinity ? 0 : calcMaxX,
      calcMaxY == -double.infinity ? 0 : calcMaxY,
    );

    setState(() {
      _treeSize = Size(
        maxXAll + padding,
        totalHeight + padding,
      );
    });

    widget.onLayoutReady?.call(centers, computedBounds, _treeSize);
  }

  _LayoutNode _buildLayoutTree(TreeNode node) {
    final kids = node.children.map(_buildLayoutTree).toList();
    return _LayoutNode(node, kids);
  }

  void _assignNumbers(_LayoutNode root) {
    final q = <_LayoutNode>[root];
    while (q.isNotEmpty) {
      final n = q.removeAt(0);
      for (int i = 0; i < n.children.length; i++) {
        n.children[i].number = i + 1;
        n.children[i].depth = n.depth + 1;
        q.add(n.children[i]);
      }
    }
  }

  void _collect(_LayoutNode n, List<_LayoutNode> out) {
    out.add(n);
    for (final c in n.children) _collect(c, out);
  }

  (double, double, double, double) _boundsOf(_LayoutNode root) {
    final nodes = <_LayoutNode>[];
    _collect(root, nodes);
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final n in nodes) {
      minX = math.min(minX, n.x);
      maxX = math.max(maxX, n.x);
      minY = math.min(minY, n.y);
      maxY = math.max(maxY, n.y);
    }
    return (minX, maxX, minY, maxY);
  }

  double get _distance => nodeWidth + siblingGap;

  void _firstWalk(_LayoutNode v, int depth) {
    if (v.children.isEmpty) {
      final left = v.leftSibling();
      v.prelim = (left == null) ? 0 : left.prelim + _distance;
    } else {
      _LayoutNode? defaultAncestor = v.children.first;
      for (final w in v.children) {
        _firstWalk(w, depth + 1);
        defaultAncestor = _apportion(w, defaultAncestor);
      }
      _executeShifts(v);

      final midpoint =
          (v.children.first.prelim + v.children.last.prelim) / 2.0;

      final left = v.leftSibling();
      if (left == null) {
        v.prelim = midpoint;
      } else {
        v.prelim = left.prelim + _distance;
        v.mod = v.prelim - midpoint;
      }
    }
  }

  // ✅ تطبيق Null Safety كامل
  _LayoutNode? _apportion(_LayoutNode v, _LayoutNode? defaultAncestor) {
    final w = v.leftSibling();
    if (w == null) return defaultAncestor;

    _LayoutNode? vir = v;
    _LayoutNode? vor = v;
    _LayoutNode? vil = w;
    _LayoutNode? vol = v.parent?.children.first;

    double sir = v.mod;
    double sor = v.mod;
    double sil = vil.mod;
    double sol = vol?.mod ?? 0;

    while (true) {
      final vilNext = vil?.nextRight();
      final virNext = vir?.nextLeft();

      if (vilNext == null || virNext == null) {
        break;
      }

      vil = vilNext;
      vir = virNext;
      vol = vol?.nextLeft();
      vor = vor?.nextRight();

      if (vor == null) {
        break;
      }

      vor.ancestor = v;

      final shift = (vil.prelim + sil) - (vir.prelim + sir) + _distance;
      if (shift > 0) {
        final a = _ancestor(vil, v, defaultAncestor);
        _moveSubtree(a, v, shift);
        sir += shift;
        sor += shift;
      }

      sil += vil.mod;
      sir += vir.mod;
      sol += vol?.mod ?? 0;
      sor += vor.mod;
    }

    final vilRight = vil?.nextRight();
    final vorRight = vor?.nextRight();
    if (vilRight != null && vorRight == null && vor != null) {
      vor.thread = vilRight;
      vor.mod += sil - sor;
    }

    final virLeft = vir?.nextLeft();
    final volLeft = vol?.nextLeft();
    if (virLeft != null && volLeft == null && vol != null) {
      vol.thread = virLeft;
      vol.mod += sir - sol;
      defaultAncestor = v;
    }

    return defaultAncestor;
  }

  _LayoutNode _ancestor(_LayoutNode? vil, _LayoutNode v, _LayoutNode? defaultAncestor) {
    if (vil == null) return defaultAncestor ?? v;
    if (vil.ancestor != null && vil.ancestor!.parent == v.parent) {
      return vil.ancestor!;
    }
    return defaultAncestor ?? v;
  }

  void _moveSubtree(_LayoutNode wl, _LayoutNode wr, double shift) {
    final subtrees = (wr.number - wl.number).toDouble();
    wr.change -= shift / subtrees;
    wr.shift += shift;
    wl.change += shift / subtrees;
    wr.prelim += shift;
    wr.mod += shift;
  }

  void _executeShifts(_LayoutNode v) {
    double shift = 0;
    double change = 0;
    for (int i = v.children.length - 1; i >= 0; i--) {
      final w = v.children[i];
      w.prelim += shift;
      w.mod += shift;
      change += w.change;
      shift += w.shift + change;
    }
  }

  void _secondWalk(_LayoutNode v, double m, double depth) {
    v.x = v.prelim + m;
    v.y = depth * (nodeHeight + verticalGap);
    for (final w in v.children) {
      _secondWalk(w, m + v.mod, depth + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.roots.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد بيانات لعرضها',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    return InteractiveViewer(
      transformationController: _controller,
      boundaryMargin: const EdgeInsets.all(2000),
      minScale: minScale,
      maxScale: maxScale,
      constrained: false,
      child: SizedBox(
        width: _treeSize.width,
        height: _treeSize.height,
        child: CustomPaint(
          painter: _FamilyTreePainter(
            positions: _positions,
            selectedNodeId: widget.selectedNodeId,
          ),
          child: Stack(
            children: _positions.map((pos) {
              return Positioned(
                left: pos.x,
                top: pos.y,
                child: _NodeWidget(
                  node: pos.node,
                  isSelected: pos.node.id == widget.selectedNodeId,
                  onTap: () => widget.onNodeTap?.call(pos.node),
                  onToggleChildren: () => widget.onToggleChildren?.call(pos.node.id),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (widget.externalController == null) {
      _controller.dispose();
    }
    super.dispose();
  }
}

class _FamilyTreePainter extends CustomPainter {
  final List<NodePosition> positions;
  final String? selectedNodeId;

  _FamilyTreePainter({
    required this.positions,
    this.selectedNodeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final parentPos in positions) {
      if (parentPos.node.children.isEmpty) continue;

      final parentCenterX =
          parentPos.x + _CustomFamilyTreeViewState.nodeWidth / 2;

      // ✅ الجد موجود في الأسفل، والأبناء فوقه
      // لذا نبدأ الرسم من أعلى مربع الجد (السطح العلوي له)
      final parentTopY = parentPos.y;

      for (final child in parentPos.node.children) {
        final childPos = positions.firstWhere((p) => p.node.id == child.id);
        final childCenterX =
            childPos.x + _CustomFamilyTreeViewState.nodeWidth / 2;

        // ✅ والابن موجود فوق الجد
        // لذا ننهي الرسم عند أسفل مربع الابن (السطح السفلي له)
        final childBottomY =
            childPos.y + _CustomFamilyTreeViewState.nodeHeight;

        _drawConnection(
          canvas,
          parentCenterX,
          parentTopY,
          childCenterX,
          childBottomY,
          parentPos.node.branchColor,
        );
      }
    }
  }

  void _drawConnection(
      Canvas canvas,
      double x1,
      double y1,
      double x2,
      double y2,
      Color color,
      ) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(x1, y1);

    final midY = (y1 + y2) / 2;
    path.cubicTo(
      x1,
      y1 - 30, // انحناء للأعلى من الجد
      x1,
      midY,
      x1,
      midY,
    );
    path.lineTo(x2, midY);
    path.cubicTo(
      x2,
      midY,
      x2,
      y2 + 30, // انحناء للأعلى نحو الابن
      x2,
      y2,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool Repaint(_FamilyTreePainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.selectedNodeId != selectedNodeId;
  }

  @override
  bool shouldRepaint(covariant _FamilyTreePainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.selectedNodeId != selectedNodeId;
  }
}

class _NodeWidget extends StatelessWidget {
  final TreeNode node;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onToggleChildren;

  const _NodeWidget({
    required this.node,
    required this.isSelected,
    this.onTap,
    this.onToggleChildren,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _CustomFamilyTreeViewState.nodeWidth,
        height: _CustomFamilyTreeViewState.nodeHeight,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2125) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? node.branchColor : node.branchColor.withValues(alpha: 0.4),
            width: isSelected ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: node.branchColor.withValues(alpha: isSelected ? 0.30 : 0.12),
              blurRadius: isSelected ? 12 : 6,
              offset: Offset(0, isSelected ? 4 : 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: node.branchColor, width: 2.5),
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: node.branchColor.withValues(alpha: 0.15),
                    backgroundImage: (node.photoUrl != null && node.photoUrl!.isNotEmpty)
                        ? NetworkImage(node.photoUrl!)
                        : null,
                    child: (node.photoUrl == null || node.photoUrl!.isEmpty)
                        ? Icon(Icons.person, size: 36, color: node.branchColor)
                        : null,
                  ),
                ),
                if (node.isRoot)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.star, size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: node.branchColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                node.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.grey[900],
                  shadows: [
                    Shadow(
                      color: node.branchColor.withValues(alpha: 0.25),
                      blurRadius: 3,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            // عرض عدد الأبناء (إما من الداتا المحسوبة أو من الأطفال المحملين)
            if (node.children.isNotEmpty || node.childrenCount > 0)
              GestureDetector(
                onTap: onToggleChildren,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: node.branchColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: node.branchColor.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (node.isCollapsed)
                        Icon(Icons.unfold_more_rounded, size: 14, color: node.branchColor),
                      Text(
                        ' ${node.childrenCount} ${node.childrenCount == 1 ? 'ابن' : 'أبناء'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}