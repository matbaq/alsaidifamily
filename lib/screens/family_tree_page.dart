import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../controllers/access_controller.dart';
import '../data/family_repository.dart';
import '../models/family_member.dart';
import '../models/tree_node.dart';
import '../widgets/family_tree/custom_family_tree_view.dart';
import '../widgets/family_tree/tidy_tree_layout.dart';
import '../widgets/family_tree/node_widget.dart'; // ⭐ تم إرجاع هذا الاستيراد لحل المشكلة
import '../utils/relationship_utils.dart';
import '../services/security_service.dart';
import '../services/privacy_service.dart';
import 'family_women_page.dart';
import 'pin_management_page.dart';
import 'admin_panel_page.dart';
import 'private_family_tree_page.dart';

final FirebaseFirestore _db = FirebaseFirestore.instance;

Color? _parseHexColor(String? hex) {
  if (hex == null || hex.trim().isEmpty) return null;
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(v);
}

String _toHex(Color c) =>
    '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

class AppColors {
  static const bg        = Color(0xFF0D0F14);
  static const surface   = Color(0xFF161921);
  static const card      = Color(0xFF1E2230);
  static const border    = Color(0xFF2A2F42);
  static const gold      = Color(0xFFFFD700);
  static const goldDark  = Color(0xFFB8860B);
  static const text      = Color(0xFFF0F2FF);
  static const textSub   = Color(0xFF8892AA);
}

class FamilyTreePage extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeToggle;
  final String collection;

  const FamilyTreePage({
    super.key,
    required this.isDarkMode,
    required this.onThemeToggle,
    this.collection = 'members_public',
  });

  @override
  State<FamilyTreePage> createState() => _FamilyTreePageState();
}

