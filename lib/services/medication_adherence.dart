import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/medication_model.dart';
import '../utils/medication_regimen.dart';

DateTime? contextDate(Object? value) => value is Timestamp
    ? value.toDate()
    : value is DateTime
    ? value
    : null;

class MedicationAdherence {
  MedicationAdherence(this.expected, this.recorded, this.issues);
  final int expected;
  final int recorded;
  final List<String> issues;
  double? get percentage =>
      issues.isEmpty && expected > 0 ? recorded * 100 / expected : null;
  String get summary {
    final buffer = StringBuffer('【今天與前6天，目前藥品的服藥紀錄完整度】\n');
    if (issues.isNotEmpty) {
      buffer.writeln('無法精確計算依從率：${issues.join('；')}。不得推算或宣稱精確百分比。');
      buffer.writeln('可重建部分：已記錄服用 $recorded／應服 $expected 個到期時段。');
    } else if (expected == 0) {
      buffer.writeln('此期間沒有到期的固定應服時段，不計算百分比。');
    } else {
      buffer.writeln(
        '已記錄服用 $recorded／應服 $expected 個到期時段，紀錄完成率 ${percentage!.toStringAsFixed(1)}%。',
      );
    }
    buffer.writeln(
      '以應服時段為分母，每時段採最後操作（取消後不算服用）。未記錄不視為已服用；紀錄無法證明實際吞服。不含已刪除藥品與需要時服用。',
    );
    return buffer.toString();
  }
}

medicine _versionMedicine(Map<String, dynamic> data, String id) => medicine(
  medicine_id: id,
  name: '歷史療程',
  dosage: '1',
  unit: '顆',
  total_supply: 1,
  total_pills: 1,
  frequency: data['frequency'] as String,
  times_of_day_list: (data['times_of_day_list'] as List)
      .map((t) => contextDate(t)!)
      .toList(),
  times_status: [],
  instruction: '',
  route: '',
  remaining_days: 0,
  start_date: contextDate(data['start_date'])!,
  duration_days: data['duration_days'] as int,
);

