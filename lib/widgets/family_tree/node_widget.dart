import 'package:flutter/material.dart';
import '../../models/tree_node.dart';

// ألوان كل جيل — تدرج من الجد للأحفاد
class GenerationPalette {
  static const List<List<Color>> generations = [
    // الجد (جيل 0) — ذهبي ملكي
    [Color(0xFFB8860B), Color(0xFFFFD700)],
    // الجيل 1 — أزرق عميق
    [Color(0xFF1a3a6b), Color(0xFF4a90d9)],
    // الجيل 2 — أخضر زمردي
    [Color(0xFF1a5c3a), Color(0xFF2ecc71)],
    // الجيل 3 — بنفسجي
    [Color(0xFF4a1a7a), Color(0xFF9b59b6)],
    // الجيل 4 — برتقالي
    [Color(0xFF8B4513), Color(0xFFE67E22)],
    // الجيل 5 — وردي غامق
    [Color(0xFF8B1a4a), Color(0xFFE91E8C)],
    // الجيل 6+ — رمادي أنيق
    [Color(0xFF2c3e50), Color(0xFF7f8c8d)],
  ];

  static List<Color> forLevel(int level) {
    if (level >= generations.length) return generations.last;
    return generations[level];
  }

  static Color primaryForLevel(int level) => forLevel(level)[0];
  static Color accentForLevel(int level)  => forLevel(level)[1];
}

class NodeWidget extends StatefulWidget {
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
  State<NodeWidget> createState() => _NodeWidgetState();
}

class _NodeWidgetState extends State<NodeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnim = Tween(begin: 1.0, end: 1.07)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    if (widget.node.isRoot) _pulseCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final level      = widget.generationLevel;
    final primary    = GenerationPalette.primaryForLevel(level);
    final accent     = GenerationPalette.accentForLevel(level);
    final isRoot     = widget.node.isRoot;
    final isSelected = widget.isSelected;
    final isCollapsed= widget.node.isCollapsed;
    final hasChildren= widget.node.childrenCount > 0;

    Widget card = GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp:   (_) => setState(() => _pressed = false),
      onTapCancel:()  => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.91 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: SizedBox(
          width: 120,
          height: 140,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ─── الكرت الرئيسي ───
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
                    // شريط جيل ملون
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

                    // نمط زخرفي خلفي للجد
                    if (isRoot)
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.04,
                          child: CustomPaint(painter: _DiamondPatternPainter(accent)),
                        ),
                      ),

                    // المحتوى
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 6),
                        _buildAvatar(primary, accent, isDark, isRoot),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            widget.node.name,
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

              // ─── شارة الجد الذهبية ───
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

              // ─── عداد الجيل ───
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

              // ─── زر الطي/البسط ───
              if (hasChildren)
                Positioned(
                  bottom: -14, left: 0, right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: widget.onToggleChildren,
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

              // ─── حلقة تحديد ───
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
      ),
    );

    if (isRoot) {
      card = AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) => Transform.scale(scale: _pulseAnim.value, child: child),
        child: card,
      );
    }

    return card;
  }

  Widget _buildAvatar(Color primary, Color accent, bool isDark, bool isRoot) {
    final hasPhoto = widget.node.photoUrl?.isNotEmpty == true;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto ? null : LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [primary.withValues(alpha: 0.25), accent.withValues(alpha: 0.10)],
        ),
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
        backgroundColor: Colors.transparent,
        backgroundImage: hasPhoto ? NetworkImage(widget.node.photoUrl!) : null,
        child: hasPhoto ? null : Icon(
          isRoot ? Icons.person_rounded : Icons.person_outline_rounded,
          size: isRoot ? 28 : 24,
          color: isRoot ? accent : primary.withValues(alpha: 0.8),
        ),
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
            '${widget.node.childrenCount}',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c),
          ),
        ],
      ),
    );
  }
}

// زخرفة خلفية للجد
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