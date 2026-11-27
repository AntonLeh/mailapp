import 'dart:convert';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:path_provider/path_provider.dart';

/// Eine Nachricht in der Quarantäne. Gespeichert werden Absender, Betreff und
/// Klartext, nicht die Anhänge und kein HTML (Bilder aus Spam-Mails würden sonst laden).
class QuarantineEntry {
  const QuarantineEntry({
    required this.key,
    required this.subject,
    required this.fromName,
    required this.fromEmail,
    required this.sentAt,
    required this.reason,
    required this.savedAt,
    required this.text,
  });

  final String key;
  final String subject;
  final String fromName;
  final String fromEmail;
  final int sentAt; // ms seit Epoche, 0 wenn unbekannt
  final String reason;
  final int savedAt; // ms seit Epoche
  final String text;

  DateTime get expiresAt => DateTime.fromMillisecondsSinceEpoch(savedAt)
      .add(QuarantineStore.retention);

  Map<String, dynamic> toJson() => {
        'key': key,
        'subject': subject,
        'fromName': fromName,
        'fromEmail': fromEmail,
        'sentAt': sentAt,
        'reason': reason,
        'savedAt': savedAt,
        'text': text,
      };

  factory QuarantineEntry.fromJson(Map<String, dynamic> j) => QuarantineEntry(
        key: j['key'] as String? ?? '',
        subject: j['subject'] as String? ?? '',
        fromName: j['fromName'] as String? ?? '',
        fromEmail: j['fromEmail'] as String? ?? '',
        sentAt: j['sentAt'] as int? ?? 0,
        reason: j['reason'] as String? ?? '',
        savedAt: j['savedAt'] as int? ?? 0,
        text: j['text'] as String? ?? '',
      );
}

/// Erkennt Spam- und Virusverdacht. Verlässt sich auf die Befunde des
/// Anbieters (Header) und auf Regeln für gefährliche Anhänge. Die App
/// scannt selbst keine Dateien.
class SuspicionCheck {
  SuspicionCheck._();

  static const _dangerousExtensions = {
    'exe', 'scr', 'bat', 'cmd', 'com', 'js', 'jse', 'vbs', 'vbe', 'wsf',
    'ps1', 'msi', 'lnk', 'hta', 'jar', 'reg', 'iso', 'img', 'dll', 'cpl',
    'docm', 'xlsm', 'pptm',
  };

  /// Grund für den Verdacht oder null, wenn die Nachricht unauffällig ist.
  static String? reasonFor(MimeMessage m) {
    if (_headerStartsWith(m, 'X-Spam-Flag', 'yes') ||
        _headerStartsWith(m, 'X-Spam-Status', 'yes')) {
      return 'Spam laut Filter des Anbieters';
    }
    final virus = (m.getHeaderValue('X-Virus-Status') ?? '').toLowerCase();
    if (virus.contains('infect') ||
        (virus.contains('found') && !virus.contains('not found'))) {
      return 'Virusverdacht laut Scanner des Anbieters';
    }
    for (final info in m.findContentInfo()) {
      final name = (info.fileName ?? '').toLowerCase();
      final dot = name.lastIndexOf('.');
      if (dot < 0) continue;
      final ext = name.substring(dot + 1);
      if (_dangerousExtensions.contains(ext)) {
        return 'Gefährlicher Anhang (.$ext)';
      }
    }
    return null;
  }

  static bool _headerStartsWith(MimeMessage m, String header, String prefix) {
    final value = m.getHeaderValue(header);
    return value != null && value.trim().toLowerCase().startsWith(prefix);
  }

  /// Eindeutiger Schlüssel einer Nachricht, unabhängig von der UID im Ordner.
  static String keyOf(MimeMessage m) {
    final id = m.getHeaderValue('Message-ID')?.trim();
    if (id != null && id.isNotEmpty) return id;
    final date = m.decodeDate()?.millisecondsSinceEpoch ?? 0;
    return 'uid-${m.uid}-$date-${m.decodeSubject() ?? ''}';
  }
}

/// Lokale Quarantäne im App-Datenordner. Einträge werden nach [retention]
/// automatisch entfernt. Die Datei liegt unverschlüsselt auf dem Gerät.
class QuarantineStore {
  QuarantineStore._();

  static const retention = Duration(days: 5);

  static List<QuarantineEntry>? _cache;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}quarantine.json');
  }

  /// Lädt den Bestand und entfernt abgelaufene Einträge.
  static Future<List<QuarantineEntry>> _load() async {
    if (_cache == null) {
      try {
        final file = await _file();
        if (await file.exists()) {
          final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
          _cache = raw
              .map((e) => QuarantineEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        } else {
          _cache = [];
        }
      } catch (_) {
        _cache = [];
      }
    }
    final cutoff = DateTime.now().subtract(retention).millisecondsSinceEpoch;
    final before = _cache!.length;
    _cache!.removeWhere((e) => e.savedAt < cutoff);
    if (_cache!.length != before) await _save();
    return _cache!;
  }

  static Future<void> _save() async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(_cache!.map((e) => e.toJson()).toList()),
    );
  }

  /// Aktueller Bestand (ohne abgelaufene Einträge).
  static Future<List<QuarantineEntry>> all() async =>
      List.unmodifiable(await _load());

  static Future<void> add(MimeMessage m, String reason) async {
    final list = await _load();
    final key = SuspicionCheck.keyOf(m);
    if (list.any((e) => e.key == key)) return;
    final from = m.from?.firstOrNull;
    list.insert(
      0,
      QuarantineEntry(
        key: key,
        subject: m.decodeSubject() ?? '',
        fromName: from?.personalName ?? '',
        fromEmail: from?.email ?? '',
        sentAt: m.decodeDate()?.millisecondsSinceEpoch ?? 0,
        reason: reason,
        savedAt: DateTime.now().millisecondsSinceEpoch,
        text: m.decodeTextPlainPart() ?? '',
      ),
    );
    await _save();
  }

  static Future<void> delete(String key) async {
    final list = await _load();
    list.removeWhere((e) => e.key == key);
    await _save();
  }
}
