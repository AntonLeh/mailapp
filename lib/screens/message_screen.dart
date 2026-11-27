import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';

import '../services/mail_service.dart';
import 'compose_screen.dart';
import 'pdf_screen.dart';

/// Einzelne Nachricht mit Text, Anhängen und Aktionen
/// (gelesen/ungelesen, Stern, Antworten, Spam, Löschen).
/// Gibt `true` zurück, wenn die Nachricht den Ordner verlassen hat.
class MessageScreen extends StatefulWidget {
  const MessageScreen({
    super.key,
    required this.service,
    required this.box,
    required this.boxes,
    required this.message,
    required this.senderEmail,
  });

  final MailService service;
  final Mailbox box;
  final List<Mailbox> boxes;
  final MimeMessage message;
  final String senderEmail;

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  bool _busy = false;

  MimeMessage get _m => widget.message;

  @override
  void initState() {
    super.initState();
    if (!_m.isSeen) {
      // Beim Öffnen automatisch als gelesen markieren.
      widget.service.setSeen(widget.box, _m, true).then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {});
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action, {required bool leaves}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (leaves) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {});
      }
    } catch (e) {
      _snack('Aktion fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleSeen() => _run(
        () => widget.service.setSeen(widget.box, _m, !_m.isSeen),
        leaves: false,
      );

  Future<void> _flag() => _run(
        () => widget.service.setFlagged(widget.box, _m),
        leaves: false,
      );

  Future<void> _moveTo(Mailbox? target, String what) async {
    if (target == null) {
      _snack('Kein $what-Ordner gefunden.');
      return;
    }
    await _run(
      () => widget.service.moveMessage(widget.box, _m, target),
      leaves: true,
    );
  }

  void _reply() {
    final from = _m.from?.firstOrNull;
    final original = _m.decodeTextPlainPart() ?? '';
    final quoted = original.split('\n').map((l) => '> $l').join('\n');
    final subject = _m.decodeSubject() ?? '';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          service: widget.service,
          from: widget.senderEmail,
          initialTo: from?.email ?? '',
          initialSubject:
              subject.toLowerCase().startsWith('re:') ? subject : 'Re: $subject',
          initialBody: '\n\n$quoted',
        ),
      ),
    );
  }

  Future<void> _openAttachment(ContentInfo info) async {
    final name = info.fileName ?? 'anhang';
    setState(() => _busy = true);
    try {
      final bytes = await widget.service.fetchAttachment(widget.box, _m, info);
      if (bytes == null) {
        _snack('Anhang ist leer.');
        return;
      }
      if (!mounted) return;
      if (name.toLowerCase().endsWith('.pdf')) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfScreen(title: name, bytes: bytes),
          ),
        );
      } else {
        _snack('$name geladen (${bytes.length} Bytes). Nur PDFs werden angezeigt.');
      }
    } catch (e) {
      _snack('Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = _m.from?.firstOrNull;
    final body = _m.decodeTextPlainPart() ?? _m.decodeTextHtmlPart() ?? '(kein Text)';
    final attachments = _m.findContentInfo();
    final inTrash = widget.box.hasFlag(MailboxFlag.trash);

    return Scaffold(
      appBar: AppBar(
        title: Text(_m.decodeSubject() ?? '(kein Betreff)'),
        actions: [
          IconButton(
            tooltip: 'Antworten',
            icon: const Icon(Icons.reply),
            onPressed: _busy ? null : _reply,
          ),
          IconButton(
            tooltip: _m.isSeen ? 'Als ungelesen markieren' : 'Als gelesen markieren',
            icon: Icon(_m.isSeen ? Icons.mark_email_unread_outlined : Icons.drafts_outlined),
            onPressed: _busy ? null : _toggleSeen,
          ),
          IconButton(
            tooltip: 'Markieren',
            icon: Icon(_m.isFlagged ? Icons.star : Icons.star_border),
            onPressed: _busy || _m.isFlagged ? null : _flag,
          ),
          IconButton(
            tooltip: 'Als Spam verschieben',
            icon: const Icon(Icons.report_outlined),
            onPressed: _busy
                ? null
                : () => _moveTo(
                      _findJunk(),
                      'Spam',
                    ),
          ),
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy || inTrash
                ? null
                : () => _moveTo(
                      _findTrash(),
                      'Papierkorb',
                    ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Von: ${from?.personalName ?? ''} <${from?.email ?? ''}>',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 24),
          SelectableText(body),
          if (attachments.isNotEmpty) ...[
            const Divider(height: 32),
            Text('Anhänge', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final info in attachments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(info.fileName ?? 'Anhang'),
                onTap: _busy ? null : () => _openAttachment(info),
              ),
          ],
        ],
      ),
    );
  }

  Mailbox? _findJunk() => MailService.findJunk(widget.boxes);

  Mailbox? _findTrash() => MailService.findTrash(widget.boxes);
}
