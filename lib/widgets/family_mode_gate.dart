import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/access_controller.dart';

class FamilyModeGate extends StatelessWidget {
  final String title;
  final Widget child;

  const FamilyModeGate({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();

    if (access.isGuest) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, size: 60),
                const SizedBox(height: 16),
                Text(
                  'هذه الصفحة خاصة بالعائلة',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'افتح وضع العائلة أولًا حتى تتمكن من رؤية المحتوى الخاص.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('رجوع'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return child;
  }
}