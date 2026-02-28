import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import '../../models/tree_node.dart';
import 'tidy_tree_layout.dart';
import 'family_tree_painter.dart';
import 'node_widget.dart';

class CustomFamilyTreeView extends StatefulWidget {
  final List<TreeNode> roots;
  final Function(TreeNode)? onNodeTap;
  final String? selectedNodeId;
  final TransformationController? externalController;
  final void Function(Map<String, Offset> centers, Rect bounds, Size canvasSize)? onLayoutReady;
  final void Function(String nodeId)? onToggleChildren;

  const CustomFamilyTreeView({
    super.key,
    required this.roots,
    this.onNodeTap,
    this.selectedNodeId,
    this.externalController,
    this.onLayoutReady,
    this.onToggleChildren,
  });

  @override
  State<CustomFamilyTreeView> createState() => _CustomFamilyTreeViewState();
}

class _CustomFamilyTreeViewState extends State<CustomFamilyTreeView> {
  late final TransformationController _controller;
  bool _ownsController = false;
  List<NodePosition> _positions = [];
  Size _treeSize = const Size(400, 400);
  int _lastFingerprint = 0;
  bool _didInitialZoom = false;

  static const double nodeWidth = 120.0;
  static const double nodeHeight = 140.0;
  static const double minScale = 0.01;
  static const double maxScale = 5.0;

  final Set<String> _visibleIds = {};
  final Map<String, int> _levelMap = {};

  bool get _usingExternalController => widget.externalController != null;

  @override
  void initState() {
    super.initState();
    _controller = widget.externalController ?? TransformationController();
    _ownsController = widget.externalController == null;
    _controller.addListener(_onTransformChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _rebuild(force: true));
  }

  @override
  void didUpdateWidget(covariant CustomFamilyTreeView old) {
    super.didUpdateWidget(old);
    if (old.externalController != widget.externalController) {
      _controller.removeListener(_onTransformChanged);
      if (_ownsController) _controller.dispose();
      _controller = widget.externalController ?? TransformationController();
      _ownsController = widget.externalController == null;
      _controller.addListener(_onTransformChanged);
      _didInitialZoom = false;
    }
    _rebuild();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    if (_positions.isNotEmpty) _updateVisible();
  }

  int _fingerprint(List<TreeNode> roots) {
    int h = 17;
    void visit(TreeNode n) {
      h = 37 * h + n.id.hashCode;
      h = 37 * h + n.children.length;
      h = 37 * h + (n.isCollapsed ? 1 : 0);
      for (final c in n.children) visit(c);
    }
    for (final r in roots) visit(r);
    return h;
  }

  void _buildLevelMap(List<TreeNode> roots) {
    _levelMap.clear();
    void visit(TreeNode n, int level) {
      _levelMap[n.id] = level;
      for (final c in n.children) visit(c, level + 1);
    }
    for (final r in roots) visit(r, 0);
  }

