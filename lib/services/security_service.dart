import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

class SecurityService {
  final FirebaseFirestore _db;

  SecurityService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _securityRef =>
      _db.collection('settings').doc('security');

  String hashPin(String pin) {
    return sha256.convert(utf8.encode(pin.trim())).toString();
  }

  Future<Map<String, dynamic>?> loadSecurityDoc() async {
    final snap = await _securityRef.get();
    return snap.data();
  }

  Future<bool> verifyFamilyPin(String pin) async {
    final data = await loadSecurityDoc();
    if (data == null) return false;

    final storedHash = (data['familyPinHash'] ?? '').toString();
    if (storedHash.isEmpty) return false;

    return hashPin(pin) == storedHash;
  }

  Future<bool> verifyAdminPin(String pin) async {
    final data = await loadSecurityDoc();
    if (data == null) return false;

    final storedHash = (data['adminPinHash'] ?? '').toString();
    if (storedHash.isEmpty) return false;

    return hashPin(pin) == storedHash;
  }

  Future<void> setPins({
    required String familyPin,
    required String adminPin,
  }) async {
    await _securityRef.set({
      'familyPinHash': hashPin(familyPin),
      'adminPinHash': hashPin(adminPin),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setFamilyPin(String familyPin) async {
    await _securityRef.set({
      'familyPinHash': hashPin(familyPin),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setAdminPin(String adminPin) async {
    await _securityRef.set({
      'adminPinHash': hashPin(adminPin),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}