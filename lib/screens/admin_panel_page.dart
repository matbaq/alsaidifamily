import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/access_controller.dart';
import 'pin_management_page.dart';
import 'family_women_page.dart';
import 'audit_log_page.dart';
import 'admin_users_page.dart';
import 'privacy_settings_page.dart'; // ⭐ تم الإضافة هنا

class AdminPanelPage extends StatelessWidget {
  const AdminPanelPage({super.key});

  Widget _card(
      BuildContext context, {
        required IconData icon,
        required String title,
        required VoidCallback onTap,
        Color color = const Color(0xFF1e3c72),
      }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleBanner(BuildContext context, AccessController access) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1e3c72).withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF1e3c72).withOpacity(0.22),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded, color: Color(0xFF1e3c72)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'الدور الحالي: ${access.adminRole.isEmpty ? 'admin' : access.adminRole}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();

    if (access.isLoadingAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('لوحة تحكم الأدمن'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!access.isAdmin || !access.adminIsActive) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('لوحة تحكم الأدمن'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'ليس لديك صلاحية للوصول إلى لوحة التحكم.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    final cards = <Widget>[];

    if (access.adminRole == 'super_admin') {
      cards.add(
        _card(
          context,
          icon: Icons.admin_panel_settings_rounded,
          title: 'إدارة المشرفين',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminUsersPage(),
              ),
            );
          },
        ),
      );
    }

    if (access.canManagePins) {
      cards.add(
        _card(
          context,
          icon: Icons.password_rounded,
          title: 'إدارة رموز PIN',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PinManagementPage(),
              ),
            );
          },
        ),
      );
    }

    if (access.canViewAuditLog) {
      cards.add(
        _card(
          context,
          icon: Icons.history_rounded,
          title: 'سجل التعديلات',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AuditLogPage(),
              ),
            );
          },
        ),
      );
    }

    if (access.canManagePrivacy) {
      cards.add(
        // ⭐ تم التعديل هنا لفتح صفحة إعدادات الخصوصية
        _card(
          context,
          icon: Icons.security_rounded,
          title: 'إعدادات الخصوصية',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PrivacySettingsPage(),
              ),
            );
          },
        ),
      );
    }

    cards.add(
      _card(
        context,
        icon: Icons.female_rounded,
        title: 'نساء العائلة',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FamilyWomenPage(),
            ),
          );
        },
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم الأدمن'),
      ),
      body: Column(
        children: [
          _roleBanner(context, access),
          Expanded(
            child: cards.isEmpty
                ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا توجد أدوات متاحة لك حاليًا داخل لوحة التحكم.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            )
                : Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                children: cards,
              ),
            ),
          ),
        ],
      ),
    );
  }
}