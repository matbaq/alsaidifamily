import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';

import '../data/family_repository.dart';
import '../models/family_member.dart';
import '../models/tree_node.dart';
import '../widgets/family_tree/custom_family_tree_view.dart';
import '../widgets/family_tree/node_widget.dart';

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

  const FamilyTreePage({
    super.key,
    required this.isDarkMode,
    required this.onThemeToggle,
  });

  @override
  State<FamilyTreePage> createState() => _FamilyTreePageState();
}

class _FamilyTreePageState extends State<FamilyTreePage>
    with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _repo = FamilyRepository();

  final _searchCtrl     = TextEditingController();
  final _treeController = TransformationController();
  final GlobalKey _treeShotKey = GlobalKey();

  String  _searchQuery = '';
  String? _selectedId;

  bool _isBottomSheetOpen = false;
  bool _showSearch = false;

  Map<String, Offset> _nodeCenters = {};
  Rect? _treeBounds;
  Size? _treeCanvasSize;

  int _lastFitKey = 0;

  List<FamilyMember>? _cachedAll;
  String _cachedQuery = '';
  Set<String> _cachedCollapsed = {};
  List<FamilyMember> _cachedFiltered = [];
  List<TreeNode> _cachedRoots = [];

  final Set<String> _collapsedIds = {};

  bool get _isAdmin => _auth.currentUser != null;

  static const double _topOffset = 130.0;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.toLowerCase().trim();
      if (q == _searchQuery) return;
      setState(() => _searchQuery = q);
      _lastFitKey++;
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _treeController.dispose();
    super.dispose();
  }

  void _setInitialCollapse(List<FamilyMember> all) {}

  void _fitTree() {
    if (_treeBounds == null) return;

    final b = _treeBounds!;
    final screen = MediaQuery.of(context).size;

    const pad = 40.0;
    final availableW = screen.width;
    final availableH = (screen.height - _topOffset).clamp(200.0, screen.height);

    final sx = availableW / (b.width + pad * 2);
    final sy = availableH / (b.height + pad * 2);
    final scale = (sx < sy ? sx : sy).clamp(0.06, 2.2);

    final tx = (availableW - b.width * scale) / 2 - b.left * scale + pad * scale;
    final ty = (availableH - b.height * scale) / 2 - b.top  * scale + pad * scale;

    _treeController.value = Matrix4.identity()
      ..translate(tx, ty + _topOffset)
      ..scale(scale);
  }

  void _centerOn(String id) {
    final center = _nodeCenters[id];
    if (center == null) return;

    final screen = MediaQuery.of(context).size;
    final sc = _treeController.value.getMaxScaleOnAxis();

    final tx = screen.width / 2 - center.dx * sc;
    final ty = (screen.height + _topOffset) / 2 - center.dy * sc;

    final target = Matrix4.identity()..translate(tx, ty)..scale(sc);

    final ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
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

  String _norm(String t) => t
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[\u064B-\u0652]'), '');

  List<FamilyMember> _filter(List<FamilyMember> all) {
    if (_searchQuery.isEmpty) return all;

    final q = _norm(_searchQuery);
    final visible = <String>{};

    for (final m in all) {
      if (_norm(m.name.toLowerCase()).contains(q)) {
        visible.add(m.id);

        String? pid = m.fatherId;
        while (pid != null) {
          if (visible.contains(pid)) break;
          visible.add(pid);
          try {
            pid = all.firstWhere((x) => x.id == pid).fatherId;
          } catch (_) {
            pid = null;
          }
        }
      }
    }

    return all.where((m) => visible.contains(m.id)).toList();
  }

  List<TreeNode> _buildTree(List<FamilyMember> filtered, List<FamilyMember> all) {
    final roots = filtered.where((m) => m.fatherId == null).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return roots.map((r) => _buildNode(r, filtered, all)).toList();
  }

  Color _nodeColor(FamilyMember m, List<FamilyMember> all) {
    final level = _getLevelOf(m.id, all);
    return GenerationPalette.primaryForLevel(level);
  }

  TreeNode _buildNode(FamilyMember m, List<FamilyMember> filtered, List<FamilyMember> all) {
    final directChildren = filtered.where((x) => x.fatherId == m.id).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final isCollapsed = _collapsedIds.contains(m.id) && _searchQuery.isEmpty;
    final childrenCount = directChildren.length;

    final childNodes = isCollapsed
        ? <TreeNode>[]
        : directChildren.map((c) => _buildNode(c, filtered, all)).toList();

    return TreeNode(
      id: m.id,
      name: m.name,
      photoUrl: m.photoUrl,
      branchColor: _nodeColor(m, all),
      isRoot: m.fatherId == null,
      children: childNodes,
      childrenCount: childrenCount,
      isCollapsed: isCollapsed,
    );
  }

  void _recompute(List<FamilyMember> all) {
    final sameData = identical(_cachedAll, all);
    final sameQuery = _cachedQuery == _searchQuery;
    final sameCollapse = _cachedCollapsed.length == _collapsedIds.length &&
        _cachedCollapsed.containsAll(_collapsedIds);

    if (sameData && sameQuery && sameCollapse) return;

    _cachedAll = all;
    _cachedQuery = _searchQuery;
    _cachedCollapsed = Set.from(_collapsedIds);
    _cachedFiltered = _filter(all);
    _cachedRoots = _buildTree(_cachedFiltered, all);
  }

  Future<Uint8List?> _captureTreePng({double pixelRatio = 3}) async {
    try {
      final boundary = _treeShotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareTreeAsImage() async {
    final bytes = await _captureTreePng(pixelRatio: 3);
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
      text: 'شجرة عائلة الصايدي',
    );
  }

  Future<void> _printTree() async {
    final bytes = await _captureTreePng(pixelRatio: 3);
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تجهيز الطباعة')),
        );
      }
      return;
    }

    await Printing.layoutPdf(
      onLayout: (format) async {
        final doc = await Printing.convertHtml(
          format: format,
          html: '<center><img src="data:image/png;base64,${base64Encode(bytes)}" style="width:100%"/></center>',
        );
        return doc;
      },
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.card : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.gold),
              const SizedBox(width: 10),
              Text('حول التطبيق', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('شجرة عائلة الصايدي',
                  style: TextStyle(fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 6),
              Text('الإصدار 1.0.0', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
              const SizedBox(height: 14),
              Text(
                'تم تصميم التطبيق لعرض شجرة العائلة بشكل منظم مع البحث والتنقل السريع.',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق', style: TextStyle(color: AppColors.goldDark)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMemberDetails(List<FamilyMember> all, FamilyMember m) async {
    if (_isBottomSheetOpen) return;
    _isBottomSheetOpen = true;

    setState(() => _selectedId = m.id);
    _centerOn(m.id);

    final children = all.where((x) => x.fatherId == m.id).toList();
    final father = m.fatherId != null
        ? all.where((x) => x.id == m.fatherId).firstOrNull
        : null;

    final isRoot = m.fatherId == null;
    final level = _getLevelOf(m.id, all);
    final primary = GenerationPalette.primaryForLevel(level);
    final accent = GenerationPalette.accentForLevel(level);
    final isCollapsed = _collapsedIds.contains(m.id);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MemberBottomSheet(
        member: m,
        father: father,
        children: children,
        isRoot: isRoot,
        isCollapsed: isCollapsed,
        isAdmin: _isAdmin,
        primary: primary,
        accent: accent,
        level: level,
        allMembers: all,
        onToggle: () {
          _toggleCollapse(m.id);
          Navigator.pop(ctx);
        },
        onFocusTree: () {
          Navigator.pop(ctx);
          _focusOnMember(m, all);
        },
        onEdit: _isAdmin
            ? () async {
          Navigator.pop(ctx);
          final draft = await Navigator.push<MemberDraft>(
            context,
            MaterialPageRoute(
              builder: (_) => AddEditMemberPage(title: 'تعديل', members: all, initial: m),
            ),
          );
          if (draft != null) {
            await _repo.updateName(id: m.id, name: draft.name, fatherId: draft.fatherId);
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
        onMakeRoot: _isAdmin
            ? () async {
          await _repo.updateFatherId(id: m.id, fatherId: null);
          if (ctx.mounted) Navigator.pop(ctx);
        }
            : null,
      ),
    );

    _isBottomSheetOpen = false;
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
      final idsWithChildren = all.map((x) => x.fatherId).whereType<String>().toSet();
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

  Future<bool?> _confirmDelete(String name) => showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('تأكيد الحذف'),
      content: Text('هل تريد حذف "$name"؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );

  Future<void> _pickPhoto(String id) async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;

      final ref = FirebaseStorage.instance.ref().child('family_photos').child('$id.jpg');
      await ref.putFile(File(picked.path));
      await _repo.updatePhoto(id, await ref.getDownloadURL());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم تحديث الصورة'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
    }
  }

  Future<bool?> _showLogin() => showDialog<bool>(
    context: context,
    builder: (ctx) {
      final emailCtrl = TextEditingController();
      final passCtrl = TextEditingController();
      return AlertDialog(
        title: const Text('دخول الإدارة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'البريد')),
            TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              try {
                await _auth.signInWithEmailAndPassword(
                  email: emailCtrl.text.trim(),
                  password: passCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (_) {
                if (ctx.mounted) Navigator.pop(ctx, false);
              }
            },
            child: const Text('دخول'),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.bg : const Color(0xFFF0F4FF),
        body: StreamBuilder<List<FamilyMember>>(
          stream: _repo.membersStream(),
          builder: (context, snap) {
            if (snap.hasError) return const Center(child: Text('خطأ في البيانات'));
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: AppColors.gold));
            }

            final all = snap.data!;
            _setInitialCollapse(all);
            _recompute(all);

            return Stack(
              children: [
                _buildBackground(isDark),

                Positioned.fill(
                  top: _topOffset,
                  child: RepaintBoundary(
                    key: _treeShotKey,
                    child: _buildTreeView(isDark),
                  ),
                ),

                _buildAppBar(isDark, all),

                if (_showSearch)
                  Positioned(
                    top: 90,
                    left: 16,
                    right: 16,
                    child: _buildSearchBar(isDark),
                  ),

                if (_isAdmin)
                  Positioned(
                    bottom: 24,
                    right: 16,
                    child: _buildFAB(all),
                  ),

                Positioned(
                  bottom: 24,
                  left: 16,
                  child: _buildMemberCount(all),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBackground(bool isDark) {
    return Positioned.fill(child: CustomPaint(painter: _BgPainter(isDark)));
  }

  Widget _buildAppBar(bool isDark, List<FamilyMember> all) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8, right: 8, bottom: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: isDark
                ? [AppColors.bg, AppColors.bg.withValues(alpha: 0.0)]
                : [const Color(0xFFF0F4FF), const Color(0xFFF0F4FF).withValues(alpha: 0.0)],
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.goldDark, AppColors.gold]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.4), blurRadius: 12)],
              ),
              child: const Icon(Icons.account_tree_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'شجرة عائلة الصايدي',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text('${all.length} عضو', style: const TextStyle(fontSize: 12, color: AppColors.gold)),
                ],
              ),
            ),

            _appBarBtn(
              icon: Icons.search_rounded,
              isDark: isDark,
              active: _showSearch,
              onTap: () {
                setState(() => _showSearch = !_showSearch);
                _lastFitKey++;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _fitTree();
                });
              },
            ),
            const SizedBox(width: 6),

            _appBarBtn(
              icon: Icons.center_focus_strong_rounded,
              isDark: isDark,
              onTap: _fitTree,
            ),
            const SizedBox(width: 6),

            _appBarBtn(
              icon: Icons.ios_share_rounded,
              isDark: isDark,
              onTap: _shareTreeAsImage,
            ),
            const SizedBox(width: 6),

            _appBarBtn(
              icon: Icons.print_rounded,
              isDark: isDark,
              onTap: _printTree,
            ),
            const SizedBox(width: 6),

            _appBarBtn(
              icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              isDark: isDark,
              onTap: () => widget.onThemeToggle(!isDark),
            ),
            const SizedBox(width: 6),

            _appBarBtn(
              icon: Icons.info_outline_rounded,
              isDark: isDark,
              onTap: _showAboutDialog,
            ),
            const SizedBox(width: 6),

            _appBarBtn(
              icon: _isAdmin ? Icons.logout_rounded : Icons.admin_panel_settings_rounded,
              isDark: isDark,
              gold: _isAdmin,
              onTap: () async {
                if (_isAdmin) {
                  await _auth.signOut();
                  if (mounted) setState(() {});
                } else {
                  final ok = await _showLogin();
                  if (ok == true && mounted) setState(() {});
                }
              },
            ),
          ],
        ),
      ),
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
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: gold
              ? AppColors.gold.withValues(alpha: 0.15)
              : active
              ? AppColors.gold.withValues(alpha: 0.15)
              : (isDark ? AppColors.surface : Colors.white.withValues(alpha: 0.8)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (gold || active) ? AppColors.gold.withValues(alpha: 0.5) : Colors.transparent,
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
          color: (gold || active) ? AppColors.gold : (isDark ? Colors.white70 : Colors.black54),
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.border : Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20)],
      ),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: 'ابحث عن اسم...',
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
          prefixIcon: Icon(Icons.search_rounded, color: isDark ? Colors.white38 : Colors.grey),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildTreeView(bool isDark) {
    if (_cachedRoots.isEmpty) {
      return Center(
        child: Text('لا توجد نتائج', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey)),
      );
    }

    final fitKey = _lastFitKey;

    return CustomFamilyTreeView(
      key: ValueKey('tree-$fitKey-${_cachedRoots.length}'),
      roots: _cachedRoots,
      selectedNodeId: _selectedId,
      externalController: _treeController,
      onToggleChildren: _toggleCollapse,
      onLayoutReady: (centers, bounds, canvasSize) {
        _nodeCenters = centers;
        _treeBounds = bounds;
        _treeCanvasSize = canvasSize;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _fitTree();
        });
      },
      onNodeTap: (node) async {
        final all = _cachedAll ?? [];
        final m = all.where((x) => x.id == node.id).firstOrNull;
        if (m != null) await _showMemberDetails(all, m);
      },
    );
  }

  Widget _buildFAB(List<FamilyMember> all) {
    return GestureDetector(
      onTap: () async {
        final draft = await Navigator.push<MemberDraft>(
          context,
          MaterialPageRoute(builder: (_) => AddEditMemberPage(title: 'إضافة', members: all, initial: null)),
        );
        if (draft != null) {
          await _repo.addMemberRaw(name: draft.name, fatherId: draft.fatherId);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.goldDark, AppColors.gold]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: AppColors.gold.withValues(alpha: 0.45), blurRadius: 20, spreadRadius: 2),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('إضافة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCount(List<FamilyMember> all) {
    final filtered = _cachedFiltered;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isDarkMode ? AppColors.surface.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.isDarkMode ? AppColors.border : Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_rounded, size: 16, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            _searchQuery.isEmpty ? '${all.length} عضو' : '${filtered.length} / ${all.length}',
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
}

class _MemberBottomSheet extends StatelessWidget {
  final FamilyMember member;
  final FamilyMember? father;
  final List<FamilyMember> children;
  final List<FamilyMember> allMembers;

  final bool isRoot, isCollapsed, isAdmin;
  final Color primary, accent;
  final int level;

  final VoidCallback? onToggle, onFocusTree, onEdit, onDelete, onPhoto, onMakeRoot;

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
    this.onToggle,
    this.onFocusTree,
    this.onEdit,
    this.onDelete,
    this.onPhoto,
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
          BoxShadow(color: primary.withValues(alpha: 0.25), blurRadius: 30, spreadRadius: 2),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [primary.withValues(alpha: 0.2), accent.withValues(alpha: 0.1)],
                  ),
                  border: Border.all(color: accent, width: 2),
                  boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 12)],
                ),
                child: member.photoUrl?.isNotEmpty == true
                    ? ClipOval(child: Image.network(member.photoUrl!, fit: BoxFit.cover))
                    : Icon(Icons.person_rounded, color: accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    member.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    _chip('ج${level + 1}', primary),
                    if (isRoot) ...[const SizedBox(width: 6), _chip('⭐ جد رئيسي', AppColors.gold)],
                    const SizedBox(width: 6),
                    _chip('${children.length} أبناء', accent),
                  ]),
                ]),
              ),
            ]),

            if (father != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primary.withValues(alpha: 0.15)),
                ),
                child: Row(children: [
                  Icon(Icons.arrow_downward_rounded, size: 16, color: primary),
                  const SizedBox(width: 8),
                  Text('الأب: ', style: TextStyle(color: isDark ? Colors.white54 : Colors.grey, fontSize: 13)),
                  Text(
                    father!.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 13,
                    ),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            Wrap(spacing: 10, runSpacing: 10, children: [
              if (children.isNotEmpty)
                _actionBtn(
                  icon: isCollapsed ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
                  label: isCollapsed ? 'عرض الأبناء (${children.length})' : 'طي الأبناء',
                  color: isCollapsed ? Colors.orange : primary,
                  onTap: onToggle,
                ),
              _actionBtn(
                icon: Icons.center_focus_strong_rounded,
                label: 'عرض شجرته',
                color: accent,
                onTap: onFocusTree,
              ),
              if (isAdmin) ...[
                _actionBtn(icon: Icons.edit_rounded, label: 'تعديل', color: primary, onTap: onEdit),
                _actionBtn(icon: Icons.image_rounded, label: 'صورة', color: Colors.teal, onTap: onPhoto),
                if (!isRoot)
                  _actionBtn(icon: Icons.star_rounded, label: 'جعله جداً', color: AppColors.gold, onTap: onMakeRoot),
                _actionBtn(icon: Icons.delete_rounded, label: 'حذف', color: Colors.red, onTap: onDelete),
              ],
            ]),
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
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
        ]),
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

  const AddEditMemberPage({
    super.key,
    required this.title,
    required this.members,
    this.initial,
  });

  @override
  State<AddEditMemberPage> createState() => _AddEditMemberPageState();
}

