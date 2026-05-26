import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../common/format.dart';
import '../../models/dtos.dart';

class SuggestionPhotosDialog {
  SuggestionPhotosDialog._();

  static Future<void> openGallery({
    required BuildContext context,
    required ApiClient api,
    required String suggestionId,
    required int maxPhotos,
    required bool canDelete,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        child: _SuggestionPhotosGalleryScreen(
          api: api,
          suggestionId: suggestionId,
          maxPhotos: maxPhotos,
          canDelete: canDelete,
        ),
      ),
    );
  }

  static Future<void> openAdd({
    required BuildContext context,
    required ApiClient api,
    required String suggestionId,
    required int maxPhotos,
    required int currentCount,
  }) {
    final remaining = (maxPhotos - currentCount).clamp(0, maxPhotos);
    final canAdd = remaining > 0;

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _SuggestionPhotosAddSheet(
            api: api,
            suggestionId: suggestionId,
            maxPhotos: maxPhotos,
            currentCount: currentCount,
            canAdd: canAdd,
            remainingSlots: remaining,
          ),
        ),
      ),
    );
  }
}

class _SuggestionPhotosAddSheet extends StatefulWidget {
  final ApiClient api;
  final String suggestionId;
  final int maxPhotos;
  final int currentCount;
  final bool canAdd;
  final int remainingSlots;

  const _SuggestionPhotosAddSheet({
    required this.api,
    required this.suggestionId,
    required this.maxPhotos,
    required this.currentCount,
    required this.canAdd,
    required this.remainingSlots,
  });

  @override
  State<_SuggestionPhotosAddSheet> createState() => _SuggestionPhotosAddSheetState();
}

class _SuggestionPhotosAddSheetState extends State<_SuggestionPhotosAddSheet> {
  bool _busy = false;

  Future<void> _pickAndUpload({required bool fromCamera}) async {
    if (_busy || !widget.canAdd) return;

    try {
      setState(() => _busy = true);

      final allowedSlots = widget.remainingSlots;
      if (allowedSlots <= 0) return;

      if (kIsWeb) {
        final res = await FilePicker.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: true,
        );

        if (res == null || res.files.isEmpty) return;

        final picked = res.files;
        final allowed = picked.take(allowedSlots).toList();
        final rejectedCount = picked.length - allowed.length;

        for (final pf in allowed) {
          final bytes = pf.bytes;
          if (bytes == null) {
            throw Exception('Keine Dateidaten für "${pf.name}" erhalten.');
          }

          await widget.api.uploadSuggestionPhoto(
            suggestionId: widget.suggestionId,
            bytes: bytes,
            filename: pf.name,
          );
        }

        if (!mounted) return;
        final msg = rejectedCount > 0
            ? '${allowed.length} Foto(s) hochgeladen. ($rejectedCount ignoriert, Limit: ${widget.maxPhotos})'
            : '${allowed.length} Foto(s) hochgeladen.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        Navigator.of(context).pop();
        return;
      }

      final picker = ImagePicker();

      final List<XFile> files;
      if (fromCamera) {
        final shot = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
        );
        files = shot == null ? const [] : [shot];
      } else {
        files = await picker.pickMultiImage(imageQuality: 92);
      }

      if (files.isEmpty) return;

      final allowed = files.take(allowedSlots).toList();
      final rejectedCount = files.length - allowed.length;

      for (final f in allowed) {
        await widget.api.uploadSuggestionPhoto(
          suggestionId: widget.suggestionId,
          filePath: f.path,
          filename: f.name,
        );
      }

      if (!mounted) return;
      final msg = rejectedCount > 0
          ? '${allowed.length} Foto(s) hochgeladen. ($rejectedCount ignoriert, Limit: ${widget.maxPhotos})'
          : '${allowed.length} Foto(s) hochgeladen.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb;
    final canAdd = widget.canAdd && !_busy;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.add_photo_alternate_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Fotos hinzufügen',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Chip(label: Text('${widget.currentCount}/${widget.maxPhotos}')),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          widget.canAdd
              ? 'Du kannst noch ${widget.remainingSlots} Foto(s) hochladen.'
              : 'Upload-Limit erreicht (max. ${widget.maxPhotos} Fotos).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          onPressed: canAdd ? () => _pickAndUpload(fromCamera: false) : null,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(isWeb ? 'Bilder auswählen' : 'Aus Galerie auswählen'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: (!canAdd || isWeb) ? null : () => _pickAndUpload(fromCamera: true),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(isWeb ? 'Kamera (nicht im Web)' : 'Mit Kamera aufnehmen'),
        ),
      ],
    );
  }
}

