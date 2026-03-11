import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../models/tree_node.dart';
import 'family_tree_painter.dart';
import 'node_widget.dart';
import 'tidy_tree_layout.dart';

class CustomFamilyTreeView extends StatefulWidget {
  final List<TreeNode> roots;
  final Function(TreeNode)? onNodeTap;
  final String? selectedNodeId;
  final TransformationController? externalController;
  final void Function(Map<String, Offset> centers, Rect bounds, Size canvasSize)? onLayoutReady;
  final void Function(String nodeId)? onToggleChildren;
  final TreeVerticalDirection direction;

  const CustomFamilyTreeView({
    super.key,
    required this.roots,
    this.onNodeTap,
    this.selectedNodeId,
    this.externalController,
    this.onLayoutReady,
    this.onToggleChildren,
    this.direction = TreeVerticalDirection.bottomToTop,
  });

  @override
  State<CustomFamilyTreeView> createState() => _CustomFamilyTreeViewState();
}

class _CustomFamilyTreeViewState extends State<CustomFamilyTreeView> {
  late TransformationController _controller;
  bool _ownsController = false;

  List<NodePosition> _positions = [];
  Size _treeSize = const Size(400, 400);
  int _lastFingerprint = 0;
  bool _didInitialZoom = false;

  static const double nodeWidth = 120.0;
  static const double nodeHeight = 140.0;
  static const double minScale = 0.001;
  static const double maxScale = 6.0;

  final Set<String> _visibleIds = {};
  final Map<String, int> _levelMap = {};

  Timer? _visibleDebounce;
  bool _isInteracting = false;

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

    if (widget.selectedNodeId != null && old.selectedNodeId != widget.selectedNodeId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusSelected();
      });
    }
  }

  @override
  void dispose() {
    _visibleDebounce?.cancel();
    _controller.removeListener(_onTransformChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    if (_positions.isEmpty || _isInteracting) return;

    _visibleDebounce?.cancel();
    _visibleDebounce = Timer(const Duration(milliseconds: 70), () {
      if (mounted) _updateVisible();
    });
  }

  int _fingerprint(List<TreeNode> roots) {
    int h = 17;
    void visit(TreeNode n) {
      h = 37 * h + n.id.hashCode;
      h = 37 * h + n.children.length;
      h = 37 * h + (n.isCollapsed ? 1 : 0);
      for (final c in n.children) {
        visit(c);
      }
    }

    for (final r in roots) {
      visit(r);
    }
    return h;
  }

  void _buildLevelMap(List<TreeNode> roots) {
    _levelMap.clear();

    void visit(TreeNode n, int level) {
      _levelMap[n.id] = level;
      for (final c in n.children) {
        visit(c, level + 1);
      }
    }

    for (final r in roots) {
      visit(r, 0);
    }
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

    final result = TidyTreeLayout.layout(
      widget.roots,
      config: TreeLayoutConfig(
        direction: widget.direction,
        padding: 24,
        levelGap: 72,
        siblingGap: 20,
        rootGap: 36,
      ),
    );

    if (!_usingExternalController) _didInitialZoom = false;

    setState(() {
      _positions = result.positions;
      _treeSize = result.canvasSize;
      _lastFingerprint = fp;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emitCenters();
      _setInitialZoom();
      _updateVisible(force: true);
      _focusSelected();
    });
  }

  void _focusSelected() {
    final selectedId = widget.selectedNodeId;
    if (selectedId == null) return;
    final center = _nodeCenter(selectedId);
    if (center == null) return;

    final size = MediaQuery.of(context).size;
    final currentScale = _controller.value.getMaxScaleOnAxis().clamp(minScale, maxScale);

    final tx = size.width / 2 - center.dx * currentScale;
    final ty = size.height / 2 - center.dy * currentScale;

    _controller.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(currentScale);
  }

  Offset? _nodeCenter(String id) {
    for (final p in _positions) {
      if (p.node.id == id) {
        return Offset(p.x + nodeWidth / 2, p.y + nodeHeight / 2);
      }
    }
    return null;
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

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;

    for (final p in _positions) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x + nodeWidth);
      maxY = math.max(maxY, p.y + nodeHeight);
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _setInitialZoom() {
    if (_usingExternalController || _didInitialZoom) return;

    _didInitialZoom = true;

    final screen = MediaQuery.of(context).size;
    const margin = 32.0;

    final sx = (screen.width - margin * 2) / _treeSize.width;
    final sy = (screen.height - margin * 2) / _treeSize.height;

    final scale = math.min(sx, sy).clamp(minScale, 1.35);
    final tx = (screen.width - _treeSize.width * scale) / 2;
    final ty = (screen.height - _treeSize.height * scale) / 2;

    _controller.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
  }

  void _updateVisible({bool force = false}) {
    if (!mounted) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateVisible(force: true);
      });
      return;
    }

    final inv = Matrix4.inverted(_controller.value);

    Offset toScene(Offset p) {
      final v = inv.transform3(Vector3(p.dx, p.dy, 0));
      return Offset(v.x, v.y);
    }

    final tl = toScene(Offset.zero);
    final br = toScene(Offset(box.size.width, box.size.height));
    final rect = Rect.fromPoints(tl, br).inflate(500);

    final newIds = <String>{};
    for (final p in _positions) {
      if (Rect.fromLTWH(p.x, p.y, nodeWidth, nodeHeight).overlaps(rect)) {
        newIds.add(p.node.id);
      }
    }

    if (newIds.isEmpty) {
      for (final p in _positions) {
        newIds.add(p.node.id);
      }
    }

    if (!force &&
        newIds.length == _visibleIds.length &&
        _visibleIds.containsAll(newIds)) {
      return;
    }

    setState(() {
      _visibleIds
        ..clear()
        ..addAll(newIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.roots.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد بيانات',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    final visiblePos = (_isInteracting || _visibleIds.isEmpty)
        ? _positions
        : _positions.where((p) => _visibleIds.contains(p.node.id)).toList();

    return InteractiveViewer(
      transformationController: _controller,
      boundaryMargin: const EdgeInsets.all(120),
      minScale: minScale,
      maxScale: maxScale,
      constrained: false,
      clipBehavior: Clip.none,
      panEnabled: true,
      scaleEnabled: true,
      onInteractionStart: (_) => _isInteracting = true,
      onInteractionEnd: (_) {
        _isInteracting = false;
        _updateVisible(force: true);
      },
      child: SizedBox(
        width: _treeSize.width,
        height: _treeSize.height,
        child: CustomPaint(
          painter: FamilyTreePainter(
            positions: _positions,
            visibleIds: _visibleIds,
            selectedNodeId: widget.selectedNodeId,
          ),
          child: Stack(
            children: visiblePos.map((pos) {
              final level = _levelMap[pos.node.id] ?? pos.level;
              return AnimatedPositioned(
                key: ValueKey('node-${pos.node.id}'),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: pos.x,
                top: pos.y,
                child: NodeWidget(
                  node: pos.node,
                  isSelected: pos.node.id == widget.selectedNodeId,
                  generationLevel: level,
                  onTap: () => widget.onNodeTap?.call(pos.node),
                  onToggleChildren: widget.onToggleChildren == null
                      ? null
                      : () => widget.onToggleChildren!(pos.node.id),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
