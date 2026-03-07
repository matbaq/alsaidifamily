import 'package:flutter/material.dart';
import '../widgets/family_mode_gate.dart';
import 'family_tree_page.dart';

class PrivateFamilyTreePage extends StatelessWidget {
  final bool isDarkMode;
  final Function(bool) onThemeToggle;

  const PrivateFamilyTreePage({
    super.key,
    required this.isDarkMode,
    required this.onThemeToggle,
  });

  @override
  Widget build(BuildContext context) {
    return FamilyModeGate(
      title: 'الشجرة الخاصة',
      child: FamilyTreePage(
        collection: 'members_private',
        isDarkMode: isDarkMode,
        onThemeToggle: onThemeToggle,
      ),
    );
  }
}