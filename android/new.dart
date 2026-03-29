enum Gender { male, female, other }

class Person {
  final String id;
  final String fullName;
  final Gender gender;
  final String? fatherId;
  final String? motherId;
  final String? photoUrl;
  final DateTime? birthDate;
  final DateTime? deathDate;
  final Map<String, dynamic> metadata;

  Person({
    required this.id,
    required this.fullName,
    required this.gender,
    this.fatherId,
    this.motherId,
    this.photoUrl,
    this.birthDate,
    this.deathDate,
    this.metadata = const {},
  });

  // Helper to check if person is a root (no parents recorded)
  bool get isRoot => fatherId == null && motherId == null;
}