/// Only claim a percentage when every current regimen and operation in the
/// requested window is reconstructable. Coverage is never invented from a
/// medication's current frequency, slot index, name, or UI state.
MedicationAdherence calculateMedicationAdherence(Map<String, dynamic> context) {
  final metadata = context['medicationContext'] as Map?;
  final from = contextDate(metadata?['windowStart']);
  final now = contextDate(metadata?['windowEnd']);
  final issues = <String>{};
  if (metadata == null || from == null || now == null || !now.isAfter(from)) {
    return MedicationAdherence(0, 0, ['缺少查詢範圍與完整性資訊']);
  }
  if (metadata['logsTruncated'] != false) issues.add('操作紀錄已截斷或完整性未知');
  if (metadata['medicationsTruncated'] != false) issues.add('藥品清單已截斷或完整性未知');
  final medications = context['medications'] as List? ?? [];
  final logs = context['medicationLogs'] as List? ?? [];
  final expected = <String>{};
  final ids = <String>{};
  for (final item in medications) {
    final med = item as Map;
    final id = med['medicine_id'];
    if (id is! String || id.isEmpty || !ids.add(id)) {
      issues.add('藥品缺少穩定 ID 或重複');
      continue;
    }
    final versions = med['regimen_history'];
    if (versions is! List || versions.isEmpty) {
      issues.add('舊藥品缺少療程歷史');
      continue;
    }
    try {
      final history = versions
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      final dates = history
          .map((v) => contextDate(v['effective_from'])!)
          .toList();
      for (var i = 1; i < dates.length; i++) {
        if (dates[i].isBefore(dates[i - 1]))
          throw const FormatException('歷史順序不明');
      }
      final first = MedicationRegimen(_versionMedicine(history.first, id));
      final relevantStart = first.start.isAfter(from) ? first.start : from;
      if (first.slotsPerDay > 0 &&
          dates.first.isAfter(relevantStart) &&
          relevantStart.isBefore(now)) {
        issues.add('療程歷史未涵蓋完整查詢期間');
      }
      for (var i = 0; i < history.length; i++) {
        final regimen = MedicationRegimen(_versionMedicine(history[i], id));
        final begin = dates[i].isAfter(from) ? dates[i] : from;
        final upper = i + 1 < dates.length && !dates[i + 1].isAfter(now)
            ? dates[i + 1]
            : now.add(const Duration(microseconds: 1));
        for (final time in regimen.occurrences(begin, upper)) {
          expected.add(occurrenceKey(id, time));
        }
      }
    } catch (_) {
      issues.add('療程歷史或頻率無法重建');
    }
  }
  final states = <String, ({int sequence, bool taken})>{};
  final visibleSequences = <String, int>{};
  for (final item in logs) {
    final log = item as Map;
    final id = log['medicine_id'];
    if (!ids.contains(id))
      continue; // Explicitly scoped to current medications.
    final at = contextDate(log['intake_time']);
    final due = contextDate(log['scheduled_at']);
    final sequence = log['operation_sequence'];
    if (at == null ||
        due == null ||
        log['is_taken'] is! bool ||
        sequence is! int ||
        sequence <= 0) {
      issues.add('舊操作缺少應服時段或交易順序，無法重建取消後狀態');
      continue;
    }
    if (at.isAfter(now) || at.isBefore(from)) continue;
    final previousSequence = visibleSequences[id] ?? 0;
    if (sequence > previousSequence) visibleSequences[id as String] = sequence;
    if (due.isAfter(now) || due.isBefore(from)) continue;
    final key = occurrenceKey(id as String, due);
    if (!expected.contains(key)) {
      issues.add('操作時段與已知療程不一致');
      continue;
    }
    final previous = states[key];
    final taken = log['is_taken'] as bool;
    if (previous != null &&
        sequence == previous.sequence &&
        taken != previous.taken) {
      issues.add('同時操作順序不明');
    }
    if (previous == null || sequence > previous.sequence)
      states[key] = (sequence: sequence, taken: taken);
  }
  // These queries are not an atomic snapshot. Check both directions for due
  // slots today; a missing operation does not imply a missing cancellation.
  // Yesterday's flags and future/not-prescribed slots cannot describe today.
  for (final item in medications) {
    final med = item as Map;
    final updated = contextDate(med['lastUpdated']);
    final sequence = med['intake_sequence'];
    // When the document's last operation is within this query window, its
    // counter must agree with the latest visible operation, even on prior days.
    // Counters outside the window and legacy absent counters prove no gap.
    if (sequence is int &&
        sequence > 0 &&
        updated != null &&
        !updated.isBefore(from) &&
        (updated.isAfter(now) ||
            visibleSequences[med['medicine_id']] != sequence)) {
      issues.add('藥品與操作紀錄的交易順序不一致或紀錄缺漏');
    }
    if (updated == null || calendarDay(updated) != calendarDay(now)) continue;
    final times = med['times_of_day_list'] as List? ?? [];
    final status = med['times_status'];
    for (var i = 0; i < times.length; i++) {
      final clock = contextDate(times[i]);
      if (clock == null || med['medicine_id'] is! String) continue;
      final due = DateTime(
        now.year,
        now.month,
        now.day,
        clock.hour,
        clock.minute,
      );
      final key = occurrenceKey(med['medicine_id'], due);
      if (!expected.contains(key)) continue;
      if (status is! List || i >= status.length || status[i] is! bool) {
        issues.add('今日已到期時段的服用狀態缺漏或無效');
        continue;
      }
      // No operation and a false flag agree: the due dose is unrecorded.
      // Any other disagreement is uncertainty, never a fabricated operation.
      final recordedTaken = states[key]?.taken ?? false;
      if (status[i] != recordedTaken) {
        issues.add('今日服用狀態與可見操作紀錄不一致');
      }
    }
  }
  return MedicationAdherence(
    expected.length,
    states.values.where((s) => s.taken).length,
    issues.toList(),
  );
}
