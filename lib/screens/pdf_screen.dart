import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Integrierter PDF-Reader für Anhänge. Die Daten liegen bereits im Speicher,
/// es wird nichts auf die Festplatte geschrieben.
class PdfScreen extends StatelessWidget {
  const PdfScreen({super.key, required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfViewer.data(
        bytes,
        sourceName: title,
        params: const PdfViewerParams(),
      ),
    );
  }
}
