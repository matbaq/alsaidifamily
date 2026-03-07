import 'package:flutter/material.dart';
import '../../models/tree_node.dart';

enum PalettePreset {
  classic,
  ocean,
  emerald,
  mono,
}

class GenerationPalette {
  static PalettePreset currentPreset = PalettePreset.classic;

  static List<List<Color>> generations = _classic;

  static const List<List<Color>> _classic = [
    [Color(0xFFB8860B), Color(0xFFFFD700)],
    [Color(0xFF1a3a6b), Color(0xFF4a90d9)],
    [Color(0xFF1a5c3a), Color(0xFF2ecc71)],
    [Color(0xFF4a1a7a), Color(0xFF9b59b6)],
    [Color(0xFF8B4513), Color(0xFFE67E22)],
    [Color(0xFF8B1a4a), Color(0xFFE91E8C)],
    [Color(0xFF2c3e50), Color(0xFF7f8c8d)],
  ];

  static const List<List<Color>> _ocean = [
    [Color(0xFF0B3D91), Color(0xFF4FC3F7)],
    [Color(0xFF0D47A1), Color(0xFF64B5F6)],
    [Color(0xFF1A237E), Color(0xFF7986CB)],
    [Color(0xFF004D40), Color(0xFF4DB6AC)],
    [Color(0xFF263238), Color(0xFF90A4AE)],
    [Color(0xFF37474F), Color(0xFFB0BEC5)],
    [Color(0xFF2c3e50), Color(0xFF7f8c8d)],
  ];

  static const List<List<Color>> _emerald = [
    [Color(0xFF1B5E20), Color(0xFF66BB6A)],
    [Color(0xFF2E7D32), Color(0xFFA5D6A7)],
    [Color(0xFF00695C), Color(0xFF80CBC4)],
    [Color(0xFF33691E), Color(0xFFC5E1A5)],
    [Color(0xFF004D40), Color(0xFF4DB6AC)],
    [Color(0xFF263238), Color(0xFF90A4AE)],
    [Color(0xFF2c3e50), Color(0xFF7f8c8d)],
  ];

  static const List<List<Color>> _mono = [
    [Color(0xFF263238), Color(0xFFB0BEC5)],
    [Color(0xFF263238), Color(0xFFB0BEC5)],
    [Color(0xFF263238), Color(0xFFB0BEC5)],
    [Color(0xFF263238), Color(0xFFB0BEC5)],
    [Color(0xFF263238), Color(0xFFB0BEC5)],
    [Color(0xFF263238), Color(0xFFB0BEC5)],
    [Color(0xFF263238), Color(0xFFB0BEC5)],
  ];

  static void setPreset(PalettePreset preset) {
    currentPreset = preset;
    switch (preset) {
      case PalettePreset.classic:
        generations = _classic;
        break;
      case PalettePreset.ocean:
        generations = _ocean;
        break;
      case PalettePreset.emerald:
        generations = _emerald;
        break;
      case PalettePreset.mono:
        generations = _mono;
        break;
    }
  }

  static List<Color> forLevel(int level) {
    if (level >= generations.length) return generations.last;
    return generations[level];
  }

  static Color primaryForLevel(int level) => forLevel(level)[0];
  static Color accentForLevel(int level)  => forLevel(level)[1];
}

// ⭐ تم التحويل إلى StatelessWidget لتحسين الأداء بشكل هائل
class NodeWidget extends StatelessWidget {
  final TreeNode node;
  final bool isSelected;
  final int generationLevel;
  final VoidCallback? onTap;
  final VoidCallback? onToggleChildren;

  const NodeWidget({
    super.key,
    required this.node,
    required this.isSelected,
    required this.generationLevel,
    this.onTap,
    this.onToggleChildren,
  });

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final level       = generationLevel;

    final Color primary = node.branchColor;
    final Color accent = Color.lerp(node.branchColor, Colors.white, 0.28) ?? node.branchColor;

