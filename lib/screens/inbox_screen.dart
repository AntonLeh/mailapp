import 'dart:async';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';

import '../models/mail_account.dart';
import '../services/mail_service.dart';
import '../services/notifier.dart';
import '../services/quarantine.dart';
import '../ui/format.dart';
import '../ui/widgets.dart';
import 'compose_screen.dart';
import 'message_screen.dart';
import 'quarantine_screen.dart';

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

/// Hauptansicht: Konten und Ordner (Drawer), Filter, Suche, Liste, Verfassen.
class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.account,
    required this.password,
    required this.accounts,
    required this.onSwitchAccount,
    required this.onAddAccount,
    required this.onLogout,
  });

  final AccountConfig account;
  final String password;
  final List<AccountConfig> accounts;
  final Future<void> Function(AccountConfig account) onSwitchAccount;
  final VoidCallback onAddAccount;
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

  // Neue-Mail-Prüfung: höchste bekannte UID im Posteingang.
  int? _lastUid;

  // Anzahl der Mails in der Quarantäne (für das Menü).
  int _quarantined = 0;

  // Mehrfachauswahl (über UIDs).
  final Set<int> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelect(MimeMessage m) {
    final uid = m.uid;
    if (uid == null) return;
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
  }

  List<Widget> _selectionActions() => [
        IconButton(
          tooltip: 'Alle auswählen',
          icon: const Icon(Icons.select_all),
          onPressed: () => setState(() {
            _selected
              ..clear()
              ..addAll(_visible.map((m) => m.uid).whereType<int>());
          }),
        ),
        IconButton(
          tooltip: 'In den Papierkorb',
          icon: const Icon(Icons.delete_outline),
          onPressed: _trashSelected,
        ),
      ];

  /// Alle markierten Mails in den Papierkorb verschieben.
  Future<void> _trashSelected() async {
    final box = _current;
    final trash = _trash;
    if (box == null) return;
    if (trash == null) {
      _snack('Kein Papierkorb gefunden.');
      return;
    }
    final victims = _messages.where((m) => _selected.contains(m.uid)).toList();
    final count = victims.length;
    setState(() {
      _messages.removeWhere((m) => _selected.contains(m.uid));
      _selected.clear();
    });
    try {
      await _service.moveMessages(box, victims, trash);
      _snack('$count ${count == 1 ? 'Mail' : 'Mails'} in den Papierkorb verschoben.');
    } catch (e) {
      _snack('Löschen fehlgeschlagen: $e');
      _refresh();
    }
  }
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _pollTimer = Timer.periodic(const Duration(seconds: 90), (_) => _checkNewMail());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Mailbox? get _trash => MailService.findTrash(_boxes);

  Mailbox? get _inbox =>
      _boxes.where((b) => b.hasFlag(MailboxFlag.inbox)).firstOrNull ??
      _boxes.where((b) => b.name.toLowerCase() == 'inbox').firstOrNull;

  /// Systemordner lassen sich nicht umbenennen oder löschen. Erkannt wird über
  /// die Server-Markierung oder, falls der Server keine liefert, über den Namen.
  bool _isSystemFolder(Mailbox box) {
    if (box.hasFlag(MailboxFlag.inbox) ||
        box.hasFlag(MailboxFlag.trash) ||
        box.hasFlag(MailboxFlag.junk) ||
        box.hasFlag(MailboxFlag.sent) ||
        box.hasFlag(MailboxFlag.drafts)) {
      return true;
    }
    const systemNames = {
      'inbox', 'sent', 'sent items', 'sent messages', 'gesendet',
      'gesendete elemente', 'drafts', 'entwürfe', 'entwurf', 'trash',
      'deleted items', 'papierkorb', 'junk', 'junk e-mail', 'spam',
    };
    return systemNames.contains(box.name.toLowerCase());
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boxes = await _service.listMailboxes();
      final previous = _current;
      final inbox = boxes.where((b) => b.hasFlag(MailboxFlag.inbox)).firstOrNull ??
          boxes.where((b) => b.name.toLowerCase() == 'inbox').firstOrNull ??
          boxes.firstOrNull;
      // Gewählten Ordner nach Umbenennen wiederfinden, sonst Posteingang.
      final current = (previous == null
              ? null
              : boxes.where((b) => b.encodedPath == previous.encodedPath).firstOrNull) ??
          inbox;
      setState(() {
        _boxes = boxes;
        _current = current;
      });
      await _refresh();
    } catch (e) {
      setState(() => _error = 'Ordner laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Verdächtige Mails (Spam, Virus, gefährliche Anhänge) kommen in die lokale
  /// Quarantäne und werden im Server-Spam-Ordner abgelegt. Gilt nur für den Posteingang.
  Future<List<MimeMessage>> _sortOutSuspicious(
    Mailbox box,
    List<MimeMessage> messages,
  ) async {
    if (!box.hasFlag(MailboxFlag.inbox)) return messages;
    try {
      final known = (await QuarantineStore.all()).map((e) => e.key).toSet();
      final kept = <MimeMessage>[];
      final moved = <MimeMessage>[];
      for (final m in messages) {
        final key = SuspicionCheck.keyOf(m);
        if (known.contains(key)) continue; // schon in Quarantäne: ausblenden
        final reason = SuspicionCheck.reasonFor(m);
        if (reason == null) {
          kept.add(m);
          continue;
        }
        await QuarantineStore.add(m, reason);
        known.add(key);
        moved.add(m);
      }
      final junk = MailService.findJunk(_boxes);
      if (moved.isNotEmpty && junk != null) {
        try {
          await _service.moveMessages(box, moved, junk);
        } catch (_) {
          // Bleibt im Posteingang, ist aber lokal in Quarantäne und ausgeblendet.
        }
      }
      if (moved.isNotEmpty) {
        _snack('${moved.length} verdächtige Mail(s) in die Quarantäne verschoben.');
      }
      _quarantined = (await QuarantineStore.all()).length;
      return kept;
    } catch (_) {
      return messages;
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
      final kept = await _sortOutSuspicious(box, page.messages);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(kept);
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
      final kept = await _sortOutSuspicious(box, page.messages);
      if (!mounted) return;
      setState(() {
        _messages.addAll(kept);
        _page += 1;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Nachladen fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Prüft im Hintergrund, ob ungelesene Mails dazugekommen sind.
  Future<void> _checkNewMail() async {
    final box = _current;
    if (box == null || !box.hasFlag(MailboxFlag.inbox) || _loading || !mounted) {
      return;
    }
    try {
      final headers = await _service.fetchLatestHeaders(box);
      final uids = headers.map((m) => m.uid).whereType<int>().toList();
      if (uids.isEmpty) return;
      final newest = uids.reduce((a, b) => a > b ? a : b);
      final previous = _lastUid;
      _lastUid = newest;
      if (previous == null) return; // erste Runde: nur Ausgangspunkt merken
      // Verdächtige Mails nicht melden; sie landen beim nächsten Abruf in der Quarantäne.
      final arrived = headers.where((m) => (m.uid ?? 0) > previous).toList();
      if (arrived.isEmpty) return;
      final fresh = arrived
          .where((m) => !m.isSeen && SuspicionCheck.reasonFor(m) == null)
          .toList();
      for (final m in fresh.take(3)) {
        final from = m.from?.firstOrNull;
        await Notifier.show(
          id: m.uid ?? 0,
          title: from?.personalName?.isNotEmpty == true
              ? from!.personalName!
              : (from?.email ?? 'Neue Mail'),
          body: m.decodeSubject() ?? '(kein Betreff)',
        );
      }
      if (mounted) _refresh();
    } catch (_) {
      // Stilles Scheitern: die nächste Runde versucht es erneut.
    }
  }

  void _selectFolder(Mailbox box) {
    Navigator.of(context).pop(); // Drawer schließen
    setState(() {
      _current = box;
      _messages.clear();
      _query = '';
      _searching = false;
      _lastUid = null;
      _selected.clear();
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

  // ---------- Ordner verwalten ----------

  Future<String?> _askName(String title, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _createFolder() async {
    Navigator.of(context).pop(); // Drawer schließen
    final name = await _askName('Neuer Ordner');
    if (name == null || name.isEmpty) return;
    final parent = _inbox;
    await _folderAction(
      () => _service.createFolder(name, parent: parent),
      'Ordner angelegt.',
    );
  }

  Future<void> _renameFolder(Mailbox box) async {
    final name = await _askName('Ordner umbenennen', initial: box.name);
    if (name == null || name.isEmpty || name == box.name) return;
    await _folderAction(
      () => _service.renameFolder(box, name),
      'Ordner umbenannt.',
    );
  }

  Future<void> _deleteFolder(Mailbox box) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('„${box.name}“ löschen?'),
        content: const Text(
          'Der Ordner und alle Nachrichten darin werden entfernt. Das lässt sich nicht rückgängig machen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _folderAction(() => _service.deleteFolder(box), 'Ordner gelöscht.');
  }

  Future<void> _folderAction(Future<void> Function() action, String done) async {
    try {
      await action();
      _snack(done);
      await _loadFolders();
    } catch (e) {
      _snack('Fehlgeschlagen: $e');
    }
  }

  // ---------- Konten ----------

  void _switchAccount(AccountConfig account) {
    Navigator.of(context).pop(); // Drawer schließen
    if (account.email == widget.account.email) return;
    widget.onSwitchAccount(account);
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

    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                tooltip: 'Auswahl aufheben',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selected.clear()),
              )
            : null,
        title: _selecting
            ? Text('${_selected.length} ausgewählt')
            : _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Suchen …',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : Text(_current?.name ?? widget.account.email),
        actions: _selecting ? _selectionActions() : [
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Image.asset('assets/icon/app_icon.png', height: 36),
                    const SizedBox(width: 10),
                    Text(
                      'Mail',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              for (final acc in widget.accounts)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  selected: acc.email == widget.account.email,
                  selectedTileColor: scheme.primaryContainer,
                  leading: SenderAvatar(name: acc.email),
                  title: Text(
                    acc.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(acc.provider),
                  onTap: () => _switchAccount(acc),
                ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(Icons.add),
                title: const Text('Konto hinzufügen'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onAddAccount();
                },
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
                  trailing: _isSystemFolder(box)
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: 'Ordner-Optionen',
                          onSelected: (value) {
                            Navigator.of(context).pop();
                            if (value == 'rename') _renameFolder(box);
                            if (value == 'delete') _deleteFolder(box);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
                            PopupMenuItem(value: 'delete', child: Text('Löschen')),
                          ],
                        ),
                ),
              const Divider(height: 24),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Ordner anlegen'),
                onTap: _createFolder,
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Quarantäne'),
                trailing: _quarantined > 0 ? Text('$_quarantined') : null,
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const QuarantineScreen()),
                  );
                },
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
                          final m = visible[i];
                          return _MessageTile(
                            message: m,
                            snippet: _snippet(m),
                            selecting: _selecting,
                            selected: _selected.contains(m.uid),
                            onTap: () => _selecting
                                ? _toggleSelect(m)
                                : _openMessage(m),
                            onLongPress: () => _toggleSelect(m),
                            onDismissed: () => _trashFromList(m),
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
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onDismissed,
  });

  final MimeMessage message;
  final String snippet;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
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
      direction: selecting ? DismissDirection.none : DismissDirection.endToStart,
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
          color: selected
              ? scheme.secondaryContainer
              : unread
                  ? scheme.primaryContainer.withValues(alpha: 0.35)
                  : scheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  selected
                      ? CircleAvatar(
                          radius: 20,
                          backgroundColor: scheme.primary,
                          child: Icon(Icons.check, color: scheme.onPrimary),
                        )
                      : SenderAvatar(name: name),
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