class _FamilyTreePageState extends State<FamilyTreePage>
    with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  late final FamilyRepository _repo;
  final _privacyService = PrivacyService();

  final _searchCtrl     = TextEditingController();
  final _treeController = TransformationController();

  final GlobalKey _treeShotKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String  _searchQuery = '';
  String? _selectedId;
  String? _showGrandchildrenForId;

  bool _isBottomSheetOpen = false;
  bool _showSearch = false;

  PalettePreset _palettePreset = GenerationPalette.currentPreset;

  Map<String, Offset> _nodeCenters = {};
  Rect? _treeBounds;

  int _lastFitKey = 0;
  bool _didAutoFitOnce = false;

  bool _indexShowFamilies = true;
  final TextEditingController _indexSearchCtrl = TextEditingController();
  String _indexQuery = '';

  AnimationController? _zoomAC;
  static const double _minScale = 0.001;
  static const double _maxScale = 4.0;

  List<FamilyMember>? _cachedAll;
  String _cachedQuery = '';
  String _cachedAccessMode = '';
  Set<String> _cachedCollapsed = {};
  List<FamilyMember> _cachedFiltered = [];
  List<TreeNode> _cachedRoots = [];

  final Set<String> _collapsedIds = {};

  bool get _isAdmin => _auth.currentUser != null;

  static const double _baseTopOffset = 130.0;

  double _effectiveTopOffset(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    final searchExtra = _showSearch ? 58.0 : 0.0;
    return _baseTopOffset + (safeTop > 24 ? 10.0 : 0.0) + searchExtra;
  }

  double _searchBarTop(BuildContext context) {
    return MediaQuery.of(context).padding.top + 54.0;
  }

  double _memberCountTop(BuildContext context) {
    final base = MediaQuery.of(context).padding.top + 62.0;
    if (!_showSearch) return base;
    return _searchBarTop(context) + 52.0;
  }

  static const String _supportEmail = 'zker2003@gmail.com';
  static const String _supportPhone = '9109999979';
  static const String _privacyUrl  = 'https://sites.google.com/view/privacypolicyalsaidifamilytree';

  Future<void> _launchExternal(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الرابط')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _repo = FamilyRepository(collection: widget.collection);

    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.toLowerCase().trim();
      if (q == _searchQuery) return;
      setState(() {
        _searchQuery = q;
        _selectedId = null;
        _showGrandchildrenForId = null;
      });
      _lastFitKey++;
    });

    _indexSearchCtrl.addListener(() {
      final q = _indexSearchCtrl.text.trim().toLowerCase();
      if (q == _indexQuery) return;
      setState(() => _indexQuery = q);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _treeController.dispose();
    _zoomAC?.dispose();
    _indexSearchCtrl.dispose();
    super.dispose();
  }

  void _setInitialCollapse(List<FamilyMember> all) {
    if (_cachedAll != null) return;

    final roots = all.where((m) => m.fatherId == null).toList();
    for (final root in roots) {
      _collapseSubtree(root.id, all, 0);
    }
  }

  void _collapseSubtree(String id, List<FamilyMember> all, int level) {
    final children = all.where((m) => m.fatherId == id).toList();
    if (children.isEmpty) return;

    if (level >= 2) {
      _collapsedIds.add(id);
    }

    for (final child in children) {
      _collapseSubtree(child.id, all, level + 1);
    }
  }

  void _viewFullTree(List<FamilyMember> all) {
    setState(() {
      _searchQuery = '';
      _selectedId = null;
      _showGrandchildrenForId = null;
      _searchCtrl.clear();
      _collapsedIds.clear();
      _showSearch = false;
      _didAutoFitOnce = false;

      final roots = all.where((m) => m.fatherId == null).toList();
      for (final root in roots) {
        _collapseSubtree(root.id, all, 0);
      }
    });

    _lastFitKey++;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitTree());
  }

  void _expandAll(List<FamilyMember> all) {
    setState(() {
      _collapsedIds.clear();
    });
  }

  void _collapseAll(List<FamilyMember> all) {
    setState(() {
      final idsWithChildren =
      all.map((x) => x.fatherId).whereType<String>().toSet();
      _collapsedIds
        ..clear()
        ..addAll(idsWithChildren);
    });
  }

  void _resetView() {
    _treeController.value = Matrix4.identity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitTree();
    });
  }

  void _fitTree() {
    if (_treeBounds == null) return;

    final b = _treeBounds!;
    final screen = MediaQuery.of(context).size;

    const pad = 40.0;
    final availableW = screen.width;
    final topOffset = _effectiveTopOffset(context);
    final availableH =
    (screen.height - topOffset).clamp(200.0, screen.height);

    final sx = availableW / (b.width + pad * 2);
    final sy = availableH / (b.height + pad * 2);

    final scale = (sx < sy ? sx : sy).clamp(_minScale, 2.4);

    final tx = (availableW - b.width * scale) / 2 - b.left * scale;
    final ty = (availableH - b.height * scale) / 2 - b.top * scale;

    _treeController.value = Matrix4.identity()
      ..translate(tx, ty + topOffset)
      ..scale(scale);
  }

  void _animateMatrixTo(Matrix4 target, {int ms = 130}) {
    _zoomAC?.stop();
    _zoomAC?.dispose();

    _zoomAC = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    );

    final curved =
    CurvedAnimation(parent: _zoomAC!, curve: Curves.easeOutCubic);
    final tween = Matrix4Tween(begin: _treeController.value, end: target);

    curved.addListener(() {
      _treeController.value = tween.evaluate(curved);
    });

    _zoomAC!.addStatusListener((s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        curved.dispose();
        _zoomAC?.dispose();
        _zoomAC = null;
      }
    });

    _zoomAC!.forward();
  }

  void _zoomBy(double scaleFactor) {
    final m = _treeController.value;
    final currentScale = m.getMaxScaleOnAxis();

    final newScale = (currentScale * scaleFactor).clamp(_minScale, _maxScale);
    final factor = newScale / currentScale;
    if (factor == 1.0) return;

    final screen = MediaQuery.of(context).size;
    final focal = Offset(
      screen.width / 2,
      (screen.height + _effectiveTopOffset(context)) / 2,
    );

    final next = Matrix4.identity()
      ..translate(focal.dx, focal.dy)
      ..scale(factor)
      ..translate(-focal.dx, -focal.dy)
      ..multiply(m);

    _animateMatrixTo(next, ms: 120);
  }

  void _centerOn(String id) {
    final center = _nodeCenters[id];
    if (center == null) return;

    final screen = MediaQuery.of(context).size;
    final sc = _treeController.value.getMaxScaleOnAxis();

    final tx = screen.width / 2 - center.dx * sc;
    final ty = (screen.height + _effectiveTopOffset(context)) / 2 - center.dy * sc;

    final target = Matrix4.identity()..translate(tx, ty)..scale(sc);

    final ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    final curved = CurvedAnimation(parent: ac, curve: Curves.easeOutCubic);
    final tween = Matrix4Tween(begin: _treeController.value, end: target);

    curved.addListener(() {
      _treeController.value = tween.evaluate(curved);
    });

    ac.addStatusListener((s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        curved.dispose();
        ac.dispose();
      }
    });

    ac.forward();
  }

  void _toggleCollapse(String id) {
    setState(() {
      if (_collapsedIds.contains(id)) {
        _collapsedIds.remove(id);
      } else {
        _collapsedIds.add(id);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerOn(id);
    });
  }

  void _focusOnNode(String id) {
    if (_nodeCenters.isEmpty) return;

    final center = _nodeCenters[id];
    if (center == null) return;

    final matrix = Matrix4.identity();

    matrix.translate(
      -center.dx + MediaQuery.of(context).size.width / 2,
      -center.dy + MediaQuery.of(context).size.height / 2,
    );

    matrix.scale(1.3);

    _treeController.value = matrix;
  }

  void _showGrandchildrenOf(FamilyMember m, List<FamilyMember> all) {
    setState(() {
      _searchQuery = '';
      _selectedId = null;
      _showGrandchildrenForId = m.id;
      _searchCtrl.clear();
      _collapsedIds.clear();
      _didAutoFitOnce = false;
    });

    _lastFitKey++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerOn(m.id);
    });
  }

  Future<void> _openBranchColorSheet(FamilyMember m) async {
    final colors = <Color>[
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.blueGrey,
    ];

    await showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDarkMode ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.palette_rounded, color: AppColors.gold),
                    const SizedBox(width: 8),
                    const Text(
                      'لون الفرع',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: colors.map((color) {
                    final selected = _toHex(color) == m.branchColor;
                    return GestureDetector(
                      onTap: () async {
                        await _repo.updateBranchColor(m.id, _toHex(color));
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.black : Colors.white,
                            width: selected ? 3 : 1.5,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await _repo.updateBranchColor(m.id, null);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.format_color_reset_rounded),
                    label: const Text('إزالة اللون المخصص'),
                  ),
                ),

                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await _repo.updateInheritToChildren(
                        id: m.id,
                        inherit: !m.inheritToChildren,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: Icon(
                      m.inheritToChildren
                          ? Icons.call_split_rounded
                          : Icons.alt_route_rounded,
                    ),
                    label: Text(
                      m.inheritToChildren
                          ? 'إلغاء توريث اللون للأبناء'
                          : 'توريث اللون للأبناء',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> exportTreeImage() async {
    try {
      final bytes = await _captureTreePng(pixelRatio: 3.0);

      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر التقاط صورة للشجرة')),
          );
        }
        return;
      }

      final dir = await Directory.systemTemp.createTemp('tree_share_');
      final file = File('${dir.path}/family_tree.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: widget.collection == 'members_private'
            ? 'الشجرة الخاصة'
            : 'شجرة عائلة الصايدي',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء مشاركة الصورة: $e')),
        );
      }
    }
  }

  String _norm(String t) => t
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[\u064B-\u0652]'), '');

  String _displayName(
      FamilyMember m,
      AccessController access,
      PrivacySettings privacy,
      ) {
    if (access.isGuest &&
        m.isFemale &&
        privacy.hideFemaleNamesForGuest) {
      return 'عضو أنثى';
    }
    return m.name;
  }

  List<FamilyMember> _filter(
      List<FamilyMember> all,
      AccessController access,
      PrivacySettings privacy,
      ) {
    if (_searchQuery.isEmpty &&
        _selectedId == null &&
        _showGrandchildrenForId == null) {
      return all;
    }

    final visible = <String>{};

    if (_showGrandchildrenForId != null) {
      final rootId = _showGrandchildrenForId!;
      visible.add(rootId);

      void addAllDescendants(String id) {
        final children = all.where((x) => x.fatherId == id).toList();
        for (final child in children) {
          if (visible.add(child.id)) {
            addAllDescendants(child.id);
          }
        }
      }

      addAllDescendants(rootId);

      // إضافة الآباء فوق العضو الحالي حتى يبقى السياق واضح
      String? pid = all.where((x) => x.id == rootId).firstOrNull?.fatherId;
      while (pid != null) {
        visible.add(pid);
        try {
          pid = all.firstWhere((x) => x.id == pid).fatherId;
        } catch (_) {
          pid = null;
        }
      }

      return all.where((m) => visible.contains(m.id)).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _norm(_searchQuery);

      for (final m in all) {
        if (privacy.hideFemalesFromGeneralSearch && m.isFemale) {
          continue;
        }

        final name = _norm(m.name);

        String fatherName = '';
        if (m.fatherId != null) {
          final father = all.firstWhere(
                (e) => e.id == m.fatherId,
            orElse: () => m,
          );
          fatherName = _norm(father.name);
        }

        final branch = _norm(m.branchColor ?? '');

        if (name.contains(q) || fatherName.contains(q) || branch.contains(q)) {
          visible.add(m.id);
          String? pid = m.fatherId;
          while (pid != null) {
            visible.add(pid);
            try {
              pid = all.firstWhere((x) => x.id == pid).fatherId;
            } catch (_) {
              pid = null;
            }
          }
        }
      }
    } else if (_selectedId != null) {
      visible.add(_selectedId!);

      void addChildren(String id) {
        for (final m in all.where((x) => x.fatherId == id)) {
          visible.add(m.id);
          addChildren(m.id);
        }
      }

      addChildren(_selectedId!);

      String? pid = all.where((x) => x.id == _selectedId).firstOrNull?.fatherId;
      while (pid != null) {
        visible.add(pid);
        try {
          pid = all.firstWhere((x) => x.id == pid).fatherId;
        } catch (_) {
          pid = null;
        }
      }
    }

    return all.where((m) => visible.contains(m.id)).toList();
  }

  List<TreeNode> _buildTree(
      List<FamilyMember> filtered,
      List<FamilyMember> all,
      AccessController access,
      PrivacySettings privacy,
      ) {
    final roots = filtered.where((m) => m.fatherId == null).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return roots
        .map((r) => _buildNode(r, filtered, all, access, privacy))
        .toList();
  }

  FamilyMember? _findById(String? id, List<FamilyMember> all) {
    if (id == null) return null;
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  Color _nodeColor(FamilyMember m, List<FamilyMember> all) {
    final self = _parseHexColor(m.branchColor);
    if (self != null) return self;

    String? currentFatherId = m.fatherId;

    while (currentFatherId != null) {
      final father = _findById(currentFatherId, all);
      if (father == null) break;

      final fatherColor = _parseHexColor(father.branchColor);

      if (fatherColor != null && father.inheritToChildren) {
        return fatherColor;
      }

      // إذا الأب عنده لون لكن الوراثة متوقفة نتوقف هنا
      if (fatherColor != null && !father.inheritToChildren) {
        break;
      }

      currentFatherId = father.fatherId;
    }

    final level = _getLevelOf(m.id, all);
    return GenerationPalette.primaryForLevel(level);
  }

  TreeNode _buildNode(
      FamilyMember m,
      List<FamilyMember> filtered,
      List<FamilyMember> all,
      AccessController access,
      PrivacySettings privacy,
      ) {
    final directChildren = filtered.where((x) => x.fatherId == m.id).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final isCollapsed = _collapsedIds.contains(m.id) && _searchQuery.isEmpty;
    final childrenCount = directChildren.length;

    final childNodes = isCollapsed
        ? <TreeNode>[]
        : directChildren
        .map((c) => _buildNode(c, filtered, all, access, privacy))
        .toList();

    return TreeNode(
      id: m.id,
      name: _displayName(m, access, privacy),
      photoUrl: (access.isGuest &&
          m.isFemale &&
          privacy.hideFemalePhotosForGuest)
          ? null
          : m.photoUrl,
      branchColor: _nodeColor(m, all),
      isRoot: m.fatherId == null,
      children: childNodes,
      childrenCount: childrenCount,
      isCollapsed: isCollapsed,
    );
  }

  void _recompute(
      List<FamilyMember> all,
      AccessController access,
      PrivacySettings privacy,
      ) {
    final sameData = identical(_cachedAll, all);
    final sameQuery = _cachedQuery == _searchQuery;
    final sameAccess = _cachedAccessMode == access.mode.name;
    final sameCollapse = _cachedCollapsed.length == _collapsedIds.length &&
        _cachedCollapsed.containsAll(_collapsedIds);

    if (sameData && sameQuery && sameCollapse && sameAccess && _showGrandchildrenForId == null) return;

    _cachedAll = all;
    _cachedQuery = _searchQuery;
    _cachedAccessMode = access.mode.name;
    _cachedCollapsed = Set.from(_collapsedIds);
    _cachedFiltered = _filter(all, access, privacy);
    _cachedRoots = _buildTree(_cachedFiltered, all, access, privacy);
  }

  Future<Uint8List?> _captureTreePng({double pixelRatio = 2.0}) async {
    try {
      final boundary = _treeShotKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _printTree() async {
    final bytes = await _captureTreePng(pixelRatio: 2.0);
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تجهيز الطباعة')),
        );
      }
      return;
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final doc = pw.Document();
        final image = pw.MemoryImage(bytes);

        doc.addPage(
          pw.Page(
            pageFormat: format,
            build: (pw.Context context) {
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Center(
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              );
            },
          ),
        );
        return doc.save();
      },
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final titleColor = isDark ? Colors.white : Colors.black87;
        final subColor = isDark ? Colors.white70 : Colors.black54;

        return AlertDialog(
          backgroundColor: isDark ? AppColors.card : Colors.white,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.gold),
              const SizedBox(width: 10),
              Text('حول التطبيق', style: TextStyle(color: titleColor)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'شجرة عائلة الصايدي',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text('الإصدار 1.0.0', style: TextStyle(color: subColor)),
                const SizedBox(height: 14),
                Text(
                  'تم تصميم التطبيق لعرض شجرة العائلة بشكل منظم مع البحث والتنقل السريع.',
                  style: TextStyle(color: subColor),
                ),
                const SizedBox(height: 16),
                Divider(color: isDark ? Colors.white12 : Colors.black12),
                const SizedBox(height: 10),
                Text(
                  'التواصل',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.email_outlined,
                    color: AppColors.gold,
                  ),
                  title: Text(_supportEmail, style: TextStyle(color: titleColor)),
                  subtitle:
                  Text('راسلنا عبر البريد', style: TextStyle(color: subColor)),
                  onTap: () => _launchExternal(Uri.parse('mailto:$_supportEmail')),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.phone_outlined,
                    color: AppColors.gold,
                  ),
                  title: Text(_supportPhone, style: TextStyle(color: titleColor)),
                  subtitle:
                  Text('اتصل بنا مباشرة', style: TextStyle(color: subColor)),
                  trailing: IconButton(
                    tooltip: 'اتصال',
                    icon: const Icon(
                      Icons.call_rounded,
                      color: AppColors.goldDark,
                    ),
                    onPressed: () => _launchExternal(Uri.parse('tel:$_supportPhone')),
                  ),
                  onTap: () => _launchExternal(Uri.parse('tel:$_supportPhone')),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.privacy_tip_outlined,
                    color: AppColors.gold,
                  ),
                  title:
                  Text('سياسة الخصوصية', style: TextStyle(color: titleColor)),
                  subtitle: Text(_privacyUrl, style: TextStyle(color: subColor)),
                  trailing: const Icon(
                    Icons.open_in_new_rounded,
                    size: 18,
                    color: AppColors.goldDark,
                  ),
                  onTap: () => _launchExternal(Uri.parse(_privacyUrl)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'إغلاق',
                style: TextStyle(color: AppColors.goldDark),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openFamilyModeQuick() async {
    final pinCtrl = TextEditingController();
    String? error;
    bool loading = false;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.isDarkMode ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 14,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 14,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.lock_open_rounded, color: AppColors.gold),
                      SizedBox(width: 8),
                      Text(
                        'فتح وضع العائلة',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'أدخل رمز العائلة للوصول إلى الصفحات الخاصة.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Family PIN',
                      prefixIcon: Icon(Icons.password_rounded),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                          loading ? null : () => Navigator.pop(ctx, false),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: loading
                              ? null
                              : () async {
                            final pin = pinCtrl.text.trim();

                            if (pin.isEmpty) {
                              setSheetState(
                                    () => error = 'اكتب رمز العائلة',
                              );
                              return;
                            }

                            setSheetState(() {
                              loading = true;
                              error = null;
                            });

                            try {
                              final security = SecurityService();
                              final valid =
                              await security.verifyFamilyPin(pin);

                              if (!valid) {
                                setSheetState(() {
                                  loading = false;
                                  error = 'رمز العائلة غير صحيح';
                                });
                                return;
                              }

                              if (ctx.mounted) {
                                Navigator.pop(ctx, true);
                              }
                            } catch (_) {
                              setSheetState(() {
                                loading = false;
                                error = 'تعذر التحقق من الرمز';
                              });
                            }
                          },
                          child: loading
                              ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Text('فتح'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (ok == true && mounted) {
      context.read<AccessController>().setFamily();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تفعيل وضع العائلة')),
      );
    }
  }

  Future<void> _showMemberDetails(
      List<FamilyMember> all,
      FamilyMember m,
      AccessController access,
      PrivacySettings privacy,
      ) async {
    if (_isBottomSheetOpen) return;
    _isBottomSheetOpen = true;

    setState(() => _selectedId = m.id);
    _centerOn(m.id);

    final children = all.where((x) => x.fatherId == m.id).toList();
    final father =
    m.fatherId != null ? all.where((x) => x.id == m.fatherId).firstOrNull : null;

    final isRoot = m.fatherId == null;
    final level = _getLevelOf(m.id, all);
    final primary = GenerationPalette.primaryForLevel(level);
    final accent = GenerationPalette.accentForLevel(level);
    final isCollapsed = _collapsedIds.contains(m.id);

    final displayMember = (access.isGuest && m.isFemale)
        ? FamilyMember(
      id: m.id,
      name: privacy.hideFemaleNamesForGuest ? 'عضو أنثى' : m.name,
      fatherId: m.fatherId,
      photoUrl: privacy.hideFemalePhotosForGuest ? null : m.photoUrl,
      branchColor: m.branchColor,
      inheritToChildren: m.inheritToChildren,
      isFemale: m.isFemale,
    )
        : m;

    final hasGrandchildren = children.any(
          (child) => all.any((x) => x.fatherId == child.id),
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MemberBottomSheet(
        member: displayMember,
        father: father,
        children: children,
        allMembers: all,
        isRoot: isRoot,
        isCollapsed: isCollapsed,
        isAdmin: _isAdmin,
        primary: primary,
        accent: accent,
        level: level,
        displayName: _displayName(m, access, privacy),
        onToggle: () {
          _toggleCollapse(m.id);
          Navigator.pop(ctx);
        },
        onFocusTree: () {
          Navigator.pop(ctx);
          _focusOnMember(m, all);
        },
        onShowGrandchildren: hasGrandchildren
            ? () {
          Navigator.pop(ctx);
          _showGrandchildrenOf(m, all);
        }
            : null,
        onRelation: () async {
          Navigator.pop(ctx);
          await _showRelationFlow(m, all, privacy);
        },
        onAddChild: _isAdmin
            ? () async {
          Navigator.pop(ctx);
          final draft = await Navigator.push<MemberDraft>(
            context,
            MaterialPageRoute(
              builder: (_) => AddEditMemberPage(
                title: 'إضافة ابن لـ ${m.name}',
                members: all,
                initial: null,
                presetFatherId: m.id,
              ),
            ),
          );
          if (draft != null) {
            await _repo.addMemberRaw(
              name: draft.name,
              fatherId: draft.fatherId,
              isFemale: draft.isFemale,
            );
          }
        }
            : null,
        onAddFather: _isAdmin
            ? () async {
          Navigator.pop(ctx);

          final draft = await Navigator.push<MemberDraft>(
            context,
            MaterialPageRoute(
              builder: (_) => AddEditMemberPage(
                title: 'إضافة أب لـ ${m.name}',
                members: all,
                initial: null,
                presetFatherId: m.fatherId,
              ),
            ),
          );

          if (draft != null) {
            final newFatherId = await _repo.addMemberAndReturnId(
              name: draft.name,
              fatherId: draft.fatherId,
              isFemale: draft.isFemale,
            );

            await _repo.updateFatherId(
              id: m.id,
              fatherId: newFatherId,
            );

            await _repo.addCustomAuditLog(
              action: 'add_father',
              targetName: m.name,
              details: 'تمت إضافة أب جديد فوق العضو الحالي',
            );
          }
        }
            : null,
        onEdit: _isAdmin
            ? () async {
          Navigator.pop(ctx);
          final draft = await Navigator.push<MemberDraft>(
            context,
            MaterialPageRoute(
              builder: (_) => AddEditMemberPage(
                title: 'تعديل',
                members: all,
                initial: m,
              ),
            ),
          );
          if (draft != null) {
            await _repo.updateName(
              id: m.id,
              name: draft.name,
              fatherId: draft.fatherId,
              isFemale: draft.isFemale,
            );
          }
        }
            : null,
        onDelete: _isAdmin
            ? () async {
          final ok = await _confirmDelete(m.name);
          if (ok != true) return;
          await _repo.deleteMember(m.id);
          if (_selectedId == m.id) setState(() => _selectedId = null);
          if (ctx.mounted) Navigator.pop(ctx);
        }
            : null,
        onPhoto: _isAdmin
            ? () async {
          Navigator.pop(ctx);
          await _pickPhoto(m.id);
        }
            : null,
        onBranchColor: _isAdmin
            ? () async {
          Navigator.pop(ctx);
          await Future.delayed(const Duration(milliseconds: 180));
          if (!mounted) return;
          await _openBranchColorSheet(m);
        }
            : null,
        onMakeRoot: _isAdmin
            ? () async {
          await _repo.updateFatherId(id: m.id, fatherId: null);
          if (ctx.mounted) Navigator.pop(ctx);
        }
            : null,
      ),
    );

    _isBottomSheetOpen = false;
    setState(() => _selectedId = null);
  }

  int _getLevelOf(String id, List<FamilyMember> all) {
    int level = 0;
    String? currentId = id;
    final visited = <String>{};

    while (currentId != null && !visited.contains(currentId)) {
      visited.add(currentId);
      try {
        final m = all.firstWhere((x) => x.id == currentId);
        if (m.fatherId == null) break;
        currentId = m.fatherId;
        level++;
      } catch (_) {
        break;
      }
    }
    return level;
  }

  void _focusOnMember(FamilyMember m, List<FamilyMember> all) {
    setState(() {
      final idsWithChildren =
      all.map((x) => x.fatherId).whereType<String>().toSet();
      _collapsedIds
        ..clear()
        ..addAll(idsWithChildren);

      String? cid = m.id;
      while (cid != null) {
        _collapsedIds.remove(cid);
        try {
          final parent = all.firstWhere((x) => x.id == cid);
          cid = parent.fatherId;
        } catch (_) {
          break;
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerOn(m.id);
    });
  }

  int _countBranchMembers(String rootId, List<FamilyMember> all) {
    final childrenByFather = <String, List<String>>{};
    for (final m in all) {
      final f = m.fatherId;
      if (f == null) continue;
      (childrenByFather[f] ??= []).add(m.id);
    }

    int count = 1;
    final stack = <String>[rootId];

    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      final kids = childrenByFather[cur] ?? const <String>[];
      count += kids.length;
      stack.addAll(kids);
    }
    return count;
  }

  Future<bool?> _confirmDelete(String name) => showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('تأكيد الحذف'),
      content: Text('هل تريد حذف "$name"؟'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );

  Future<FamilyMember?> _pickMemberDialog({
    required List<FamilyMember> all,
    required String excludeId,
    required PrivacySettings privacy,
    required AccessController access,
  }) async {
    return showDialog<FamilyMember>(
      context: context,
      builder: (ctx) {
        final searchCtrl = TextEditingController();
        String q = '';

        List<FamilyMember> filtered() {
          final base = all.where((m) => m.id != excludeId).toList();
          if (q.trim().isEmpty) {
            base.sort((a, b) => a.name.compareTo(b.name));
            return base;
          }
          final nq = _norm(q.trim().toLowerCase());
          final res = base.where((m) => _norm(m.name).contains(nq)).toList();
          res.sort((a, b) => a.name.compareTo(b.name));
          return res;
        }

        return StatefulBuilder(
          builder: (ctx, setState) {
            final list = filtered();
            return AlertDialog(
              title: const Text('اختر شخصًا للمقارنة'),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'ابحث بالاسم...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: q.isNotEmpty
                            ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            searchCtrl.clear();
                            setState(() => q = '');
                          },
                        )
                            : null,
                      ),
                      onChanged: (v) => setState(() => q = v),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(child: Text('لا توجد نتائج'))
                          : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) => ListTile(
                          leading: const Icon(Icons.person_rounded),
                          title: Text(
                            _displayName(list[i], access, privacy),
                          ),
                          onTap: () => Navigator.pop(ctx, list[i]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRelationFlow(
      FamilyMember a,
      List<FamilyMember> all,
      PrivacySettings privacy,
      ) async {
    final access = context.read<AccessController>();
    final b = await _pickMemberDialog(
      all: all,
      excludeId: a.id,
      privacy: privacy,
      access: access,
    );
    if (b == null) return;

    final rel = relationshipBetween(aId: a.id, bId: b.id, all: all);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('صلة القرابة'),
        content: Text(
          '${_displayName(a, access, privacy)} بالنسبة لـ ${_displayName(b, access, privacy)}:\n\n$rel',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto(String id) async {
    try {
      final picked =
      await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;

      final ref =
      FirebaseStorage.instance.ref().child('family_photos').child('$id.jpg');
      await ref.putFile(File(picked.path));
      await _repo.updatePhoto(id, await ref.getDownloadURL());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث الصورة'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _handleAdminTap(bool isDark) async {
    if (_isAdmin) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('تسجيل خروج الأدمن'),
            content: const Text('هل تريد تسجيل الخروج من وضع الأدمن؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('خروج'),
              ),
            ],
          );
        },
      );

      if (ok == true) {
        await _auth.signOut();
        if (mounted) setState(() {});
      }
      return;
    }

    final ok = await _showLoginImproved(isDark);
    if (ok == true && mounted) {
      setState(() {});
    }
  }

  Future<bool?> _showLoginImproved(bool isDark) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.surface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      final emailCtrl = TextEditingController();
      final passCtrl = TextEditingController();
      bool loading = false;
      bool obscure = true;
      String? error;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 14,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 14,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'تسجيل دخول الأدمن',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'هذا الدخول مخصص للمشرفين فقط.',
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_rounded),
                    suffixIcon: IconButton(
                      tooltip: obscure ? 'إظهار' : 'إخفاء',
                      onPressed: () =>
                          setSheetState(() => obscure = !obscure),
                      icon: Icon(
                        obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                      ),
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                        loading ? null : () => Navigator.pop(ctx, false),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: loading
                            ? null
                            : () async {
                          final email = emailCtrl.text.trim();
                          final pass = passCtrl.text;

                          if (email.isEmpty || pass.isEmpty) {
                            setSheetState(
                                  () => error = 'اكتب البريد وكلمة المرور',
                            );
                            return;
                          }

                          setSheetState(() {
                            loading = true;
                            error = null;
                          });

                          try {
                            await _auth.signInWithEmailAndPassword(
                              email: email,
                              password: pass,
                            );
                            if (ctx.mounted) {
                              Navigator.pop(ctx, true);
                            }
                          } catch (_) {
                            setSheetState(() {
                              loading = false;
                              error = 'بيانات الدخول غير صحيحة';
                            });
                          }
                        },
                        child: loading
                            ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text('دخول'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();
    final isDark = widget.isDarkMode;

    return StreamBuilder<PrivacySettings>(
      stream: _privacyService.streamSettings(),
      builder: (context, privacySnap) {
        final privacy = privacySnap.data ??
            const PrivacySettings(
              hideFemaleNamesForGuest: true,
              hideFemalePhotosForGuest: true,
              womenPageAdminOnly: false,
              hideFemalesFromGeneralSearch: false,
            );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: isDark ? AppColors.bg : const Color(0xFFF0F4FF),
            endDrawer: _buildFamilyIndexDrawer(access, privacy),
            body: StreamBuilder<List<FamilyMember>>(
              stream: _repo.membersStream(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(child: Text('خطأ في البيانات'));
                }
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  );
                }

                final all = snap.data!;
                _setInitialCollapse(all);
                _recompute(all, access, privacy);

                final safeBottom = MediaQuery.of(context).padding.bottom;
                final topOffset = _effectiveTopOffset(context);

                return Stack(
                  children: [
                    _buildBackground(isDark),
                    Positioned.fill(
                      top: topOffset,
                      child: RepaintBoundary(
                        key: _treeShotKey,
                        child: _buildTreeView(isDark, access),
                      ),
                    ),
                    _buildAppBar(isDark),
                    if (_showSearch)
                      Positioned(
                        top: _searchBarTop(context),
                        left: 16,
                        right: 16,
                        child: _buildSearchBar(isDark),
                      ),
                    Positioned(
                      top: _memberCountTop(context),
                      left: 16,
                      child: _buildMemberCount(all, access, privacy),
                    ),
                    if (_isAdmin)
                      Positioned(
                        bottom: safeBottom + 16,
                        right: 16,
                        child: _buildFAB(all),
                      ),
                    Positioned(
                      bottom: safeBottom + 16,
                      left: 16,
                      child: Column(
                        children: [
                          _zoomBtn(
                            Icons.add_rounded,
                            () => _zoomBy(1.18),
                            isDark,
                            tooltip: 'تكبير',
                          ),
                          const SizedBox(height: 10),
                          _zoomBtn(
                            Icons.remove_rounded,
                            () => _zoomBy(1 / 1.18),
                            isDark,
                            tooltip: 'تصغير',
                          ),
                          const SizedBox(height: 10),
                          _zoomBtn(
                            Icons.fit_screen_rounded,
                            _fitTree,
                            isDark,
                            tooltip: 'ملاءمة الشاشة',
                          ),
                          const SizedBox(height: 10),
                          _zoomBtn(
                            Icons.center_focus_strong_rounded,
                            _resetView,
                            isDark,
                            tooltip: 'إعادة الضبط',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildBackground(bool isDark) {
    return Positioned.fill(child: CustomPaint(painter: _BgPainter(isDark)));
  }

  Widget _buildAppBar(bool isDark) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 8,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [AppColors.bg, AppColors.bg.withValues(alpha: 0.0)]
                : [
              const Color(0xFFF0F4FF),
              const Color(0xFFF0F4FF).withValues(alpha: 0.0),
            ],
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.account_tree_rounded,
              color: AppColors.gold,
              size: 28,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.collection == 'members_private'
                    ? 'الشجرة الخاصة'
                    : 'شجرة عائلة الصايدي',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _appBarBtn(
              icon: _isAdmin
                  ? Icons.verified_user_rounded
                  : Icons.admin_panel_settings_rounded,
              isDark: isDark,
              gold: _isAdmin,
              onTap: () => _handleAdminTap(isDark),
            ),
            const SizedBox(width: 8),
            _appBarBtn(
              icon: Icons.settings_rounded,
              isDark: isDark,
              onTap: () => _openMoreMenu(isDark, _cachedAll ?? []),
            ),
          ],
        ),
      ),
    );
  }

  void _openMoreMenu(bool isDark, List<FamilyMember> all) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final access = context.read<AccessController>();
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetHeader(isDark),
                  _sheetItem(
                    _showSearch
                        ? Icons.search_off_rounded
                        : Icons.search_rounded,
                    _showSearch ? 'إخفاء البحث' : 'بحث',
                        () {
                      Navigator.pop(ctx);
                      setState(() => _showSearch = !_showSearch);
                    },
                  ),
                  _sheetItem(Icons.refresh_rounded, 'عرض الشجرة كاملة', () {
                    Navigator.pop(ctx);
                    _viewFullTree(all);
                  }),
                  _sheetItem(Icons.menu_book_rounded, 'فهرس الأسماء', () {
                    Navigator.pop(ctx);
                    _scaffoldKey.currentState?.openEndDrawer();
                  }),
                  _sheetItem(Icons.female_rounded, 'نساء العائلة', () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FamilyWomenPage(),
                      ),
                    );
                  }),
                  if (widget.collection == 'members_public')
                    _sheetItem(Icons.lock_outline_rounded, 'الشجرة الخاصة', () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PrivateFamilyTreePage(
                            isDarkMode: widget.isDarkMode,
                            onThemeToggle: widget.onThemeToggle,
                          ),
                        ),
                      );
                    }),
                  if (widget.collection == 'members_private')
                    _sheetItem(Icons.public, 'العودة للشجرة العامة', () {
                      Navigator.pop(ctx);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FamilyTreePage(
                            isDarkMode: widget.isDarkMode,
                            onThemeToggle: widget.onThemeToggle,
                            collection: 'members_public',
                          ),
                        ),
                      );
                    }),
                  _sheetItem(Icons.unfold_more_rounded, 'فتح الكل', () {
                    Navigator.pop(ctx);
                    _expandAll(all);
                  }),
                  _sheetItem(Icons.unfold_less_rounded, 'طي الكل', () {
                    Navigator.pop(ctx);
                    _collapseAll(all);
                  }),
                  _sheetItem(
                    Icons.center_focus_strong_rounded,
                    'توسيط / ملائمة الشجرة',
                        () {
                      Navigator.pop(ctx);
                      _fitTree();
                    },
                  ),
                  const Divider(),
                  _sheetItem(Icons.print_rounded, 'طباعة', () {
                    Navigator.pop(ctx);
                    _printTree();
                  }),
                  _sheetItem(Icons.ios_share_rounded, 'مشاركة صورة', () {
                    Navigator.pop(ctx);
                    exportTreeImage();
                  }),
                  const Divider(),
                  _sheetItem(
                    isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    isDark ? 'الوضع الفاتح' : 'الوضع الداكن',
                        () {
                      Navigator.pop(ctx);
                      widget.onThemeToggle(!isDark);
                    },
                  ),
                  const Divider(),
                  if (access.isGuest)
                    _sheetItem(Icons.lock_open_rounded, 'فتح وضع العائلة', () {
                      Navigator.pop(ctx);
                      _openFamilyModeQuick();
                    }),
                  if (!access.isGuest)
                    _sheetItem(
                      Icons.lock_reset_rounded,
                      'الرجوع لوضع الضيف',
                          () {
                        Navigator.pop(ctx);
                        context.read<AccessController>().setGuest();
                      },
                    ),
                  if (_isAdmin)
                    _sheetItem(
                      Icons.admin_panel_settings_rounded,
                      'لوحة تحكم الأدمن',
                          () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminPanelPage(),
                          ),
                        );
                      },
                    ),
                  _sheetItem(Icons.info_outline_rounded, 'عن التطبيق', () {
                    Navigator.pop(ctx);
                    _showAboutDialog();
                  }),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sheetHeader(bool isDark) {
    return Container(
      width: 44,
      height: 5,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white24 : Colors.black12,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  Widget _sheetItem(
      IconData icon,
      String title,
      VoidCallback onTap, {
        bool danger = false,
      }) {
    final color = danger ? Colors.red : null;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _appBarBtn({
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
    bool active = false,
    bool gold = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: gold
              ? AppColors.gold.withValues(alpha: 0.15)
              : active
              ? AppColors.gold.withValues(alpha: 0.2)
              : (isDark
              ? AppColors.surface
              : Colors.white.withValues(alpha: 0.8)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (gold || active)
                ? AppColors.gold.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 18,
          color: (gold || active)
              ? AppColors.gold
              : (isDark ? Colors.white70 : Colors.black54),
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.border : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: 'ابحث عن اسم...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white38 : Colors.grey,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? Colors.white38 : Colors.grey,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear_rounded),
            onPressed: () {
              _searchCtrl.clear();
              _lastFitKey++;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fitTree();
              });
            },
            color: isDark ? Colors.white38 : Colors.grey,
          )
              : null,
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildTreeView(bool isDark, AccessController access) {
    if (_cachedRoots.isEmpty) {
      return Center(
        child: Text(
          'لا توجد نتائج',
          style: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
        ),
      );
    }

    final fitKey = _lastFitKey;

    return CustomFamilyTreeView(
      key: ValueKey('tree-$fitKey-${_cachedRoots.length}'),
      roots: _cachedRoots,
      selectedNodeId: _selectedId,
      externalController: _treeController,
      onToggleChildren: _toggleCollapse,
      direction: TreeVerticalDirection.topToBottom,
      onLayoutReady: (centers, bounds, canvasSize) {
        _nodeCenters = centers;
        _treeBounds = bounds;

        if (!_didAutoFitOnce) {
          _didAutoFitOnce = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _fitTree();
          });
        }
      },
      onNodeTap: (node) async {
        final all = _cachedAll ?? [];
        final m = all.where((x) => x.id == node.id).firstOrNull;
        final privacy = await _privacyService.getSettings();

        if (m != null) {
          await _showMemberDetails(all, m, access, privacy);
        }
      },
    );
  }

  Widget _buildFAB(List<FamilyMember> all) {
    return GestureDetector(
      onTap: () async {
        final draft = await Navigator.push<MemberDraft>(
          context,
          MaterialPageRoute(
            builder: (_) => AddEditMemberPage(
              title: 'إضافة',
              members: all,
              initial: null,
            ),
          ),
        );
        if (draft != null) {
          await _repo.addMemberRaw(
            name: draft.name,
            fatherId: draft.fatherId,
            isFemale: draft.isFemale,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.goldDark, AppColors.gold],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.45),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'إضافة',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCount(
      List<FamilyMember> all,
      AccessController access,
      PrivacySettings privacy,
      ) {
    final filtered = _cachedFiltered;

    final visibleCount = all.where((m) {
      if (access.isGuest &&
          privacy.hideFemalesFromGeneralSearch &&
          m.isFemale) {
        return false;
      }
      return true;
    }).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? AppColors.surface.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isDarkMode ? AppColors.border : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_rounded, size: 16, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            _searchQuery.isEmpty
                ? '$visibleCount عضو'
                : '${filtered.length} / $visibleCount',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: widget.isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoomBtn(
    IconData icon,
    VoidCallback onTap,
    bool isDark, {
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surface : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? AppColors.border : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 14,
              ),
            ],
          ),
          child: Icon(icon, color: AppColors.gold, size: 22),
        ),
      ),
    );
  }

  Widget _buildFamilyIndexDrawer(
    AccessController access,
    PrivacySettings privacy,
  ) {
    final isDark = widget.isDarkMode;

    Widget tabBtn({
      required String text,
      required bool active,
      required VoidCallback onTap,
      required IconData icon,
    }) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.gold.withValues(alpha: isDark ? 0.18 : 0.22)
                  : (isDark
                  ? AppColors.surface.withValues(alpha: 0.8)
                  : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? AppColors.gold.withValues(alpha: 0.6)
                    : (isDark ? AppColors.border : Colors.grey.shade200),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: active
                      ? AppColors.goldDark
                      : (isDark ? Colors.white70 : Colors.black54),
                ),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: active
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget searchBox() {
      return Container(
        margin: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.border : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
            ),
          ],
        ),
        child: TextField(
          controller: _indexSearchCtrl,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: _indexShowFamilies ? 'ابحث عن عائلة/جد...' : 'ابحث عن اسم...',
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: isDark ? Colors.white38 : Colors.grey,
            ),
            suffixIcon: _indexQuery.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.clear_rounded),
              color: isDark ? Colors.white38 : Colors.grey,
              onPressed: () {
                _indexSearchCtrl.clear();
                setState(() => _indexQuery = '');
              },
            )
                : null,
            border: InputBorder.none,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      );
    }

    return Drawer(
      backgroundColor: isDark ? AppColors.bg : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.goldDark, AppColors.gold],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'الدليل',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      tabBtn(
                        text: 'عائلات',
                        icon: Icons.folder_shared,
                        active: _indexShowFamilies,
                        onTap: () => setState(() => _indexShowFamilies = true),
                      ),
                      const SizedBox(width: 10),
                      tabBtn(
                        text: 'أسماء',
                        icon: Icons.people_rounded,
                        active: !_indexShowFamilies,
                        onTap: () => setState(() => _indexShowFamilies = false),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            searchBox(),
            Expanded(
              child: StreamBuilder<List<FamilyMember>>(
                stream: _repo.membersStream(),
                builder: (context, snap) {
                  if (!snap.hasData) return const SizedBox();

                  final all = snap.data!;

                  if (_indexShowFamilies) {
                    final roots = all.where((m) => m.fatherId == null).toList()
                      ..sort((a, b) => a.name.compareTo(b.name));

                    final q = _indexQuery.trim();
                    final shown = q.isEmpty
                        ? roots
                        : roots.where((m) => m.name.toLowerCase().contains(q)).toList();

                    final counts = <String, int>{};
                    for (final r in shown) {
                      counts[r.id] = _countBranchMembers(r.id, all);
                    }

                    if (shown.isEmpty) {
                      return Center(
                        child: Text(
                          'لا توجد نتائج',
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.grey,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 18),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                      itemBuilder: (ctx, i) {
                        final m = shown[i];
                        final total = counts[m.id] ?? 1;
                        return ListTile(
                          leading: const Icon(
                            Icons.folder_shared,
                            color: AppColors.gold,
                          ),
                          title: Text(
                            _displayName(m, access, privacy),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            'عدد أفراد الفرع: $total',
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _focusOnMember(m, all);
                          },
                        );
                      },
                    );
                  }

                  final list = [...all]..sort((a, b) => a.name.compareTo(b.name));

                  final q = _indexQuery.trim();
                  final shown = q.isEmpty
                      ? list
                      : list.where((m) => m.name.toLowerCase().contains(q)).toList();

                  if (shown.isEmpty) {
                    return Center(
                      child: Text(
                        'لا توجد نتائج',
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.grey,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 18),
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                    itemBuilder: (ctx, i) {
                      final m = shown[i];
                      return ListTile(
                        leading: const Icon(
                          Icons.person_rounded,
                          color: AppColors.gold,
                        ),
                        title: Text(
                          _displayName(m, access, privacy),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _focusOnMember(m, all);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberBottomSheet extends StatelessWidget {
  final FamilyMember member;
  final FamilyMember? father;
  final List<FamilyMember> children;
  final List<FamilyMember> allMembers;

  final bool isRoot, isCollapsed, isAdmin;
  final Color primary, accent;
  final int level;
  final String displayName;

  final VoidCallback? onToggle,
      onFocusTree,
      onShowGrandchildren,
      onRelation,
      onAddChild,
      onAddFather,
      onEdit,
      onDelete,
      onPhoto,
      onBranchColor,
      onMakeRoot;

  const _MemberBottomSheet({
    required this.member,
    required this.father,
    required this.children,
    required this.allMembers,
    required this.isRoot,
    required this.isCollapsed,
    required this.isAdmin,
    required this.primary,
    required this.accent,
    required this.level,
    required this.displayName,
    this.onToggle,
    this.onFocusTree,
    this.onShowGrandchildren,
    this.onRelation,
    this.onAddChild,
    this.onAddFather,
    this.onEdit,
    this.onDelete,
    this.onPhoto,
    this.onBranchColor,
    this.onMakeRoot,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.card : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.25),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        primary.withValues(alpha: 0.2),
                        accent.withValues(alpha: 0.1),
                      ],
                    ),
                    border: Border.all(color: accent, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: member.photoUrl?.isNotEmpty == true
                      ? ClipOval(
                    child: Image.network(member.photoUrl!, fit: BoxFit.cover),
                  )
                      : Icon(Icons.person_rounded, color: accent, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _chip('ج${level + 1}', primary),
                          if (isRoot) ...[
                            const SizedBox(width: 6),
                            _chip('⭐ جد رئيسي', AppColors.gold),
                          ],
                          const SizedBox(width: 6),
                          _chip('${children.length} أبناء', accent),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (father != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.arrow_downward_rounded, size: 16, color: primary),
                    const SizedBox(width: 8),
                    Text(
                      'الأب: ',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      father!.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (isAdmin)
                  _actionBtn(
                    icon: Icons.person_add_rounded,
                    label: 'إضافة ابن',
                    color: Colors.indigo,
                    onTap: () => onAddChild?.call(),
                  ),
                if (isAdmin)
                  _actionBtn(
                    icon: Icons.arrow_upward_rounded,
                    label: 'إضافة أب',
                    color: Colors.deepOrange,
                    onTap: () => onAddFather?.call(),
                  ),
                if (children.isNotEmpty)
                  _actionBtn(
                    icon: isCollapsed
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    label: isCollapsed
                        ? 'عرض الأبناء (${children.length})'
                        : 'طي الأبناء',
                    color: isCollapsed ? Colors.orange : primary,
                    onTap: onToggle,
                  ),
                _actionBtn(
                  icon: Icons.center_focus_strong_rounded,
                  label: 'عرض شجرته',
                  color: accent,
                  onTap: onFocusTree,
                ),
                if (onShowGrandchildren != null)
                  _actionBtn(
                    icon: Icons.account_tree_rounded,
                    label: 'عرض الأحفاد',
                    color: Colors.blueGrey,
                    onTap: onShowGrandchildren,
                  ),
                _actionBtn(
                  icon: Icons.link_rounded,
                  label: 'صلة القرابة',
                  color: Colors.purple,
                  onTap: onRelation,
                ),
                if (isAdmin) ...[
                  _actionBtn(
                    icon: Icons.edit_rounded,
                    label: 'تعديل',
                    color: primary,
                    onTap: onEdit,
                  ),
                  _actionBtn(
                    icon: Icons.image_rounded,
                    label: 'صورة',
                    color: Colors.teal,
                    onTap: onPhoto,
                  ),
                  _actionBtn(
                    icon: Icons.palette_rounded,
                    label: member.branchColor?.isNotEmpty == true ? 'تغيير اللون' : 'لون الفرع',
                    color: member.branchColor?.isNotEmpty == true
                        ? (_parseHexColor(member.branchColor) ?? Colors.teal)
                        : Colors.teal,
                    onTap: onBranchColor,
                  ),
                  _actionBtn(
                    icon: member.inheritToChildren
                        ? Icons.account_tree_rounded
                        : Icons.account_tree_outlined,
                    label: 'توريث اللون',
                    color: member.inheritToChildren ? Colors.green : Colors.grey,
                    onTap: onBranchColor,
                  ),
                  if (!isRoot)
                    _actionBtn(
                      icon: Icons.star_rounded,
                      label: 'جعله جداً',
                      color: AppColors.gold,
                      onTap: onMakeRoot,
                    ),
                  _actionBtn(
                    icon: Icons.delete_rounded,
                    label: 'حذف',
                    color: Colors.red,
                    onTap: onDelete,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BgPainter extends CustomPainter {
  final bool isDark;
  _BgPainter(this.isDark);

  @override
  void paint(Canvas canvas, Size size) {
    if (!isDark) return;

    final spots = [
      Offset(size.width * 0.2, size.height * 0.2),
      Offset(size.width * 0.8, size.height * 0.7),
      Offset(size.width * 0.5, size.height * 0.5),
    ];
    final colors = [
      const Color(0xFF1e3c72),
      const Color(0xFF2d6a4f),
      const Color(0xFF6B2D8B),
    ];

    for (int i = 0; i < spots.length; i++) {
      canvas.drawCircle(
        spots[i],
        size.width * 0.35,
        Paint()
          ..color = colors[i].withValues(alpha: 0.07)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80),
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class AddEditMemberPage extends StatefulWidget {
  final String title;
  final List<FamilyMember> members;
  final FamilyMember? initial;
  final String? presetFatherId;

  const AddEditMemberPage({
    super.key,
    required this.title,
    required this.members,
    this.initial,
    this.presetFatherId,
  });

  @override
  State<AddEditMemberPage> createState() => _AddEditMemberPageState();
}

class _AddEditMemberPageState extends State<AddEditMemberPage> {
  late final TextEditingController _nameCtrl;
  String? _fatherId;
  String _searchFather = '';
  bool _showFatherList = false;

  bool _isFemale = false;
  bool _userClearedFather = false;
  late final bool _isAddChildFlow;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial?.name ?? '');
    _fatherId = widget.initial?.fatherId ?? widget.presetFatherId;
    _showFatherList = _fatherId == null;

    _isFemale = widget.initial?.isFemale ?? false;
    _isAddChildFlow = widget.presetFatherId != null && widget.initial == null;
  }

  String _norm(String t) => t
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[\u064B-\u0652]'), '');

  bool _isDescendant({
    required String rootId,
    required String candidateId,
    required List<FamilyMember> all,
  }) {
    final childrenByFather = <String, List<String>>{};
    for (final m in all) {
      final f = m.fatherId;
      if (f == null) continue;
      (childrenByFather[f] ??= []).add(m.id);
    }

    final stack = <String>[rootId];
    final visited = <String>{rootId};

    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      final kids = childrenByFather[cur] ?? const <String>[];
      for (final k in kids) {
        if (k == candidateId) return true;
        if (visited.add(k)) stack.add(k);
      }
    }
    return false;
  }

  Future<void> _showInvalidFatherDialog(String msg) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('اختيار غير صحيح'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _norm(_searchFather.toLowerCase());
    final filtered = widget.members
        .where((m) =>
    m.id != widget.initial?.id &&
        _norm(m.name.toLowerCase()).contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final selectedFather = _fatherId != null
        ? widget.members.where((m) => m.id == _fatherId).firstOrNull
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.goldDark,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'الاسم',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.person_rounded),
              ),
            ),

            const SizedBox(height: 18),

            Text('الجنس:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    value: false,
                    groupValue: _isFemale,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ذكر'),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _isFemale = v);
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    value: true,
                    groupValue: _isFemale,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('أنثى'),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _isFemale = v);
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Text('الأب:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            if (selectedFather != null)
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.gold,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedFather.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        _fatherId = null;
                        _showFatherList = true;
                        _userClearedFather = true;
                      }),
                      child: const Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),

            if (selectedFather != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _showFatherList = !_showFatherList),
                  icon: Icon(
                    _showFatherList
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                  label: Text(
                    _showFatherList ? 'إخفاء القائمة' : 'تغيير الأب',
                  ),
                ),
              ),

            if (_showFatherList) ...[
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'بحث عن الأب...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                onChanged: (v) => setState(() => _searchFather = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    if (!_isAddChildFlow || _userClearedFather)
                      ListTile(
                        leading:
                        const Icon(Icons.block_rounded, color: Colors.grey),
                        title: const Text('بلا أب (جد رئيسي)'),
                        selected: _fatherId == null,
                        onTap: () => setState(() => _fatherId = null),
                      ),
                    ...filtered.map(
                          (m) => ListTile(
                        leading: Icon(
                          Icons.person_rounded,
                          color:
                          _fatherId == m.id ? AppColors.gold : Colors.grey,
                        ),
                        title: Text(m.name),
                        selected: _fatherId == m.id,
                        selectedColor: AppColors.gold,
                        onTap: () async {
                          final editingId = widget.initial?.id;

                          if (editingId != null) {
                            if (m.id == editingId) {
                              await _showInvalidFatherDialog(
                                'لا يمكن اختيار نفس الشخص كأب.',
                              );
                              return;
                            }

                            final bad = _isDescendant(
                              rootId: editingId,
                              candidateId: m.id,
                              all: widget.members,
                            );

                            if (bad) {
                              await _showInvalidFatherDialog(
                                'لا يمكن اختيار هذا الشخص كأب لأنه من نسل العضو (ابن/حفيد).\nهذا يسبب حلقة في شجرة العائلة.',
                              );
                              return;
                            }
                          }

                          setState(() => _fatherId = m.id);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const Spacer(),
            ],

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.goldDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.pop(
                  context,
                  MemberDraft(
                    name: _nameCtrl.text.trim(),
                    fatherId: _fatherId,
                    isFemale: _isFemale,
                  ),
                ),
                child: const Text(
                  'حفظ',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
