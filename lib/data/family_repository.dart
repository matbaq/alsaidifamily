import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/family_member.dart';
import '../models/audit_log_item.dart';

class FamilyRepository {
  final FirebaseFirestore _db;
  final String collection;

  FamilyRepository({
    FirebaseFirestore? db,
    this.collection = 'members_public',
  }) : _db = db ?? FirebaseFirestore.instance;

  Stream<List<FamilyMember>> membersStream() {
    return _db.collection(collection).snapshots().map(
          (snap) => snap.docs.map((d) => FamilyMember.fromDoc(d)).toList(),
    );
  }

  Stream<List<AuditLogItem>> auditLogsStream() {
    return _db
        .collection('audit_logs')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AuditLogItem.fromDoc(d)).toList());
  }

  Future<void> _addAuditLog({
    required String action,
    required String targetName,
    String? details,
    String actor = 'admin',
  }) async {
    await _db.collection('audit_logs').add({
      'action': action,
      'targetName': targetName,
      'details': details,
      'actor': actor,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addMember({
    required String name,
    String? fatherId,
    bool isFemale = false,
  }) async {
    await _db.collection(collection).add({
      'name': name,
      'fatherId': fatherId,
      'photoUrl': null,
      'branchColor': null,
      'inheritToChildren': false,
      'isFemale': isFemale,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _addAuditLog(
      action: 'add_member',
      targetName: name,
      details: isFemale ? 'تمت إضافة عضوة' : 'تمت إضافة عضو',
    );
  }

  Future<void> addMemberRaw({
    required String name,
    String? fatherId,
    bool isFemale = false,
  }) async {
    await _db.collection(collection).add({
      'name': name,
      'fatherId': fatherId,
      'photoUrl': null,
      'branchColor': null,
      'inheritToChildren': false,
      'isFemale': isFemale,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _addAuditLog(
      action: 'add_member',
      targetName: name,
      details: isFemale ? 'تمت إضافة عضوة' : 'تمت إضافة عضو',
    );
  }

  // ⭐ تمت إضافة الدالة الجديدة هنا
  Future<String> addMemberAndReturnId({
    required String name,
    String? fatherId,
    bool isFemale = false,
  }) async {
    final doc = await _db.collection(collection).add({
      'name': name,
      'fatherId': fatherId,
      'photoUrl': null,
      'branchColor': null,
      'inheritToChildren': false,
      'isFemale': isFemale,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _addAuditLog(
      action: 'add_member',
      targetName: name,
      details: isFemale ? 'تمت إضافة عضوة' : 'تمت إضافة عضو',
    );

    return doc.id;
  }

  Future<void> updateMember({
    required String id,
    required String name,
    String? fatherId,
    bool isFemale = false,
  }) async {
    await _db.collection(collection).doc(id).update({
      'name': name,
      'fatherId': fatherId,
      'isFemale': isFemale,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _addAuditLog(
      action: 'update_member',
      targetName: name,
      details: 'تم تحديث بيانات العضو',
    );
  }

  Future<void> updateName({
    required String id,
    required String name,
    String? fatherId,
    bool isFemale = false,
  }) async {
    await _db.collection(collection).doc(id).update({
      'name': name,
      'fatherId': fatherId,
      'isFemale': isFemale,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _addAuditLog(
      action: 'update_member',
      targetName: name,
      details: 'تم تعديل الاسم / الأب / الجنس',
    );
  }

  Future<void> updateFatherId({
    required String id,
    required String? fatherId,
  }) async {
    final doc = await _db.collection(collection).doc(id).get();
    final name = ((doc.data() ?? {})['name'] ?? 'عضو').toString();

    await _db.collection(collection).doc(id).update({
      'fatherId': fatherId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _addAuditLog(
      action: 'update_father',
      targetName: name,
      details: fatherId == null ? 'تم جعله جداً رئيسيًا' : 'تم تغيير الأب',
    );
  }

  Future<void> deleteMember(String id) async {
    final doc = await _db.collection(collection).doc(id).get();
    final name = ((doc.data() ?? {})['name'] ?? 'عضو').toString();

    await _db.collection(collection).doc(id).delete();

    await _addAuditLog(
      action: 'delete_member',
      targetName: name,
      details: 'تم حذف العضو',
    );
  }

  Future<void> updatePhoto(String id, String url) async {
    final doc = await _db.collection(collection).doc(id).get();
    final name = ((doc.data() ?? {})['name'] ?? 'عضو').toString();

    await _db.collection(collection).doc(id).update({
      'photoUrl': url,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _addAuditLog(
      action: 'update_photo',
      targetName: name,
      details: 'تم تحديث الصورة',
    );
  }

  Future<void> updateBranchColor(String id, String? colorString) async {
    final doc = await _db.collection(collection).doc(id).get();
    final name = ((doc.data() ?? {})['name'] ?? 'عضو').toString();

    await _db.collection(collection).doc(id).update({
      'branchColor': colorString,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _addAuditLog(
      action: 'update_branch_color',
      targetName: name,
      details: 'تم تغيير لون الفرع',
    );
  }

  // ⭐ الدالة الجديدة لتوريث اللون للأبناء
  Future<void> updateInheritToChildren({
    required String id,
    required bool inherit,
  }) async {
    final doc = await _db.collection(collection).doc(id).get();
    final name = ((doc.data() ?? {})['name'] ?? 'عضو').toString();

    await _db.collection(collection).doc(id).update({
      'inheritToChildren': inherit,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _addAuditLog(
      action: 'update_inherit_color',
      targetName: name,
      details: inherit
          ? 'تم تفعيل توريث اللون للأبناء'
          : 'تم إلغاء توريث اللون للأبناء',
    );
  }

  Future<void> makeRoot(String id) async {
    final doc = await _db.collection(collection).doc(id).get();
    final name = ((doc.data() ?? {})['name'] ?? 'عضو').toString();

    await _db.collection(collection).doc(id).update({
      'fatherId': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _addAuditLog(
      action: 'make_root',
      targetName: name,
      details: 'تم جعله جداً رئيسيًا',
    );
  }

  Future<void> addCustomAuditLog({
    required String action,
    required String targetName,
    String? details,
    String actor = 'admin',
  }) async {
    await _addAuditLog(
      action: action,
      targetName: targetName,
      details: details,
      actor: actor,
    );
  }
}