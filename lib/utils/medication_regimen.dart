import '../models/medication_dose.dart';
import '../models/medication_model.dart';

DateTime calendarDay(DateTime time) =>
    DateTime(time.year, time.month, time.day);
int calendarDistance(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
String occurrenceKey(String id, DateTime time) =>
    '$id:${time.year}-${time.month}-${time.day}:${time.hour}:${time.minute}';

/// Interval regimens are anchored on the course start date. Ambiguous weekly
/// schedules (e.g. twice weekly without weekdays) are never guessed.
class MedicationRegimen {
  MedicationRegimen(this.medication) {
    final f = medication.frequency.replaceAll(' ', '').toUpperCase();
    if (f == '隔日1次' || f == '隔日一次' || f == 'QOD') {
      intervalDays = 2;
      slotsPerDay = 1;
    } else if (f == '每週1次' || f == '每周1次' || f == '每週一次' || f == '每周一次') {
      intervalDays = 7;
      slotsPerDay = 1;
    } else {
      intervalDays = 1;
      slotsPerDay = MedicationDose.frequencyPerDay(f);
    }
    if (slotsPerDay == 0) return; // PRN has no scheduled denominator.
    if (medication.duration_days <= 0) {
      throw const FormatException('療程天數不明，請確認後再啟用提醒。');
    }
    if (medication.times_of_day_list.length != slotsPerDay ||
        medication.times_of_day_list
                .map((t) => '${t.hour}:${t.minute}')
                .toSet()
                .length !=
            slotsPerDay) {
      throw const FormatException('頻率與提醒時段不一致，請編輯確認。');
    }
  }
  final medicine medication;
  late final int intervalDays;
  late final int slotsPerDay;
  DateTime get start => calendarDay(medication.start_date);
  DateTime get end =>
      DateTime(start.year, start.month, start.day + medication.duration_days);
  bool includesDay(DateTime day) {
    final offset = calendarDistance(start, day);
    return slotsPerDay > 0 &&
        offset >= 0 &&
        offset < medication.duration_days &&
        offset % intervalDays == 0;
  }

  DateTime timeOn(DateTime day, int slot) {
    final clock = medication.times_of_day_list[slot];
    return DateTime(day.year, day.month, day.day, clock.hour, clock.minute);
  }

  Iterable<DateTime> occurrences(DateTime from, DateTime until) sync* {
    var day = calendarDay(from.isAfter(start) ? from : start);
    while (day.isBefore(until) && day.isBefore(end)) {
      if (includesDay(day)) {
        for (var i = 0; i < slotsPerDay; i++) {
          final time = timeOn(day, i);
          if (!time.isBefore(from) && time.isBefore(until)) yield time;
        }
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
  }
}

int regimenSlotCount(String frequency) {
  final f = frequency.replaceAll(' ', '');
  if (['隔日1次', '隔日一次', 'QOD', '每週1次', '每周1次', '每週一次', '每周一次'].contains(f))
    return 1;
  return MedicationDose.frequencyPerDay(frequency);
}
