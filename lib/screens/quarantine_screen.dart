import 'package:flutter/material.dart';

import '../services/quarantine.dart';
import '../ui/format.dart';
import '../ui/widgets.dart';

/// Liste der lokal gespeicherten verdächtigen Mails.
class QuarantineScreen extends StatefulWidget {
  const QuarantineScreen({super.key});

  @override
  State<QuarantineScreen> createState() => _QuarantineScreenState();
}

class _QuarantineScreenState extends State<QuarantineScreen> {
  List<QuarantineEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await QuarantineStore.all();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _delete(QuarantineEntry e) async {
    await QuarantineStore.delete(e.key);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Quarantäne')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: scheme.secondaryContainer,
            padding: const EdgeInsets.all(12),
            child: Text(
              'Verdächtige Mails werden nur lokal auf diesem Gerät gespeichert '
              'und nach 5 Tagen automatisch gelöscht.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? EmptyState(
                    icon: Icons.shield_outlined,
                    text: 'Keine verdächtigen Mails',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final e = _items[i];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            Icons.warning_amber_outlined,
                            color: scheme.error,
                          ),
                          title: Text(
                            e.subject.isEmpty ? '(kein Betreff)' : e.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${e.fromName.isNotEmpty ? e.fromName : e.fromEmail}\n${e.reason}',
                          ),
                          isThreeLine: true,
                          onTap: () => Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => _QuarantineDetail(
                                    entry: e,
                                    onDelete: () => _delete(e),
                                  ),
                                ),
                              )
                              .then((_) => _load()),
                          trailing: IconButton(
                            tooltip: 'Löschen',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(e),
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

/// Eine Quarantäne-Mail im Klartext, ohne HTML und ohne Bilder.
class _QuarantineDetail extends StatelessWidget {
  const _QuarantineDetail({required this.entry, required this.onDelete});

  final QuarantineEntry entry;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sent = entry.sentAt == 0
        ? '–'
        : formatLongDate(DateTime.fromMillisecondsSinceEpoch(entry.sentAt));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          entry.subject.isEmpty ? '(kein Betreff)' : entry.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Endgültig löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await onDelete();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.reason,
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Von: ${entry.fromName} <${entry.fromEmail}>'),
                  Text('Datum: $sent'),
                  const SizedBox(height: 8),
                  Text(
                    'Wird automatisch gelöscht am ${formatLongDate(entry.expiresAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: SelectableText(
                entry.text.isEmpty
                    ? 'Kein Klartext vorhanden. HTML-Inhalte werden aus Sicherheitsgründen nicht angezeigt.'
                    : entry.text,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
