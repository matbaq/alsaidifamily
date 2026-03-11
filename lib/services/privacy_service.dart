import 'package:cloud_firestore/cloud_firestore.dart';

class PrivacySettings {
  final bool hideFemaleNamesForGuest;
  final bool hideFemalePhotosForGuest;
  final bool womenPageAdminOnly;
  final bool hideFemalesFromGeneralSearch;

  const PrivacySettings({
    required this.hideFemaleNamesForGuest,
    required this.hideFemalePhotosForGuest,
    required this.womenPageAdminOnly,
    required this.hideFemalesFromGeneralSearch,
  });

  factory PrivacySettings.fromMap(Map<String, dynamic>? data) {
    final map = data ?? {};
    return PrivacySettings(
      hideFemaleNamesForGuest:
      (map['hideFemaleNamesForGuest'] ?? true) as bool,
      hideFemalePhotosForGuest:
      (map['hideFemalePhotosForGuest'] ?? true) as bool,
      womenPageAdminOnly:
      (map['womenPageAdminOnly'] ?? false) as bool,
      hideFemalesFromGeneralSearch:
      (map['hideFemalesFromGeneralSearch'] ?? false) as bool,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hideFemaleNamesForGuest': hideFemaleNamesForGuest,
      'hideFemalePhotosForGuest': hideFemalePhotosForGuest,
      'womenPageAdminOnly': womenPageAdminOnly,
      'hideFemalesFromGeneralSearch': hideFemalesFromGeneralSearch,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  PrivacySettings copyWith({
    bool? hideFemaleNamesForGuest,
    bool? hideFemalePhotosForGuest,
    bool? womenPageAdminOnly,
    bool? hideFemalesFromGeneralSearch,
  }) {
    return PrivacySettings(
      hideFemaleNamesForGuest:
      hideFemaleNamesForGuest ?? this.hideFemaleNamesForGuest,
      hideFemalePhotosForGuest:
      hideFemalePhotosForGuest ?? this.hideFemalePhotosForGuest,
      womenPageAdminOnly:
      womenPageAdminOnly ?? this.womenPageAdminOnly,
      hideFemalesFromGeneralSearch:
      hideFemalesFromGeneralSearch ?? this.hideFemalesFromGeneralSearch,
    );
  }
}

class PrivacyService {
  final FirebaseFirestore _db;

  PrivacyService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection('settings').doc('privacy');

  Stream<PrivacySettings> streamSettings() {
    return _ref.snapshots().map((snap) {
      return PrivacySettings.fromMap(snap.data());
    });
  }

  Future<PrivacySettings> getSettings() async {
    final snap = await _ref.get();
    return PrivacySettings.fromMap(snap.data());
  }

  Future<void> saveSettings(PrivacySettings settings) async {
    await _ref.set(settings.toMap(), SetOptions(merge: true));
  }
}