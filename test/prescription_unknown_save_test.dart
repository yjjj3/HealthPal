import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:health_management_app/models/prescription_model.dart';
import 'package:health_management_app/services/prescription_scan_service.dart';
import 'package:health_management_app/screens/prescription_confirm_screen.dart';
import 'package:health_management_app/models/ai/prescription_recognition.dart';

void main() {
  for (final key in [
    'dosage',
    'unit',
    'frequency',
    'timing',
    'route',
    'durationDays',
    'totalQuantity',
  ]) {
    for (final absent in [false, true]) {
      testWidgets(
        'confirmation/save characterizes ${absent ? 'missing' : 'null'} $key',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = const Size(1200, 2000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final dataset = jsonDecode(
            File(
              'test/fixtures/prescription_eval/golden.json',
            ).readAsStringSync(),
          );
          final raw = dataset['cases'][0]['truth'] as Map<String, dynamic>;
          if (absent) {
            raw['medicines'][0].remove(key);
          } else {
            raw['medicines'][0][key] = null;
          }
          final parsed = PrescriptionRecognition.parse(jsonEncode(raw));
          final models = (parsed.data['medicines'] as List)
              .map(
                (v) => PrescriptionMedicine.fromJson(v as Map<String, dynamic>),
              )
              .toList();
          final db = FakeFirebaseFirestore();
          final service = PrescriptionScanService(
            firestore: db,
            currentUid: () => 'synthetic-save',
          );
          await tester.pumpWidget(
            MaterialApp(
              home: PrescriptionConfirmScreen(
                medicines: models,
                imageFiles: const [],
                service: service,
                currentUid: () => 'synthetic-save',
              ),
            ),
          );
          await tester.tap(find.text('確認並儲存'));
          await tester.pump();
          await tester.pumpAndSettle();
          final docs =
              (await db.collection('users/synthetic-save/medicine').get()).docs;
          final zeroDefault = ['durationDays', 'totalQuantity'].contains(key);
          expect(docs.length, zeroDefault ? 1 : 0);
          if (zeroDefault) {
            expect(
              docs.single.data()[key == 'durationDays'
                  ? 'duration_days'
                  : 'total_supply'],
              0,
            );
            expect(find.text('藥品已成功加入用藥清單！'), findsOneWidget);
          } else {
            expect(find.textContaining('儲存失敗:'), findsOneWidget);
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
