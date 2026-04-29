enum MemberStatus {
  fux,
  bursch,
  inaktiver,
  philister,
}

class MemberStatuses {
  static const String fux = 'FUX';
  static const String bursch = 'BURSCH';
  static const String inaktiver = 'INAKTIVER';
  static const String philister = 'PHILISTER';

  static const String defaultBackendValue = bursch;

  static const List<String> backendValues = [
    fux,
    bursch,
    inaktiver,
    philister,
  ];

  static MemberStatus parse(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case fux:
        return MemberStatus.fux;
      case inaktiver:
        return MemberStatus.inaktiver;
      case philister:
        return MemberStatus.philister;
      case bursch:
      default:
        return MemberStatus.bursch;
    }
  }

  static String backendValue(MemberStatus status) {
    switch (status) {
      case MemberStatus.fux:
        return fux;
      case MemberStatus.bursch:
        return bursch;
      case MemberStatus.inaktiver:
        return inaktiver;
      case MemberStatus.philister:
        return philister;
    }
  }

  static String label(String? raw) {
    switch (parse(raw)) {
      case MemberStatus.fux:
        return 'Fux';
      case MemberStatus.bursch:
        return 'Bursch';
      case MemberStatus.inaktiver:
        return 'Inaktiver';
      case MemberStatus.philister:
        return 'Philister';
    }
  }

  static bool isPhilister(String? raw) => parse(raw) == MemberStatus.philister;

  static bool isAktivitas(String? raw) => !isPhilister(raw);

  static String pickerDisplayName({
    required String displayName,
    required String? memberStatus,
  }) {
    if (isPhilister(memberStatus)) return 'Ph. $displayName';
    return displayName;
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