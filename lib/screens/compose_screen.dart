import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/mail_service.dart';
import '../ui/widgets.dart';

/// Neue Nachricht verfassen, antworten oder weiterleiten. Versendet per SMTP.
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
  final _cc = TextEditingController();
  late final _subject = TextEditingController(text: widget.initialSubject);
  late final _body = TextEditingController(text: widget.initialBody);
  bool _showCc = false;
  bool _sending = false;
  String? _error;
  final List<OutgoingAttachment> _attachments = [];

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    final added = <OutgoingAttachment>[];
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      added.add(OutgoingAttachment(f.name, Uint8List.fromList(bytes)));
    }
    if (!mounted || added.isEmpty) return;
    setState(() => _attachments.addAll(added));
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  bool _isAddress(String v) => v.contains('@') && !v.contains(' ');

  Future<void> _send() async {
    final to = _to.text.trim();
    if (!_isAddress(to)) {
      setState(() => _error = 'Bitte eine gültige Empfängeradresse eingeben.');
      return;
    }
    final ccList = _cc.text.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty);
    if (ccList.any((a) => !_isAddress(a))) {
      setState(() => _error = 'Mindestens eine CC-Adresse ist ungültig.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.service.send(
        to: to,
        cc: _cc.text,
        subject: _subject.text,
        body: _body.text,
        attachments: _attachments,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _snack('Nachricht gesendet.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Versand fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neue Nachricht'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('Senden'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null) ErrorBanner(text: _error!),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      children: [
                        _field(
                          controller: _to,
                          label: 'An',
                          keyboardType: TextInputType.emailAddress,
                          trailing: _showCc
                              ? null
                              : TextButton(
                                  onPressed: () => setState(() => _showCc = true),
                                  child: const Text('CC'),
                                ),
                        ),
                        if (_showCc)
                          _field(
                            controller: _cc,
                            label: 'CC',
                            keyboardType: TextInputType.emailAddress,
                          ),
                        _field(controller: _subject, label: 'Betreff'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _body,
                      minLines: 14,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        hintText: 'Nachricht schreiben …',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _attachments.isEmpty
                            ? 'Keine Anhänge'
                            : 'Anhänge (${_attachments.length})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _sending ? null : _pickAttachments,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Anhang hinzufügen'),
                    ),
                  ],
                ),
                for (var i = 0; i < _attachments.length; i++)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.secondaryContainer,
                        child: Icon(Icons.insert_drive_file_outlined,
                            color: scheme.onSecondaryContainer),
                      ),
                      title: Text(
                        _attachments[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_sizeLabel(_attachments[i].bytes.length)),
                      trailing: IconButton(
                        tooltip: 'Entfernen',
                        icon: const Icon(Icons.close),
                        onPressed: _sending
                            ? null
                            : () => setState(() => _attachments.removeAt(i)),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.account_circle_outlined,
                        size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Von: ${widget.from}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    Widget? trailing,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }
}
