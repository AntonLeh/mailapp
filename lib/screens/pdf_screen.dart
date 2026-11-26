import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// Integrierter PDF-Reader für Anhänge. Die Daten liegen bereits im Speicher,
/// es wird nichts auf die Festplatte geschrieben.
class PdfScreen extends StatefulWidget {
  const PdfScreen({super.key, required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  late final PdfController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfController(
      document: PdfDocument.openData(widget.bytes),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Vorherige Seite',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _controller.previousPage(
              curve: Curves.ease,
              duration: const Duration(milliseconds: 200),
            ),
          ),
          IconButton(
            tooltip: 'Nächste Seite',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _controller.nextPage(
              curve: Curves.ease,
              duration: const Duration(milliseconds: 200),
            ),
          ),
        ],
      ),
      body: PdfView(controller: _controller),
    );
  }
}
