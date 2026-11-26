import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';

import '../models/mail_account.dart';
import '../services/mail_service.dart';
import 'compose_screen.dart';
import 'message_screen.dart';

/// Posteingang: Liste der neuesten Nachrichten, Aktualisieren, Verfassen.
class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.account,
    required this.password,
    required this.onLogout,
  });

  final AccountConfig account;
  final String password;
  final Future<void> Function() onLogout;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late final MailService _service =
      MailService(widget.account, widget.password);
  List<MimeMessage> _messages = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await _service.fetchInbox();
      setState(() => _messages = messages);
    } catch (e) {
      setState(() => _error = 'Abruf fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _compose() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(service: _service, from: widget.account.email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.account.email),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') widget.onLogout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Konto entfernen')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        icon: const Icon(Icons.edit),
        label: const Text('Neu'),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _messages.isEmpty && !_loading
                ? const Center(child: Text('Keine Nachrichten'))
                : ListView.separated(
                    itemCount: _messages.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final from = m.from?.firstOrNull;
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.mail_outline)),
                        title: Text(
                          from?.personalName ?? from?.email ?? '(unbekannt)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          m.decodeSubject() ?? '(kein Betreff)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MessageScreen(
                              service: _service,
                              message: m,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
