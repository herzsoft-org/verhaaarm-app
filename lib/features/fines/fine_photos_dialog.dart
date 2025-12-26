import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../models/dtos.dart';

class FinePhotosDialog extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String fineId;

  const FinePhotosDialog({
    super.key,
    required this.api,
    required this.authStore,
    required this.fineId,
  });

  @override
  State<FinePhotosDialog> createState() => _FinePhotosDialogState();

  static Future<void> open({
    required BuildContext context,
    required ApiClient api,
    required AuthStore authStore,
    required String fineId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => FinePhotosDialog(api: api, authStore: authStore, fineId: fineId),
    );
  }
}

class _FinePhotosDialogState extends State<FinePhotosDialog> {
  bool _loading = true;
  bool _busy = false;

  List<FinePhotoDto> _photos = const [];

  // simple in-memory thumbnail/full bytes cache
  final Map<String, Uint8List> _bytesByPhotoId = {};

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
      setState(() => _photos = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fotos laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canManage {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    return Roles.canManageFines(roles);
  }

  Future<Uint8List?> _getBytes(FinePhotoDto p) async {
    final cached = _bytesByPhotoId[p.id];
    if (cached != null) return cached;

    try {
      final bytes = await widget.api.downloadFinePhotoBytes(
        fineId: widget.fineId,
        photoId: p.id,
      );
      _bytesByPhotoId[p.id] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickAndUpload({required bool fromCamera}) async {
    if (_busy) return;

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

      for (final f in files) {
        // On web, path may not exist for MultipartFile.fromFile.
        // image_picker_web typically provides a pseudo-path; if this breaks on web,
        // tell me and I’ll switch this to MultipartFile.fromBytes for web.
        await widget.api.uploadFinePhoto(
          fineId: widget.fineId,
          filePath: f.path,
          filename: f.name,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${files.length} Foto(s) hochgeladen.')),
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

  Future<void> _deletePhoto(FinePhotoDto p) async {
    if (!_canManage || _busy) return;

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
      _bytesByPhotoId.remove(p.id);
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

  void _openFull(FinePhotoDto p, Uint8List bytes) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FinePhotoFullScreen(
          title: p.originalFilename.isEmpty ? 'Foto' : p.originalFilename,
          bytes: bytes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb;

    return AlertDialog(
      title: const Text('Fotos'),
      content: SizedBox(
        width: 640,
        child: _loading
            ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            : _photos.isEmpty
            ? const SizedBox(height: 140, child: Center(child: Text('Keine Fotos.')))
            : SizedBox(
          height: 420,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _photos.length,
            itemBuilder: (ctx, i) {
              final p = _photos[i];
              return _PhotoTile(
                photo: p,
                busy: _busy,
                canDelete: _canManage,
                getBytes: () => _getBytes(p),
                onOpen: (bytes) => _openFull(p, bytes),
                onDelete: () => _deletePhoto(p),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
        // Gallery upload (multi)
        FilledButton.tonal(
          onPressed: _busy ? null : () => _pickAndUpload(fromCamera: false),
          child: const Text('Aus Galerie'),
        ),
        // Camera upload (single)
        FilledButton(
          onPressed: (_busy || isWeb) ? null : () => _pickAndUpload(fromCamera: true),
          child: const Text('Kamera'),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatefulWidget {
  final FinePhotoDto photo;
  final bool busy;
  final bool canDelete;
  final Future<Uint8List?> Function() getBytes;
  final void Function(Uint8List bytes) onOpen;
  final VoidCallback onDelete;

  const _PhotoTile({
    required this.photo,
    required this.busy,
    required this.canDelete,
    required this.getBytes,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  Future<void> _preload() async {
    setState(() => _loading = true);
    final b = await widget.getBytes();
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photo;

    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: (_bytes == null || widget.busy) ? null : () => widget.onOpen(_bytes!),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_bytes == null)
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Laden fehlgeschlagen\n${p.contentType}\n${(p.sizeBytes / 1024).round()} KB',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
                  : Image.memory(_bytes!, fit: BoxFit.cover),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  p.originalFilename.isEmpty ? 'Foto' : p.originalFilename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Erstellt: ${Format.dateTimeShort(p.createdAt)}',
                    child: const Icon(Icons.info_outline_rounded, size: 18, color: Colors.white),
                  ),
                  if (widget.canDelete) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Löschen',
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                      onPressed: widget.busy ? null : widget.onDelete,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinePhotoFullScreen extends StatelessWidget {
  final String title;
  final Uint8List bytes;

  const _FinePhotoFullScreen({
    required this.title,
    required this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: Image.memory(bytes),
        ),
      ),
    );
  }
}
