import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/security_service.dart';

enum AccessMode {
  guest,
  family,
  admin,
}

class AccessController extends ChangeNotifier {
  final SecurityService _securityService = SecurityService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  AccessMode _mode = AccessMode.guest;
  AccessMode get mode => _mode;

  bool get isGuest => _mode == AccessMode.guest;
  bool get isFamily => _mode == AccessMode.family;
  bool get isAdmin => _mode == AccessMode.admin;

  bool get canSeePrivate => isFamily || isAdmin;

  bool _isLoadingAdmin = false;
  bool get isLoadingAdmin => _isLoadingAdmin;

  bool _adminAccountExists = false;
  bool get adminAccountExists => _adminAccountExists;

  bool _adminIsActive = false;
  bool get adminIsActive => _adminIsActive;

  String _adminRole = '';
  String get adminRole => _adminRole;

  bool _canManageTreeMembers = false;
  bool get canManageTreeMembers => _canManageTreeMembers;

  bool _canManagePins = false;
  bool get canManagePins => _canManagePins;

  bool _canViewAuditLog = false;
  bool get canViewAuditLog => _canViewAuditLog;

  bool _canManagePrivacy = false;
  bool get canManagePrivacy => _canManagePrivacy;

  StreamSubscription<User?>? _authSub;

  AccessController() {
    _authSub = _auth.authStateChanges().listen((user) async {
      await refreshAdminAccess();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _resetAdminFlags() {
    _adminAccountExists = false;
    _adminIsActive = false;
    _adminRole = '';
    _canManageTreeMembers = false;
    _canManagePins = false;
    _canViewAuditLog = false;
    _canManagePrivacy = false;
  }

  Future<void> refreshAdminAccess() async {
    final user = _auth.currentUser;

    if (user == null) {
      _resetAdminFlags();
      if (_mode == AccessMode.admin) {
        _mode = AccessMode.guest;
      }
      notifyListeners();
      return;
    }

    final email = user.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      _resetAdminFlags();
      if (_mode == AccessMode.admin) {
        _mode = AccessMode.guest;
      }
      notifyListeners();
      return;
    }

    _isLoadingAdmin = true;
    notifyListeners();

    try {
      final snap = await _db
          .collection('admin_users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        _resetAdminFlags();
        if (_mode == AccessMode.admin) {
          _mode = AccessMode.guest;
        }
      } else {
        final data = snap.docs.first.data();

        _adminAccountExists = true;
        _adminIsActive = (data['isActive'] ?? false) as bool;
        _adminRole = (data['role'] ?? 'viewer').toString();

        _canManageTreeMembers =
        (data['canManageTreeMembers'] ?? false) as bool;
        _canManagePins = (data['canManagePins'] ?? false) as bool;
        _canViewAuditLog = (data['canViewAuditLog'] ?? false) as bool;
        _canManagePrivacy = (data['canManagePrivacy'] ?? false) as bool;

        if (_adminIsActive) {
          _mode = AccessMode.admin;
        } else {
          if (_mode == AccessMode.admin) {
            _mode = AccessMode.guest;
          }
        }
      }
    } catch (_) {
      _resetAdminFlags();
      if (_mode == AccessMode.admin) {
        _mode = AccessMode.guest;
      }
    } finally {
      _isLoadingAdmin = false;
      notifyListeners();
    }
  }

  void setGuest() {
    if (_mode == AccessMode.guest) return;
    _mode = AccessMode.guest;
    notifyListeners();
  }

  void setFamily() {
    if (_mode == AccessMode.family) return;
    _mode = AccessMode.family;
    notifyListeners();
  }

  void setAdmin() {
    if (_mode == AccessMode.admin) return;
    _mode = AccessMode.admin;
    notifyListeners();
  }

  Future<bool> checkFamilyPin(String value) async {
    return await _securityService.verifyFamilyPin(value.trim());
  }

  Future<bool> checkAdminPin(String value) async {
    return await _securityService.verifyAdminPin(value.trim());
  }

  Future<bool> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await refreshAdminAccess();

    return isAdmin && adminIsActive;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _resetAdminFlags();
    if (_mode == AccessMode.admin) {
      _mode = AccessMode.guest;
    }
    notifyListeners();
  }
}