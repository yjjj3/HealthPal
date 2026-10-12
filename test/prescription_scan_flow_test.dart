import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:health_management_app/services/ai/ai_client.dart';
import 'package:health_management_app/services/prescription_scan_service.dart';
import 'package:health_management_app/screens/prescription_scan_screen.dart';
import 'package:health_management_app/screens/prescription_confirm_screen.dart';
import 'package:health_management_app/models/ai/prescription_recognition.dart';

// All data synthetic, non-medical. This test never uses a real transport.
Map<String, dynamic> completeSynthetic() => {
  'medicines': [
    {
      for (final key in PrescriptionRecognition.textFields) key: null,
      'name': 'SYNTH-A',
      'dosage': '1',
      'unit': '測試單位',
      'frequency': '每天1次',
      'timing': '飯後',
      'route': '測試途徑',
      'durationDays': 1,
      'totalQuantity': 1,
    },
  ],
  'hospitalInfo': {
    for (final key in PrescriptionRecognition.hospitalFields) key: null,
  },
  'confidence': 0.1,
  'error': null,
};

class ResponseService implements PrescriptionScanService {
  ResponseService(this.result);
  final Map<String, dynamic> result;
  @override
  Future<Map<String, dynamic>> recognizePrescriptionImage(File image) async =>
      result;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ByteService implements PrescriptionScanService {
  ByteService(this.delegate);
  final PrescriptionScanService delegate;
  @override
  Future<Map<String, dynamic>> recognizePrescriptionImage(File image) =>
      delegate.recognizePrescriptionFromBytes(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final error in [null, 'SYNTH failure']) {
    testWidgets('actual scan flow error=$error does not skip success', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final result = completeSynthetic()..['error'] = error;
      final transportService = error == null
          ? ByteService(
              PrescriptionScanService(
                firestore: FakeFirebaseFirestore(),
                currentUid: () => 'synthetic-user',
                client: AIClient(
                  apiKey: () => 'synthetic-placeholder',
                  clientFactory: () => MockClient(
                    (request) async => http.Response(
                      jsonEncode({
                        'choices': [
                          {
                            'finish_reason': 'stop',
                            'message': {'content': jsonEncode(result)},
                          },
                        ],
                      }),
                      200,
                      headers: {
                        'content-type': 'application/json; charset=utf-8',
                      },
                    ),
                  ),
                ),
              ),
            )
          : ResponseService(result);
      final service = transportService;
      final dir = Directory.systemTemp.createTempSync('healthpal-fake-scan-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/synthetic.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j1ioAAAAASUVORK5CYII=',
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: PrescriptionScanScreen(
            service: service,
            currentUid: () => 'synthetic-user',
            initialImages: [file],
          ),
        ),
      );
      await tester.tap(find.text('開始 AI 辨識 (1 張照片)'));
      await tester.pump();
      await tester.runAsync(
        () async =>
            await Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final page = tester.widget<PrescriptionConfirmScreen>(
        find.byType(PrescriptionConfirmScreen),
      );
      expect(
        page.medicines.map((m) => m.name),
        error == null ? ['SYNTH-A'] : isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}
