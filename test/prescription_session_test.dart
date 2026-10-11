import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:health_management_app/services/ai/ai_client.dart';
import 'package:health_management_app/utils/account_page_session.dart';
import 'medication_boundary_test.dart' as boundary;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_management_app/services/prescription_scan_service.dart';
import 'package:health_management_app/models/prescription_model.dart';
import 'medication_567_test.dart' as f;
import 'package:health_management_app/screens/prescription_confirm_screen.dart';

class AckLossFirestore extends boundary.RetryFirestore {
  bool loseAcknowledgement = true;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final result = await super.runTransaction(
      handler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw StateError('simulated lost acknowledgement');
    }
    return result;
  }
}

class BlockedSettings implements PrescriptionScanService {
  BlockedSettings(this.delegate);
  final PrescriptionScanService delegate;
  final ready = Completer<MealTimeSettings>();
  @override
  Future<MealTimeSettings> loadMealTimeSettings() => ready.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('switch away and back does not revive the old page session', () async {
    var uid = 'a';
    final changes = StreamController<String?>.broadcast(sync: true);
    final session = AccountPageSession(() => uid, changes.stream);
    uid = 'b';
    changes.add(uid);
    uid = 'a';
    changes.add(uid);
    expect(session.active, false);
    session.dispose();
    await changes.close();
  });
  test(
    'acknowledgement loss retry preserves one copy and original history',
    () async {
      final db = AckLossFirestore();
      final service = PrescriptionScanService(
        firestore: db,
        currentUid: () => 'a',
        now: () => f.today,
      );
      final prepared = service.prepareMedications([
        f.med().copyWith(medicine_id: 'reserved-ack'),
      ]);
      await expectLater(service.saveMedications(prepared), throwsStateError);
      final retry = await service.saveMedications(prepared);
      expect(retry.single.medicine_id, prepared.single.medicine_id);
      expect(
        (await db.collection('users/a/medicine').get()).docs,
        hasLength(1),
      );
    },
  );
  for (final action in ['switch', 'cancel', 'reject']) {
    test(
      'before commit $action writes no medicine to either account',
      () async {
        final db = boundary.RetryFirestore();
        var uid = 'a', active = true;
        final service = PrescriptionScanService(
          firestore: db,
          currentUid: () => uid,
        );
        db.conflict = () async {
          if (action == 'switch') uid = 'b';
          if (action == 'cancel') active = false;
          if (action == 'reject') throw StateError('simulated write failure');
        };
        final prepared = service.prepareMedications([f.med()]);
        await expectLater(
          service.saveMedications(
            prepared,
            expectedUid: 'a',
            isActive: () => active,
          ),
          throwsStateError,
        );
        expect((await db.collection('users/a/medicine').get()).docs, isEmpty);
        expect((await db.collection('users/b/medicine').get()).docs, isEmpty);
        if (action == 'reject') {
          await service.saveMedications(prepared, expectedUid: 'a');
          expect(
            (await db.collection('users/a/medicine').get()).docs,
            hasLength(1),
          );
        }
      },
    );
  }
  test('failed fake recognition cannot report saved data', () async {
    final db = FakeFirebaseFirestore();
    final service = PrescriptionScanService(
      firestore: db,
      currentUid: () => 'a',
      client: AIClient(
        apiKey: () => 'fake',
        clientFactory: () => MockClient(
          (_) async =>
              http.Response('{"error":{"message":"fake rejected"}}', 400),
        ),
      ),
    );
    await expectLater(
      service.recognizePrescriptionFromBytes(
        Uint8List.fromList([255, 216, 255]),
      ),
      throwsA(isA<AIException>()),
    );
    expect((await db.collection('users/a/medicine').get()).docs, isEmpty);
  });
  testWidgets(
    'return while settings are pending does not store or setState after dispose',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = FakeFirebaseFirestore();
      final blocked = BlockedSettings(
        PrescriptionScanService(firestore: db, currentUid: () => 'a'),
      );
      final pm = PrescriptionMedicine.fromJson({
        'name': '假藥',
        'dosage': '1',
        'unit': '顆',
        'frequency': '每天1次',
        'timing': '飯後',
        'route': '口服',
        'durationDays': 7,
        'totalQuantity': 7,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PrescriptionConfirmScreen(
            medicines: [pm],
            imageFiles: const [],
            service: blocked,
            currentUid: () => 'a',
          ),
        ),
      );
      await tester.tap(find.text('確認並儲存'));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      blocked.ready.complete(MealTimeSettings());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect((await db.collection('users/a/medicine').get()).docs, isEmpty);
    },
  );
  testWidgets(
    'double click, failed acknowledgement and retry keep one medicine',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AckLossFirestore();
      final service = PrescriptionScanService(
        firestore: db,
        currentUid: () => 'a',
      );
      final pm = PrescriptionMedicine.fromJson({
        'name': '假藥',
        'dosage': '1',
        'unit': '顆',
        'frequency': '每天1次',
        'timing': '飯後',
        'route': '口服',
        'durationDays': 7,
        'totalQuantity': 7,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PrescriptionConfirmScreen(
            medicines: [pm],
            imageFiles: const [],
            service: service,
            currentUid: () => 'a',
          ),
        ),
      );
      await tester.tap(find.text('確認並儲存'));
      await tester.tap(find.text('確認並儲存'));
      await tester.pumpAndSettle();
      final first = (await db.collection('users/a/medicine').get()).docs;
      expect(first, hasLength(1));
      expect(find.textContaining('儲存失敗:'), findsOneWidget);
      await tester.tap(find.text('確認並儲存'));
      await tester.pumpAndSettle();
      final retry = (await db.collection('users/a/medicine').get()).docs;
      expect(retry, hasLength(1));
      expect(retry.single.id, first.single.id);
    },
  );
  test(
    'pending meal preference write does not follow switched account',
    () async {
      SharedPreferences.setMockInitialValues({});
      var uid = 'a';
      final service = PrescriptionScanService(
        firestore: FakeFirebaseFirestore(),
        currentUid: () => uid,
      );
      final pending = service.saveMealTimeSettings(MealTimeSettings());
      uid = 'b';
      await expectLater(pending, throwsStateError);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );
  testWidgets('switching account dismisses the old medicine edit sheet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var uid = 'a';
    final changes = StreamController<String?>.broadcast(sync: true);
    final service = PrescriptionScanService(
      firestore: FakeFirebaseFirestore(),
      currentUid: () => uid,
    );
    final pm = PrescriptionMedicine.fromJson({
      'name': '假藥',
      'dosage': '1',
      'unit': '顆',
      'frequency': '每天1次',
      'timing': '飯後',
      'route': '口服',
      'durationDays': 7,
      'totalQuantity': 7,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionConfirmScreen(
          medicines: [pm],
          imageFiles: const [],
          service: service,
          currentUid: () => uid,
          accountChanges: changes.stream,
        ),
      ),
    );
    await tester.tap(find.text('編輯'));
    await tester.pumpAndSettle();
    expect(find.text('儲存修改'), findsOneWidget);
    uid = 'b';
    changes.add(uid);
    await tester.pumpAndSettle();
    expect(find.text('儲存修改'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await changes.close();
  });
  testWidgets('old confirmation page cannot save under the new account', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = FakeFirebaseFirestore();
    var uid = 'a';
    final service = PrescriptionScanService(
      firestore: db,
      currentUid: () => uid,
    );
    final pm = PrescriptionMedicine.fromJson({
      'name': '假藥',
      'dosage': '1',
      'unit': '顆',
      'frequency': '每天1次',
      'timing': '飯後',
      'route': '口服',
      'durationDays': 7,
      'totalQuantity': 7,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionConfirmScreen(
          medicines: [pm],
          imageFiles: const [],
          service: service,
          currentUid: () => uid,
        ),
      ),
    );
    uid = 'b';
    await tester.tap(find.text('確認並儲存'));
    await tester.pumpAndSettle();
    expect((await db.collection('users/b/medicine').get()).docs, isEmpty);
  });
  test('meal settings belong to the signed-in account', () async {
    SharedPreferences.setMockInitialValues({});
    var uid = 'a';
    final service = PrescriptionScanService(
      firestore: FakeFirebaseFirestore(),
      currentUid: () => uid,
    );
    await service.saveMealTimeSettings(
      MealTimeSettings(breakfastTime: const TimeOfDay(hour: 9, minute: 15)),
    );
    uid = 'b';
    expect((await service.loadMealTimeSettings()).breakfastTime.hour, 7);
    uid = 'a';
    expect((await service.loadMealTimeSettings()).breakfastTime.hour, 9);
  });
  test(
    'repeated save with reserved IDs never adds or overwrites medicine',
    () async {
      final db = FakeFirebaseFirestore();
      final service = PrescriptionScanService(
        firestore: db,
        currentUid: () => 'a',
        now: () => f.today,
      );
      final meds = [f.med(id: 'reserved', enabled: false)];
      final first = await service.saveMedications(meds);
      await db
          .collection('users/a/medicine')
          .doc(first.single.medicine_id)
          .update({'total_supply': 3});
      final retry = await service.saveMedications(meds);
      final docs = (await db.collection('users/a/medicine').get()).docs;
      expect(docs, hasLength(1));
      expect(retry.single.medicine_id, 'reserved');
      expect(retry.single.total_supply, 3);
      expect(docs.single.data()['regimen_history'], hasLength(1));
    },
  );
}
