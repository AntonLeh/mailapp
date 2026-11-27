import 'package:flutter/material.dart';

import '../services/mail_service.dart';

/// Neue Nachricht verfassen und über SMTP versenden.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    super.key,
    required this.service,
    required this.from,
    this.initialTo = '',
    this.initialSubject = '',
    this.initialBody = '',
  });

  final MailService service;
  final String from;
  final String initialTo;
  final String initialSubject;
  final String initialBody;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final _to = TextEditingController(text: widget.initialTo);
  late final _subject = TextEditingController(text: widget.initialSubject);
  late final _body = TextEditingController(text: widget.initialBody);
  bool _sending = false;

  Future<void> _send() async {
    if (_to.text.trim().isEmpty || !_to.text.contains('@')) {
      _snack('Bitte eine gültige Empfängeradresse eingeben.');
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.service.send(
        to: _to.text.trim(),
        subject: _subject.text,
        body: _body.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _snack('Gesendet.');
    } catch (e) {
      _snack('Versand fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neue Nachricht'),
        actions: [
          IconButton(
            tooltip: 'Senden',
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            onPressed: _sending ? null : _send,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Von: ${widget.from}', style: Theme.of(context).textTheme.bodySmall),
            TextField(
              controller: _to,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'An'),
            ),
            TextField(
              controller: _subject,
              decoration: const InputDecoration(labelText: 'Betreff'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _body,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: 'Nachricht',
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
