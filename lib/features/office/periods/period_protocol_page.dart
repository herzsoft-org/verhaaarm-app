import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart';

import '../../../api/api_client.dart';
import '../../../common/format.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';
import '../../legal/legal_document_save_result.dart';
import 'period_protocol_viewer_platform.dart';

class PeriodProtocolPage extends StatefulWidget {
  final ApiClient api;
  final String periodId;
  final ConventPeriodDto? initialPeriod;

  const PeriodProtocolPage({
    super.key,
    required this.api,
    required this.periodId,
    this.initialPeriod,
  });

  @override
  State<PeriodProtocolPage> createState() => _PeriodProtocolPageState();
}

class _PeriodProtocolPageState extends State<PeriodProtocolPage> {
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;

  ConventPeriodDto? _period;
  ConventPeriodProtocolDto? _protocol;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final period = await widget.api.getPeriod(widget.periodId);

      ConventPeriodProtocolDto? protocol;
      if (period.hasProtocolPdf) {
        try {
          protocol = await widget.api.getPeriodProtocol(widget.periodId);
        } on DioException catch (e) {
          if (e.response?.statusCode != 404) rethrow;
          protocol = null;
        }
      }

      if (!mounted) return;
      setState(() {
        _period = period;
        _protocol = protocol;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Protokoll konnte nicht geladen werden: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _periodTitle {
    final p = _period;
    if (p == null) return 'Conventsprotokoll';

    return '${p.semester} · ${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}';
  }

  bool get _hasProtocol => _protocol != null;

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';

    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';

    final mib = kib / 1024;
    if (mib < 1024) return '${mib.toStringAsFixed(1)} MiB';

    final gib = mib / 1024;
    return '${gib.toStringAsFixed(1)} GiB';
  }

  String _downloadFileName() {
    final name = _protocol?.originalFilename.trim();
    if (name != null && name.isNotEmpty) return name;

    final p = _period;
    if (p == null) return 'conventsprotokoll.pdf';

    final safeSemester = p.semester
        .replaceAll('/', '-')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

    return 'conventsprotokoll_$safeSemester.pdf';
  }

  Future<void> _pickAndUploadPdf() async {
    if (_busy) return;

    final replacing = _protocol != null;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: kIsWeb,
      allowMultiple: false,
    );

    if (!mounted || result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final filename = file.name.trim().isEmpty ? 'protokoll.pdf' : file.name.trim();

    if (!filename.toLowerCase().endsWith('.pdf')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte eine PDF-Datei auswählen.')),
      );
      return;
    }

    final hasBytes = file.bytes != null;
    final hasPath = file.path != null && file.path!.trim().isNotEmpty;

    if (!hasBytes && !hasPath) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datei konnte nicht gelesen werden.')),
      );
      return;
    }

    setState(() => _busy = true);

    try {
      final uploaded = await widget.api.uploadPeriodProtocol(
        periodId: widget.periodId,
        filePath: hasBytes ? null : file.path,
        bytes: hasBytes ? file.bytes : null,
        filename: filename,
        contentType: 'application/pdf',
      );

      if (!mounted) return;
      setState(() {
        _protocol = uploaded;
        _changed = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            replacing
                ? 'Protokoll wurde ersetzt.'
                : 'Protokoll wurde hochgeladen.',
          ),
        ),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewPdf() async {
    if (_busy || !_hasProtocol) return;

    setState(() => _busy = true);

    try {
      final bytes = await widget.api.getPeriodProtocolFileBytes(widget.periodId);

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PeriodProtocolPdfViewerPage(
            title: 'Conventsprotokoll',
            subtitle: _periodTitle,
            fileName: _downloadFileName(),
            bytes: bytes,
            onDownload: () => _saveBytes(bytes),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF konnte nicht geöffnet werden: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<LegalDocumentSaveResult> _saveBytes(Uint8List bytes) async {
    final fileName = _downloadFileName();
    final baseName = fileName.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );

    await FileSaver.instance.saveAs(
      name: baseName,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );

    return LegalDocumentSaveResult.saved;
  }

  Future<void> _downloadPdf() async {
    if (_busy || !_hasProtocol) return;

    setState(() => _busy = true);

    try {
      final bytes = await widget.api.downloadPeriodProtocolBytes(widget.periodId);
      final result = await _saveBytes(bytes);

      if (!mounted) return;

      final message = switch (result) {
        LegalDocumentSaveResult.saved => 'Protokoll wird heruntergeladen.',
        LegalDocumentSaveResult.opened => 'Protokoll wurde im Browser geöffnet.',
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePdf() async {
    if (_busy || !_hasProtocol) return;

    final nav = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Protokoll löschen?'),
          content: Text(
            'Willst du das Conventsprotokoll wirklich löschen?\n\n'
                '$_periodTitle',
          ),
          actions: [
            TextButton(
              onPressed: () => nav.pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => nav.pop(true),
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;

    setState(() => _busy = true);

    try {
      await widget.api.deletePeriodProtocol(widget.periodId);

      if (!mounted) return;
      setState(() {
        _protocol = null;
        _changed = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Protokoll wurde gelöscht.')),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _close() {
    context.pop(_changed);
  }

  Widget _buildHeaderCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final protocol = _protocol;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: protocol == null
                    ? cs.surfaceContainerHighest
                    : cs.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                protocol == null
                    ? Icons.upload_file_rounded
                    : Icons.picture_as_pdf_rounded,
                color: protocol == null
                    ? cs.onSurfaceVariant
                    : cs.onPrimaryContainer,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Conventsprotokoll',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _periodTitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: protocol == null
                          ? cs.surfaceContainerHighest
                          : cs.primaryContainer.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      protocol == null ? 'Kein PDF hinterlegt' : 'PDF vorhanden',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: protocol == null
                            ? cs.onSurfaceVariant
                            : cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final protocol = _protocol;
    if (protocol == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Für diese Conventsperiode wurde noch kein Protokoll hochgeladen.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Datei', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Text(
              protocol.originalFilename,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 6),
            Text(
              _formatBytes(protocol.sizeBytes),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Aktualisiert: ${Format.dateTimeShort(protocol.updatedAt.toIso8601String())}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryAction(BuildContext context) {
    if (_protocol == null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy ? null : _pickAndUploadPdf,
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('PDF hochladen'),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _busy ? null : _viewPdf,
        icon: const Icon(Icons.visibility_rounded),
        label: const Text('Protokoll lesen'),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        titleAlignment: ListTileTitleAlignment.center,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    if (_protocol == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        _buildActionTile(
          icon: Icons.download_rounded,
          title: 'Herunterladen',
          subtitle: 'PDF-Datei speichern',
          onTap: _busy ? null : _downloadPdf,
        ),
        const SizedBox(height: 8),
        _buildActionTile(
          icon: Icons.upload_file_rounded,
          title: 'Ersetzen',
          subtitle: 'Eine neue PDF-Datei hochladen',
          onTap: _busy ? null : _pickAndUploadPdf,
        ),
        const SizedBox(height: 8),
        _buildActionTile(
          icon: Icons.delete_outline_rounded,
          title: 'Löschen',
          subtitle: 'PDF aus dieser Periode entfernen',
          onTap: _busy ? null : _deletePdf,
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _buildHeaderCard(context),
        const SizedBox(height: 12),
        _buildInfoCard(context),
        const SizedBox(height: 16),
        _buildPrimaryAction(context),
        const SizedBox(height: 16),
        _buildActions(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _close();
      },
      child: AppScaffold(
        title: 'Conventsprotokoll',
        showNotificationButton: false,
        showProfileButton: false,
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        body: Stack(
          children: [
            _buildContent(context),
            if (_busy && !_loading)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.45),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodProtocolPdfViewerPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final String fileName;
  final Uint8List bytes;
  final Future<LegalDocumentSaveResult> Function() onDownload;

  const _PeriodProtocolPdfViewerPage({
    required this.title,
    required this.subtitle,
    required this.fileName,
    required this.bytes,
    required this.onDownload,
  });

  @override
  State<_PeriodProtocolPdfViewerPage> createState() =>
      _PeriodProtocolPdfViewerPageState();
}

class _PeriodProtocolPdfViewerPageState
    extends State<_PeriodProtocolPdfViewerPage> {
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
      document: PdfDocument.openData(widget.bytes),
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
      final result = await widget.onDownload();

      if (!mounted) return;

      final message = switch (result) {
        LegalDocumentSaveResult.saved => 'Protokoll wird heruntergeladen.',
        LegalDocumentSaveResult.opened => 'Protokoll wurde im Browser geöffnet.',
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Protokoll konnte nicht heruntergeladen werden.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openExternally() {
    openPeriodProtocolExternally(
      bytes: widget.bytes,
      fileName: widget.fileName,
    );
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
      ),
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
                      widget.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
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
                        onPressed: _openExternally,
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
    if (shouldUseProtocolBrowserPdfFallback) {
      return _buildMobileWebFallback(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
      ),
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
