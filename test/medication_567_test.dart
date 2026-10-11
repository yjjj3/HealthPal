import 'package:health_management_app/services/prescription_scan_service.dart';
import 'package:health_management_app/services/ai/ai_client.dart';
import 'package:http/testing.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_management_app/models/medication_model.dart';
import 'package:health_management_app/models/prescription_model.dart';
import 'package:health_management_app/models/prescription_draft.dart';
import 'package:health_management_app/repositories/health_context_repository.dart';
import 'package:health_management_app/services/firestore_service.dart';
import 'package:health_management_app/services/medication_adherence.dart';
import 'package:health_management_app/services/medication_history.dart';
import 'package:health_management_app/services/medication_reminder_planner.dart';
import 'package:health_management_app/services/prescription_medication_mapper.dart';
import 'package:health_management_app/utils/medication_regimen.dart';

final today = DateTime(2026, 10, 11);
medicine med({
  String id = 'a',
  String frequency = '每天1次',
  List<int> hours = const [8],
  DateTime? start,
  int days = 20,
  List<bool>? status,
  DateTime? updated,
  bool enabled = true,
}) => medicine(
  medicine_id: id,
  name: '同名藥',
  dosage: '0.5 顆',
  unit: '顆',
  total_supply: 10,
  total_pills: 0.5,
  frequency: frequency,
  times_of_day_list: hours.map((h) => DateTime(2026, 10, 11, h)).toList(),
  times_status: status ?? List.filled(hours.length, false),
  instruction: '飯後',
  route: '口服',
  remaining_days: days,
  start_date: start ?? today,
  duration_days: days,
  lastUpdated: updated ?? today,
  reminderEnabled: enabled,
);
MedicationReminderPlan plan(
  List<medicine> meds,
  DateTime now, {
  int count = 2,
  int interval = 30,
}) => planMedicationReminders(
  meds,
  now: now,
  capacity: 10000,
  missedCount: count,
  missedInterval: interval,
);
Map<String, dynamic> tracked(medicine m, DateTime at) => {
  ...medicationCreationData(m, at),
  'medicine_id': m.medicine_id,
};
Map<String, dynamic> operation(
  String id,
  DateTime due,
  DateTime at,
  bool taken,
) => {
  'medicine_id': id,
  'scheduled_at': Timestamp.fromDate(due),
  'intake_time': Timestamp.fromDate(at),
  'is_taken': taken,
  'operation_sequence': at.microsecondsSinceEpoch,
};
Map<String, dynamic> context(
  List<Map<String, dynamic>> meds,
  List<Map<String, dynamic>> logs, {
  DateTime? from,
  DateTime? now,
  bool truncated = false,
}) => {
  'medications': meds,
  'medicationLogs': logs,
  'medicationContext': {
    'windowStart': Timestamp.fromDate(from ?? DateTime(2026, 10, 7)),
    'windowEnd': Timestamp.fromDate(now ?? DateTime(2026, 10, 11, 23)),
    'logsTruncated': truncated,
    'medicationsTruncated': false,
  },
};

class FakeNotifications {
  final requests = <int, PendingReminder>{};
  final planned = <int, PlannedMedicationReminder>{};
  Completer<void>? block;
  bool fail = false;
  late final scheduler = MedicationReminderScheduler(
    pending: () async => requests.values.toList(),
    cancel: (id) async {
      requests.remove(id);
      planned.remove(id);
    },
    schedule: (id, r) async {
      final wait = block;
      block = null;
      if (wait != null) await wait.future;
      if (fail) throw StateError('native scheduling failed');
      requests[id] = PendingReminder(id, r.payload);
      planned[id] = r;
    },
  );
  Future<MedicationReminderPlan?> replace(
    List<medicine> meds, {
    DateTime? now,
    bool enabled = true,
  }) => scheduler.replace(
    meds,
    now: now ?? DateTime(2026, 10, 11, 7),
    isCurrent: () => true,
    enabled: enabled,
  );
}

