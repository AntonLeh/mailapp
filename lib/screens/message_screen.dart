import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../services/mail_service.dart';
import '../ui/format.dart';
import '../ui/widgets.dart';
import 'compose_screen.dart';
import 'pdf_screen.dart';

/// Einzelne Nachricht mit Kopfzeile, Text, Anhängen und Aktionen.
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
  bool _left = false;

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
        _left = true;
        Navigator.of(context).pop(true);
      } else {
        setState(() {});
      }
    } catch (e) {
      _snack('Aktion fehlgeschlagen: $e');
    } finally {
      if (mounted && !_left) setState(() => _busy = false);
    }
  }

  Future<void> _toggleSeen() => _run(
        () => widget.service.setSeen(widget.box, _m, !_m.isSeen),
        leaves: false,
      );

  Future<void> _toggleFlag() => _run(
        () => widget.service.setFlagged(widget.box, _m, !_m.isFlagged),
        leaves: false,
      );

  /// Speichert einen Anhang über den Dateidialog des Systems.
  Future<void> _saveAttachment(ContentInfo info) async {
    final name = info.fileName ?? 'anhang';
    setState(() => _busy = true);
    try {
      final bytes = await widget.service.fetchAttachment(widget.box, _m, info);
      if (bytes == null) {
        _snack('Anhang ist leer.');
        return;
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Anhang speichern',
        fileName: name,
        bytes: bytes,
      );
      if (path == null) return; // Dialog abgebrochen
      // Auf dem Desktop schreibt file_picker die Datei nicht selbst.
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await File(path).writeAsBytes(bytes);
      }
      _snack('Gespeichert: $name');
    } catch (e) {
      _snack('Speichern fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

  List<String> _quotedLines() {
    final original = _m.decodeTextPlainPart() ?? '';
    return original.split('\n').map((l) => '> $l').toList();
  }

  void _reply() {
    final from = _m.from?.firstOrNull;
    final subject = _m.decodeSubject() ?? '';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          service: widget.service,
          from: widget.senderEmail,
          initialTo: from?.email ?? '',
          initialSubject:
              subject.toLowerCase().startsWith('re:') ? subject : 'Re: $subject',
          initialBody: '\n\n${_quotedLines().join('\n')}',
        ),
      ),
    );
  }

  void _forward() {
    final subject = _m.decodeSubject() ?? '';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          service: widget.service,
          from: widget.senderEmail,
          initialSubject:
              subject.toLowerCase().startsWith('fwd:') ? subject : 'Fwd: $subject',
          initialBody:
              '\n\n---------- Weitergeleitete Nachricht ----------\n${_quotedLines().join('\n')}',
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
        _snack('$name ist kein PDF. Nur PDF-Anhänge werden angezeigt.');
      }
    } catch (e) {
      _snack('Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Nachrichtentext: HTML bevorzugt (mit Bildern aus dem Netz), sonst Klartext.
  /// HTML-Mails sind für helle Hintergründe gestaltet, daher steht der Inhalt
  /// auf einer weißen Fläche, auch im Dunkelmodus.
  Widget _buildBody(ThemeData theme) {
    final html = _m.decodeTextHtmlPart();
    if (html != null && html.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Html(data: html),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(18),
      child: SelectableText(
        _m.decodeTextPlainPart() ?? '(kein Text)',
        style: const TextStyle(fontSize: 15, height: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final from = _m.from?.firstOrNull;
    final name = from?.personalName?.isNotEmpty == true
        ? from!.personalName!
        : (from?.email ?? '(unbekannt)');
    final attachments = _m.findContentInfo();
    final inTrash = widget.box.hasFlag(MailboxFlag.trash);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Antworten',
            icon: const Icon(Icons.reply_outlined),
            onPressed: _busy ? null : _reply,
          ),
          IconButton(
            tooltip: 'Weiterleiten',
            icon: const Icon(Icons.forward_outlined),
            onPressed: _busy ? null : _forward,
          ),
          IconButton(
            tooltip: _m.isSeen ? 'Als ungelesen markieren' : 'Als gelesen markieren',
            icon: Icon(_m.isSeen
                ? Icons.mark_email_unread_outlined
                : Icons.drafts_outlined),
            onPressed: _busy ? null : _toggleSeen,
          ),
          IconButton(
            tooltip: _m.isFlagged ? 'Stern entfernen' : 'Mit Stern markieren',
            icon: Icon(
              _m.isFlagged ? Icons.star : Icons.star_border,
              color: _m.isFlagged ? Colors.amber.shade700 : null,
            ),
            onPressed: _busy ? null : _toggleFlag,
          ),
          IconButton(
            tooltip: 'Als Spam verschieben',
            icon: const Icon(Icons.report_outlined),
            onPressed: _busy
                ? null
                : () => _moveTo(MailService.findJunk(widget.boxes), 'Spam'),
          ),
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy || inTrash
                ? null
                : () => _moveTo(MailService.findTrash(widget.boxes), 'Papierkorb'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _m.decodeSubject() ?? '(kein Betreff)',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SenderAvatar(name: name, radius: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              from?.email ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatLongDate(_m.decodeDate()),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: _buildBody(theme),
          ),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Anhänge (${attachments.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final info in attachments)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: scheme.secondaryContainer,
                    child: Icon(
                      Icons.picture_as_pdf_outlined,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  title: Text(
                    info.fileName ?? 'Anhang',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Herunterladen',
                        icon: const Icon(Icons.download_outlined),
                        onPressed: _busy ? null : () => _saveAttachment(info),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: _busy ? null : () => _openAttachment(info),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
