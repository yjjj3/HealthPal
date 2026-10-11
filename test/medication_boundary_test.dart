import 'dart:async';
import 'package:health_management_app/services/medication_reminder_planner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_management_app/models/medication_model.dart';
import 'package:health_management_app/services/firestore_service.dart';
import 'package:health_management_app/services/medication_adherence.dart';
import 'medication_567_test.dart' as f;

// Scripted retries discard writes from the first attempt, unlike FakeFirestore's
// immediate-write transaction. This is a deterministic local conflict model.
class RetryFirestore extends FakeFirebaseFirestore {
  Future<void> Function()? conflict;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final competingWrite = conflict;
    conflict = null;
    if (competingWrite != null) {
      await handler(BufferedTransaction());
      await competingWrite();
    }
    final tx = BufferedTransaction();
    final result = await handler(tx);
    await tx.commit();
    return result;
  }
}

class BufferedTransaction implements Transaction {
  final writes = <Future<void> Function()>[];
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> ref,
  ) => ref.get();
  @override
  Transaction update(DocumentReference ref, Map<Object, Object?> data) {
    writes.add(() => ref.update(data));
    return this;
  }

  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    writes.add(() => ref.set(data, options));
    return this;
  }

  @override
  Transaction delete(DocumentReference ref) {
    writes.add(ref.delete);
    return this;
  }

  Future<void> commit() async {
    for (final write in writes) {
      await write();
    }
  }
}

