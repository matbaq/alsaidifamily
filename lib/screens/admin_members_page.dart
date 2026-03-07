import 'package:flutter/material.dart';
import '../data/family_repository.dart';
import '../models/family_member.dart';

class AdminMembersPage extends StatefulWidget {
  const AdminMembersPage({super.key});

  @override
  State<AdminMembersPage> createState() => _AdminMembersPageState();
}

class _AdminMembersPageState extends State<AdminMembersPage> {
  final _repo = FamilyRepository();
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q == _query) return;
      setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _norm(String t) => t
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[\u064B-\u0652]'), '')
      .toLowerCase();

  Future<void> _openMemberForm({
    FamilyMember? initial,
    String? presetFatherId,
  }) async {
    final allSnap = await _repo.membersStream().first;

    if (!mounted) return;

    final result = await Navigator.push<_AdminMemberFormResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _AdminMemberFormPage(
          title: initial == null ? 'إضافة عضو' : 'تعديل عضو',
          members: allSnap,
          initial: initial,
          presetFatherId: presetFatherId,
        ),
      ),
    );

    if (result == null) return;

    if (initial == null) {
      await _repo.addMemberRaw(
        name: result.name,
        fatherId: result.fatherId,
        isFemale: result.isFemale,
      );
    } else {
      await _repo.updateName(
        id: initial.id,
        name: result.name,
        fatherId: result.fatherId,
        isFemale: result.isFemale,
      );
    }
  }

  Future<void> _deleteMember(FamilyMember member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف "${member.name}"؟'),
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

    if (ok == true) {
      await _repo.deleteMember(member.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الأعضاء'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openMemberForm(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('إضافة'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'ابحث عن عضو...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () => _searchCtrl.clear(),
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<FamilyMember>>(
              stream: _repo.membersStream(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(child: Text('خطأ في البيانات'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snap.data!..sort((a, b) => a.name.compareTo(b.name));

                final shown = _query.isEmpty
                    ? all
                    : all.where((m) => _norm(m.name).contains(_norm(_query))).toList();

                if (shown.isEmpty) {
                  return const Center(child: Text('لا توجد نتائج'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final member = shown[i];

                    FamilyMember? father;
                    if (member.fatherId != null) {
                      for (final x in all) {
                        if (x.id == member.fatherId) {
                          father = x;
                          break;
                        }
                      }
                    }

                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2230) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF2A2F42)
                              : Colors.grey.shade200,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: member.isFemale
                              ? Colors.pink.withOpacity(0.14)
                              : Colors.blue.withOpacity(0.14),
                          backgroundImage: (member.photoUrl != null &&
                              member.photoUrl!.isNotEmpty)
                              ? NetworkImage(member.photoUrl!)
                              : null,
                          child: (member.photoUrl != null &&
                              member.photoUrl!.isNotEmpty)
                              ? null
                              : Icon(
                            member.isFemale
                                ? Icons.female_rounded
                                : Icons.male_rounded,
                          ),
                        ),
                        title: Text(
                          member.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            father != null
                                ? 'الأب: ${father.name} • ${member.isFemale ? 'أنثى' : 'ذكر'}'
                                : 'جد رئيسي • ${member.isFemale ? 'أنثى' : 'ذكر'}',
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'add_child') {
                              await _openMemberForm(presetFatherId: member.id);
                            } else if (v == 'edit') {
                              await _openMemberForm(initial: member);
                            } else if (v == 'delete') {
                              await _deleteMember(member);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'add_child',
                              child: Text('إضافة ابن/ابنة'),
                            ),
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('تعديل'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('حذف'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminMemberFormResult {
  final String name;
  final String? fatherId;
  final bool isFemale;

  _AdminMemberFormResult({
    required this.name,
    required this.fatherId,
    required this.isFemale,
  });
}

class _AdminMemberFormPage extends StatefulWidget {
  final String title;
  final List<FamilyMember> members;
  final FamilyMember? initial;
  final String? presetFatherId;

  const _AdminMemberFormPage({
    required this.title,
    required this.members,
    this.initial,
    this.presetFatherId,
  });

  @override
  State<_AdminMemberFormPage> createState() => _AdminMemberFormPageState();
}

class _AdminMemberFormPageState extends State<_AdminMemberFormPage> {
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String _norm(String t) => t
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[\u064B-\u0652]'), '')
      .toLowerCase();

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
    final q = _norm(_searchFather);
    final filtered = widget.members
        .where((m) =>
    m.id != widget.initial?.id && _norm(m.name).contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final selectedFather = _fatherId != null
        ? widget.members.where((m) => m.id == _fatherId).firstOrNull
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
                  color: Colors.amber.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.40)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.amber, size: 18),
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
                    _showFatherList ? Icons.expand_less : Icons.expand_more,
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
                          color: _fatherId == m.id
                              ? Colors.amber.shade700
                              : Colors.grey,
                        ),
                        title: Text(m.name),
                        selected: _fatherId == m.id,
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
                                'لا يمكن اختيار هذا الشخص كأب لأنه من نسل العضو (ابن/حفيد).',
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
                onPressed: () {
                  final name = _nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('اكتب الاسم أولًا')),
                    );
                    return;
                  }

                  Navigator.pop(
                    context,
                    _AdminMemberFormResult(
                      name: name,
                      fatherId: _fatherId,
                      isFemale: _isFemale,
                    ),
                  );
                },
                child: const Text('حفظ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}