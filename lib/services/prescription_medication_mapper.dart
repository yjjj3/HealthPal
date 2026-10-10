import '../models/medication_model.dart';
import '../models/medication_dose.dart';
import '../models/prescription_model.dart';

class PrescriptionMedicationMapper {
  static List<medicine> convert(
    List<PrescriptionMedicine> prescriptionMedicines,
    MealTimeSettings mealTimeSettings, {
    Map<int, String>? sources,
  }) {
    final List<medicine> medications = [];

    for (int i = 0; i < prescriptionMedicines.length; i++) {
      final pm = prescriptionMedicines[i];
      // 計算服用時間
      final reminderTimes = mealTimeSettings.calculateReminderTimes(
        timing: pm.timing,
        frequency: pm.frequency,
        baseDate: pm.startDate,
      );

      final pillsPerDose = MedicationDose.parse(pm.dosage);
      if (pm.timing.trim().isEmpty || pm.route.trim().isEmpty)
        throw const FormatException('請確認服用時機與給藥途徑。');
      if (pm.unit.trim().isEmpty) throw const FormatException('請確認藥品單位。');

      final medName = (pm.name.isNotEmpty)
          ? pm.name
          : (pm.englishName ?? pm.name);
      final med = medicine(
        name: medName,
        dosage: pm.dosage.trim().endsWith(pm.unit)
            ? pm.dosage
            : '${pm.dosage} ${pm.unit}',
        unit: pm.unit,
        total_supply: pm.totalQuantity,
        total_pills: pillsPerDose,
        frequency: pm.frequency,
        times_of_day_list: reminderTimes,
        times_status: List<bool>.filled(reminderTimes.length, false),
        instruction: pm.timing,
        route: pm.route,
        remaining_days: pm.durationDays,
        start_date: pm.startDate,
        duration_days: pm.durationDays,
        reminderEnabled: reminderTimes.isNotEmpty,
        source: sources?[i],
        clinicalUse: pm.clinicalUse,
        sideEffects: pm.sideEffects,
        precautions: pm.precautions,
        storageMethod: pm.storageMethod,
        appearance: pm.appearance,
      );

      medications.add(med);
    }

    return medications;
  }
}
