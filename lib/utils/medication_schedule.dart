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

/// Stable across process restarts; reserve 64 IDs for each medication slot.
int medicationNotificationId(String id, int slot) {
  var hash = 2166136261;
  for (final byte in '$id:$slot'.codeUnits) {
    hash = ((hash ^ byte) * 16777619) & 0xffffffff;
  }
  return (hash & 0x01ffffff) * 64;
}

/// Includes old prescription payloads, regardless of the ID or reminder count.
bool belongsToMedication(String? payload, String id, {String? legacyName}) {
  final parts = payload?.split('|') ?? [];
  if (parts.length < 2 || !['medication', 'missed_dose'].contains(parts[0]))
    return false;
  return parts[1] == id ||
      (legacyName != null &&
          RegExp(
            '^${RegExp.escape(legacyName)}_[0-9]+'
            r'$',
          ).hasMatch(parts[1]));
}
