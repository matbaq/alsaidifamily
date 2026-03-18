import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/family_graph.dart';
import '../../models/person.dart';
import '../../models/family_tree_layout_result.dart';
import '../../services/family_tree_layout_engine.dart';
import 'family_tree_painter.dart';
import 'family_unit_connector.dart';
import 'person_node_card.dart';

/// Top-level V2 rendering surface that owns pan/zoom and initial focus behavior.
class FamilyTreeCanvas extends StatefulWidget {
  const FamilyTreeCanvas({
    super.key,
    required this.graph,
    this.focusPersonId,
    this.onPersonTap,
    this.layoutConfig = const FamilyTreeLayoutConfig(),
    this.collapsedFamilyUnitIds = const <String>{},
    this.onFamilyUnitTap,
    this.initialScale = 1.0,
    this.minScale = 0.35,
    this.maxScale = 2.4,
    this.padding = const EdgeInsets.all(24),
    this.backgroundColor,
  });

  final FamilyGraph graph;
  final String? focusPersonId;
  final ValueChanged<Person>? onPersonTap;
  final FamilyTreeLayoutConfig layoutConfig;
  final Set<String> collapsedFamilyUnitIds;
  final ValueChanged<String>? onFamilyUnitTap;
  final double initialScale;
  final double minScale;
  final double maxScale;
  final EdgeInsets padding;
  final Color? backgroundColor;

  @override
  State<FamilyTreeCanvas> createState() => _FamilyTreeCanvasState();
}

class _FamilyTreeCanvasState extends State<FamilyTreeCanvas> {
  final TransformationController _transformationController = TransformationController();
  final FamilyTreeLayoutEngine _layoutEngine = const FamilyTreeLayoutEngine();

  Size _viewportSize = Size.zero;
  FamilyTreeLayoutResult? _lastLayout;
  String? _lastFocusKey;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.backgroundColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0D1118)
            : const Color(0xFFF4F7FB));

    final layout = _layoutEngine.layout(
      FamilyTreeLayoutRequest(
        graph: widget.graph,
        focusPersonId: widget.focusPersonId,
        config: widget.layoutConfig,
      ),
    );

    _lastLayout = layout;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final viewport = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
        );
        _applyInitialFocusIfNeeded(viewport, layout);

        final canvasWidth = math.max(
          viewport.width,
          layout.bounds.width + widget.padding.horizontal,
        );
        final canvasHeight = math.max(
          viewport.height,
          layout.bounds.height + widget.padding.vertical,
        );

        return DecoratedBox(
          decoration: BoxDecoration(color: backgroundColor),
          child: InteractiveViewer(
            transformationController: _transformationController,
            constrained: false,
            minScale: widget.minScale,
            maxScale: widget.maxScale,
            boundaryMargin: const EdgeInsets.all(240),
            child: SizedBox(
              width: canvasWidth,
              height: canvasHeight,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FamilyTreeV2Painter(
                        layout: layout,
                        canvasOffset: Offset(
                          widget.padding.left - layout.bounds.left,
                          widget.padding.top - layout.bounds.top,
                        ),
                        focusedNodeId: widget.focusPersonId,
                      ),
                    ),
                  ),
                  ...layout.nodes.values.map((node) {
                    final left = node.left - layout.bounds.left + widget.padding.left;
                    final top = node.top - layout.bounds.top + widget.padding.top;

                    if (node.type == FamilyGraphNodeType.familyUnit) {
                      return Positioned(
                        key: ValueKey<String>('family-${node.id}'),
                        left: left,
                        top: top,
                        width: node.size.width,
                        height: node.size.height,
                        child: FamilyUnitConnector(
                          isHighlighted: widget.focusPersonId != null &&
                              widget.graph.familyUnitByChildId[widget.focusPersonId!] == node.id,
                          isCollapsed: widget.collapsedFamilyUnitIds.contains(node.id),
                          childCount: widget.graph.familyUnits[node.id]?.childrenIds.length ?? 0,
                          onTap: widget.onFamilyUnitTap == null
                              ? null
                              : () => widget.onFamilyUnitTap!(node.id),
                        ),
                      );
                    }

                    final person = widget.graph.persons[node.id]!;
                    return Positioned(
                      key: ValueKey<String>('person-${node.id}'),
                      left: left,
                      top: top,
                      width: node.size.width,
                      height: node.size.height,
                      child: PersonNodeCard(
                        person: person,
                        isFocused: widget.focusPersonId == person.id,
                        onTap: widget.onPersonTap == null
                            ? null
                            : () => widget.onPersonTap!(person),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _applyInitialFocusIfNeeded(Size viewport, FamilyTreeLayoutResult layout) {
    if (viewport.isEmpty) {
      return;
    }

    final focusKey = '${widget.focusPersonId}|${layout.bounds}|$viewport';
    if (_lastFocusKey == focusKey && _viewportSize == viewport) {
      return;
    }

    _viewportSize = viewport;
    _lastFocusKey = focusKey;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastLayout != layout) {
        return;
      }

      final matrix = _initialMatrixFor(
        viewport: viewport,
        layout: layout,
        focusNodeId: widget.focusPersonId,
        scale: widget.initialScale,
      );
      _transformationController.value = matrix;
    });
  }


  FamilyTreeLayoutNode? _firstPersonNode(FamilyTreeLayoutResult layout) {
    for (final node in layout.nodes.values) {
      if (node.type == FamilyGraphNodeType.person) {
        return node;
      }
    }
    return null;
  }

  Matrix4 _initialMatrixFor({
    required Size viewport,
    required FamilyTreeLayoutResult layout,
    required String? focusNodeId,
    required double scale,
  }) {
    final safeScale = scale.clamp(widget.minScale, widget.maxScale);
    final anchorNode = (focusNodeId != null ? layout.nodeFor(focusNodeId) : null) ??
        _firstPersonNode(layout) ??
        layout.nodes.values.first;

    final contentFocus = Offset(
      (anchorNode.center.dx - layout.bounds.left) + widget.padding.left,
      (anchorNode.center.dy - layout.bounds.top) + widget.padding.top,
    );

    final targetViewportCenter = Offset(
      viewport.width / 2,
      viewport.height * 0.34,
    );

    return Matrix4.identity()
      ..translate(
        targetViewportCenter.dx - (contentFocus.dx * safeScale),
        targetViewportCenter.dy - (contentFocus.dy * safeScale),
      )
      ..scale(safeScale, safeScale);
  }
}
