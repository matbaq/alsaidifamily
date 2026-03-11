import 'package:flutter/material.dart';
import '../data/family_repository.dart';
import '../models/audit_log_item.dart';

class AuditLogPage extends StatelessWidget {
  const AuditLogPage({super.key});

  String _actionLabel(String action) {
    switch (action) {
      case 'add_member':
        return 'إضافة عضو';
      case 'update_member':
        return 'تعديل عضو';
      case 'delete_member':
        return 'حذف عضو';
      case 'update_father':
        return 'تعديل الأب';
      case 'make_root':
        return 'جعله جدًا رئيسيًا';
      case 'update_photo':
        return 'تحديث الصورة';
      case 'update_branch_color':
        return 'تغيير لون الفرع';
      case 'pin_update':
        return 'تغيير PIN';
      default:
        return action;
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'add_member':
        return Icons.person_add_alt_1_rounded;
      case 'update_member':
        return Icons.edit_rounded;
      case 'delete_member':
        return Icons.delete_rounded;
      case 'update_father':
      case 'make_root':
        return Icons.account_tree_rounded;
      case 'update_photo':
        return Icons.image_rounded;
      case 'update_branch_color':
        return Icons.palette_rounded;
      case 'pin_update':
        return Icons.password_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'الآن';
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day  $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final repo = FamilyRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل التعديلات'),
      ),
      body: StreamBuilder<List<AuditLogItem>>(
        stream: repo.auditLogsStream(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('خطأ في تحميل السجل'));
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snap.data!;
          if (logs.isEmpty) {
            return const Center(
              child: Text(
                'لا توجد تعديلات بعد',
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final item = logs[i];

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
                    vertical: 10,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: Colors.amber.withOpacity(0.14),
                    child: Icon(
                      _actionIcon(item.action),
                      color: Colors.amber.shade800,
                    ),
                  ),
                  title: Text(
                    _actionLabel(item.action),
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
                        Text('العضو: ${item.targetName}'),
                        if (item.details != null && item.details!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(item.details!),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _formatDate(item.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}