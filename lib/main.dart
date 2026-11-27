import 'package:flutter/material.dart';

import 'models/mail_account.dart';
import 'screens/inbox_screen.dart';
import 'screens/setup_screen.dart';
import 'services/account_store.dart';
import 'services/notifier.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Notifier.init();
  runApp(const MailApp());
}

class MailApp extends StatelessWidget {
  const MailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mail',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _Root(),
    );
  }
}

/// Verwaltet die Konten: lädt sie beim Start, wechselt das aktive Konto
/// und zeigt die Einrichtung, solange kein Konto oder ein neues angelegt wird.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  final _store = AccountStore();
  List<AccountConfig> _accounts = [];
  AccountConfig? _active;
  String? _password;
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await _store.loadAccounts();
    final activeEmail = await _store.loadActiveEmail();
    final active = accounts.where((a) => a.email == activeEmail).firstOrNull ??
        accounts.firstOrNull;
    final password = active == null ? null : await _store.loadPassword(active);
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _active = active;
      _password = password;
      _loading = false;
    });
  }

  Future<void> _switchTo(AccountConfig account) async {
    final password = await _store.loadPassword(account);
    await _store.setActive(account.email);
    if (!mounted) return;
    setState(() {
      _active = account;
      _password = password;
    });
  }

  Future<void> _onSaved(AccountConfig account, String password) async {
    await _store.setActive(account.email);
    setState(() => _adding = false);
    await _load();
  }

  Future<void> _removeActive() async {
    final active = _active;
    if (active == null) return;
    await _store.remove(active);
    setState(() {
      _active = null;
      _password = null;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final active = _active;
    final password = _password;
    if (_adding || active == null || password == null) {
      return SetupScreen(
        onSaved: _onSaved,
        onCancel: _accounts.isEmpty
            ? null
            : () => setState(() => _adding = false),
      );
    }
    return InboxScreen(
      key: ValueKey(active.email),
      account: active,
      password: password,
      accounts: _accounts,
      onSwitchAccount: _switchTo,
      onAddAccount: () => setState(() => _adding = true),
      onLogout: _removeActive,
    );
  }
}
