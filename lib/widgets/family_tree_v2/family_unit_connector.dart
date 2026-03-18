import 'package:flutter/material.dart';

/// Visual and interactive representation of a collapsible family-unit node.
class FamilyUnitConnector extends StatelessWidget {
  const FamilyUnitConnector({
    super.key,
    this.isHighlighted = false,
    this.isCollapsed = false,
    this.childCount = 0,
    this.onTap,
  });

  final bool isHighlighted;
  final bool isCollapsed;
  final int childCount;
  final VoidCallback? onTap;

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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
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
              Icon(
                isCollapsed ? Icons.add_rounded : Icons.remove_rounded,
                size: 16,
                color: foreground,
              ),
              const SizedBox(width: 4),
              Text(
                childCount.toString(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}
