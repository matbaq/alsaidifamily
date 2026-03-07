import 'dart:math' as math;
import '../models/family_member.dart';

FamilyMember? _byId(String id, List<FamilyMember> all) {
  for (final m in all) {
    if (m.id == id) return m;
  }
  return null;
}

Map<String, int> _ancestorsWithSteps(String startId, List<FamilyMember> all) {
  final map = <String, int>{};
  int steps = 0;
  String? cur = startId;
  final visited = <String>{};

  while (cur != null && !visited.contains(cur)) {
    visited.add(cur);
    map[cur] = steps;
    cur = _byId(cur, all)?.fatherId;
    steps++;
  }
  return map;
}

String relationshipBetween({
  required String aId,
  required String bId,
  required List<FamilyMember> all,
}) {
  if (aId == bId) return 'نفس الشخص';

  final aAnc = _ancestorsWithSteps(aId, all);
  final bAnc = _ancestorsWithSteps(bId, all);

  String? lca;
  int best = 1 << 30;

  for (final e in aAnc.entries) {
    final sb = bAnc[e.key];
    if (sb == null) continue;
    final score = e.value + sb;
    if (score < best) {
      best = score;
      lca = e.key;
    }
  }

  if (lca == null) return 'لا توجد قرابة (فروع غير متصلة)';

  final upA = aAnc[lca]!;
  final upB = bAnc[lca]!;

  // A هو سلف لـ B
  if (upA == 0) {
    if (upB == 1) return 'أب';
    if (upB == 2) return 'جد';
    return 'جد أعلى (فرق أجيال: ${upB - 2})';
  }

  // A هو نسل لـ B
  if (upB == 0) {
    if (upA == 1) return 'ابن';
    if (upA == 2) return 'حفيد';
    return 'حفيد أعلى (فرق أجيال: ${upA - 2})';
  }

  // إخوة
  if (upA == 1 && upB == 1) return 'أخ/أخت';

  // عم / ابن أخ (تقريبًا)
  if (upA == 1 && upB >= 2) return upB == 2 ? 'عم/عمة' : 'عم/عمة أكبر (فرق أجيال: ${upB - 2})';
  if (upB == 1 && upA >= 2) return upA == 2 ? 'ابن أخ/أخت' : 'ابن أخ/أخت أكبر (فرق أجيال: ${upA - 2})';

  // أبناء عمومة عامة
  final degree = math.min(upA, upB) - 1;
  final removed = (upA - upB).abs();

  final base = 'أبناء عمومة (درجة $degree)';
  if (removed == 0) return base;
  return '$base — فرق أجيال: $removed';
}