  void _rebuild({bool force = false}) {
    if (widget.roots.isEmpty) {
      setState(() {
        _positions = [];
        _treeSize = const Size(400, 400);
        _lastFingerprint = 0;
        _visibleIds.clear();
        _levelMap.clear();
        _didInitialZoom = false;
      });
      widget.onLayoutReady?.call({}, Rect.zero, const Size(400, 400));
      return;
    }

    final fp = _fingerprint(widget.roots);
    if (!force && fp == _lastFingerprint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateVisible();
      });
      return;
    }

    _buildLevelMap(widget.roots);
    final result = TidyTreeLayout.layout(widget.roots);
    final canvasH = result.canvasSize.height;
    const pad = 60.0;

    final flipped = result.positions.map((p) => NodePosition(
      node: p.node,
      x: p.x,
      y: canvasH - p.y - nodeHeight,
      level: p.level,
    )).toList();

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in flipped) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x + nodeWidth > maxX) maxX = p.x + nodeWidth;
      if (p.y + nodeHeight > maxY) maxY = p.y + nodeHeight;
    }

    final shiftX = -minX + pad;
    final shiftY = -minY + pad;
    final normalized = flipped.map((p) => NodePosition(
      node: p.node,
      x: p.x + shiftX,
      y: p.y + shiftY,
      level: p.level,
    )).toList();

    final newSize = Size((maxX - minX) + pad * 2, (maxY - minY) + pad * 2);
    if (!_usingExternalController) _didInitialZoom = false;

    setState(() {
      _positions = normalized;
      _treeSize = newSize;
      _lastFingerprint = fp;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emitCenters();
      _setInitialZoom();
      _updateVisible(force: true);
    });
  }

  void _emitCenters() {
    final cb = widget.onLayoutReady;
    if (cb == null) return;
    final map = <String, Offset>{};
    for (final p in _positions) {
      map[p.node.id] = Offset(p.x + nodeWidth / 2, p.y + nodeHeight / 2);
    }
    cb(map, _computeBounds(), _treeSize);
  }

  Rect _computeBounds() {
    if (_positions.isEmpty) return Rect.zero;
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in _positions) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x + nodeWidth > maxX) maxX = p.x + nodeWidth;
      if (p.y + nodeHeight > maxY) maxY = p.y + nodeHeight;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _setInitialZoom() {
    if (_usingExternalController) return;
    if (_didInitialZoom) return;
    _didInitialZoom = true;
    final screen = MediaQuery.of(context).size;
    const margin = 48.0;
    final sx = (screen.width - margin * 2) / _treeSize.width;
    final sy = (screen.height - margin * 2) / _treeSize.height;
    final scale = math.min(sx, sy).clamp(minScale, 1.5);
    final tx = (screen.width - _treeSize.width * scale) / 2;
    final ty = (screen.height - _treeSize.height * scale) / 2;
    _controller.value = Matrix4.identity()..translate(tx, ty)..scale(scale);
  }

  void _updateVisible({bool force = false}) {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final inv = Matrix4.inverted(_controller.value);
    Offset toScene(Offset p) {
      final v = inv.transform3(Vector3(p.dx, p.dy, 0));
      return Offset(v.x, v.y);
    }
    final vs = box.size;
    final tl = toScene(Offset.zero);
    final br = toScene(Offset(vs.width, vs.height));
    final rect = Rect.fromPoints(tl, br).inflate(200);
    final newIds = <String>{};
    for (final p in _positions) {
      if (Rect.fromLTWH(p.x, p.y, nodeWidth, nodeHeight).overlaps(rect)) {
        newIds.add(p.node.id);
      }
    }
    if (newIds.isEmpty) {
      for (final p in _positions) newIds.add(p.node.id);
    }
    if (!force && newIds.length == _visibleIds.length && _visibleIds.containsAll(newIds)) return;
    setState(() {
      _visibleIds..clear()..addAll(newIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.roots.isEmpty) {
      return const Center(child: Text('لا توجد بيانات', style: TextStyle(fontSize: 18, color: Colors.grey)));
    }
    final visiblePos = _positions.where((p) => _visibleIds.contains(p.node.id)).toList();
    return InteractiveViewer(
      transformationController: _controller,
      boundaryMargin: const EdgeInsets.all(800),
      minScale: minScale,
      maxScale: maxScale,
      constrained: false,
      child: SizedBox(
        width: _treeSize.width,
        height: _treeSize.height,
        child: CustomPaint(
          painter: FamilyTreePainter(positions: _positions, selectedNodeId: widget.selectedNodeId),
          child: Stack(
            children: visiblePos.map((pos) {
              final level = _levelMap[pos.node.id] ?? pos.level;
              return Positioned(
                left: pos.x,
                top: pos.y,
                child: NodeWidget(
                  node: pos.node,
                  isSelected: pos.node.id == widget.selectedNodeId,
                  generationLevel: level,
                  onTap: () => widget.onNodeTap?.call(pos.node),
                  onToggleChildren: widget.onToggleChildren == null ? null : () => widget.onToggleChildren!(pos.node.id),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}