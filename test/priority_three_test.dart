import 'package:health_management_app/utils/medication_schedule.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:health_management_app/services/ai/ai_client.dart';
import 'package:health_management_app/services/ai_service.dart';
import 'package:health_management_app/models/ai/nutrition_analysis.dart';
import 'package:health_management_app/models/ai/prescription_recognition.dart';
import 'package:health_management_app/models/medication_dose.dart';
import 'package:health_management_app/models/medication_model.dart';
import 'package:health_management_app/models/prescription_model.dart';
import 'package:health_management_app/repositories/health_context_repository.dart';
import 'package:health_management_app/services/prescription_medication_mapper.dart';
import 'package:health_management_app/services/firestore_service.dart';
import 'package:health_management_app/utils/plain_ai_text.dart';

http.Response completion(String content, {String finish = 'stop'}) =>
    http.Response(
      jsonEncode({
        'choices': [
          {
            'finish_reason': finish,
            'message': {'content': content},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
final nutrition = <String, dynamic>{
  'is_food': true,
  'food_name': '雞肉',
  'estimated_portion': '100克',
  'category': '蛋白質',
  'suggestions': '搭配蔬菜',
  'estimated_calories': 165,
  'protein_g': 31,
  'carbs_g': 0,
  'fat_g': 3.6,
  'health_score': 9,
};
Map<String, dynamic> prescription({Map<String, dynamic> medicine = const {}}) =>
    {
      'medicines': [
        {
          'name': '藥品 A',
          'dosage': '0.5',
          'unit': '顆',
          'frequency': '每天2次',
          'timing': '飯後',
          'route': '口服',
          'durationDays': 7,
          'totalQuantity': 7,
          'precautions': '未滿12歲不宜使用；孕婦使用前請諮詢醫師。',
          ...medicine,
        },
      ],
      'hospitalInfo': {'prescriptionDate': '2026-10-10'},
      'confidence': 0.7,
      'error': null,
    };
Matcher aiError(String code) =>
    isA<AIException>().having((e) => e.code, 'code', code);

void main() {
  test('valid nutrition preserves numbers and accepts fenced JSON', () {
    final parsed = NutritionAnalysis.parse(
      '```json\n${jsonEncode(nutrition)}\n```',
    );
    expect(parsed.toJson()['fat_g'], 3.6);
    expect(parsed.toJson()['health_score'], 9);
    expect(
      NutritionAnalysis.fromJson({
        'is_food': false,
        'error_message': '不是食物',
      }).isFood,
      false,
    );
  });
  for (final bad in [
    <String, dynamic>{},
    {...nutrition, 'is_food': 'true'},
    {...nutrition, 'fat_g': -1},
    {...nutrition, 'estimated_calories': '165'},
    {...nutrition, 'health_score': 11},
    {...nutrition, 'health_score': 2.5},
  ]) {
    test(
      'reject incomplete or invalid nutrition: $bad',
      () =>
          expect(() => NutritionAnalysis.fromJson(bad), throwsFormatException),
    );
  }
  test(
    'reject prose, arrays and non-finite nutrition without inventing a result',
    () {
      expect(
        () => NutritionAnalysis.parse('說明 ${jsonEncode(nutrition)}'),
        throwsFormatException,
      );
      expect(() => NutritionAnalysis.parse('[]'), throwsFormatException);
      expect(
        () =>
            NutritionAnalysis.fromJson({...nutrition, 'protein_g': double.nan}),
        throwsFormatException,
      );
      expect(
        () => NutritionAnalysis.fromJson({'is_food': false}),
        throwsFormatException,
      );
    },
  );
  test(
    'prescription keeps exact warnings, partial unknowns and root confidence',
    () {
      final result = PrescriptionRecognition.parse(
        jsonEncode(prescription(medicine: {'dosage': null, 'frequency': null})),
      );
      final med = PrescriptionMedicine.fromJson(
        (result.data['medicines'] as List).single,
      );
      expect(med.precautions, '未滿12歲不宜使用；孕婦使用前請諮詢醫師。');
      expect(med.dosage, '');
      expect(med.frequency, '');
      expect(med.confidence, 0.7);
    },
  );
  test(
    'reject malformed, failed, empty, negative and invalid-date prescriptions',
    () {
      for (final bad in [
        {'medicines': [], 'confidence': 0},
        {...prescription(), 'confidence': 1.1},
        prescription(medicine: {'name': null}),
        prescription(medicine: {'durationDays': -1}),
        prescription(medicine: {'dosage': true}),
        {
          ...prescription(),
          'hospitalInfo': {'prescriptionDate': '2026-02-30'},
        },
        {'error': '無法辨識', 'confidence': 0},
      ]) {
        expect(
          () => PrescriptionRecognition.parse(jsonEncode(bad)),
          throwsFormatException,
        );
      }
    },
  );
  test('dosage parses decimals and fractions and rejects ambiguous ranges', () {
    for (final value in ['0.5', '1/2', '½', '半顆', '0.5 顆'])
      expect(MedicationDose.parse(value), 0.5);
    expect(MedicationDose.parse('5 ml'), 5);
    for (final value in [
      '',
      '0',
      '-1',
      '1/0',
      '1-2',
      '1至2',
      '每天1次',
      '1 顆，必要時2顆',
    ])
      expect(() => MedicationDose.parse(value), throwsFormatException);
    expect(MedicationDose.remainingDays(9.5, 0.5, '每天2次'), 9);
    expect(MedicationDose.frequencyPerDay('每6小時'), 4);
    expect(MedicationDose.frequencyPerDay('需要時服用'), 0);
    expect(() => MedicationDose.frequencyPerDay('不明'), throwsFormatException);
  });
  test(
    'meal schedule handles offsets, ordering, hourly, PRN and start date',
    () {
      final settings = MealTimeSettings(
        breakfastTime: const TimeOfDay(hour: 7, minute: 30),
      );
      final date = DateTime(2026, 11, 1);
      final times = settings.calculateReminderTimes(
        timing: '飯前',
        frequency: '每天3次',
        baseDate: date,
      );
      expect(times, [
        DateTime(2026, 11, 1, 7),
        DateTime(2026, 11, 1, 11, 30),
        DateTime(2026, 11, 1, 18),
      ]);
      final hourly = settings.calculateReminderTimes(
        timing: '不限',
        frequency: '每6小時',
        baseDate: date,
      );
      expect(hourly[1].difference(hourly.first), const Duration(hours: 6));
      expect(hourly, hasLength(4));
      expect(
        settings.calculateReminderTimes(timing: '需要時', frequency: '需要時服用'),
        isEmpty,
      );
      expect(
        () =>
            settings.calculateReminderTimes(timing: '早餐飯後', frequency: '每天3次'),
        throwsFormatException,
      );
    },
  );
  test(
    'prescription mapper keeps half dose and refuses unknown dosage or route',
    () {
      final pm = PrescriptionMedicine.fromJson(
        (PrescriptionRecognition.parse(
                  jsonEncode(prescription()),
                ).data['medicines']
                as List)
            .single,
      );
      final mapped = PrescriptionMedicationMapper.convert([
        pm,
      ], MealTimeSettings()).single;
      expect(mapped.total_pills, 0.5);
      expect(mapped.total_supply, 7);
      expect(mapped.remaining_days_calculated, 7);
      expect(
        () => PrescriptionMedicationMapper.convert([
          pm.copyWith(dosage: ''),
        ], MealTimeSettings()),
        throwsFormatException,
      );
      expect(
        () => PrescriptionMedicationMapper.convert([
          pm.copyWith(route: ''),
        ], MealTimeSettings()),
        throwsFormatException,
      );
      final prn = PrescriptionMedicationMapper.convert([
        pm.copyWith(frequency: '需要時服用'),
      ], MealTimeSettings()).single;
      expect(prn.reminderEnabled, false);
      expect(prn.times_of_day_list, isEmpty);
    },
  );
  test(
    'fractional intake and cancellation keep inventory and logs precise',
    () async {
      final db = FakeFirebaseFirestore();
      final ref = db.doc('users/alice/medicine/pill');
      final initial = medicine(
        name: '藥品 A',
        dosage: '0.5 顆',
        unit: '顆',
        total_supply: 10,
        total_pills: 0.5,
        frequency: '每天2次',
        times_of_day_list: [DateTime.now()],
        times_status: [false],
        instruction: '飯後',
        route: '口服',
        remaining_days: 10,
        start_date: DateTime.now(),
        duration_days: 10,
      );
      await ref.set(initial.toFirestore());
      final service = FirestoreService(
        firestore: db,
        currentUid: () => 'alice',
      );
      var med = medicine.fromFirestore(await ref.get());
      expect(
        await service.toggleMedicationIntake(medication: med, timeSlotIndex: 0),
        true,
      );
      med = medicine.fromFirestore(await ref.get());
      expect(med.total_supply, 9.5);
      expect(med.total_pills, 0.5);
      expect(
        await service.toggleMedicationIntake(medication: med, timeSlotIndex: 0),
        false,
      );
      expect(medicine.fromFirestore(await ref.get()).total_supply, 10);
      final logs =
          (await db.collection('users/alice/medication_logs').get()).docs;
      expect(logs, hasLength(2));
      expect(logs.map((d) => d.data()['dosage_taken']), everyElement(0.5));
    },
  );
  test(
    'health context filters dates, bounds reads and never reads another account',
    () async {
      final db = FakeFirebaseFirestore();
      final now = DateTime(2026, 10, 10);
      await db.doc('users/alice').set({'fullName': 'Alice'});
      await db.doc('users/alice/health_records/recent').set({
        'record_time': Timestamp.fromDate(now),
      });
      await db.doc('users/alice/health_records/old').set({
        'record_time': Timestamp.fromDate(
          now.subtract(const Duration(days: 40)),
        ),
      });
      await db.doc('users/bob/health_records/private').set({
        'record_time': Timestamp.fromDate(now),
      });
      for (var i = 0; i < 55; i++)
        await db.doc('users/alice/diet_records/$i').set({
          'timestamp': Timestamp.fromDate(now),
        });
      final data = await HealthContextRepository(
        db,
        now: () => now,
      ).collect('alice');
      expect(data['profile'], {'fullName': 'Alice'});
      expect(data['healthRecords'], hasLength(1));
      expect(data['dietRecords'], hasLength(50));
      expect(data['medicationLogs'], isEmpty);
    },
  );
  test(
    'plain text cleanup preserves text instead of literal replacement groups',
    () {
      expect(plainAIText('# 摘要\n**血壓** *正常*\n- 維持紀錄'), '摘要\n血壓 正常\n• 維持紀錄');
    },
  );
  test(
    'image detection uses bytes and rejects empty or unsupported images',
    () {
      final image = validatedImage([137, 80, 78, 71, 13, 10, 26, 10]);
      expect(image['image_url']['url'], startsWith('data:image/png;'));
      expect(() => validatedImage([]), throwsFormatException);
      expect(() => validatedImage([1, 2, 3]), throwsFormatException);
    },
  );
  test('transport sets structured format and preserves model', () async {
    late Map<String, dynamic> sent;
    final client = AIClient(
      apiKey: () => 'test-key',
      clientFactory: () => MockClient((request) async {
        sent = jsonDecode(request.body);
        expect(request.headers['Authorization'], 'Bearer test-key');
        return completion(jsonEncode(nutrition));
      }),
    );
    final service = AIService(client: client);
    final result = NutritionAnalysis.parse(
      await service.analyzeFoodByName('雞肉', '午餐'),
    );
    expect(result.isFood, true);
    expect(sent['model'], 'gpt-4o');
    expect(sent['response_format']['json_schema']['strict'], true);
  });
  test('429 retries once, quota and authentication do not retry', () async {
    var calls = 0;
    final client = AIClient(
      apiKey: () => 'test-key',
      delay: (_) async {},
      clientFactory: () => MockClient((_) async {
        calls++;
        return calls == 1 ? http.Response('{}', 429) : completion('ok');
      }),
    );
    expect(
      await client.complete(
        messages: [
          {'role': 'user', 'content': 'hello'},
        ],
      ),
      'ok',
    );
    expect(calls, 2);
    for (final status in [401, 403, 429]) {
      var count = 0;
      final api = AIClient(
        apiKey: () => 'test-key',
        clientFactory: () => MockClient((_) async {
          count++;
          return http.Response(
            jsonEncode({
              'error': {'code': 'insufficient_quota'},
            }),
            status,
          );
        }),
      );
      await expectLater(
        api.complete(messages: []),
        throwsA(aiError(status == 429 ? 'quota' : 'authorization')),
      );
      expect(count, 1);
    }
  });
  test(
    'malformed choices, empty, refused and truncated responses are clear failures',
    () async {
      final values = [
        http.Response('{}', 200),
        completion(''),
        completion('partial', finish: 'length'),
        http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'refusal': 'no'},
              },
            ],
          }),
          200,
        ),
        http.Response('upstream secret error', 500),
      ];
      final codes = [
        'invalid_response',
        'invalid_response',
        'truncated',
        'refusal',
        'server',
      ];
      for (var i = 0; i < values.length; i++) {
        final client = AIClient(
          apiKey: () => 'test-key',
          clientFactory: () => MockClient((_) async => values[i]),
        );
        await expectLater(
          client.complete(messages: []),
          throwsA(aiError(codes[i])),
        );
      }
    },
  );
  test('unknown legacy frequency has no guessed stock duration', () {
    expect(MedicationDose.remainingDays(10, 0.5, '隔日1次'), 0);
    expect(() => MedicationDose.frequencyPerDay('隔日1次'), throwsFormatException);
  });
  test('editing unchanged times preserves intake even when reordered', () {
    final morning = DateTime(2026, 10, 10, 8),
        evening = DateTime(2026, 10, 10, 18);
    expect(
      reconcileIntakeStatus(
        previousTimes: [morning, evening],
        previousStatus: [true, false],
        nextTimes: [evening, morning, DateTime(2026, 10, 10, 12)],
      ),
      [false, true, false],
    );
  });
  test('account change during retry does not send old data again', () async {
    var identity = 'alice';
    var calls = 0;
    final client = AIClient(
      apiKey: () => 'test-key',
      currentIdentity: () => identity,
      delay: (_) async {
        identity = 'bob';
      },
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response('{}', 429);
      }),
    );
    await expectLater(
      client.complete(messages: []),
      throwsA(aiError('authentication')),
    );
    expect(calls, 1);
  });
  test('timeout does not retry and limits queued requests', () async {
    var calls = 0;
    final client = AIClient(
      apiKey: () => 'test-key',
      timeout: const Duration(milliseconds: 10),
      clientFactory: () => MockClient((_) {
        calls++;
        return Completer<http.Response>().future;
      }),
    );
    await expectLater(
      client.complete(messages: []),
      throwsA(aiError('timeout')),
    );
    expect(calls, 1);
    final release = Completer<http.Response>();
    var entered = 0;
    final bounded = AIClient(
      apiKey: () => 'test-key',
      maxConcurrent: 1,
      maxQueued: 1,
      clientFactory: () => MockClient((_) async {
        entered++;
        return release.future;
      }),
    );
    final first = bounded.complete(messages: []);
    final second = bounded.complete(messages: []);
    await expectLater(bounded.complete(messages: []), throwsA(aiError('busy')));
    await Future<void>.delayed(Duration.zero);
    expect(entered, 1);
    release.complete(completion('ok'));
    expect(await Future.wait([first, second]), ['ok', 'ok']);
    expect(entered, 2);
  });
  test(
    'queued requests cannot send prior-account data under the next account',
    () async {
      var identity = 'alice';
      var calls = 0;
      final release = Completer<http.Response>();
      final client = AIClient(
        apiKey: () => '',
        authorization: () async => 'id-token',
        currentIdentity: () => identity,
        maxConcurrent: 1,
        clientFactory: () => MockClient((_) {
          calls++;
          return release.future;
        }),
      );
      final first = client.complete(messages: []);
      final second = client.complete(messages: []);
      final firstCheck = expectLater(first, throwsA(aiError('authentication')));
      final secondCheck = expectLater(
        second,
        throwsA(aiError('authentication')),
      );
      await Future<void>.delayed(Duration.zero);
      identity = 'bob';
      release.complete(completion('private'));
      await Future.wait([firstCheck, secondCheck]);
      expect(calls, 1);
    },
  );
}
