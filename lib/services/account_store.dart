import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/mail_account.dart';

/// Speichert das Konto (ohne Passwort) und das Passwort getrennt.
/// Das Passwort liegt im Systemschlüsselbund (Windows Credential Store,
/// macOS Keychain, Android Keystore).
class AccountStore {
  static const _storage = FlutterSecureStorage();
  static const _accountKey = 'account';
  static const _passwordKey = 'password';

  Future<AccountConfig?> loadAccount() async {
    final raw = await _storage.read(key: _accountKey);
    if (raw == null) return null;
    return AccountConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<String?> loadPassword() => _storage.read(key: _passwordKey);

  Future<void> save(AccountConfig account, String password) async {
    await _storage.write(key: _accountKey, value: jsonEncode(account.toJson()));
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accountKey);
    await _storage.delete(key: _passwordKey);
  }
}
