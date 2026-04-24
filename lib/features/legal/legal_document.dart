class LegalDocument {
  final String id;
  final String title;
  final String assetPath;
  final String fileName;

  const LegalDocument({
    required this.id,
    required this.title,
    required this.assetPath,
    required this.fileName,
  });

  static const all = <LegalDocument>[
    LegalDocument(
      id: 'beschlussbuch-2025',
      title: 'Beschlussbuch (Stand 2025)',
      assetPath: 'assets/legal/Beschlussbuch_2025.pdf',
      fileName: 'Beschlussbuch_2025.pdf',
    ),
    LegalDocument(
      id: 'bierkomment',
      title: 'Bierkomment',
      assetPath: 'assets/legal/Bierkomment.pdf',
      fileName: 'Bierkomment.pdf',
    ),
    LegalDocument(
      id: 'quodlibet',
      title: 'Quodlibet',
      assetPath: 'assets/legal/Quodlibet.pdf',
      fileName: 'Quodlibet.pdf',
    ),
    LegalDocument(
      id: 'satzung-2013',
      title: 'Satzung (Stand 2013)',
      assetPath: 'assets/legal/Satzung_2013.pdf',
      fileName: 'Satzung_2013.pdf',
    ),
    LegalDocument(
      id: 'sk-satzung-2022',
      title: 'SK-Satzung (Stand 2022)',
      assetPath: 'assets/legal/SK_Satzung_2022.pdf',
      fileName: 'SK_Satzung_2022.pdf',
    ),
  ];

  static LegalDocument? byId(String id) {
    for (final doc in all) {
      if (doc.id == id) return doc;
    }
    return null;
  }
}