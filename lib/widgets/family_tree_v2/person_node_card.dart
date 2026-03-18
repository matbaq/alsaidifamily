import 'package:flutter/material.dart';

import '../../models/person.dart';

class PersonNodeCard extends StatelessWidget {
  const PersonNodeCard({
    super.key,
    required this.person,
    this.isFocused = false,
    this.onTap,
  });

  final Person person;
  final bool isFocused;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _colorsForPerson(theme, person.gender, isFocused);
    final radius = BorderRadius.circular(20);
    final titleDirection = _looksArabic(person.fullName)
        ? TextDirection.rtl
        : Directionality.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors.background,
            ),
            border: Border.all(
              color: colors.border,
              width: isFocused ? 2.2 : 1.2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.shadow,
                blurRadius: isFocused ? 26 : 12,
                spreadRadius: isFocused ? 1.5 : 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _AvatarBadge(
                      photoUrl: person.photoUrl,
                      accent: colors.accent,
                      icon: _iconForGender(person.gender),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.pillBackground,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _genderLabel(person.gender),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.pillForeground,
                              fontWeight: FontWeight.w700,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(
                      person.fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textDirection: titleDirection,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.foreground,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _lifeSummary(person.lifeInfo),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryForeground,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _PersonCardColors _colorsForPerson(
    ThemeData theme,
    PersonGender gender,
    bool isFocused,
  ) {
    final brightness = theme.brightness;
    final base = switch (gender) {
      PersonGender.male => const Color(0xFF2459B8),
      PersonGender.female => const Color(0xFF8D3DAF),
      PersonGender.unknown => const Color(0xFF54606E),
    };

    final top = Color.alphaBlend(base.withValues(alpha: 0.22),
        brightness == Brightness.dark ? const Color(0xFF1A1F2B) : Colors.white);
    final bottom = Color.alphaBlend(base.withValues(alpha: 0.12),
        brightness == Brightness.dark ? const Color(0xFF11141C) : const Color(0xFFF7F9FF));
    final border = isFocused
        ? Color.alphaBlend(base.withValues(alpha: 0.8), Colors.white)
        : base.withValues(alpha: brightness == Brightness.dark ? 0.64 : 0.4);

    return _PersonCardColors(
      background: <Color>[top, bottom],
      border: border,
      foreground: brightness == Brightness.dark ? Colors.white : const Color(0xFF17212F),
      secondaryForeground: brightness == Brightness.dark
          ? const Color(0xFFD2D8E4)
          : const Color(0xFF556173),
      pillBackground: base.withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.12),
      pillForeground: base,
      accent: base,
      shadow: base.withValues(alpha: isFocused ? 0.28 : 0.14),
    );
  }

  String _genderLabel(PersonGender gender) {
    return switch (gender) {
      PersonGender.male => 'ذكر',
      PersonGender.female => 'أنثى',
      PersonGender.unknown => 'غير محدد',
    };
  }

  IconData _iconForGender(PersonGender gender) {
    return switch (gender) {
      PersonGender.male => Icons.male_rounded,
      PersonGender.female => Icons.female_rounded,
      PersonGender.unknown => Icons.person_rounded,
    };
  }

  String _lifeSummary(PersonLifeInfo info) {
    final birthYear = info.birthDate?.year;
    final deathYear = info.deathDate?.year;

    if (birthYear != null && deathYear != null) {
      return '$birthYear - $deathYear';
    }
    if (birthYear != null) {
      return 'مواليد $birthYear';
    }
    if (deathYear != null) {
      return 'وفاة $deathYear';
    }
    return 'لا توجد بيانات إضافية';
  }

  bool _looksArabic(String input) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(input);
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({
    required this.photoUrl,
    required this.accent,
    required this.icon,
  });

  final String? photoUrl;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.trim().isNotEmpty;

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.14),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(icon, color: accent, size: 24),
            )
          : Icon(icon, color: accent, size: 24),
    );
  }
}

class _PersonCardColors {
  const _PersonCardColors({
    required this.background,
    required this.border,
    required this.foreground,
    required this.secondaryForeground,
    required this.pillBackground,
    required this.pillForeground,
    required this.accent,
    required this.shadow,
  });

  final List<Color> background;
  final Color border;
  final Color foreground;
  final Color secondaryForeground;
  final Color pillBackground;
  final Color pillForeground;
  final Color accent;
  final Color shadow;
}
