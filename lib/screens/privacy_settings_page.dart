import 'package:flutter/material.dart';
import '../services/privacy_service.dart';
import '../data/family_repository.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  final _service = PrivacyService();
  final _repo = FamilyRepository();

  bool _loading = true;
  bool _saving = false;

  bool _hideFemaleNamesForGuest = true;
  bool _hideFemalePhotosForGuest = true;
  bool _womenPageAdminOnly = false;
  bool _hideFemalesFromGeneralSearch = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _service.getSettings();
    if (!mounted) return;

    setState(() {
      _hideFemaleNamesForGuest = settings.hideFemaleNamesForGuest;
      _hideFemalePhotosForGuest = settings.hideFemalePhotosForGuest;
      _womenPageAdminOnly = settings.womenPageAdminOnly;
      _hideFemalesFromGeneralSearch = settings.hideFemalesFromGeneralSearch;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      final settings = PrivacySettings(
        hideFemaleNamesForGuest: _hideFemaleNamesForGuest,
        hideFemalePhotosForGuest: _hideFemalePhotosForGuest,
        womenPageAdminOnly: _womenPageAdminOnly,
        hideFemalesFromGeneralSearch: _hideFemalesFromGeneralSearch,
      );

      await _service.saveSettings(settings);

      await _repo.addCustomAuditLog(
        action: 'privacy_update',
        targetName: 'privacy_settings',
        details: 'تم تحديث إعدادات الخصوصية',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حفظ إعدادات الخصوصية')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الحفظ: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _tile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle),
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات الخصوصية'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _tile(
              title: 'إخفاء أسماء النساء عن الضيف',
              subtitle: 'يظهر بدل الاسم الحقيقي: عضو أنثى',
              value: _hideFemaleNamesForGuest,
              onChanged: (v) =>
                  setState(() => _hideFemaleNamesForGuest = v),
            ),
            const Divider(),

            _tile(
              title: 'إخفاء صور النساء عن الضيف',
              subtitle: 'لن تظهر صورة المرأة في وضع الضيف',
              value: _hideFemalePhotosForGuest,
              onChanged: (v) =>
                  setState(() => _hideFemalePhotosForGuest = v),
            ),
            const Divider(),

            _tile(
              title: 'صفحة نساء العائلة للأدمن فقط',
              subtitle: 'إذا فعلتها فلن تظهر الصفحة إلا للأدمن',
              value: _womenPageAdminOnly,
              onChanged: (v) =>
                  setState(() => _womenPageAdminOnly = v),
            ),
            const Divider(),

            _tile(
              title: 'إخفاء النساء من البحث العام',
              subtitle: 'لن تظهر النساء في نتائج البحث في الشجرة العامة',
              value: _hideFemalesFromGeneralSearch,
              onChanged: (v) =>
                  setState(() => _hideFemalesFromGeneralSearch = v),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text('حفظ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}