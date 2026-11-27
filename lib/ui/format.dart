import 'package:flutter/material.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Heute: Uhrzeit. Dieses Jahr: Tag.Monat. Sonst: Tag.Monat.Jahr.
String formatMailDate(DateTime? date) {
  if (date == null) return '';
  final d = date.toLocal();
  final now = DateTime.now();
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  if (sameDay) return '${_two(d.hour)}:${_two(d.minute)}';
  if (d.year == now.year) return '${_two(d.day)}.${_two(d.month)}.';
  return '${_two(d.day)}.${_two(d.month)}.${d.year}';
}

/// Ausgeschriebenes Datum für die Detailansicht.
String formatLongDate(DateTime? date) {
  if (date == null) return '';
  final d = date.toLocal();
  return '${_two(d.day)}.${_two(d.month)}.${d.year}, ${_two(d.hour)}:${_two(d.minute)}';
}

/// Initialen aus Name oder E-Mail-Adresse, z. B. „Anton Lehmann“ → „AL“.
String initialsOf(String text) {
  final clean = text.trim();
  if (clean.isEmpty) return '?';
  final parts = clean
      .split(RegExp(r'[\s@._-]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length >= 2) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return clean[0].toUpperCase();
}

const _palette = <Color>[
  Color(0xFF3B5BDB),
  Color(0xFF0CA678),
  Color(0xFFF08C00),
  Color(0xFFD6336C),
  Color(0xFF7048E8),
  Color(0xFF1098AD),
  Color(0xFFE8590C),
  Color(0xFF5C940D),
];

/// Stabile Farbe pro Absender.
Color avatarColorFor(String seed) {
  var hash = 0;
  for (final unit in seed.toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _palette[hash % _palette.length];
}