void main() {
  group('finite calendar notification planning', () {
    test(
      'future start and exclusive course end, no today/tomorrow shortcut',
      () {
        final result = plan([
          med(start: DateTime(2026, 10, 13), days: 2),
        ], DateTime(2026, 10, 11, 7));
        expect(result.requests.where((r) => r.repeat == 0).map((r) => r.due), [
          DateTime(2026, 10, 13, 8),
          DateTime(2026, 10, 14, 8),
        ]);
        expect(
          result.requests.every((r) => r.at.isBefore(DateTime(2026, 10, 15))),
          true,
        );
        expect(plan([med(days: 1)], DateTime(2026, 10, 12)).requests, isEmpty);
      },
    );
    test('alternate days and weekly anchor on start date across month', () {
      final start = DateTime(2026, 9, 29);
      final alternate = plan([
        med(frequency: '隔日1次', start: start),
      ], DateTime(2026, 10, 1, 7));
      expect(
        alternate.requests
            .where((r) => r.repeat == 0)
            .take(3)
            .map((r) => r.due.day),
        [1, 3, 5],
      );
      final weekly = plan([
        med(frequency: '每週1次', start: start),
      ], DateTime(2026, 10, 1, 7));
      expect(
        weekly.requests.where((r) => r.repeat == 0).map((r) => r.due.day),
        [6, 13],
      );
      expect(calendarDistance(DateTime(2026, 3, 7), DateTime(2026, 3, 9)), 2);
    });
    test(
      'PRN excluded; ambiguous frequency and unknown duration are reported',
      () {
        expect(
          plan([med(frequency: '需要時服用', hours: [], days: 0)], today).requests,
          isEmpty,
        );
        for (final invalid in [
          med(frequency: '每周2次'),
          med(days: 0),
          med(frequency: '每天2次'),
        ]) {
          final result = plan([invalid], today);
          expect(result.requests, isEmpty);
          expect(result.issues, isNotEmpty);
        }
      },
    );
    test('missed reminders stop before next dose, midnight and course end', () {
      final result = plan(
        [
          med(frequency: '每天2次', hours: [8, 9], days: 1),
        ],
        DateTime(2026, 10, 11, 8, 10),
        count: 0,
      );
      expect(result.requests.where((r) => r.due.hour == 8).map((r) => r.at), [
        DateTime(2026, 10, 11, 8, 30),
      ]);
      expect(
        result.requests.every((r) => r.at.isBefore(DateTime(2026, 10, 12))),
        true,
      );
      final late = plan(
        [
          med(hours: [23], days: 1),
        ],
        DateTime(2026, 10, 11, 22),
        count: 50,
      );
      expect(late.requests.map((r) => r.at), [
        DateTime(2026, 10, 11, 23),
        DateTime(2026, 10, 11, 23, 30),
      ]);
    });
    test(
      'taken today removes only today; yesterday state never suppresses future',
      () {
        final now = DateTime(2026, 10, 11, 7);
        final result = plan([
          med(days: 3, status: [true]),
        ], now);
        expect(
          result.requests.where((r) => r.repeat == 0).map((r) => r.due.day),
          [12, 13],
        );
        expect(
          plan([
            med(days: 1, status: [true], updated: DateTime(2026, 10, 10)),
          ], now).requests,
          hasLength(3),
        );
      },
    );
    test(
      'after cancellation only future alarms from the actual occurrence return',
      () {
        final result = plan([med(days: 2)], DateTime(2026, 10, 11, 8, 40));
        expect(result.requests.first.at, DateTime(2026, 10, 11, 9));
        expect(result.requests.first.repeat, 2);
        expect(
          result.requests.where((r) => r.repeat == 0).single.due,
          DateTime(2026, 10, 12, 8),
        );
      },
    );
    test('long courses stop at rolling 30-day horizon', () {
      final result = plan([med(days: 365)], DateTime(2026, 10, 11, 7));
      expect(result.requests.where((r) => r.repeat == 0), hasLength(30));
      expect(result.until, DateTime(2026, 11, 10));
    });
  });
  group('shared device scheduling', () {
    test(
      'capacity includes unrelated pending notifications and continuous mode',
      () async {
        final fake = FakeNotifications();
        for (var i = 0; i < 12; i++)
          fake.requests[i] = PendingReminder(i, 'health|visit');
        final result = await fake.scheduler.replace(
          [med(days: 365), med(id: 'b', days: 365)],
          now: DateTime(2026, 10, 11, 7),
          isCurrent: () => true,
          missedCount: 0,
        );
        expect(fake.requests.length, 60);
        expect(result!.requests.length, 48);
        expect(result.omitted, greaterThan(0));
        expect(result.firstOmitted, isNotNull);
        expect(
          fake.planned.values.map((r) => r.at).toList(),
          orderedEquals(result.requests.map((r) => r.at)),
        );
        expect(
          fake.requests.values.where((p) => p.payload == 'health|visit'),
          hasLength(12),
        );
      },
    );
    test(
      'global disable, medicine disable and deletion remove legacy/all dates',
      () async {
        final fake = FakeNotifications();
        fake.requests[100] = PendingReminder(100, 'medication|同名藥_0');
        fake.requests[101] = PendingReminder(101, 'missed_dose|a|50');
        await fake.replace([med(days: 2)]);
        expect(fake.requests.containsKey(100), false);
        await fake.replace([med(days: 2, enabled: false)]);
        expect(fake.requests, isEmpty);
        await fake.replace([med(days: 2)]);
        await fake.replace([]);
        expect(fake.requests, isEmpty);
        await fake.replace([med(days: 2)]);
        await fake.replace([med(days: 2)], enabled: false);
        expect(fake.requests, isEmpty);
      },
    );
    test(
      'edit and intake rebuild dates, cancellation preserves tomorrow IDs',
      () async {
        final fake = FakeNotifications();
        await fake.replace([med(days: 3)]);
        final tomorrow = fake.planned.entries
            .where((e) => e.value.due.day == 12)
            .map((e) => e.key)
            .toSet();
        await fake.replace([
          med(days: 3, status: [true]),
        ]);
        expect(fake.planned.values.any((r) => r.due.day == 11), false);
        expect(fake.planned.keys.toSet().containsAll(tomorrow), true);
        await fake.replace([med(days: 3)]);
        expect(fake.planned.values.any((r) => r.due.day == 11), true);
        await fake.replace([
          med(days: 3, hours: [10]),
        ]);
        expect(fake.planned.values.every((r) => r.due.hour == 10), true);
      },
    );
    test(
      'refresh after horizon exhaustion replenishes while app is open',
      () async {
        final fake = FakeNotifications();
        await fake.replace([med(days: 90)]);
        await fake.replace([med(days: 90)], now: DateTime(2026, 11, 9, 7));
        expect(
          fake.planned.values.every(
            (r) => !r.at.isBefore(DateTime(2026, 11, 9)),
          ),
          true,
        );
        expect(
          fake.planned.values.any((r) => r.due.month == 11 && r.due.day == 10),
          true,
        );
      },
    );
    test(
      'overlapping replacement cannot resurrect stale taken or edited alarms',
      () async {
        final fake = FakeNotifications();
        final gate = Completer<void>();
        fake.block = gate;
        final first = fake.replace([med(days: 2)]);
        await Future<void>.delayed(Duration.zero);
        final latest = fake.replace([
          med(days: 2, hours: [10], status: [true]),
        ]);
        gate.complete();
        await first;
        await latest;
        expect(
          fake.planned.values.every((r) => r.due.day == 12 && r.due.hour == 10),
          true,
        );
      },
    );
    test(
      'account cleanup drains an in-flight native call before clearing',
      () async {
        final fake = FakeNotifications();
        final gate = Completer<void>();
        fake.block = gate;
        final old = fake.replace([med(id: 'old-account')]);
        await Future<void>.delayed(Duration.zero);
        fake.scheduler.invalidate();
        var drained = false;
        final draining = fake.scheduler.idle.then((_) => drained = true);
        await Future<void>.delayed(Duration.zero);
        expect(drained, false);
        gate.complete();
        await old;
        await draining;
        fake.requests.clear();
        fake.planned.clear();
        await fake.replace([med(id: 'new-account', days: 1)]);
        expect(
          fake.planned.values.every(
            (r) => r.medication.medicine_id == 'new-account',
          ),
          true,
        );
      },
    );
    test(
      'account invalidation stops queued work; native errors are not success',
      () async {
        final fake = FakeNotifications();
        var current = true;
        final task = fake.scheduler.replace(
          [med()],
          now: today,
          isCurrent: () => current,
        );
        current = false;
        fake.scheduler.invalidate();
        expect(await task, null);
        expect(fake.requests, isEmpty);
        fake.fail = true;
        await expectLater(fake.replace([med()]), throwsStateError);
        fake.fail = false;
        await fake.replace([med(days: 1)]);
        expect(fake.requests, isNotEmpty);
      },
    );
  });
  group('expected slots and final-operation adherence', () {
    final regimen = med(
      frequency: '每天2次',
      hours: [8, 18],
      start: DateTime(2026, 10, 7),
      days: 5,
    );
    final data = tracked(regimen, DateTime(2026, 10, 6));
    test('ten expected doses and one recorded is 10%, not 100%', () {
      final result = calculateMedicationAdherence(
        context(
          [data],
          [
            operation(
              'a',
              DateTime(2026, 10, 7, 8),
              DateTime(2026, 10, 7, 9),
              true,
            ),
          ],
        ),
      );
      expect(result.expected, 10);
      expect(result.recorded, 1);
      expect(result.percentage, 10);
    });
    test('take, cancel, take use final state despite reverse log order', () {
      final due = DateTime(2026, 10, 7, 8);
      final take = operation('a', due, DateTime(2026, 10, 7, 9), true);
      final cancel = operation('a', due, DateTime(2026, 10, 7, 10), false);
      expect(
        calculateMedicationAdherence(
          context([data], [cancel, take]),
        ).percentage,
        0,
      );
      final retake = operation('a', due, DateTime(2026, 10, 7, 11), true);
      expect(
        calculateMedicationAdherence(
          context([data], [cancel, retake, take]),
        ).percentage,
        10,
      );
    });
    test('transaction sequence wins over device clock order', () {
      final due = DateTime(2026, 10, 7, 8);
      final taken = {
        ...operation('a', due, DateTime(2026, 10, 7, 10), true),
        'operation_sequence': 1,
      };
      final cancelled = {
        ...operation('a', due, DateTime(2026, 10, 7, 9), false),
        'operation_sequence': 2,
      };
      expect(
        calculateMedicationAdherence(
          context([data], [taken, cancelled]),
        ).percentage,
        0,
      );
    });
    test(
      'missing operations and no logs remain in denominator; future excluded',
      () {
        final result = calculateMedicationAdherence(
          context([data], [], now: DateTime(2026, 10, 7, 12)),
        );
        expect(result.expected, 1);
        expect(result.recorded, 0);
        expect(result.percentage, 0);
        expect(
          calculateMedicationAdherence(
            context([data], [], now: DateTime(2026, 10, 7, 7)),
          ).percentage,
          null,
        );
      },
    );
    test(
      'alternate and weekly course days shared with notification planner',
      () {
        final alternate = tracked(
          med(frequency: '隔日1次', start: DateTime(2026, 10, 7), days: 5),
          DateTime(2026, 10, 6),
        );
        expect(
          calculateMedicationAdherence(context([alternate], [])).expected,
          3,
        );
        final weekly = tracked(
          med(frequency: '每週1次', start: DateTime(2026, 10, 1), days: 20),
          DateTime(2026, 9, 30),
        );
        expect(calculateMedicationAdherence(context([weekly], [])).expected, 1);
      },
    );
    test('reminder disabled has a denominator, PRN does not', () {
      final disabled = {...data, 'reminderEnabled': false};
      expect(
        calculateMedicationAdherence(context([disabled], [])).expected,
        10,
      );
      final prn = tracked(
        med(frequency: 'PRN', hours: [], days: 0),
        DateTime(2026, 10, 6),
      );
      final result = calculateMedicationAdherence(context([prn], []));
      expect(result.expected, 0);
      expect(result.issues, isEmpty);
      expect(result.percentage, null);
    });
    test(
      'edited regimen uses versions, not current frequency retroactively',
      () {
        final changed = med(hours: [10], start: DateTime(2026, 10, 7), days: 5);
        final current = {
          ...changed.toFirestore(),
          'medicine_id': 'a',
          'regimen_history': appendRegimenHistory(
            data,
            changed.toFirestore(),
            DateTime(2026, 10, 9, 12),
          ),
        };
        final logs = [
          operation(
            'a',
            DateTime(2026, 10, 9, 8),
            DateTime(2026, 10, 9, 9),
            true,
          ),
        ];
        final result = calculateMedicationAdherence(context([current], logs));
        expect(result.expected, 7);
        expect(result.recorded, 1);
        expect(result.issues, isEmpty);
      },
    );
    test(
      'reordered clock slots preserve log identity and final cancellation',
      () {
        final changed = regimen.copyWith(
          times_of_day_list: regimen.times_of_day_list.reversed.toList(),
        );
        final current = {
          ...changed.toFirestore(),
          'medicine_id': 'a',
          'regimen_history': appendRegimenHistory(
            data,
            changed.toFirestore(),
            DateTime(2026, 10, 8, 12),
          ),
        };
        final due = DateTime(2026, 10, 8, 8);
        final result = calculateMedicationAdherence(
          context(
            [current],
            [
              operation('a', due, DateTime(2026, 10, 8, 9), true),
              operation('a', due, DateTime(2026, 10, 8, 13), false),
            ],
          ),
        );
        expect(result.expected, 10);
        expect(result.recorded, 0);
        expect(result.percentage, 0);
      },
    );
    test(
      'truncation, missing histories, legacy slots and ties never claim precision',
      () {
        final due = DateTime(2026, 10, 7, 8);
        final take = operation('a', due, DateTime(2026, 10, 7, 9), true);
        final variants = [
          context([data], [take], truncated: true),
          context(
            [
              {...regimen.toFirestore(), 'medicine_id': 'a'},
            ],
            [take],
          ),
          context(
            [data],
            [
              {
                'medicine_id': 'a',
                'intake_time': Timestamp.fromDate(due),
                'is_taken': true,
              },
            ],
          ),
          context([tracked(regimen, DateTime(2026, 10, 8))], [take]),
          context(
            [data],
            [
              take,
              {...take, 'is_taken': false},
            ],
          ),
          {
            'medications': [data],
            'medicationLogs': [take],
          },
          {
            ...context([data], [take]),
            'medicationContext': {
              ...(context([], [])['medicationContext'] as Map),
              'medicationsTruncated': true,
            },
          },
        ];
        for (final input in variants) {
          final result = calculateMedicationAdherence(input);
          expect(result.percentage, null);
          expect(result.issues, isNotEmpty);
          expect(result.summary, contains('不得推算'));
          expect(RegExp(r'\d+(?:\.\d+)?%').hasMatch(result.summary), false);
        }
      },
    );
    test('current taken flag without explaining log is incomplete', () {
      final taken = {
        ...data,
        'lastUpdated': Timestamp.fromDate(DateTime(2026, 10, 11, 8)),
        'times_status': [true, false],
      };
      expect(
        calculateMedicationAdherence(context([taken], [])).percentage,
        null,
      );
    });
    test('history is bounded and truncated coverage prevents a percentage', () {
      var current = data;
      for (var i = 0; i < 40; i++) {
        current = {
          ...current,
          'regimen_history': appendRegimenHistory(
            current,
            regimen.toFirestore(),
            DateTime(2026, 10, 8, 0, i),
          ),
        };
      }
      expect(current['regimen_history'], hasLength(32));
      expect(
        calculateMedicationAdherence(context([current], [])).percentage,
        null,
      );
    });
  });
  group('snapshot consistency', () {
    final now = DateTime(2026, 10, 11, 12);
    final due = DateTime(2026, 10, 11, 8);
    final complete = tracked(
      med(frequency: '每天2次', hours: [8, 18], days: 1),
      DateTime(2026, 10, 10),
    );
    final take = operation('a', due, DateTime(2026, 10, 11, 9), true);
    final cancel = operation('a', due, DateTime(2026, 10, 11, 10), false);
    MedicationAdherence check(
      Map<String, dynamic> data,
      List<Map<String, dynamic>> logs, {
      DateTime? at,
    }) => calculateMedicationAdherence(
      context([data], logs, from: today, now: at ?? now),
    );
    void unknown(MedicationAdherence result) {
      expect(result.percentage, null);
      expect(result.issues, isNotEmpty);
      expect(RegExp(r'\d+(?:\.\d+)?%').hasMatch(result.summary), false);
    }

    test('current false with only visible take cannot claim an exact rate', () {
      final result = check(
        {
          ...complete,
          'times_status': [false, false],
        },
        [take],
      );
      unknown(result);
      expect(result.expected, 1);
      expect(
        result.recorded,
        1,
      ); // Preserve the observation; never invent a cancellation.
    });
    test(
      'current true with a final cancel or no visible take is incomplete',
      () {
        for (final logs in [
          <Map<String, dynamic>>[],
          [take, cancel],
        ]) {
          unknown(
            check({
              ...complete,
              'times_status': [true, false],
            }, logs),
          );
        }
      },
    );
    test('unoperated false is a valid unrecorded due slot', () {
      final result = check({
        ...complete,
        'times_status': [false, false],
      }, []);
      expect(result.expected, 1);
      expect(result.recorded, 0);
      expect(result.percentage, 0);
      expect(result.issues, isEmpty);
    });
    test('matching take and matching final cancellation remain precise', () {
      final taken = check(
        {
          ...complete,
          'times_status': [true, false],
        },
        [take],
      );
      expect(taken.percentage, 100);
      expect(taken.issues, isEmpty);
      final cancelled = check(
        {
          ...complete,
          'times_status': [false, false],
        },
        [cancel, take],
      );
      expect(cancelled.percentage, 0);
      expect(cancelled.issues, isEmpty);
    });
    test('future slots do not cause a mismatch or missing-status warning', () {
      final futureTake = operation(
        'a',
        DateTime(2026, 10, 11, 18),
        DateTime(2026, 10, 11, 11),
        true,
      );
      for (final statuses in [
        [false, true],
        [false, false],
        [false],
        [false, null],
      ]) {
        final result = check(
          {...complete, 'times_status': statuses},
          [futureTake],
        );
        expect(result.expected, 1);
        expect(result.recorded, 0);
        expect(result.percentage, 0);
        expect(result.issues, isEmpty);
      }
    });
    test('absent or malformed status for a due slot stays unknown', () {
      final absent = Map<String, dynamic>.from(complete)
        ..remove('times_status');
      unknown(check(absent, [take]));
      for (final statuses in [
        null,
        <bool>[],
        [null, false],
        ['false', false],
        false,
      ]) {
        unknown(check({...complete, 'times_status': statuses}, [take]));
      }
    });
    test('missing status of the second due slot is not silently ignored', () {
      unknown(
        check(
          {
            ...complete,
            'times_status': [false],
          },
          [],
          at: DateTime(2026, 10, 11, 19),
        ),
      );
    });
    test(
      'outside-course and stale yesterday flags are not today mismatches',
      () {
        for (final m in [
          med(start: DateTime(2026, 10, 12)),
          med(start: DateTime(2026, 10, 9), days: 1),
        ]) {
          final result = check({
            ...tracked(m, DateTime(2026, 10, 8)),
            'times_status': null,
          }, []);
          expect(result.expected, 0);
          expect(result.percentage, null);
          expect(result.issues, isEmpty);
        }
        final stale = check({
          ...complete,
          'lastUpdated': Timestamp.fromDate(DateTime(2026, 10, 10)),
          'times_status': [true, true],
        }, []);
        expect(stale.percentage, 0);
        expect(stale.issues, isEmpty);
      },
    );
    test(
      'repository future-time cutoff cannot turn a cancellation into 100 percent',
      () async {
        final db = FakeFirebaseFirestore();
        await db.doc('users/alice/medicine/a').set({
          ...complete,
          'times_status': [false, false],
          'lastUpdated': Timestamp.fromDate(
            now.add(const Duration(minutes: 1)),
          ),
        });
        await db.doc('users/alice/medication_logs/take').set(take);
        await db
            .doc('users/alice/medication_logs/cancel')
            .set(
              operation('a', due, now.add(const Duration(minutes: 1)), false),
            );
        final data = await HealthContextRepository(
          db,
          now: () => now,
        ).collect('alice');
        expect(data['medicationLogs'], hasLength(1));
        expect(data['medicationContext']['logsTruncated'], false);
        unknown(calculateMedicationAdherence(data));
      },
    );
  });
  group('fake Firestore full flow', () {
    test(
      'creation, intake, cancellation and schedule edit retain history and receipts',
      () async {
        final db = FakeFirebaseFirestore();
        var clock = DateTime(2026, 10, 11, 7);
        final service = FirestoreService(
          firestore: db,
          currentUid: () => 'alice',
          now: () => clock,
        );
        final id = await service.addMedication(med(days: 2));
        final ref = db.doc('users/alice/medicine/$id');
        var current = medicine.fromFirestore(await ref.get());
        clock = DateTime(2026, 10, 11, 8, 5);
        await service.toggleMedicationIntake(
          medication: current,
          timeSlotIndex: 0,
        );
        current = medicine.fromFirestore(await ref.get());
        clock = DateTime(2026, 10, 11, 8, 10);
        await service.toggleMedicationIntake(
          medication: current,
          timeSlotIndex: 0,
        );
        current = medicine.fromFirestore(await ref.get());
        final saved = await service.editMedication(
          current,
          current.copyWith(frequency: '隔日1次'),
        );
        expect(saved.total_supply, 10);
        expect(saved.times_status, [false]);
        expect((await ref.get()).data()!['regimen_history'], hasLength(2));
        final logs =
            (await db.collection('users/alice/medication_logs').get()).docs;
        expect(logs, hasLength(2));
        expect(
          logs.map((d) => d.data()['scheduled_at']),
          everyElement(Timestamp.fromDate(DateTime(2026, 10, 11, 8))),
        );
        clock = DateTime(2026, 10, 12, 8);
        await expectLater(
          service.toggleMedicationIntake(medication: saved, timeSlotIndex: 0),
          throwsStateError,
        );
        expect((await ref.get()).data()!['total_supply'], 10);
      },
    );
    test(
      'course start/end block new intake but never block a valid cancellation',
      () async {
        final db = FakeFirebaseFirestore();
        final clock = DateTime(2026, 10, 11, 9);
        final service = FirestoreService(
          firestore: db,
          currentUid: () => 'alice',
          now: () => clock,
        );
        final ref = db.doc('users/alice/medicine/a');
        for (final invalid in [
          med(start: DateTime(2026, 10, 12)),
          med(start: DateTime(2026, 10, 9), days: 1),
        ]) {
          await ref.set(invalid.toFirestore());
          await expectLater(
            service.toggleMedicationIntake(
              medication: medicine.fromFirestore(await ref.get()),
              timeSlotIndex: 0,
            ),
            throwsStateError,
          );
          expect((await ref.get()).data()!['total_supply'], 10);
        }
        await ref.set(med().toFirestore());
        await service.toggleMedicationIntake(
          medication: medicine.fromFirestore(await ref.get()),
          timeSlotIndex: 0,
        );
        final taken = medicine.fromFirestore(await ref.get());
        final edited = await service.editMedication(
          taken,
          taken.copyWith(start_date: DateTime(2026, 10, 12)),
        );
        expect(
          await service.toggleMedicationIntake(
            medication: edited,
            timeSlotIndex: 0,
          ),
          false,
        );
        expect((await ref.get()).data()!['total_supply'], 10);
      },
    );
    test(
      'bounded context records IDs, cutoff and cap-plus-one sentinels',
      () async {
        final db = FakeFirebaseFirestore();
        final now = DateTime(2026, 10, 11, 12);
        for (var i = 0; i < 51; i++)
          await db
              .doc('users/alice/medication_logs/$i')
              .set(
                operation('a', today, now.subtract(Duration(minutes: i)), true),
              );
        for (var i = 0; i < 101; i++)
          await db.doc('users/alice/medicine/$i').set(med().toFirestore());
        await db
            .doc('users/alice/medication_logs/future')
            .set(operation('a', today, now.add(const Duration(days: 1)), true));
        final data = await HealthContextRepository(
          db,
          now: () => now,
        ).collect('alice');
        expect(data['medicationLogs'], hasLength(50));
        expect(data['medications'], hasLength(100));
        expect(
          (data['medications'] as List).every((m) => m['medicine_id'] != null),
          true,
        );
        expect(data['medicationContext']['logsTruncated'], true);
        expect(data['medicationContext']['medicationsTruncated'], true);
        expect(
          data['medicationContext']['windowStart'],
          Timestamp.fromDate(DateTime(2026, 10, 5)),
        );
        expect(
          (data['medicationLogs'] as List).every(
            (l) => !contextDate(l['intake_time'])!.isAfter(now),
          ),
          true,
        );
        expect(calculateMedicationAdherence(data).percentage, null);
      },
    );
  });
  group('prescription source identity', () {
    PrescriptionMedicine prescription(String name) =>
        PrescriptionMedicine.fromJson({
          'name': name,
          'dosage': '0.5',
          'unit': '顆',
          'frequency': '每天1次',
          'timing': '飯後',
          'route': '口服',
          'durationDays': 7,
          'totalQuantity': 7,
        });
    test('delete first/middle/last then map source to surviving medicine', () {
      for (final removed in [0, 1, 3]) {
        final draft = PrescriptionDraft(
          List.generate(4, (i) => prescription('藥$i')),
        );
        for (var i = 0; i < 4; i++) draft.entries[i].source = '來源$i';
        draft.remove(draft.entries[removed]);
        final mapped = PrescriptionMedicationMapper.convert(
          draft.medicines,
          MealTimeSettings(),
          sources: draft.sources,
        );
        for (final medication in mapped)
          expect(medication.source, '來源${medication.name.substring(1)}');
      }
    });
    test(
      'same-name entries, editing and clearing source remain independent',
      () {
        final draft = PrescriptionDraft([
          prescription('同名'),
          prescription('同名'),
          prescription('同名'),
        ], source: '醫院');
        final first = draft.entries.first, last = draft.entries.last;
        draft.update(last, last.medicine.copyWith(name: '編輯'), '藥局');
        draft.remove(first);
        draft.update(last, last.medicine, null);
        expect(draft.sources, {0: '醫院'});
        expect(draft.medicines.last.name, '編輯');
        draft.update(first, first.medicine, '不應復活');
        expect(draft.entries, hasLength(2));
      },
    );
    test(
      'deleted draft entry converts and batch-saves the correct sources and IDs',
      () async {
        final db = FakeFirebaseFirestore();
        final service = PrescriptionScanService(
          firestore: db,
          currentUid: () => 'alice',
          now: () => today,
          client: AIClient(
            apiKey: () => 'fake',
            clientFactory: () => MockClient(
              (_) async => throw StateError('No API allowed in this test'),
            ),
          ),
        );
        final draft = PrescriptionDraft([
          prescription('同名'),
          prescription('同名'),
          prescription('C'),
        ]);
        draft.entries[0].source = '第一來源';
        draft.entries[1].source = '第二來源';
        draft.entries[2].source = '第三來源';
        draft.remove(draft.entries.first);
        final converted = await service.convertToMedications(
          draft.medicines,
          MealTimeSettings(),
          sources: draft.sources,
        );
        final saved = await service.saveMedications(converted);
        expect(saved.map((m) => m.source), ['第二來源', '第三來源']);
        expect(saved.map((m) => m.medicine_id).toSet(), hasLength(2));
        for (final medication in saved) {
          final stored =
              (await db
                      .doc('users/alice/medicine/${medication.medicine_id}')
                      .get())
                  .data()!;
          expect(stored['source'], medication.source);
          expect(stored['name'], medication.name);
          expect(stored['regimen_history'], hasLength(1));
        }
      },
    );
    test('prescription interval schedules generate one confirmed clock', () {
      for (final frequency in ['隔日1次', '每週1次']) {
        final mapped = PrescriptionMedicationMapper.convert([
          prescription('藥').copyWith(frequency: frequency),
        ], MealTimeSettings()).single;
        expect(mapped.times_of_day_list, hasLength(1));
        expect(MedicationRegimen(mapped).slotsPerDay, 1);
      }
    });
  });
}
