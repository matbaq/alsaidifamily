import 'package:flutter/material.dart';
import '../data/admin_users_repository.dart';
import '../models/admin_user.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final _repo = AdminUsersRepository();

  Future<void> _openForm({AdminUser? initial}) async {
    final result = await showDialog<_AdminUserFormResult>(
      context: context,
      builder: (context) => _AdminUserFormDialog(initial: initial),
    );

    if (result == null) return;

    if (initial == null) {
      await _repo.addAdmin(
        email: result.email,
        role: result.role,
        isActive: result.isActive,
        canManageTreeMembers: result.canManageTreeMembers,
        canManagePins: result.canManagePins,
        canViewAuditLog: result.canViewAuditLog,
        canManagePrivacy: result.canManagePrivacy,
      );
    } else {
      await _repo.updateAdmin(
        id: initial.id,
        email: result.email,
        role: result.role,
        isActive: result.isActive,
        canManageTreeMembers: result.canManageTreeMembers,
        canManagePins: result.canManagePins,
        canViewAuditLog: result.canViewAuditLog,
        canManagePrivacy: result.canManagePrivacy,
      );
    }
  }

  Future<void> _deleteAdmin(AdminUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف ${user.email} ؟'),
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
      await _repo.deleteAdmin(user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المشرفين والصلاحيات'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('إضافة مشرف'),
      ),
      body: StreamBuilder<List<AdminUser>>(
        stream: _repo.streamAdmins(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('خطأ في تحميل المشرفين'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final admins = snap.data!;
          if (admins.isEmpty) {
            return const Center(child: Text('لا يوجد مشرفون بعد'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
            itemCount: admins.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final user = admins[i];

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
                    backgroundColor: user.isActive
                        ? Colors.green.withOpacity(0.14)
                        : Colors.grey.withOpacity(0.18),
                    child: Icon(
                      user.isActive
                          ? Icons.verified_user_rounded
                          : Icons.block_rounded,
                      color: user.isActive ? Colors.green : Colors.grey,
                    ),
                  ),
                  title: Text(
                    user.email,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الدور: ${user.role}'),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (user.canManageTreeMembers)
                              _chip('إدارة الشجرة'),
                            if (user.canManagePins)
                              _chip('إدارة PIN'),
                            if (user.canViewAuditLog)
                              _chip('السجل'),
                            if (user.canManagePrivacy)
                              _chip('الخصوصية'),
                            _chip(user.isActive ? 'مفعل' : 'معطل'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        await _openForm(initial: user);
                      } else if (v == 'delete') {
                        await _deleteAdmin(user);
                      }
                    },
                    itemBuilder: (context) => const [
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
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.30)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _AdminUserFormResult {
  final String email;
  final String role;
  final bool isActive;
  final bool canManageTreeMembers;
  final bool canManagePins;
  final bool canViewAuditLog;
  final bool canManagePrivacy;

  _AdminUserFormResult({
    required this.email,
    required this.role,
    required this.isActive,
    required this.canManageTreeMembers,
    required this.canManagePins,
    required this.canViewAuditLog,
    required this.canManagePrivacy,
  });
}

class _AdminUserFormDialog extends StatefulWidget {
  final AdminUser? initial;

  const _AdminUserFormDialog({this.initial});

  @override
  State<_AdminUserFormDialog> createState() => _AdminUserFormDialogState();
}

class _AdminUserFormDialogState extends State<_AdminUserFormDialog> {
  late final TextEditingController _emailCtrl;

  late String _role;
  late bool _isActive;
  late bool _canManageTreeMembers;
  late bool _canManagePins;
  late bool _canViewAuditLog;
  late bool _canManagePrivacy;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initial?.email ?? '');
    _role = widget.initial?.role ?? 'editor';
    _isActive = widget.initial?.isActive ?? true;
    _canManageTreeMembers = widget.initial?.canManageTreeMembers ?? true;
    _canManagePins = widget.initial?.canManagePins ?? false;
    _canViewAuditLog = widget.initial?.canViewAuditLog ?? true;
    _canManagePrivacy = widget.initial?.canManagePrivacy ?? false;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'إضافة مشرف' : 'تعديل مشرف'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'البريد الإلكتروني',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(
                labelText: 'الدور',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'editor', child: Text('Editor')),
                DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _role = v);
              },
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('مفعل'),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _canManageTreeMembers,
              onChanged: (v) => setState(() => _canManageTreeMembers = v),
              title: const Text('إدارة أعضاء الشجرة'),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _canManagePins,
              onChanged: (v) => setState(() => _canManagePins = v),
              title: const Text('إدارة PIN'),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _canViewAuditLog,
              onChanged: (v) => setState(() => _canViewAuditLog = v),
              title: const Text('عرض سجل التعديلات'),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _canManagePrivacy,
              onChanged: (v) => setState(() => _canManagePrivacy = v),
              title: const Text('إدارة الخصوصية'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            final email = _emailCtrl.text.trim().toLowerCase();
            if (email.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('اكتب البريد الإلكتروني')),
              );
              return;
            }

            Navigator.pop(
              context,
              _AdminUserFormResult(
                email: email,
                role: _role,
                isActive: _isActive,
                canManageTreeMembers: _canManageTreeMembers,
                canManagePins: _canManagePins,
                canViewAuditLog: _canViewAuditLog,
                canManagePrivacy: _canManagePrivacy,
              ),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}