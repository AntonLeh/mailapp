import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';

import '../models/mail_account.dart';
import '../services/mail_service.dart';
import 'compose_screen.dart';
import 'message_screen.dart';

/// Hauptansicht: Ordnerliste (Drawer), Nachrichtenliste, Suche, Verfassen.
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
  late final MailService _service = MailService(widget.account, widget.password);

  List<Mailbox> _boxes = [];
  Mailbox? _current;
  List<MimeMessage> _messages = [];
  bool _loading = false;
  bool _searching = false;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boxes = await _service.listMailboxes();
      final inbox = boxes.where((b) => b.hasFlag(MailboxFlag.inbox)).firstOrNull ??
          boxes.where((b) => b.name.toLowerCase() == 'inbox').firstOrNull ??
          boxes.firstOrNull;
      setState(() {
        _boxes = boxes;
        _current = inbox;
      });
      await _refresh();
    } catch (e) {
      setState(() => _error = 'Ordner laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    final box = _current;
    if (box == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await _service.fetchMessages(box);
      setState(() => _messages = messages);
    } catch (e) {
      setState(() => _error = 'Abruf fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectFolder(Mailbox box) {
    Navigator.of(context).pop(); // Drawer schließen
    setState(() {
      _current = box;
      _messages = [];
      _query = '';
      _searching = false;
    });
    _refresh();
  }

  Future<void> _openMessage(MimeMessage message) async {
    final box = _current;
    if (box == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MessageScreen(
          service: _service,
          box: box,
          boxes: _boxes,
          message: message,
          senderEmail: widget.account.email,
        ),
      ),
    );
    if (changed == true) {
      _refresh();
    } else {
      setState(() {}); // Gelesen-Status in der Liste aktualisieren
    }
  }

  void _compose() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          service: _service,
          from: widget.account.email,
        ),
      ),
    );
  }

  List<MimeMessage> get _visible {
    if (_query.isEmpty) return _messages;
    final q = _query.toLowerCase();
    return _messages.where((m) {
      final from = m.from?.firstOrNull;
      final text = '${from?.personalName ?? ''} ${from?.email ?? ''} '
          '${m.decodeSubject() ?? ''}';
      return text.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Suchen …',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : Text(_current?.name ?? widget.account.email),
        actions: [
          IconButton(
            tooltip: _searching ? 'Suche beenden' : 'Suchen',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _query = '';
            }),
          ),
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
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const ListTile(
                title: Text('Ordner', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final box in _boxes)
                ListTile(
                  selected: box == _current,
                  leading: Icon(_iconFor(box)),
                  title: Text(box.name),
                  onTap: () => _selectFolder(box),
                ),
            ],
          ),
        ),
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
            child: visible.isEmpty && !_loading
                ? const Center(child: Text('Keine Nachrichten'))
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = visible[i];
                      final from = m.from?.firstOrNull;
                      final weight = m.isSeen ? FontWeight.normal : FontWeight.bold;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(m.isFlagged ? Icons.star : Icons.mail_outline),
                        ),
                        title: Text(
                          from?.personalName ?? from?.email ?? '(unbekannt)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: weight),
                        ),
                        subtitle: Text(
                          m.decodeSubject() ?? '(kein Betreff)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: weight),
                        ),
                        onTap: () => _openMessage(m),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(Mailbox box) {
    if (box.hasFlag(MailboxFlag.inbox)) return Icons.inbox;
    if (box.hasFlag(MailboxFlag.trash)) return Icons.delete_outline;
    if (box.hasFlag(MailboxFlag.junk)) return Icons.report_outlined;
    if (box.hasFlag(MailboxFlag.sent)) return Icons.send_outlined;
    if (box.hasFlag(MailboxFlag.drafts)) return Icons.drafts_outlined;
    return Icons.folder_outlined;
  }
}
