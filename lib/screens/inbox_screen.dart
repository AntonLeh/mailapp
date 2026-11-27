import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';

import '../models/mail_account.dart';
import '../services/mail_service.dart';
import '../ui/format.dart';
import '../ui/widgets.dart';
import 'compose_screen.dart';
import 'message_screen.dart';

/// Welche Nachrichten in der Liste angezeigt werden.
enum MailFilter {
  all('Alle', Icons.all_inbox),
  unread('Ungelesen', Icons.mark_email_unread_outlined),
  flagged('Markiert', Icons.star_outline),
  attachments('Anhänge', Icons.attach_file);

  const MailFilter(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Hauptansicht: Ordner (Drawer), Filter, Suche, Liste mit Seiten und Verfassen.
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
  final List<MimeMessage> _messages = [];
  int _page = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _searching = false;
  String _query = '';
  MailFilter _filter = MailFilter.all;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Mailbox? get _trash => MailService.findTrash(_boxes);

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

  /// Lädt die erste Seite neu und ersetzt die Liste.
  Future<void> _refresh() async {
    final box = _current;
    if (box == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.fetchPage(box, page: 0);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _page = 0;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Abruf fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Lädt die nächstältere Seite und hängt sie an.
  Future<void> _loadMore() async {
    final box = _current;
    if (box == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.fetchPage(box, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _messages.addAll(page.messages);
        _page += 1;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Nachladen fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _selectFolder(Mailbox box) {
    Navigator.of(context).pop(); // Drawer schließen
    setState(() {
      _current = box;
      _messages.clear();
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

  /// Wischen nach links verschiebt die Nachricht in den Papierkorb.
  Future<void> _trashFromList(MimeMessage message) async {
    final box = _current;
    final trash = _trash;
    if (box == null) return;
    if (trash == null) {
      _snack('Kein Papierkorb gefunden.');
      _refresh();
      return;
    }
    setState(() => _messages.remove(message));
    try {
      await _service.moveMessage(box, message, trash);
    } catch (e) {
      _snack('Löschen fehlgeschlagen: $e');
      _refresh();
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
    final q = _query.toLowerCase();
    return _messages.where((m) {
      final passesFilter = switch (_filter) {
        MailFilter.all => true,
        MailFilter.unread => !m.isSeen,
        MailFilter.flagged => m.isFlagged,
        MailFilter.attachments => m.findContentInfo().isNotEmpty,
      };
      if (!passesFilter) return false;
      if (q.isEmpty) return true;
      final from = m.from?.firstOrNull;
      final text = '${from?.personalName ?? ''} ${from?.email ?? ''} '
          '${m.decodeSubject() ?? ''}';
      return text.toLowerCase().contains(q);
    }).toList();
  }

  String _snippet(MimeMessage m) {
    final text = m.decodeTextPlainPart() ?? '';
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;
    final account = widget.account.email;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Suchen …',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : Text(_current?.name ?? account),
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
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                leading: SenderAvatar(name: account),
                title: Text(
                  account,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(widget.account.provider),
              ),
              const Divider(height: 24),
              for (final box in _boxes)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  selected: box == _current,
                  selectedTileColor: scheme.primaryContainer,
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
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Neu'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                for (final f in MailFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      avatar: Icon(f.icon, size: 18),
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) ErrorBanner(text: _error!),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: visible.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: 320,
                          child: EmptyState(
                            icon: _loading
                                ? Icons.hourglass_empty
                                : Icons.mark_email_read_outlined,
                            text: _loading
                                ? 'Lädt …'
                                : _query.isNotEmpty || _filter != MailFilter.all
                                    ? 'Keine passenden Nachrichten'
                                    : 'Keine Nachrichten',
                          ),
                        ),
                      ],
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.extentAfter < 400) _loadMore();
                        return false;
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                        itemCount: visible.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == visible.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          return _MessageTile(
                            message: visible[i],
                            snippet: _snippet(visible[i]),
                            onTap: () => _openMessage(visible[i]),
                            onDismissed: () => _trashFromList(visible[i]),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(Mailbox box) {
    if (box.hasFlag(MailboxFlag.inbox)) return Icons.inbox_outlined;
    if (box.hasFlag(MailboxFlag.trash)) return Icons.delete_outline;
    if (box.hasFlag(MailboxFlag.junk)) return Icons.report_outlined;
    if (box.hasFlag(MailboxFlag.sent)) return Icons.send_outlined;
    if (box.hasFlag(MailboxFlag.drafts)) return Icons.drafts_outlined;
    return Icons.folder_outlined;
  }
}

/// Eine Zeile der Nachrichtenliste: Avatar, Absender, Betreff, Vorschau, Datum.
class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.snippet,
    required this.onTap,
    required this.onDismissed,
  });

  final MimeMessage message;
  final String snippet;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final from = message.from?.firstOrNull;
    final name = from?.personalName?.isNotEmpty == true
        ? from!.personalName!
        : (from?.email ?? '(unbekannt)');
    final unread = !message.isSeen;
    final hasAttachment = message.findContentInfo().isNotEmpty;

    return Dismissible(
      key: ValueKey(message.uid ?? message.sequenceId ?? message.hashCode),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: unread
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : scheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SenderAvatar(name: name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight:
                                      unread ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              formatMailDate(message.decodeDate()),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message.decodeSubject() ?? '(kein Betreff)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        if (snippet.isNotEmpty)
                          Text(
                            snippet,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    children: [
                      if (message.isFlagged)
                        Icon(Icons.star, size: 18, color: Colors.amber.shade700),
                      if (hasAttachment)
                        Icon(Icons.attach_file, size: 18, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
