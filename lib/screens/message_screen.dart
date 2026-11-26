import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';

import '../services/mail_service.dart';
import 'pdf_screen.dart';

/// Einzelne Nachricht mit Text und Anhängen. PDF-Anhänge öffnen sich
/// direkt im integrierten Reader.
class MessageScreen extends StatelessWidget {
  const MessageScreen({super.key, required this.service, required this.message});

  final MailService service;
  final MimeMessage message;

  Future<void> _openAttachment(BuildContext context, ContentInfo info) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = info.fileName ?? 'anhang';
    try {
      final bytes = await service.fetchAttachment(message, info);
      if (bytes == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Anhang leer')));
        return;
      }
      if (!context.mounted) return;
      if (name.toLowerCase().endsWith('.pdf')) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfScreen(title: name, bytes: bytes),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('$name geladen (${bytes.length} Bytes). Nur PDFs werden angezeigt.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = message.from?.firstOrNull;
    final body = message.decodeTextPlainPart() ??
        message.decodeTextHtmlPart() ??
        '(kein Text)';
    final attachments = message.findContentInfo();

    return Scaffold(
      appBar: AppBar(title: Text(message.decodeSubject() ?? '(kein Betreff)')),
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
                onTap: () => _openAttachment(context, info),
              ),
          ],
        ],
      ),
    );
  }
}
