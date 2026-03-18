import 'package:flutter/material.dart';

class FamilyUnitConnector extends StatelessWidget {
  const FamilyUnitConnector({
    super.key,
    this.isHighlighted = false,
  });

  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final foreground = isHighlighted
        ? const Color(0xFFFFC857)
        : (brightness == Brightness.dark
            ? const Color(0xFF9AA7BC)
            : const Color(0xFF69778E));
    final background = brightness == Brightness.dark
        ? const Color(0xFF161C26)
        : Colors.white;

    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: foreground.withValues(alpha: isHighlighted ? 0.95 : 0.6),
            width: isHighlighted ? 1.8 : 1.2,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: foreground.withValues(alpha: isHighlighted ? 0.22 : 0.08),
              blurRadius: isHighlighted ? 18 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.remove_rounded, size: 16, color: foreground),
              const SizedBox(width: 2),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.remove_rounded, size: 16, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
