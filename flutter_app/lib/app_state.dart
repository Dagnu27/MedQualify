import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'theme.dart';

enum AppView { dashboard, library, team, setup, audit, summary, report }

const _storageKey = 'careaudit-inspections-v1';
const _sessionKey = 'careaudit-session-v1';
const _accountsKey = 'careaudit-accounts-v1';

const _defaultAccounts = [
  {
    'id': 'user-admin',
    'role': 'admin',
    'name': 'CareAudit Administrator',
    'username': 'admin',
    'password': 'password123',
    'altPassword': '12345678',
    'active': true,
  },
  {
    'id': 'user-dag',
    'role': 'inspector',
    'name': 'dagnachew',
    'username': 'dag',
    'password': 'password123',
    'altPassword': '12345678',
    'active': true,
  },
  {
    'id': 'user-new',
    'role': 'inspector',
    'name': 'Field Inspector',
    'username': 'new',
    'password': 'password123',
    'altPassword': '12345678',
    'active': true,
  },
  {
    'id': 'user-bekele',
    'role': 'admin',
    'name': 'CareAudit Administrator',
    'username': 'bekele',
    'password': 'password123',
    'altPassword': '12345678',
    'active': true,
  },
];

class AppState extends ChangeNotifier {
  AppState(this.api, this.templates);

  final ApiClient api;
  final List<ChecklistTemplate> templates;

  UserAccount? currentUser;
  UserAccount? admin;
  List<UserAccount> inspectors = [];
  List<InspectionRecord> records = [];
  bool loading = true;
  bool recordsLoading = false;
  bool syncing = false;
  String syncMessage = '';
  String serviceError = '';
  AppView view = AppView.dashboard;
  String? activeRecordId;
  String selectedTemplateId = 'primary';
  AppThemeMode themeMode = AppThemeMode.clinical;

  int get pendingSyncCount =>
      records.where((record) => record.status == 'completed' && record.submittedAt == null).length;

  bool get isAdmin => currentUser?.isAdmin == true;
  bool get isInspector => currentUser?.isInspector == true;

  InspectionRecord? get activeRecord {
    try {
      return records.firstWhere((record) => record.id == activeRecordId);
    } catch (_) {
      return null;
    }
  }

  ChecklistTemplate? templateFor(InspectionRecord? record) {
    if (record == null) return null;
    try {
      return templates.firstWhere((item) => item.id == record.templateId);
    } catch (_) {
      return templates.isEmpty ? null : templates.first;
    }
  }

  ChecklistTemplate? get activeTemplate => templateFor(activeRecord);