void main() {
  for (final editDose in [false, true]) {
    test(
      'discarded attempt then competing ${editDose ? "dose edit" : "intake"}',
      () async {
        final db = RetryFirestore();
        final ref = db.collection('users/u/medicine').doc('a');
        await ref.set(f.tracked(f.med(), f.today));
        final service = FirestoreService(
          firestore: db,
          currentUid: () => 'u',
          now: () => DateTime(2026, 10, 11, 9),
        );
        final original = medicine.fromFirestore(await ref.get());
        db.conflict = () async {
          if (editDose) {
            await service.editMedication(
              original,
              original.copyWith(total_pills: 2),
            );
          } else {
            await service.toggleMedicationIntake(
              medication: original,
              timeSlotIndex: 0,
            );
          }
        };
        final attempt = service.toggleMedicationIntake(
          medication: original,
          timeSlotIndex: 0,
        );
        if (editDose) {
          expect(await attempt, true);
        } else {
          await expectLater(attempt, throwsStateError);
        }
        final raw = (await ref.get()).data()!;
        expect(raw['total_supply'], editDose ? 8 : 9.5);
        expect(raw['intake_sequence'], 1);
        expect(
          (await db.collection('users/u/medication_logs').get()).docs,
          hasLength(1),
        );
        final live = medicine.fromFirestore(await ref.get());
        await service.toggleMedicationIntake(
          medication: live,
          timeSlotIndex: 0,
        );
        await expectLater(
          service.toggleMedicationIntake(medication: live, timeSlotIndex: 0),
          throwsStateError,
        );
        expect((await ref.get()).data()!['total_supply'], 10);
        expect((await ref.get()).data()!['intake_sequence'], 2);
      },
    );
  }
  for (final pause in ['pending', 'cancel', 'schedule']) {
    test(
      'account invalidation during $pause drains before new account',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final requests = <int, PendingReminder>{
          1: PendingReminder(1, 'medication|old'),
        };
        var block = true;
        Future<void> boundary(String stage) async {
          if (block && pause == stage) {
            block = false;
            entered.complete();
            await release.future;
          }
        }

        final scheduler = MedicationReminderScheduler(
          pending: () async {
            await boundary('pending');
            return requests.values.toList();
          },
          cancel: (id) async {
            await boundary('cancel');
            requests.remove(id);
          },
          schedule: (id, request) async {
            await boundary('schedule');
            requests[id] = PendingReminder(id, request.payload);
          },
        );
        var account = 'old';
        final old = scheduler.replace(
          [f.med(id: 'old', days: 1)],
          now: f.today,
          isCurrent: () => account == 'old',
        );
        await entered.future;
        account = 'new';
        scheduler.invalidate();
        final cleanup = scheduler.idle.then((_) => requests.clear());
        release.complete();
        await old;
        await cleanup;
        await scheduler.replace(
          [f.med(id: 'new', days: 1)],
          now: f.today,
          isCurrent: () => account == 'new',
        );
        expect(requests, isNotEmpty);
        expect(requests.values.every((r) => r.payload!.contains('new')), true);
      },
    );
  }

  for (final staleTaken in [false, true]) {
    test(
      'stale ${staleTaken ? "cancel" : "take"} cannot replay after ABA',
      () async {
        final db = FakeFirebaseFirestore();
        final ref = db.collection('users/u/medicine').doc('a');
        await ref.set(f.tracked(f.med(), f.today));
        final service = FirestoreService(
          firestore: db,
          currentUid: () => 'u',
          now: () => DateTime(2026, 10, 11, 9),
        );
        Future<medicine> read() async =>
            medicine.fromFirestore(await ref.get());
        Future<void> toggle(medicine m) async {
          await service.toggleMedicationIntake(medication: m, timeSlotIndex: 0);
        }

        final initial = await read();
        await toggle(initial);
        final taken = await read();
        await toggle(taken);
        if (staleTaken) await toggle(await read());
        final before = (await ref.get()).data();
        await expectLater(
          toggle(staleTaken ? taken : initial),
          throwsStateError,
        );
        expect((await ref.get()).data(), before);
        expect(
          (await db.collection('users/u/medication_logs').get()).docs.length,
          staleTaken ? 3 : 2,
        );
      },
    );
  }
  test('yesterday checked screen cannot become next-day intake', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('users/u/medicine').doc('a');
    await ref.set(f.tracked(f.med(), f.today));
    var now = DateTime(2026, 10, 11, 23);
    final service = FirestoreService(
      firestore: db,
      currentUid: () => 'u',
      now: () => now,
    );
    await service.toggleMedicationIntake(
      medication: medicine.fromFirestore(await ref.get()),
      timeSlotIndex: 0,
    );
    final checked = medicine.fromFirestore(await ref.get());
    now = DateTime(2026, 10, 12);
    await expectLater(
      service.toggleMedicationIntake(medication: checked, timeSlotIndex: 0),
      throwsStateError,
    );
    expect((await ref.get()).data()!['total_supply'], 9.5);
  });
  test('clock crossing midnight during transaction requires reload', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('users/u/medicine').doc('a');
    await ref.set(f.tracked(f.med(), f.today));
    var calls = 0;
    final service = FirestoreService(
      firestore: db,
      currentUid: () => 'u',
      now: () => calls++ == 0
          ? DateTime(2026, 10, 11, 23, 59)
          : DateTime(2026, 10, 12),
    );
    await expectLater(
      service.toggleMedicationIntake(
        medication: medicine.fromFirestore(await ref.get()),
        timeSlotIndex: 0,
      ),
      throwsStateError,
    );
    expect((await ref.get()).data()!['total_supply'], 10);
  });
  for (final visibleSequence in [1, 2, 3]) {
    test('document sequence 2 versus visible $visibleSequence', () {
      final yesterday = DateTime(2026, 10, 10);
      final raw = f.tracked(
        f.med(start: yesterday, updated: yesterday),
        yesterday,
      );
      raw['intake_sequence'] = 2;
      raw['lastUpdated'] = Timestamp.fromDate(DateTime(2026, 10, 10, 10));
      final log = f.operation(
        'a',
        DateTime(2026, 10, 10, 8),
        DateTime(2026, 10, 10, 9),
        visibleSequence == 1,
      );
      log['operation_sequence'] = visibleSequence;
      final result = calculateMedicationAdherence(
        f.context(
          [raw],
          [log],
          from: yesterday,
          now: DateTime(2026, 10, 11, 12),
        ),
      );
      expect(result.expected, 2);
      expect(result.percentage, visibleSequence == 2 ? 0 : isNull);
    });
  }
}
