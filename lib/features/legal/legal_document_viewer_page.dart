import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../../common/widgets/app_scaffold.dart';
import 'legal_document.dart';
import 'legal_document_save_result.dart';
import 'legal_document_saver.dart';
import 'legal_document_viewer_platform.dart';

class LegalDocumentViewerPage extends StatefulWidget {
  final LegalDocument document;

  const LegalDocumentViewerPage({
    super.key,
    required this.document,
  });

  @override
  State<LegalDocumentViewerPage> createState() =>
      _LegalDocumentViewerPageState();
}

class _LegalDocumentViewerPageState extends State<LegalDocumentViewerPage> {
  late final PdfControllerPinch _controller;

  bool _loading = true;
  bool _failed = false;
  bool _saving = false;

  int _currentPage = 1;
  int _pagesCount = 0;

  @override
  void initState() {
    super.initState();

    _controller = PdfControllerPinch(
      document: PdfDocument.openAsset(widget.document.assetPath),
      initialPage: 1,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveDocument() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final data = await rootBundle.load(widget.document.assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      final result = await saveLegalDocument(
        fileName: widget.document.fileName,
        assetPath: widget.document.assetPath,
        bytes: Uint8List.fromList(bytes),
      );

      if (!mounted) return;

      final message = switch (result) {
        LegalDocumentSaveResult.saved =>
        '${widget.document.title} wird heruntergeladen.',
        LegalDocumentSaveResult.opened =>
        '${widget.document.title} wurde im Browser geöffnet.',
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.document.title} konnte nicht heruntergeladen werden.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _goToPage(int page) async {
    if (_pagesCount <= 0) return;

    final safePage = page.clamp(1, _pagesCount);

    await _controller.animateToPage(
      pageNumber: safePage,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goToPreviousPage() async {
    if (_currentPage <= 1) return;

    await _controller.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goToNextPage() async {
    if (_pagesCount <= 0 || _currentPage >= _pagesCount) return;

    await _controller.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildMobileWebFallback(BuildContext context) {
    return AppScaffold(
      title: widget.document.title,
      actions: [
        IconButton(
          tooltip: 'Herunterladen',
          onPressed: _saving ? null : _saveDocument,
          icon: _saving
              ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.download_rounded),
        ),
      ],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.document.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Die PDF-Vorschau ist im mobilen Browser nicht zuverlässig. '
                          'Öffne die Datei direkt im Browser oder lade sie herunter.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          openLegalDocumentExternally(
                            widget.document.assetPath,
                          );
                        },
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Im Browser öffnen'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _saveDocument,
                        icon: _saving
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(Icons.download_rounded),
                        label: const Text('Herunterladen'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageControls(BuildContext context) {
    final canGoBack = !_loading && !_failed && _currentPage > 1;
    final canGoForward =
        !_loading && !_failed && _pagesCount > 0 && _currentPage < _pagesCount;

    final pageText = _loading
        ? 'PDF wird geladen...'
        : _failed
        ? 'PDF konnte nicht geladen werden'
        : '$_currentPage / $_pagesCount';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Erste Seite',
              onPressed: canGoBack ? () => _goToPage(1) : null,
              icon: const Icon(Icons.first_page_rounded),
            ),
            IconButton(
              tooltip: 'Vorherige Seite',
              onPressed: canGoBack ? _goToPreviousPage : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pageText,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Nächste Seite',
              onPressed: canGoForward ? _goToNextPage : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            IconButton(
              tooltip: 'Letzte Seite',
              onPressed: canGoForward ? () => _goToPage(_pagesCount) : null,
              icon: const Icon(Icons.last_page_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfBody(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Text('PDF konnte nicht angezeigt werden.'),
      );
    }

    return PdfViewPinch(
      controller: _controller,
      onDocumentLoaded: (document) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _failed = false;
          _pagesCount = document.pagesCount;
          _currentPage = 1;
        });
      },
      onDocumentError: (_) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _failed = true;
          _pagesCount = 0;
          _currentPage = 1;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF konnte nicht geladen werden.')),
        );
      },
      onPageChanged: (page) {
        if (!mounted) return;

        setState(() {
          _currentPage = page;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (shouldUseBrowserPdfFallback) {
      return _buildMobileWebFallback(context);
    }

    return AppScaffold(
      title: widget.document.title,
      actions: [
        IconButton(
          tooltip: 'Herunterladen',
          onPressed: _saving ? null : _saveDocument,
          icon: _saving
              ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.download_rounded),
        ),
      ],
      body: Column(
        children: [
          _buildPageControls(context),
          Expanded(
            child: _buildPdfBody(context),
          ),
        ],
      ),
    );
  }
}