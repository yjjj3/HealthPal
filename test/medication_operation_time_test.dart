import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_management_app/models/medication_model.dart';
import 'package:health_management_app/services/firestore_service.dart';
import 'package:health_management_app/services/medication_day_service.dart';
import 'package:health_management_app/repositories/health_context_repository.dart';
import 'package:health_management_app/services/medication_adherence.dart';
import 'medication_567_test.dart' as f;

void main() {
  test(
    'old actual intake, daily reset, collect empty logs remains zero percent',
    () async {
      final db = FakeFirebaseFirestore();
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      final old = day.subtract(const Duration(days: 8));
      final ref = db.collection('users/u/medicine').doc('a');
      final original = f.med(start: old, hours: [0], updated: old);
      await ref.set(f.tracked(original, old));
      final service = FirestoreService(
        firestore: db,
        currentUid: () => 'u',
        now: () => old.add(const Duration(hours: 1)),
      );
      await service.toggleMedicationIntake(
        medication: medicine.fromFirestore(await ref.get()),
        timeSlotIndex: 0,
      );
      final before = (await ref.get()).data()!;
      expect(await MedicationDayService(db).resetIfNeeded('u', 'a'), isNotNull);
      final reset = (await ref.get()).data()!;
      expect(reset['intake_sequence'], before['intake_sequence']);
      expect(reset['intake_updated_at'], before['intake_updated_at']);
      final context = await HealthContextRepository(db).collect('u');
      expect(context['medicationLogs'], isEmpty);
      final result = calculateMedicationAdherence(context);
      expect(result.expected, 7);
      expect(result.percentage, 0);
    },
  );
  for (final kind in ['missing', 'legacy', 'contradiction', 'complete']) {
    test('operation timestamp handling: $kind', () {
      final from = DateTime(2026, 10, 5);
      final old = DateTime(2026, 10, 1);
      final due = DateTime(2026, 10, 10, 8);
      final at = DateTime(2026, 10, 10, 10);
      final raw = f.tracked(f.med(start: old, updated: f.today), old);
      raw['intake_sequence'] = 2;
      if (kind != 'legacy') {
        raw['intake_updated_at'] = Timestamp.fromDate(
          kind == 'contradiction' ? old : at,
        );
      }
      final log = f.operation('a', due, at, false)..['operation_sequence'] = 2;
      final result = calculateMedicationAdherence(
        f.context(
          [raw],
          kind == 'complete' || kind == 'contradiction' ? [log] : [],
          from: from,
        ),
      );
      expect(result.expected, 7);
      expect(result.percentage, kind == 'complete' ? 0 : isNull);
    });
  }
}
