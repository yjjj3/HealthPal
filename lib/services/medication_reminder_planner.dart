import '../models/medication_model.dart';
import '../utils/medication_regimen.dart';
import '../utils/medication_schedule.dart';

class PlannedMedicationReminder {
  PlannedMedicationReminder({
    required this.medication,
    required this.slot,
    required this.due,
    required this.at,
    this.repeat = 0,
  });
  final medicine medication;
  final int slot;
  final DateTime due;
  final DateTime at;
  final int repeat;
  String get key => occurrenceKey(medication.medicine_id!, due);
  String get payload =>
      '${repeat == 0 ? 'medication' : 'missed_dose'}|${medication.medicine_id}|${due.toIso8601String()}|$repeat';
}

class MedicationReminderPlan {
  MedicationReminderPlan(
    this.requests,
    this.issues,
    this.omitted,
    this.until,
    this.firstOmitted,
  );
  final List<PlannedMedicationReminder> requests;
  final List<String> issues;
  final int omitted;
  final DateTime until;
  final DateTime? firstOmitted;
  DateTime? get lastScheduled => requests.isEmpty ? null : requests.last.at;
}

/// A bounded rolling calendar, NOT an indefinite background job. Already
/// queued dates can fire without opening the medication screen or Dart process.
MedicationReminderPlan planMedicationReminders(
  List<medicine> medications, {
  required DateTime now,
  required int capacity,
  int horizonDays = 30,
  bool missedEnabled = true,
  int missedInterval = 30,
  int missedCount = 2,
}) {
  final until = DateTime(now.year, now.month, now.day + horizonDays);
  final requests = <PlannedMedicationReminder>[];
  final issues = <String>[];
  final repeats = missedEnabled
      ? (missedCount == 0 ? 50 : missedCount.clamp(0, 50))
      : 0;
  for (final med in medications) {
    if (!med.reminderEnabled) continue;
    if (med.medicine_id == null) {
      issues.add('藥品缺少文件 ID');
      continue;
    }
    try {
      final regimen = MedicationRegimen(med);
      final from = calendarDay(now);
      final occurrences = regimen.occurrences(from, until).toList()..sort();
      for (var n = 0; n < occurrences.length; n++) {
        final due = occurrences[n];
        final slot = med.times_of_day_list.indexWhere(
          (t) => t.hour == due.hour && t.minute == due.minute,
        );
        final takenToday =
            calendarDay(due) == calendarDay(now) &&
            calendarDay(med.lastUpdated) == calendarDay(now) &&
            slot < med.times_status.length &&
            med.times_status[slot];
        if (takenToday) continue;
        if (due.isAfter(now))
          requests.add(
            PlannedMedicationReminder(
              medication: med,
              slot: slot,
              due: due,
              at: due,
            ),
          );
        // A reminder belongs to this occurrence only: never carry it into the
        // next dose/day/course, where today's taken status cannot describe it.
        var cutoff = DateTime(due.year, due.month, due.day + 1);
        if (n + 1 < occurrences.length && occurrences[n + 1].isBefore(cutoff))
          cutoff = occurrences[n + 1];
        for (var r = 1; r <= repeats && missedInterval > 0; r++) {
          final at = due.add(Duration(minutes: missedInterval * r));
          if (!at.isBefore(cutoff) || !at.isBefore(regimen.end)) break;
          if (at.isAfter(now))
            requests.add(
              PlannedMedicationReminder(
                medication: med,
                slot: slot,
                due: due,
                at: at,
                repeat: r,
              ),
            );
        }
      }
    } on FormatException catch (e) {
      issues.add('${med.name}：${e.message}');
    }
  }
  requests.sort((a, b) {
    final time = a.at.compareTo(b.at);
    if (time != 0) return time;
    final kind = a.repeat.compareTo(b.repeat);
    return kind != 0 ? kind : a.key.compareTo(b.key);
  });
  final count = capacity.clamp(0, requests.length);
  return MedicationReminderPlan(
    requests.take(count).toList(),
    issues,
    requests.length - count,
    until,
    count < requests.length ? requests[count].at : null,
  );
}

class PendingReminder {
  PendingReminder(this.id, this.payload);
  final int id;
  final String? payload;
}

bool isMedicationPayload(String? payload) =>
    ['medication', 'missed_dose'].contains(payload?.split('|').first);

/// Adapters are injected, so tests exercise replacement/cancellation entirely
/// in memory without Firebase or native notification APIs.
class MedicationReminderScheduler {
  MedicationReminderScheduler({
    required this.pending,
    required this.cancel,
    required this.schedule,
  });
  final Future<List<PendingReminder>> Function() pending;
  final Future<void> Function(int) cancel;
  final Future<void> Function(int, PlannedMedicationReminder) schedule;
  Future<void> _tail = Future.value();
  int _revision = 0;
  void invalidate() => _revision++;
  Future<void> get idle => _tail;
  Future<MedicationReminderPlan?> replace(
    List<medicine> medications, {
    required DateTime now,
    required bool Function() isCurrent,
    bool enabled = true,
    bool missedEnabled = true,
    int missedInterval = 30,
    int missedCount = 2,
  }) {
    final revision = ++_revision;
    bool valid() => revision == _revision && isCurrent();
    final task = _tail.then<MedicationReminderPlan?>((_) async {
      if (!valid()) return null;
      final existing = await pending();
      final other = existing
          .where((p) => !isMedicationPayload(p.payload))
          .toList();
      for (final p in existing.where((p) => isMedicationPayload(p.payload))) {
        if (!valid()) return null;
        await cancel(p.id);
      }
      final plan = planMedicationReminders(
        enabled ? medications : [],
        now: now,
        capacity: 60 - other.length,
        missedEnabled: missedEnabled,
        missedInterval: missedInterval,
        missedCount: missedCount,
      );
      final used = other.map((p) => p.id).toSet();
      final bases = <String, int>{};
      for (final request in plan.requests) {
        if (!valid()) return null;
        final base = bases.putIfAbsent(request.key, () {
          var candidate = medicationNotificationId(request.key, request.slot);
          while (List.generate(51, (i) => candidate + i).any(used.contains)) {
            candidate = (candidate + 64) & 0x7fffffc0;
          }
          used.addAll(List.generate(51, (i) => candidate + i));
          return candidate;
        });
        await schedule(base + request.repeat, request);
      }
      return valid() ? plan : null;
    });
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }
}
