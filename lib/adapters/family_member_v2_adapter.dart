import '../models/family_member.dart';
import '../models/family_tree_migration_report.dart';
import '../models/family_unit.dart';
import '../models/person.dart';

/// Supplemental relationship information that can be layered on top of the
/// legacy `FamilyMember` model during a gradual migration.
class LegacyFamilyMemberOverrides {
  const LegacyFamilyMemberOverrides({
    this.motherIdsByPersonId = const <String, String?>{},
    this.spouseIdsByPersonId = const <String, Set<String>>{},
    this.explicitFamilyUnits = const <FamilyUnit>[],
  });

  final Map<String, String?> motherIdsByPersonId;
  final Map<String, Set<String>> spouseIdsByPersonId;
  final List<FamilyUnit> explicitFamilyUnits;
}

/// Converts the legacy `FamilyMember` shape into V2 `Person` and `FamilyUnit`
/// collections while surfacing migration gaps instead of hiding them.
class FamilyMemberV2Adapter {
  const FamilyMemberV2Adapter();

  FamilyTreeMigrationData adapt({
    required List<FamilyMember> legacyMembers,
    LegacyFamilyMemberOverrides overrides = const LegacyFamilyMemberOverrides(),
  }) {
    final persons = legacyMembers
        .map(
          (member) => Person(
            id: member.id,
            fullName: member.name.trim(),
            gender: member.isFemale ? PersonGender.female : PersonGender.male,
            fatherId: _normalizeId(member.fatherId),
            motherId: _normalizeId(overrides.motherIdsByPersonId[member.id]),
            photoUrl: _normalizeText(member.photoUrl),
          ),
        )
        .toList(growable: false);

    final inferredUnits = _inferFamilyUnits(persons, overrides);
    final familyUnits = <FamilyUnit>[
      ...overrides.explicitFamilyUnits,
      ...inferredUnits.where(
        (candidate) => !overrides.explicitFamilyUnits.any((unit) => unit.id == candidate.id),
      ),
    ]..sort((a, b) => a.id.compareTo(b.id));

    final membersMissingMotherId = persons.where((person) => person.motherId == null).length;
    final membersMissingSpouseData = legacyMembers
        .where((member) => !(overrides.spouseIdsByPersonId[member.id]?.isNotEmpty ?? false))
        .length;

    final report = FamilyTreeMigrationReport(
      totalLegacyMembers: legacyMembers.length,
      totalPersonsProduced: persons.length,
      totalFamilyUnitsProduced: familyUnits.length,
      membersMissingMotherId: membersMissingMotherId,
      membersMissingSpouseData: membersMissingSpouseData,
      inferredFamilyUnits: inferredUnits.length,
      explicitFamilyUnits: overrides.explicitFamilyUnits.length,
      notes: <String>[
        'البيانات الحالية القديمة تدعم fatherId فقط بشكل مباشر.',
        'motherId غير موجود في نموذج FamilyMember القديم ويجب إضافته لتمثيل شجرة صحيحة.',
        'علاقات الأزواج ووحدات العائلة ليست جزءاً من النموذج القديم، لذلك يتم استنتاج بعض الوحدات أو إبقاؤها ناقصة.',
        'يمكن تشغيل V2 الآن على البيانات القديمة، لكن الدقة الكاملة تتطلب ترقية البيانات وإدخال motherId وعلاقات الأزواج ووحدات العائلة.',
      ],
    );

    return FamilyTreeMigrationData(
      persons: persons,
      familyUnits: familyUnits,
      report: report,
    );
  }

  List<FamilyUnit> _inferFamilyUnits(
    List<Person> persons,
    LegacyFamilyMemberOverrides overrides,
  ) {
    final groupedFamilies = <String, _FamilyDraft>{};

    for (final person in persons) {
      final familyKey = _familyKey(person.fatherId, person.motherId);
      if (familyKey == null) {
        continue;
      }

      groupedFamilies.putIfAbsent(
        familyKey,
        () => _FamilyDraft(
          husbandId: person.fatherId,
          wifeId: person.motherId,
        ),
      ).childrenIds.add(person.id);
    }

    for (final entry in overrides.spouseIdsByPersonId.entries) {
      final personId = _normalizeId(entry.key);
      if (personId == null) {
        continue;
      }

      for (final spouseId in entry.value) {
        final normalizedSpouseId = _normalizeId(spouseId);
        if (normalizedSpouseId == null) {
          continue;
        }

        final husbandId = personId.compareTo(normalizedSpouseId) <= 0
            ? personId
            : normalizedSpouseId;
        final wifeId = husbandId == personId ? normalizedSpouseId : personId;
        final familyKey = _familyKey(husbandId, wifeId)!;
        groupedFamilies.putIfAbsent(
          familyKey,
          () => _FamilyDraft(husbandId: husbandId, wifeId: wifeId),
        );
      }
    }

    return groupedFamilies.entries
        .map(
          (entry) => FamilyUnit(
            id: 'legacy_${entry.key}',
            husbandId: entry.value.husbandId,
            wifeId: entry.value.wifeId,
            childrenIds: entry.value.childrenIds.toList()..sort(),
          ),
        )
        .where((unit) =>
            unit.husbandId != null || unit.wifeId != null || unit.childrenIds.isNotEmpty)
        .toList(growable: false);
  }

  String? _familyKey(String? fatherId, String? motherId) {
    if (fatherId == null && motherId == null) {
      return null;
    }

    return '${fatherId ?? 'none'}__${motherId ?? 'none'}';
  }

  String? _normalizeId(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  String? _normalizeText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }
}

/// Result of adapting a legacy dataset into V2 domain objects.
class FamilyTreeMigrationData {
  const FamilyTreeMigrationData({
    required this.persons,
    required this.familyUnits,
    required this.report,
  });

  final List<Person> persons;
  final List<FamilyUnit> familyUnits;
  final FamilyTreeMigrationReport report;
}

class _FamilyDraft {
  _FamilyDraft({
    required this.husbandId,
    required this.wifeId,
  });

  final String? husbandId;
  final String? wifeId;
  final Set<String> childrenIds = <String>{};
}
