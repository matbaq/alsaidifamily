import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_user.dart';

class AdminUsersRepository {
  final FirebaseFirestore _db;

  AdminUsersRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _ref =>
      _db.collection('admin_users');

  Stream<List<AdminUser>> streamAdmins() {
    return _ref.orderBy('email').snapshots().map(
          (snap) => snap.docs.map((d) => AdminUser.fromDoc(d)).toList(),
    );
  }

  Future<void> addAdmin({
    required String email,
    required String role,
    required bool isActive,
    required bool canManageTreeMembers,
    required bool canManagePins,
    required bool canViewAuditLog,
    required bool canManagePrivacy,
  }) async {
    await _ref.add({
      'email': email.trim().toLowerCase(),
      'role': role,
      'isActive': isActive,
      'canManageTreeMembers': canManageTreeMembers,
      'canManagePins': canManagePins,
      'canViewAuditLog': canViewAuditLog,
      'canManagePrivacy': canManagePrivacy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateAdmin({
    required String id,
    required String email,
    required String role,
    required bool isActive,
    required bool canManageTreeMembers,
    required bool canManagePins,
    required bool canViewAuditLog,
    required bool canManagePrivacy,
  }) async {
    await _ref.doc(id).update({
      'email': email.trim().toLowerCase(),
      'role': role,
      'isActive': isActive,
      'canManageTreeMembers': canManageTreeMembers,
      'canManagePins': canManagePins,
      'canViewAuditLog': canViewAuditLog,
      'canManagePrivacy': canManagePrivacy,
    });
  }

  Future<void> deleteAdmin(String id) async {
    await _ref.doc(id).delete();
  }
}