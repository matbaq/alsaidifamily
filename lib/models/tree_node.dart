import 'package:flutter/material.dart';

class TreeNode {
  final String id;
  final String name;
  final String? photoUrl;
  final Color branchColor;
  final bool isRoot;
  final List<TreeNode> children;
  final int childrenCount;

  /// ✅ هل هذا الفرع مقفول (الأبناء مخفيين) - UI فقط
  final bool isCollapsed;

  TreeNode({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.branchColor,
    this.isRoot = false,
    this.children = const [],
    int? childrenCount,
    this.isCollapsed = false,
  }) : childrenCount = childrenCount ?? children.length;
}