class _SuggestionPhotosGalleryScreen extends StatefulWidget {
  final ApiClient api;
  final String suggestionId;
  final int maxPhotos;
  final bool canDelete;

  const _SuggestionPhotosGalleryScreen({
    required this.api,
    required this.suggestionId,
    required this.maxPhotos,
    required this.canDelete,
  });

  @override
  State<_SuggestionPhotosGalleryScreen> createState() => _SuggestionPhotosGalleryScreenState();
}

class _SuggestionPhotosGalleryScreenState extends State<_SuggestionPhotosGalleryScreen> {
  bool _loading = true;
  bool _busy = false;

  List<FineSuggestionPhotoDto> _photos = const [];
  final Map<String, Uint8List> _bytesById = {};

  int _index = 0;
  late final PageController _page = PageController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.api.listSuggestionPhotos(widget.suggestionId);
      if (!mounted) return;
      setState(() {
        _photos = list;
        _index = 0;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fotos laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uint8List?> _getBytes(FineSuggestionPhotoDto p) async {
    final cached = _bytesById[p.id];
    if (cached != null) return cached;

    try {
      final bytes = await widget.api.downloadSuggestionPhotoBytes(
        suggestionId: widget.suggestionId,
        photoId: p.id,
      );
      _bytesById[p.id] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteCurrent() async {
    if (_busy || _photos.isEmpty || !widget.canDelete) return;

    final p = _photos[_index];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto löschen?'),
        content: Text(p.originalFilename.isEmpty ? 'Wirklich löschen?' : p.originalFilename),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      setState(() => _busy = true);
      await widget.api.deleteSuggestionPhoto(
        suggestionId: widget.suggestionId,
        photoId: p.id,
      );
      _bytesById.remove(p.id);

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto gelöscht.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _photos.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fotos ansehen'),
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(child: Chip(label: Text('$count/${widget.maxPhotos}'))),
            ),
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (widget.canDelete && !_loading && _photos.isNotEmpty)
            IconButton(
              tooltip: 'Löschen',
              onPressed: (_busy || _loading || _photos.isEmpty) ? null : _deleteCurrent,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          IconButton(
            tooltip: 'Schließen',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (count == 0)
          ? const Center(child: Text('Keine Fotos vorhanden.'))
          : Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: _photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (ctx, i) {
                final p = _photos[i];
                return _BigSuggestionPhoto(
                  photo: p,
                  getBytes: () => _getBytes(p),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _photos[_index].originalFilename.isEmpty
                        ? 'Foto'
                        : _photos[_index].originalFilename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  Format.dateTimeShort(_photos[_index].createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 92,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) {
                final p = _photos[i];
                final selected = i == _index;

                return _SuggestionThumb(
                  photo: p,
                  selected: selected,
                  getBytes: () => _getBytes(p),
                  onTap: () {
                    setState(() => _index = i);
                    _page.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BigSuggestionPhoto extends StatelessWidget {
  final FineSuggestionPhotoDto photo;
  final Future<Uint8List?> Function() getBytes;

  const _BigSuggestionPhoto({
    required this.photo,
    required this.getBytes,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: getBytes(),
      builder: (ctx, snap) {
        final bytes = snap.data;

        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (bytes == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Vorschau fehlgeschlagen\n${photo.contentType}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return InteractiveViewer(
          minScale: 0.8,
          maxScale: 6,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        );
      },
    );
  }
}

class _SuggestionThumb extends StatelessWidget {
  final FineSuggestionPhotoDto photo;
  final bool selected;
  final Future<Uint8List?> Function() getBytes;
  final VoidCallback onTap;

  const _SuggestionThumb({
    required this.photo,
    required this.selected,
    required this.getBytes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
        : Border.all(color: Theme.of(context).dividerColor, width: 1);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          border: border,
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FutureBuilder<Uint8List?>(
            future: getBytes(),
            builder: (ctx, snap) {
              final bytes = snap.data;
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              if (bytes == null) {
                return const Center(child: Icon(Icons.broken_image_outlined));
              }
              return Image.memory(bytes, fit: BoxFit.cover);
            },
          ),
        ),
      ),
    );
  }
}
