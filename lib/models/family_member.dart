import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyMember {
  final String id;
  final String name;
  final String? fatherId;
  final String? photoUrl;
  final String? branchColor;
  final bool inheritToChildren;

  // ⭐ جديد
  final bool isFemale;

  FamilyMember({
    required this.id,
    required this.name,
    this.fatherId,
    this.photoUrl,
    this.branchColor,
    this.inheritToChildren = false,
    this.isFemale = false, // ⭐ افتراضي ذكر
  });

  factory FamilyMember.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});

    return FamilyMember(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      fatherId: data['fatherId'] as String?,
      photoUrl: data['photoUrl'] as String?,
      branchColor: data['branchColor'] as String?,
      inheritToChildren: (data['inheritToChildren'] as bool?) ?? false,

      // ⭐ قراءة الجنس
      isFemale: (data['isFemale'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'fatherId': fatherId,
    'photoUrl': photoUrl,
    'branchColor': branchColor,
    'inheritToChildren': inheritToChildren,

    // ⭐ تخزين الجنس
    'isFemale': isFemale,

    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class MemberDraft {
  final String name;
  final String? fatherId;

  // ⭐ جديد
  final bool isFemale;

  MemberDraft({
    required this.name,
    this.fatherId,
    this.isFemale = false,
  });
}