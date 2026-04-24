import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../common/widgets/app_scaffold.dart';
import 'legal_document.dart';
import 'legal_document_saver.dart';

class LegalDocumentsPage extends StatefulWidget {
  const LegalDocumentsPage({super.key});

  @override
  State<LegalDocumentsPage> createState() => _LegalDocumentsPageState();
}

class _LegalDocumentsPageState extends State<LegalDocumentsPage> {
  final Set<String> _savingIds = <String>{};

  Future<void> _saveDocument(LegalDocument doc) async {
    if (_savingIds.contains(doc.id)) return;

    setState(() => _savingIds.add(doc.id));

    try {
      final data = await rootBundle.load(doc.assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      await saveLegalDocument(
        fileName: doc.fileName,
        assetPath: doc.assetPath,
        bytes: Uint8List.fromList(bytes),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${doc.title} wurde geöffnet oder gespeichert.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${doc.title} konnte nicht heruntergeladen werden.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingIds.remove(doc.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Rechtsgrundlagen',
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: LegalDocument.all.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final doc = LegalDocument.all[index];
          final saving = _savingIds.contains(doc.id);

          return Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: Text(doc.title),
              onTap: () => context.push('/legal-documents/${doc.id}'),
              trailing: IconButton(
                tooltip: 'Herunterladen',
                onPressed: saving ? null : () => _saveDocument(doc),
                icon: saving
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.download_rounded),
              ),
            ),
          );
        },
      ),
    );
  }
}