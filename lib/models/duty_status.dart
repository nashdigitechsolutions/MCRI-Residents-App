enum DutyStatus { pending, inProgress, completed, missed }

extension DutyStatusJson on DutyStatus {
  static DutyStatus fromJson(String value) {
    switch (value) {
      case 'pending':
        return DutyStatus.pending;
      case 'in_progress':
        return DutyStatus.inProgress;
      case 'completed':
        return DutyStatus.completed;
      case 'missed':
        return DutyStatus.missed;
      default:
        return DutyStatus.pending;
    }
  }

  String get label {
    switch (this) {
      case DutyStatus.pending:
        return 'Pending';
      case DutyStatus.inProgress:
        return 'In progress';
      case DutyStatus.completed:
        return 'Completed';
      case DutyStatus.missed:
        return 'Missed';
    }
  }
}
