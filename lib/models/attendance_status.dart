enum AttendanceStatus { going, maybe, notGoing, invited }

extension AttendanceStatusJson on AttendanceStatus {
  static AttendanceStatus? fromJson(String? value) {
    switch (value) {
      case 'going':
        return AttendanceStatus.going;
      case 'maybe':
        return AttendanceStatus.maybe;
      case 'not_going':
        return AttendanceStatus.notGoing;
      case 'invited':
        return AttendanceStatus.invited;
      default:
        return null;
    }
  }

  String get label {
    switch (this) {
      case AttendanceStatus.going:
        return 'Going';
      case AttendanceStatus.maybe:
        return 'Maybe';
      case AttendanceStatus.notGoing:
        return 'Not going';
      case AttendanceStatus.invited:
        return 'Invited';
    }
  }
}
