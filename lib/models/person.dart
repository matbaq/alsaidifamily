import 'package:cloud_firestore/cloud_firestore.dart';

/// Biological / legal gender as stored by the family tree domain model.
enum PersonGender { male, female, unknown }

extension PersonGenderX on PersonGender {
  String get value {
    switch (this) {
      case PersonGender.male:
        return 'male';
      case PersonGender.female:
        return 'female';
      case PersonGender.unknown:
        return 'unknown';
    }
  }

  static PersonGender fromValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    switch (normalized) {
      case 'male':
      case 'm':
      case 'man':
      case 'ذكر':
        return PersonGender.male;
      case 'female':
      case 'f':
      case 'woman':
      case 'أنثى':
      case 'انثى':
        return PersonGender.female;
      default:
        return PersonGender.unknown;
    }
  }
}

/// Optional life event information used by the V2 tree.
class PersonLifeInfo {
  const PersonLifeInfo({
    this.birthDate,
    this.birthPlace,
    this.deathDate,
    this.deathPlace,
  });

  final DateTime? birthDate;
  final String? birthPlace;
  final DateTime? deathDate;
  final String? deathPlace;

  bool get isEmpty =>
      birthDate == null &&
      (birthPlace == null || birthPlace!.trim().isEmpty) &&
      deathDate == null &&
      (deathPlace == null || deathPlace!.trim().isEmpty);

  PersonLifeInfo copyWith({
    DateTime? birthDate,
    String? birthPlace,
    DateTime? deathDate,
    String? deathPlace,
    bool clearBirthDate = false,
    bool clearBirthPlace = false,
    bool clearDeathDate = false,
    bool clearDeathPlace = false,
  }) {
    return PersonLifeInfo(
      birthDate: clearBirthDate ? null : (birthDate ?? this.birthDate),
      birthPlace: clearBirthPlace ? null : (birthPlace ?? this.birthPlace),
      deathDate: clearDeathDate ? null : (deathDate ?? this.deathDate),
      deathPlace: clearDeathPlace ? null : (deathPlace ?? this.deathPlace),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'birthDate': birthDate == null ? null : Timestamp.fromDate(birthDate!),
      'birthPlace': birthPlace,
      'deathDate': deathDate == null ? null : Timestamp.fromDate(deathDate!),
      'deathPlace': deathPlace,
    };
  }

  factory PersonLifeInfo.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const PersonLifeInfo();
    }

    return PersonLifeInfo(
      birthDate: _readDate(map['birthDate']),
      birthPlace: _readString(map['birthPlace']),
      deathDate: _readDate(map['deathDate']),
      deathPlace: _readString(map['deathPlace']),
    );
  }

  static DateTime? _readDate(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String? _readString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}

class Person {
  const Person({
    required this.id,
    required this.fullName,
    required this.gender,
    this.fatherId,
    this.motherId,
    this.photoUrl,
    this.lifeInfo = const PersonLifeInfo(),
  });

  final String id;
  final String fullName;
  final PersonGender gender;
  final String? fatherId;
  final String? motherId;
  final String? photoUrl;
  final PersonLifeInfo lifeInfo;

  bool get isMale => gender == PersonGender.male;
  bool get isFemale => gender == PersonGender.female;

  Person copyWith({
    String? id,
    String? fullName,
    PersonGender? gender,
    String? fatherId,
    String? motherId,
    String? photoUrl,
    PersonLifeInfo? lifeInfo,
    bool clearFatherId = false,
    bool clearMotherId = false,
    bool clearPhotoUrl = false,
  }) {
    return Person(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      gender: gender ?? this.gender,
      fatherId: clearFatherId ? null : (fatherId ?? this.fatherId),
      motherId: clearMotherId ? null : (motherId ?? this.motherId),
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      lifeInfo: lifeInfo ?? this.lifeInfo,
    );
  }

  factory Person.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Person.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
  }

  factory Person.fromMap(String id, Map<String, dynamic> map) {
    final fullName =
        (map['fullName'] ?? map['name'] ?? '').toString().trim();

    return Person(
      id: id,
      fullName: fullName,
      gender: _readGender(map),
      fatherId: _readNullableString(map['fatherId']),
      motherId: _readNullableString(map['motherId']),
      photoUrl: _readNullableString(map['photoUrl']),
      lifeInfo: PersonLifeInfo.fromMap(
        map['lifeInfo'] is Map<String, dynamic>
            ? map['lifeInfo'] as Map<String, dynamic>
            : <String, dynamic>{
                'birthDate': map['birthDate'],
                'birthPlace': map['birthPlace'],
                'deathDate': map['deathDate'],
                'deathPlace': map['deathPlace'],
              },
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'gender': gender.value,
      'fatherId': fatherId,
      'motherId': motherId,
      'photoUrl': photoUrl,
      'lifeInfo': lifeInfo.toMap(),
    };
  }

  static PersonGender _readGender(Map<String, dynamic> map) {
    if (map.containsKey('gender')) {
      return PersonGenderX.fromValue(map['gender']);
    }

    if (map.containsKey('isFemale')) {
      final isFemale = map['isFemale'] == true;
      return isFemale ? PersonGender.female : PersonGender.male;
    }

    return PersonGender.unknown;
  }

  static String? _readNullableString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
