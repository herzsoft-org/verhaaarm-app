import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../models/dtos.dart';

class FinePhotosDialog {
  FinePhotosDialog._();

  static const int _defaultMaxPhotos = 5;

  static Future<void> openGallery({
    required BuildContext context,
    required ApiClient api,
    required AuthStore authStore,
    required String fineId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        child: _FinePhotosGalleryScreen(
          api: api,
          authStore: authStore,
          fineId: fineId,
          maxPhotos: _defaultMaxPhotos,
        ),
      ),
    );
  }

  static Future<void> openAdd({
    required BuildContext context,
    required ApiClient api,
    required AuthStore authStore,
    required String fineId,
    int maxPhotos = _defaultMaxPhotos,
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
          child: _FinePhotosAddSheet(
            api: api,
            authStore: authStore,
            fineId: fineId,
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

class _FinePhotosAddSheet extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String fineId;

  final int maxPhotos;
  final int currentCount;
  final bool canAdd;
  final int remainingSlots;

  const _FinePhotosAddSheet({
    required this.api,
    required this.authStore,
    required this.fineId,
    required this.maxPhotos,
    required this.currentCount,
    required this.canAdd,
    required this.remainingSlots,
  });

  @override
  State<_FinePhotosAddSheet> createState() => _FinePhotosAddSheetState();
}

class _FinePhotosAddSheetState extends State<_FinePhotosAddSheet> {
  bool _busy = false;

  Future<void> _pickAndUpload({required bool fromCamera}) async {
    if (_busy) return;
    if (!widget.canAdd) return;

    final picker = ImagePicker();

    try {
      setState(() => _busy = true);

      final List<XFile> files;
      if (fromCamera) {
        final shot = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
        );
        files = shot == null ? const [] : [shot];
      } else {
        final picked = await picker.pickMultiImage(imageQuality: 92);
        files = picked;
      }

      if (files.isEmpty) return;

      final allowed = files.take(widget.remainingSlots).toList();
      final rejectedCount = files.length - allowed.length;

      if (allowed.isEmpty) return;

      for (final f in allowed) {
        await widget.api.uploadFinePhoto(
          fineId: widget.fineId,
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
          label: const Text('Aus Galerie auswählen'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: (!canAdd || isWeb) ? null : () => _pickAndUpload(fromCamera: true),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(isWeb ? 'Kamera (nicht im Web)' : 'Mit Kamera aufnehmen'),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _FinePhotosGalleryScreen extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String fineId;
  final int maxPhotos;

  const _FinePhotosGalleryScreen({
    required this.api,
    required this.authStore,
    required this.fineId,
    required this.maxPhotos,
  });

  @override
  State<_FinePhotosGalleryScreen> createState() => _FinePhotosGalleryScreenState();
}

class _FinePhotosGalleryScreenState extends State<_FinePhotosGalleryScreen> {
  bool _loading = true;
  bool _busy = false;

  List<FinePhotoDto> _photos = const [];

  // bytes cache
  final Map<String, Uint8List> _bytesById = {};

  int _index = 0;
  late final PageController _page = PageController();

  bool get _canDelete {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    return Roles.canManageFines(roles);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.api.listFinePhotos(widget.fineId);
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

  Future<Uint8List?> _getBytes(FinePhotoDto p) async {
    final cached = _bytesById[p.id];
    if (cached != null) return cached;

    try {
      final bytes = await widget.api.downloadFinePhotoBytes(
        fineId: widget.fineId,
        photoId: p.id,
      );
      _bytesById[p.id] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteCurrent() async {
    if (!_canDelete || _busy || _photos.isEmpty) return;

    final p = _photos[_index];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto löschen?'),
        content: Text(p.originalFilename.isEmpty ? 'Wirklich löschen?' : p.originalFilename),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      setState(() => _busy = true);
      await widget.api.deleteFinePhoto(fineId: widget.fineId, photoId: p.id);
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
          if (_canDelete)
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
          // Big preview (swipe)
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: _photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (ctx, i) {
                final p = _photos[i];
                return _BigPhoto(
                  photo: p,
                  getBytes: () => _getBytes(p),
                );
              },
            ),
          ),

          // Filename + timestamp
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (_photos[_index].originalFilename.isEmpty)
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

          // Thumbnails row (horizontal)
          SizedBox(
            height: 92,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) {
                final p = _photos[i];
                final selected = i == _index;

                return _Thumb(
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

class _BigPhoto extends StatelessWidget {
  final FinePhotoDto photo;
  final Future<Uint8List?> Function() getBytes;

  const _BigPhoto({
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

class _Thumb extends StatelessWidget {
  final FinePhotoDto photo;
  final bool selected;
  final Future<Uint8List?> Function() getBytes;
  final VoidCallback onTap;

  const _Thumb({
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
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
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
