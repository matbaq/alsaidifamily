import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyMember {
  final String id;
  final String name;
  final String? fatherId;
  final String? motherId;
  final String? photoUrl;
  final String? branchColor;
  final bool inheritToChildren;
  final bool isFemale;

  FamilyMember({
    required this.id,
    required this.name,
    this.fatherId,
    this.motherId,
    this.photoUrl,
    this.branchColor,
    this.inheritToChildren = false,
    this.isFemale = false,
  });

  factory FamilyMember.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});

    return FamilyMember(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      fatherId: data['fatherId'] as String?,
      motherId: data['motherId'] as String?,
      photoUrl: data['photoUrl'] as String?,
      branchColor: data['branchColor'] as String?,
      inheritToChildren: (data['inheritToChildren'] as bool?) ?? false,
      isFemale: (data['isFemale'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'fatherId': fatherId,
    'motherId': motherId,
    'photoUrl': photoUrl,
    'branchColor': branchColor,
    'inheritToChildren': inheritToChildren,
    'isFemale': isFemale,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class MemberDraft {
  final String name;
  final String? fatherId;
  final String? motherId;
  final bool isFemale;

  MemberDraft({
    required this.name,
    this.fatherId,
    this.motherId,
    this.isFemale = false,
  });
}