class _AddEditMemberPageState extends State<AddEditMemberPage> {
  late final TextEditingController _nameCtrl;
  String? _fatherId;
  String _searchFather = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial?.name ?? '');
    _fatherId = widget.initial?.fatherId;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.members
        .where((m) => m.id != widget.initial?.id &&
        m.name.toLowerCase().contains(_searchFather.toLowerCase()))
        .toList();

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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.person_rounded),
              ),
            ),
            const SizedBox(height: 20),
            Text('الأب:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (selectedFather != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(selectedFather.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  GestureDetector(
                    onTap: () => setState(() => _fatherId = null),
                    child: const Icon(Icons.clear_rounded, size: 18, color: Colors.red),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'بحث عن الأب...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _searchFather = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.block_rounded, color: Colors.grey),
                    title: const Text('بلا أب (جد رئيسي)'),
                    selected: _fatherId == null,
                    onTap: () => setState(() => _fatherId = null),
                  ),
                  ...filtered.map((m) => ListTile(
                    leading: Icon(Icons.person_rounded,
                        color: _fatherId == m.id ? AppColors.gold : Colors.grey),
                    title: Text(m.name),
                    selected: _fatherId == m.id,
                    selectedColor: AppColors.gold,
                    onTap: () => setState(() => _fatherId = m.id),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.goldDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(
                  context,
                  MemberDraft(name: _nameCtrl.text.trim(), fatherId: _fatherId),
                ),
                child: const Text('حفظ', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}