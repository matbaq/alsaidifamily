import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/family_member.dart';

class FamilyRepository {
  final FirebaseFirestore _db;

  FamilyRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Stream<List<FamilyMember>> membersStream() {
    return _db.collection('members_public').snapshots().map(
          (snap) => snap.docs.map((d) => FamilyMember.fromDoc(d)).toList(),
    );
  }

  Future<void> addMember({
    required String name,
    String? fatherId,
  }) async {
    await _db.collection('members_public').add({
      'name': name,
      'fatherId': fatherId,
      'photoUrl': null,
      'branchColor': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addMemberRaw({
    required String name,
    String? fatherId,
  }) async {
    await _db.collection('members_public').add({
      'name': name,
      'fatherId': fatherId,
      'photoUrl': null,
      'branchColor': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMember({
    required String id,
    required String name,
    String? fatherId,
  }) async {
    await _db.collection('members_public').doc(id).update({
      'name': name,
      'fatherId': fatherId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateName({
    required String id,
    required String name,
    String? fatherId,
  }) async {
    await _db.collection('members_public').doc(id).update({
      'name': name,
      'fatherId': fatherId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateFatherId({
    required String id,
    required String? fatherId,
  }) async {
    await _db.collection('members_public').doc(id).update({
      'fatherId': fatherId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMember(String id) async {
    await _db.collection('members_public').doc(id).delete();
  }

  Future<void> updatePhoto(String id, String url) async {
    await _db.collection('members_public').doc(id).update({
      'photoUrl': url,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateBranchColor(String id, String? colorString) async {
    await _db.collection('members_public').doc(id).update({
      'branchColor': colorString,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> makeRoot(String id) async {
    await _db.collection('members_public').doc(id).update({
      'fatherId': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}