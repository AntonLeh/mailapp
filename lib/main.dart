import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'models/mail_account.dart';
import 'screens/inbox_screen.dart';
import 'screens/setup_screen.dart';
import 'services/account_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  runApp(const MailApp());
}

class MailApp extends StatelessWidget {
  const MailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const _Root(),
    );
  }
}

/// Entscheidet beim Start, ob schon ein Konto eingerichtet ist.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  final _store = AccountStore();
  MailAccount? _account;
  String? _password;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = await _store.loadAccount();
    final password = await _store.loadPassword();
    setState(() {
      _account = account;
      _password = password;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_account == null || _password == null) {
      return SetupScreen(
        onSaved: (account, password) {
          setState(() {
            _account = account;
            _password = password;
          });
        },
      );
    }
    return InboxScreen(
      account: _account!,
      password: _password!,
      onLogout: () async {
        await _store.clear();
        setState(() {
          _account = null;
          _password = null;
        });
      },
    );
  }
}
