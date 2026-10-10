import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:health_management_app/models/medication_model.dart';
import 'package:health_management_app/services/firestore_service.dart';
import 'package:health_management_app/utils/medication_schedule.dart';

medicine initial({num stock = 10}) => medicine(
  name: 'A',
  dosage: '0.5 顆',
  unit: '顆',
  total_supply: stock,
  total_pills: 0.5,
  frequency: '每天2次',
  times_of_day_list: [
    DateTime.now().copyWith(hour: 8),
    DateTime.now().copyWith(hour: 18),
  ],
  times_status: [false, false],
  instruction: '飯後',
  route: '口服',
  remaining_days: 10,
  start_date: DateTime.now(),
  duration_days: 10,
);
void main() {
  test('cancel restores actual deduction even after dose changes', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.doc('users/alice/medicine/a');
    await ref.set(initial(stock: 0.25).toFirestore());
    final service = FirestoreService(firestore: db, currentUid: () => 'alice');
    await service.toggleMedicationIntake(
      medication: medicine.fromFirestore(await ref.get()),
      timeSlotIndex: 0,
    );
    expect((await ref.get()).data()!['total_supply'], 0);
    await ref.update({'total_pills': 2});
    await service.toggleMedicationIntake(
      medication: medicine.fromFirestore(await ref.get()),
      timeSlotIndex: 0,
    );
    expect((await ref.get()).data()!['total_supply'], 0.25);
    final logs =
        (await db.collection('users/alice/medication_logs').get()).docs;
    expect(logs.map((d) => d.data()['dosage_taken']), everyElement(0.5));
    expect(
      logs.map((d) => d.data()['stock_change']),
      containsAll([-0.25, 0.25]),
    );
  });
  test('zero stock intake and cancellation do not invent inventory', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.doc('users/alice/medicine/a');
    await ref.set(initial(stock: 0).toFirestore());
    final service = FirestoreService(firestore: db, currentUid: () => 'alice');
    for (var i = 0; i < 2; i++) {
      await service.toggleMedicationIntake(
        medication: medicine.fromFirestore(await ref.get()),
        timeSlotIndex: 0,
      );
    }
    expect((await ref.get()).data()!['total_supply'], 0);
  });
  test(
    'stale edit preserves concurrent intake, stock and unedited fields',
    () async {
      final db = FakeFirebaseFirestore();
      final ref = db.doc('users/alice/medicine/a');
      await ref.set(initial().toFirestore());
      final service = FirestoreService(
        firestore: db,
        currentUid: () => 'alice',
      );
      final old = medicine.fromFirestore(await ref.get());
      await service.toggleMedicationIntake(medication: old, timeSlotIndex: 0);
      await ref.update({'route': '外用', 'custom_field': 'keep'});
      final saved = await service.editMedication(old, old.copyWith(name: 'B'));
      expect(saved.name, 'B');
      expect(saved.total_supply, 9.5);
      expect(saved.times_status, [true, false]);
      expect(saved.route, '外用');
      expect((await ref.get()).data()!['custom_field'], 'keep');
      await service.toggleMedicationIntake(medication: saved, timeSlotIndex: 0);
      expect((await ref.get()).data()!['total_supply'], 10);
    },
  );
  test('same-field concurrent edits are rejected', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.doc('users/alice/medicine/a');
    await ref.set(initial().toFirestore());
    final old = medicine.fromFirestore(await ref.get());
    await ref.update({'name': 'Other edit'});
    await expectLater(
      FirestoreService(
        firestore: db,
        currentUid: () => 'alice',
      ).editMedication(old, old.copyWith(name: 'B')),
      throwsStateError,
    );
    expect((await ref.get()).data()!['name'], 'Other edit');
  });
  test(
    'time reorder preserves fresh intake and exact cancellation receipt',
    () async {
      final db = FakeFirebaseFirestore();
      final ref = db.doc('users/alice/medicine/a');
      await ref.set(initial().toFirestore());
      final service = FirestoreService(
        firestore: db,
        currentUid: () => 'alice',
      );
      final old = medicine.fromFirestore(await ref.get());
      await service.toggleMedicationIntake(medication: old, timeSlotIndex: 0);
      final saved = await service.editMedication(
        old,
        old.copyWith(
          times_of_day_list: old.times_of_day_list.reversed.toList(),
        ),
      );
      expect(saved.times_status, [false, true]);
      await service.toggleMedicationIntake(medication: saved, timeSlotIndex: 1);
      expect((await ref.get()).data()!['total_supply'], 10);
    },
  );
  test(
    'cannot remove an already taken time or guess a legacy deduction',
    () async {
      final db = FakeFirebaseFirestore();
      final ref = db.doc('users/alice/medicine/a');
      await ref.set(
        initial().copyWith(times_status: [true, false]).toFirestore(),
      );
      final service = FirestoreService(
        firestore: db,
        currentUid: () => 'alice',
      );
      final old = medicine.fromFirestore(await ref.get());
      await expectLater(
        service.editMedication(
          old,
          old.copyWith(times_of_day_list: [old.times_of_day_list[1]]),
        ),
        throwsStateError,
      );
      await expectLater(
        service.toggleMedicationIntake(medication: old, timeSlotIndex: 0),
        throwsStateError,
      );
      expect((await ref.get()).data()!['total_supply'], 10);
    },
  );
  test(
    'notification identity is stable and cleanup covers old and missed payloads',
    () {
      final base = medicationNotificationId('doc-a', 0);
      expect(base, medicationNotificationId('doc-a', 0));
      expect(base, isNot(medicationNotificationId('doc-a', 1)));
      expect(base, isNot(medicationNotificationId('doc-b', 0)));
      expect(base + 50, lessThanOrEqualTo(2147483647));
      expect(belongsToMedication('medication|doc-a', 'doc-a'), true);
      for (var i = 1; i <= 50; i++) {
        expect(belongsToMedication('missed_dose|doc-a|$i', 'doc-a'), true);
      }
      expect(
        belongsToMedication('medication|藥A_2', 'doc-a', legacyName: '藥A'),
        true,
      );
      expect(
        belongsToMedication('medication|藥A_2x', 'doc-a', legacyName: '藥A'),
        false,
      );
      expect(belongsToMedication('medication|doc-b', 'doc-a'), false);
      expect(belongsToMedication('health|doc-a', 'doc-a'), false);
    },
  );
}
