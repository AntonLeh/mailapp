import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/mail_account.dart';

/// Speichert mehrere Konten. Die Kontodaten (ohne Passwort) liegen als Liste,
/// jedes Passwort separat. Alles liegt im Systemschlüsselbund
/// (Windows Credential Store, macOS Keychain, Android Keystore).
class AccountStore {
  static const _storage = FlutterSecureStorage();
  static const _accountsKey = 'accounts';
  static const _activeKey = 'active_account';

  // Schlüssel der Version mit nur einem Konto (für die Übernahme).
  static const _legacyAccountKey = 'account';
  static const _legacyPasswordKey = 'password';

  String _passwordKey(String email) => 'pw_${email.toLowerCase()}';

  /// Alle gespeicherten Konten. Übernimmt ein altes Einzel-Konto, falls vorhanden.
  Future<List<AccountConfig>> loadAccounts() async {
    final legacy = await _storage.read(key: _legacyAccountKey);
    if (legacy != null) {
      final account = AccountConfig.fromJson(jsonDecode(legacy) as Map<String, dynamic>);
      final password = await _storage.read(key: _legacyPasswordKey);
      if (password != null) {
        await save(account, password);
        await _storage.write(key: _activeKey, value: account.email);
      }
      await _storage.delete(key: _legacyAccountKey);
      await _storage.delete(key: _legacyPasswordKey);
    }
    return _readList();
  }

  Future<String?> loadActiveEmail() => _storage.read(key: _activeKey);

  Future<void> setActive(String email) =>
      _storage.write(key: _activeKey, value: email);

  Future<String?> loadPassword(AccountConfig account) =>
      _storage.read(key: _passwordKey(account.email));

  /// Legt ein Konto an oder aktualisiert es (gleiche E-Mail-Adresse).
  Future<void> save(AccountConfig account, String password) async {
    final accounts = await _readList();
    accounts.removeWhere(
      (a) => a.email.toLowerCase() == account.email.toLowerCase(),
    );
    accounts.add(account);
    await _writeList(accounts);
    await _storage.write(key: _passwordKey(account.email), value: password);
  }

  Future<void> remove(AccountConfig account) async {
    final accounts = await _readList();
    accounts.removeWhere(
      (a) => a.email.toLowerCase() == account.email.toLowerCase(),
    );
    await _writeList(accounts);
    await _storage.delete(key: _passwordKey(account.email));
  }

  Future<List<AccountConfig>> _readList() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return [
      for (final e in list) AccountConfig.fromJson(e as Map<String, dynamic>),
    ];
  }

  Future<void> _writeList(List<AccountConfig> accounts) => _storage.write(
        key: _accountsKey,
        value: jsonEncode([for (final a in accounts) a.toJson()]),
      );
}