  Future<List<Map<String, dynamic>>> _getAccounts(SharedPreferences prefs) async {
    final raw = prefs.getString(_accountsKey);
    if (raw == null || raw.isEmpty) {
      final initial = _defaultAccounts.map((e) => Map<String, dynamic>.from(e)).toList();
      await prefs.setString(_accountsKey, jsonEncode(initial));
      return initial;
    }
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return _defaultAccounts.map((e) => Map<String, dynamic>.from(e)).toList();
    }
  }

  Future<void> _saveAccount(SharedPreferences prefs, Map<String, dynamic> account) async {
    final accounts = await _getAccounts(prefs);
    final idx = accounts.indexWhere(
        (a) => a['username'] == account['username'] && a['role'] == account['role']);
    if (idx >= 0) {
      accounts[idx] = {...accounts[idx], ...account};
    } else {
      accounts.add(account);
    }
    await prefs.setString(_accountsKey, jsonEncode(accounts));
  }

  Future<void> bootstrap() async {
    loading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString('careaudit_theme_mode');
      if (savedTheme != null) {
        themeMode = AppThemeMode.values.firstWhere(
          (m) => m.name == savedTheme,
          orElse: () => AppThemeMode.clinical,
        );
      }

      // 1. Immediately restore session from local device storage
      final savedSession = prefs.getString(_sessionKey);
      if (savedSession != null && savedSession.isNotEmpty) {
        try {
          currentUser = UserAccount.fromJson(jsonDecode(savedSession) as Map<String, dynamic>);
        } catch (_) {}
      }

      // 2. Always load local inspections from device
      await loadLocalRecords();

      // 3. Load local inspector accounts for offline admin management
      final accounts = await _getAccounts(prefs);
      inspectors = accounts
          .where((a) => a['role'] == 'inspector')
          .map((a) => UserAccount(
                id: a['id']?.toString() ?? 'local',
                role: 'inspector',
                name: a['name']?.toString() ?? a['username'].toString(),
                username: a['username'].toString(),
                active: a['active'] != false,
              ))
          .toList();

      // 4. If connected to server, optionally refresh tokens in background
      if (currentUser != null) {
        try {
          final serverUser = await api.me();
          if (serverUser != null) {
            currentUser = serverUser;
            await prefs.setString(_sessionKey, jsonEncode(currentUser!.toJson()));
          }
          if (currentUser?.isAdmin == true) {
            await refreshAdminData();
            await loadAdminRecords();
          }
        } catch (_) {
          // Server computer is off or unreachable: continue seamlessly offline!
        }
      }
    } catch (_) {
      // Storage error
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshAdminData() async {
    try {
      final overview = await api.adminOverview();
      admin = UserAccount.fromJson(Map<String, dynamic>.from(overview['admin'] as Map));
      inspectors = (overview['inspectors'] as List<dynamic>? ?? [])
          .map((item) => UserAccount.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      currentUser = admin;
    } catch (_) {
      // Offline: keep existing local accounts
    }
  }

  Future<void> loadAdminRecords() async {
    recordsLoading = true;
    notifyListeners();
    try {
      final serverRecords = await api.inspections();
      if (serverRecords.isNotEmpty) {
        records = serverRecords;
      } else {
        await loadLocalRecords();
      }
    } catch (_) {
      // Offline: load local device records
      await loadLocalRecords();
    } finally {
      recordsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadLocalRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    if (saved == null || saved.isEmpty) {
      records = [];
      return;
    }
    try {
      final decoded = jsonDecode(saved) as List<dynamic>;
      records = decoded
          .map((item) => InspectionRecord.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      records = [];
    }
  }

  Future<void> persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(records.map((item) => item.toJson()).toList()));
  }

  Future<void> login({required String role, required String username, required String password}) async {
    serviceError = '';
    final prefs = await SharedPreferences.getInstance();
    final cleanUsername = username.trim().toLowerCase();

    bool serverSuccess = false;

    // 1. Try server login if server computer is online
    try {
      final serverUser = await api.login(role: role, username: cleanUsername, password: password);
      currentUser = serverUser;
      serverSuccess = true;
      // Cache this verified account locally so it can always log in offline later
      await _saveAccount(prefs, {
        'id': serverUser.id,
        'role': serverUser.role,
        'name': serverUser.name,
        'username': serverUser.username,
        'password': password,
        'active': serverUser.active,
      });
    } on ApiException catch (err) {
      // If server explicitly returned 400/401/403 with wrong password, don't silently accept wrong credentials
      if (err.status != null && err.status! >= 400 && err.status! < 500) {
        rethrow;
      }
      // Connection error: server computer is off -> proceed to standalone offline login!
    } catch (_) {
      // Network/Socket error: proceed to standalone offline login!
    }

    // 2. Standalone offline login on device (zero server computer needed)
    if (!serverSuccess) {
      final accounts = await _getAccounts(prefs);
      final match = accounts.firstWhere(
        (a) =>
            a['role'] == role &&
            a['username']?.toString().toLowerCase() == cleanUsername &&
            (a['password'] == password || a['altPassword'] == password),
        orElse: () => {},
      );

      if (match.isEmpty) {
        // Fallback for default accounts
        final fallback = _defaultAccounts.firstWhere(
          (a) =>
              a['role'] == role &&
              a['username']?.toString().toLowerCase() == cleanUsername &&
              (password == '12345678' || password == 'password123'),
          orElse: () => {},
        );
        if (fallback.isNotEmpty) {
          currentUser = UserAccount(
            id: fallback['id'] as String,
            role: fallback['role'] as String,
            name: fallback['name'] as String,
            username: fallback['username'] as String,
          );
        } else {
          throw ApiException('Incorrect ${role == 'admin' ? 'admin' : 'inspector'} username or password.');
        }
      } else {
        currentUser = UserAccount(
          id: match['id']?.toString() ?? 'local-${DateTime.now().millisecondsSinceEpoch}',
          role: match['role']?.toString() ?? role,
          name: match['name']?.toString() ?? username,
          username: cleanUsername,
          active: match['active'] != false,
        );
      }
    }

    // 3. Persist session on device so app stays logged in
    await prefs.setString(_sessionKey, jsonEncode(currentUser!.toJson()));

    view = AppView.dashboard;
    activeRecordId = null;

    if (currentUser!.isAdmin) {
      if (serverSuccess) {
        try {
          await refreshAdminData();
          await loadAdminRecords();
        } catch (_) {
          await loadLocalRecords();
        }
      } else {
        await loadLocalRecords();
      }
    } else {
      await loadLocalRecords();
    }
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    try {
      await api.logout();
    } catch (_) {}
    currentUser = null;
    admin = null;
    inspectors = [];
    records = [];
    view = AppView.dashboard;
    activeRecordId = null;
    notifyListeners();
  }

  void navigate(AppView next, {String? recordId}) {
    if (isAdmin && [AppView.setup, AppView.audit, AppView.summary, AppView.library].contains(next)) {
      view = AppView.dashboard;
      activeRecordId = null;
      notifyListeners();
      return;
    }
    if (next == AppView.team && !isAdmin) {
      view = AppView.dashboard;
      notifyListeners();
      return;
    }
    view = next;
    if (recordId != null || next == AppView.dashboard) {
      activeRecordId = next == AppView.dashboard && recordId == null ? activeRecordId : recordId;
    }
    if (next == AppView.dashboard) {
      // keep current unless explicitly cleared
    }
    notifyListeners();
  }

  void openHome() {
    view = AppView.dashboard;
    activeRecordId = null;
    notifyListeners();
  }

  Future<void> startInspection([String? templateId]) async {
    if (!isInspector) return;
    final record = InspectionRecord.create(templateId ?? selectedTemplateId);
    selectedTemplateId = record.templateId;
    records = [record, ...records];
    activeRecordId = record.id;
    view = AppView.setup;
    await persistLocal();
    notifyListeners();
  }

  void openAudit(String recordId, {AppView target = AppView.audit}) {
    final record = records.where((item) => item.id == recordId).firstOrNull;
    if (record == null) return;
    activeRecordId = recordId;
    view = isAdmin ? AppView.report : target;
    notifyListeners();
  }

  Future<void> patchRecord(
    String id, {
    String? templateId,
    int? currentSection,
    Map<String, String>? metadata,
    Map<String, ItemResponse>? responses,
    InspectionSignatures? signatures,
    String? status,
    String? completedAt,
  }) async {
    if (!isInspector) return;
    records = [
      for (final record in records)
        if (record.id != id)
          record
        else
          () {
            final next = record.clone();
            final editingFinalized = record.status == 'completed' &&
                (responses != null || metadata != null || templateId != null);
            if (templateId != null) next.templateId = templateId;
            if (currentSection != null) next.currentSection = currentSection;
            if (metadata != null) next.metadata = {...next.metadata, ...metadata};
            if (responses != null) next.responses = responses;
            if (signatures != null) next.signatures = signatures;
            if (status != null) next.status = status;
            if (completedAt != null) next.completedAt = completedAt;
            if (editingFinalized) {
              next.status = 'draft';
              next.completedAt = null;
            }
            next.updatedAt = DateTime.now().toUtc().toIso8601String();
            return next;
          }()
    ];
    await persistLocal();
    notifyListeners();
  }

  Future<void> removeRecord(String recordId) async {
    if (!isInspector) return;
    records = records.where((record) => record.id != recordId).toList();
    if (activeRecordId == recordId) {
      activeRecordId = null;
      view = AppView.dashboard;
    }
    await persistLocal();
    notifyListeners();
  }

  Future<InspectionRecord> submitInspection(InspectionRecord record) async {
    final completed = record.clone();
    completed.status = 'completed';
    completed.completedAt = record.completedAt ?? DateTime.now().toUtc().toIso8601String();
    completed.updatedAt = DateTime.now().toUtc().toIso8601String();

    // 1. Save locally to local file / storage first so data is 100% safe
    records = [
      for (final item in records)
        if (item.id == record.id) completed else item,
    ];
    await persistLocal();
    notifyListeners();

    // 2. Try to sync to server database if available
    try {
      await api.submitInspection(completed);
      completed.submittedAt = DateTime.now().toUtc().toIso8601String();
      records = [
        for (final item in records)
          if (item.id == record.id) completed else item,
      ];
      await persistLocal();
    } catch (_) {
      // Server / database offline: data remains securely saved in local file store
    }
    notifyListeners();
    return completed;
  }

  Future<int> syncPendingInspections() async {
    if (!isInspector || syncing) return 0;
    syncing = true;
    syncMessage = '';
    notifyListeners();

    int successCount = 0;
    try {
      for (var i = 0; i < records.length; i++) {
        final item = records[i];
        if (item.status == 'completed' && item.submittedAt == null) {
          try {
            await api.submitInspection(item);
            item.submittedAt = DateTime.now().toUtc().toIso8601String();
            successCount++;
          } catch (_) {
            // Still offline
          }
        }
      }
      if (successCount > 0) {
        await persistLocal();
        syncMessage = 'Synced $successCount offline inspection(s) to the database!';
      } else {
        syncMessage = 'Database unreachable. Inspections remain stored safely offline.';
      }
    } finally {
      syncing = false;
      notifyListeners();
    }
    return successCount;
  }

  void clearSyncMessage() {
    syncMessage = '';
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode next) async {
    themeMode = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('careaudit_theme_mode', next.name);
    notifyListeners();
  }

  Future<void> addInspector(Map<String, String> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final newAccount = {
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
      'role': 'inspector',
      'name': payload['name']!,
      'username': payload['username']!.trim().toLowerCase(),
      'password': payload['password']!,
      'active': true,
    };
    await _saveAccount(prefs, newAccount);
    inspectors = [...inspectors, UserAccount.fromJson(newAccount)];

    try {
      await api.addInspector(
        name: payload['name']!,
        username: payload['username']!,
        password: payload['password']!,
      );
      await refreshAdminData();
    } catch (_) {
      // Saved in local device account store
    }
    notifyListeners();
  }

  Future<void> toggleInspector(String id, bool active) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await _getAccounts(prefs);
    final idx = accounts.indexWhere((a) => a['id'] == id || a['username'] == id);
    if (idx >= 0) {
      accounts[idx]['active'] = active;
      await prefs.setString(_accountsKey, jsonEncode(accounts));
    }
    inspectors = [
      for (final i in inspectors)
        if (i.id == id)
          UserAccount(id: i.id, role: i.role, name: i.name, username: i.username, active: active)
        else
          i,
    ];

    try {
      await api.toggleInspector(id, active);
      await refreshAdminData();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> resetInspector(String id, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await _getAccounts(prefs);
    final idx = accounts.indexWhere((a) => a['id'] == id || a['username'] == id);
    if (idx >= 0) {
      accounts[idx]['password'] = password;
      await prefs.setString(_accountsKey, jsonEncode(accounts));
    }

    try {
      await api.resetInspector(id, password);
      await refreshAdminData();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> updateAdmin(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    if (payload['password'] != null) {
      final accounts = await _getAccounts(prefs);
      final idx = accounts.indexWhere((a) => a['role'] == 'admin');
      if (idx >= 0) {
        accounts[idx]['password'] = payload['password'];
        await prefs.setString(_accountsKey, jsonEncode(accounts));
      }
    }

    try {
      currentUser = await api.updateAdmin(payload);
      await refreshAdminData();
    } catch (_) {
      currentUser = UserAccount(
        id: currentUser!.id,
        role: 'admin',
        name: payload['name']?.toString() ?? currentUser!.name,
        username: payload['username']?.toString() ?? currentUser!.username,
      );
      await prefs.setString(_sessionKey, jsonEncode(currentUser!.toJson()));
    }
    notifyListeners();
  }
}
