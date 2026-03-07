import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/access_controller.dart';
import '../data/family_repository.dart';
import '../models/family_member.dart';
import '../services/privacy_service.dart';
import '../widgets/family_mode_gate.dart';

class FamilyWomenPage extends StatefulWidget {
  const FamilyWomenPage({super.key});

  @override
  State<FamilyWomenPage> createState() => _FamilyWomenPageState();
}

class _FamilyWomenPageState extends State<FamilyWomenPage> {
  final _repo = FamilyRepository();
  final _searchCtrl = TextEditingController();
  final _privacyService = PrivacyService();

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

  FamilyMember? _findFather(String? fatherId, List<FamilyMember> all) {
    if (fatherId == null) return null;
    for (final m in all) {
      if (m.id == fatherId) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

        if (privacy.womenPageAdminOnly && !access.isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('نساء العائلة')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'هذه الصفحة متاحة للأدمن فقط.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          );
        }

        return FamilyModeGate(
          title: 'نساء العائلة',
          child: Scaffold(
            appBar: AppBar(
              title: const Text('نساء العائلة'),
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن اسم...',
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

                      final all = snap.data!;
                      final women = all.where((m) => m.isFemale).toList()
                        ..sort((a, b) => a.name.compareTo(b.name));

                      final shown = _query.isEmpty
                          ? women
                          : women.where((m) {
                        final realName = _norm(m.name);
                        final shownName =
                        _norm(_displayName(m, access, privacy));
                        final q = _norm(_query);
                        return realName.contains(q) ||
                            shownName.contains(q);
                      }).toList();

                      if (shown.isEmpty) {
                        return const Center(
                          child: Text(
                            'لا توجد نتائج',
                            style: TextStyle(fontSize: 16),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final member = shown[i];
                          final father = _findFather(member.fatherId, all);

                          final canShowPhoto = !(access.isGuest &&
                              member.isFemale &&
                              privacy.hideFemalePhotosForGuest);

                          return Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E2230)
                                  : Colors.white,
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
                                radius: 26,
                                backgroundColor:
                                const Color(0xFFFFD700).withOpacity(0.18),
                                backgroundImage: canShowPhoto &&
                                    member.photoUrl != null &&
                                    member.photoUrl!.isNotEmpty
                                    ? NetworkImage(member.photoUrl!)
                                    : null,
                                child: canShowPhoto &&
                                    member.photoUrl != null &&
                                    member.photoUrl!.isNotEmpty
                                    ? null
                                    : const Icon(
                                  Icons.female_rounded,
                                  color: Color(0xFFB8860B),
                                ),
                              ),
                              title: Text(
                                _displayName(member, access, privacy),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: father != null
                                  ? Padding(
                                padding:
                                const EdgeInsets.only(top: 4),
                                child: Text(
                                  access.isGuest
                                      ? 'عضوة من العائلة'
                                      : 'الأب: ${father.name}',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              )
                                  : Padding(
                                padding:
                                const EdgeInsets.only(top: 4),
                                child: Text(
                                  access.isGuest
                                      ? 'عضوة من العائلة'
                                      : 'جدّة رئيسية / بلا أب',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
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
          ),
        );
      },
    );
  }
}