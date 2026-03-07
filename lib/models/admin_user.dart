import 'package:cloud_firestore/cloud_firestore.dart';

class AdminUser {
  final String id;
  final String email;
  final String role;
  final bool isActive;
  final bool canManageTreeMembers;
  final bool canManagePins;
  final bool canViewAuditLog;
  final bool canManagePrivacy;
  final DateTime? createdAt;

  AdminUser({
    required this.id,
    required this.email,
    required this.role,
    required this.isActive,
    required this.canManageTreeMembers,
    required this.canManagePins,
    required this.canViewAuditLog,
    required this.canManagePrivacy,
    this.createdAt,
  });

  factory AdminUser.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});
    return AdminUser(
      id: doc.id,
      email: (data['email'] ?? '').toString(),
      role: (data['role'] ?? 'editor').toString(),
      isActive: (data['isActive'] ?? true) as bool,
      canManageTreeMembers: (data['canManageTreeMembers'] ?? false) as bool,
      canManagePins: (data['canManagePins'] ?? false) as bool,
      canViewAuditLog: (data['canViewAuditLog'] ?? false) as bool,
      canManagePrivacy: (data['canManagePrivacy'] ?? false) as bool,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'role': role,
      'isActive': isActive,
      'canManageTreeMembers': canManageTreeMembers,
      'canManagePins': canManagePins,
      'canViewAuditLog': canViewAuditLog,
      'canManagePrivacy': canManagePrivacy,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}