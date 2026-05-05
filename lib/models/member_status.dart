enum MemberStatus {
  fux,
  schuelerfux,
  konkneipant,
  bursch,
  inaktiver,
  philister,
  unknown,
}

class MemberStatuses {
  static const String fux = 'FUX';
  static const String schuelerfux = 'SCHUELERFUX';
  static const String konkneipant = 'KONKNEIPANT';
  static const String bursch = 'BURSCH';
  static const String inaktiver = 'INAKTIVER';
  static const String philister = 'PHILISTER';

  static const String defaultBackendValue = bursch;

  static const List<String> backendValues = [
    fux,
    schuelerfux,
    konkneipant,
    bursch,
    inaktiver,
    philister,
  ];

  static MemberStatus parse(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case fux:
        return MemberStatus.fux;
      case schuelerfux:
        return MemberStatus.schuelerfux;
      case konkneipant:
        return MemberStatus.konkneipant;
      case bursch:
        return MemberStatus.bursch;
      case inaktiver:
        return MemberStatus.inaktiver;
      case philister:
        return MemberStatus.philister;
      default:
        return MemberStatus.unknown;
    }
  }

  static String backendValue(MemberStatus status) {
    switch (status) {
      case MemberStatus.fux:
        return fux;
      case MemberStatus.schuelerfux:
        return schuelerfux;
      case MemberStatus.konkneipant:
        return konkneipant;
      case MemberStatus.bursch:
        return bursch;
      case MemberStatus.inaktiver:
        return inaktiver;
      case MemberStatus.philister:
        return philister;
      case MemberStatus.unknown:
        return defaultBackendValue;
    }
  }

  static String label(String? raw) {
    switch (parse(raw)) {
      case MemberStatus.fux:
        return 'Fux';
      case MemberStatus.schuelerfux:
        return 'Schüler-/Militärfux';
      case MemberStatus.konkneipant:
        return 'Konkneipant';
      case MemberStatus.bursch:
        return 'Aktiver';
      case MemberStatus.inaktiver:
        return 'Inaktiver';
      case MemberStatus.philister:
        return 'Philister';
      case MemberStatus.unknown:
        final value = (raw ?? '').trim();
        return value.isEmpty ? 'Unbekannt' : value;
    }
  }

  static bool isPhilister(String? raw) => parse(raw) == MemberStatus.philister;

  static bool isAktivitas(String? raw) {
    switch (parse(raw)) {
      case MemberStatus.fux:
      case MemberStatus.schuelerfux:
      case MemberStatus.konkneipant:
      case MemberStatus.bursch:
      case MemberStatus.inaktiver:
        return true;
      case MemberStatus.philister:
      case MemberStatus.unknown:
        return false;
    }
  }

  static String pickerDisplayName({
    required String displayName,
    required String? memberStatus,
  }) {
    final name = displayName.trim().isEmpty
        ? 'Ohne Anzeigename'
        : displayName.trim();

    if (isPhilister(memberStatus)) return 'Ph. $name';
    return name;
  }

  static bool shouldShowInPicker({
    required String? memberStatus,
    required bool hidePhilister,
    bool forceShow = false,
  }) {
    if (forceShow) return true;
    if (!hidePhilister) return true;
    return !isPhilister(memberStatus);
  }
}