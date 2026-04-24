import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../common/widgets/app_scaffold.dart';
import 'legal_document.dart';

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

  int _currentPage = 1;
  int? _pagesCount;

  bool get _hasPages => (_pagesCount ?? 0) > 0;

  bool get _canGoBack => _hasPages && _currentPage > 1;

  bool get _canGoForward => _hasPages && _currentPage < (_pagesCount ?? 1);

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

  Future<void> _goToPage(int page) async {
    final pagesCount = _pagesCount;
    if (pagesCount == null) return;

    final safePage = page.clamp(1, pagesCount).toInt();

    await _controller.animateToPage(
      pageNumber: safePage,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _previousPage() async {
    if (!_canGoBack) return;

    await _controller.previousPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _nextPage() async {
    if (!_canGoForward) return;

    await _controller.nextPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openJumpToPageDialog() async {
    final pagesCount = _pagesCount;
    if (pagesCount == null) return;

    final controller = TextEditingController(text: _currentPage.toString());

    final page = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Zu Seite springen'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Seite',
              helperText: '1 bis $pagesCount',
            ),
            onSubmitted: (_) {
              final value = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                Navigator.pop(ctx, value);
              },
              child: const Text('Springen'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (page == null) return;
    await _goToPage(page);
  }

  @override
  Widget build(BuildContext context) {
    final pagesCount = _pagesCount;

    return AppScaffold(
      title: widget.document.title,
      body: Column(
        children: [
          Material(
            elevation: 1,
            child: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Erste Seite',
                      onPressed: _canGoBack ? () => _goToPage(1) : null,
                      icon: const Icon(Icons.first_page_rounded),
                    ),
                    IconButton(
                      tooltip: 'Vorherige Seite',
                      onPressed: _canGoBack ? _previousPage : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _hasPages ? _openJumpToPageDialog : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            pagesCount == null
                                ? 'PDF wird geladen…'
                                : 'Seite $_currentPage / $pagesCount',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Nächste Seite',
                      onPressed: _canGoForward ? _nextPage : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    IconButton(
                      tooltip: 'Letzte Seite',
                      onPressed: _canGoForward && pagesCount != null
                          ? () => _goToPage(pagesCount)
                          : null,
                      icon: const Icon(Icons.last_page_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: PdfViewPinch(
              controller: _controller,
              onDocumentLoaded: (document) {
                setState(() => _pagesCount = document.pagesCount);
              },
              onPageChanged: (page) {
                setState(() => _currentPage = page);
              },
              onDocumentError: (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PDF konnte nicht geladen werden.'),
                  ),
                );
              },
              builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                documentLoaderBuilder: (_) => const Center(
                  child: CircularProgressIndicator(),
                ),
                pageLoaderBuilder: (_) => const Center(
                  child: CircularProgressIndicator(),
                ),
                errorBuilder: (_, __) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('PDF konnte nicht angezeigt werden.'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}