    final isRoot      = node.isRoot;
    final isCollapsed = node.isCollapsed;
    final hasChildren = node.childrenCount > 0;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 120,
        height: 140,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 120,
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                    Color.lerp(const Color(0xFF16181E), primary, 0.22)!,
                    Color.lerp(const Color(0xFF0E1014), primary, 0.12)!,
                  ]
                      : [
                    Color.lerp(Colors.white, accent, 0.08)!,
                    Color.lerp(const Color(0xFFF0F4FF), primary, 0.10)!,
                  ],
                ),
                border: Border.all(
                  color: isSelected
                      ? accent
                      : primary.withValues(alpha: isDark ? 0.5 : 0.3),
                  width: isSelected ? 2.5 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: isSelected ? 0.45 : 0.18),
                    blurRadius: isSelected ? 22 : 10,
                    spreadRadius: isSelected ? 2 : 0,
                    offset: const Offset(0, 4),
                  ),
                  if (isRoot)
                    BoxShadow(
                      color: accent.withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(children: [
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      height: isRoot ? 6 : 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primary.withValues(alpha: 0.95), accent.withValues(alpha: 0.6)],
                        ),
                      ),
                    ),
                  ),

                  if (isRoot)
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.04,
                        child: CustomPaint(painter: _DiamondPatternPainter(accent)),
                      ),
                    ),

                  // زر الطي في الزاوية العلوية اليمنى
                  if (onToggleChildren != null && hasChildren)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: GestureDetector(
                        onTap: onToggleChildren,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E2230) : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey),
                          ),
                          child: Center(
                            child: Text(
                              isCollapsed ? '+${node.childrenCount}' : '-',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: isCollapsed && node.childrenCount > 9 ? 11 : 14,
                                color: isDark ? Colors.white : Colors.black,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 6),
                      _buildAvatar(primary, accent, isDark, isRoot),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          node.name,
                          style: TextStyle(
                            fontSize: isRoot ? 12.5 : 11.5,
                            fontWeight: isRoot ? FontWeight.w800 : FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                            height: 1.25,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasChildren)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _buildBadge(primary, accent, isCollapsed),
                        ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ]),
              ),
            ),

            if (isRoot)
              Positioned(
                top: -11, right: -9,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF16181E) : Colors.white,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withValues(alpha: 0.6),
                        blurRadius: 10, spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.star_rounded, size: 15, color: Colors.white),
                ),
              ),

            Positioned(
              top: -9, left: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF16181E) : Colors.white,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  'ج${level + 1}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // الأيقونة السفلية الافتراضية
            if (hasChildren)
              Positioned(
                bottom: -14, left: 0, right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: onToggleChildren,
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isCollapsed
                              ? [Colors.orange.shade600, Colors.orange.shade300]
                              : [primary, accent],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF0E1014) : Colors.white,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isCollapsed ? Colors.orange : primary)
                                .withValues(alpha: 0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(
                        isCollapsed ? Icons.add_rounded : Icons.remove_rounded,
                        size: 16, color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

            if (isSelected)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: accent.withValues(alpha: 0.8), width: 3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(Color primary, Color accent, bool isDark, bool isRoot) {
    final url = node.photoUrl;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isRoot ? accent : primary.withValues(alpha: 0.6),
          width: isRoot ? 2.5 : 1.8,
        ),
        boxShadow: [
          BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: 1),
        ],
      ),
      child: CircleAvatar(
        radius: isRoot ? 27 : 23,
        backgroundColor: isDark ? const Color(0xFF16181E) : Colors.white,
        backgroundImage: (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
        child: (url == null || url.isEmpty) ? const Icon(Icons.person) : null,
      ),
    );
  }

  Widget _buildBadge(Color primary, Color accent, bool isCollapsed) {
    final c = isCollapsed ? Colors.orange.shade500 : primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCollapsed ? Icons.people_outline : Icons.people_rounded,
            size: 10, color: c,
          ),
          const SizedBox(width: 3),
          Text(
            '${node.childrenCount}',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c),
          ),
        ],
      ),
    );
  }
}

class _DiamondPatternPainter extends CustomPainter {
  final Color color;
  _DiamondPatternPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;
    const step = 20.0;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        final path = Path()
          ..moveTo(x + step / 2, y)
          ..lineTo(x + step, y + step / 2)
          ..lineTo(x + step / 2, y + step)
          ..lineTo(x, y + step / 2)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}