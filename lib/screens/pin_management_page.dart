import 'package:flutter/material.dart';
import '../services/security_service.dart';

class PinManagementPage extends StatefulWidget {
  const PinManagementPage({super.key});

  @override
  State<PinManagementPage> createState() => _PinManagementPageState();
}

class _PinManagementPageState extends State<PinManagementPage> {
  final _familyPinCtrl = TextEditingController();
  final _adminPinCtrl = TextEditingController();

  bool _saving = false;
  bool _obscureFamily = true;
  bool _obscureAdmin = true;

  @override
  void dispose() {
    _familyPinCtrl.dispose();
    _adminPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePins() async {
    final familyPin = _familyPinCtrl.text.trim();
    final adminPin = _adminPinCtrl.text.trim();

    if (familyPin.isEmpty && adminPin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب على الأقل رمزًا واحدًا')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final security = SecurityService();

      if (familyPin.isNotEmpty && adminPin.isNotEmpty) {
        await security.setPins(
          familyPin: familyPin,
          adminPin: adminPin,
        );
      } else if (familyPin.isNotEmpty) {
        await security.setFamilyPin(familyPin);
      } else if (adminPin.isNotEmpty) {
        await security.setAdminPin(adminPin);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حفظ الرموز بنجاح')),
      );

      _familyPinCtrl.clear();
      _adminPinCtrl.clear();
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

  Widget _pinField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة رموز PIN'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _pinField(
              controller: _familyPinCtrl,
              label: 'PIN العائلة الجديد',
              obscure: _obscureFamily,
              onToggle: () => setState(() => _obscureFamily = !_obscureFamily),
              icon: Icons.family_restroom_rounded,
            ),
            const SizedBox(height: 16),
            _pinField(
              controller: _adminPinCtrl,
              label: 'PIN الأدمن الجديد',
              obscure: _obscureAdmin,
              onToggle: () => setState(() => _obscureAdmin = !_obscureAdmin),
              icon: Icons.admin_panel_settings_rounded,
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'اترك الحقل فارغًا إذا كنت لا تريد تغييره.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _savePins,
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