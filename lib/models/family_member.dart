import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyMember {
  final String id;
  final String name;
  final String? fatherId;
  final String? photoUrl;
  final String? branchColor;

  FamilyMember({
    required this.id,
    required this.name,
    this.fatherId,
    this.photoUrl,
    this.branchColor,
  });

  factory FamilyMember.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});
    return FamilyMember(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      fatherId: data['fatherId'] as String?,
      photoUrl: data['photoUrl'] as String?,
      branchColor: data['branchColor'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'fatherId': fatherId,
    'photoUrl': photoUrl,
    'branchColor': branchColor,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class MemberDraft {
  final String name;
  final String? fatherId;

  MemberDraft({
    required this.name,
    this.fatherId,
  });
}