/// Preserve today's intake status when unchanged reminder times are edited.
List<bool> reconcileIntakeStatus({
  required List<DateTime> previousTimes,
  required List<bool> previousStatus,
  required List<DateTime> nextTimes,
}) => nextTimes.map((time) {
  final index = previousTimes.indexWhere(
    (previous) => previous.hour == time.hour && previous.minute == time.minute,
  );
  return index >= 0 && index < previousStatus.length
      ? previousStatus[index]
      : false;
}).toList();
