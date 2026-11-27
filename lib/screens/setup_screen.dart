import 'package:flutter/material.dart';

import '../models/mail_account.dart';
import '../services/account_store.dart';

/// Ersteinrichtung: Provider wählen, E-Mail-Adresse und Passwort eingeben.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onSaved});

  final void Function(AccountConfig account, String password) onSaved;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _imapHost = TextEditingController();
  final _smtpHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  final _smtpPort = TextEditingController(text: '465');
  ProviderPreset _preset = ProviderPreset.ionos;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyPreset(_preset);
  }

  void _applyPreset(ProviderPreset preset) {
    _preset = preset;
    _imapHost.text = preset.imapHost;
    _smtpHost.text = preset.smtpHost;
    _smtpPort.text = preset.smtpPort.toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final account = AccountConfig(
      provider: _preset.name,
      email: _email.text.trim(),
      imapHost: _imapHost.text.trim(),
      imapPort: int.parse(_imapPort.text.trim()),
      smtpHost: _smtpHost.text.trim(),
      smtpPort: int.parse(_smtpPort.text.trim()),
      smtpImplicitTls: _smtpPort.text.trim() == '465',
    );
    try {
      await AccountStore().save(account, _password.text);
      widget.onSaved(account, _password.text);
    } catch (e) {
      setState(() => _error = 'Speichern fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Konto einrichten')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Icon(Icons.mark_email_read_outlined,
                    size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'Willkommen',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Verbinde dein Postfach. Die Zugangsdaten bleiben auf diesem Gerät.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                DropdownButtonFormField<ProviderPreset>(
                  value: _preset,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: [
                    for (final p in ProviderPreset.all)
                      DropdownMenuItem(value: p, child: Text(p.name)),
                  ],
                  onChanged: (p) {
                    if (p == null) return;
                    setState(() => _applyPreset(p));
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-Mail-Adresse'),
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Bitte gültige Adresse eingeben' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Passwort'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Passwort fehlt' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _imapHost,
                        decoration: const InputDecoration(labelText: 'IMAP-Server'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _imapPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Port'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _smtpHost,
                        decoration: const InputDecoration(labelText: 'SMTP-Server'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _smtpPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Port'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Port 465 = verschlüsselt ab Start, Port 587 = STARTTLS.',
                  style: TextStyle(fontSize: 12),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Speichern und anmelden'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
