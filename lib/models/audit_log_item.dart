import 'package:cloud_firestore/cloud_firestore.dart';

class AuditLogItem {
  final String id;
  final String action;
  final String targetName;
  final String? details;
  final String actor;
  final DateTime? createdAt;

  AuditLogItem({
    required this.id,
    required this.action,
    required this.targetName,
    required this.actor,
    this.details,
    this.createdAt,
  });

  factory AuditLogItem.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});
    return AuditLogItem(
      id: doc.id,
      action: (data['action'] ?? '').toString(),
      targetName: (data['targetName'] ?? '').toString(),
      actor: (data['actor'] ?? 'admin').toString(),
      details: data['details']?.toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}