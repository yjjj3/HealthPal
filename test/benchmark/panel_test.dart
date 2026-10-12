import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_management_app/screens/ai_benchmark_screen.dart';
import 'package:health_management_app/services/ai/benchmark/journal.dart';
import 'package:health_management_app/services/ai/benchmark/single_attempt.dart';
import 'runner_test.dart' show FakeTransport;

void main() {
  late Directory dir;
  late BenchmarkJournal journal;
  late FakeTransport transport;
  late ValueNotifier<int> boundary;
  BenchmarkSession? session;
  var now = 0;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('benchmark-panel-fake-');
    journal = BenchmarkJournal(File('${dir.path}/journal.json'));
    transport = FakeTransport();
    boundary = ValueNotifier(0);
    session = const BenchmarkSession('fictional', 1);
    now = 0;
  });
  tearDown(() async {
    boundary.dispose();
    await dir.delete(recursive: true);
  });
  Widget panel() => MaterialApp(
    home: BenchmarkPanel(
      boundary: boundary,
      create: (cost) => BenchmarkHandle(
        SingleAttemptBenchmark(
          journal: journal,
          transport: transport,
          session: () => session,
          token: () async => 'fake-test-token',
          canAccess: () => true,
          costReady: cost,
          nowMs: () => now,
        ),
        'fictional-hash',
      ),
    ),
  );
  Future<void> settleIO(
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    var completed = false;
    Object? failure;
    await tester.runAsync(() async {
      action().then(
        (_) {
          completed = true;
        },
        onError: (Object error) {
          failure = error;
          completed = true;
        },
      );
    });
    final deadline = Stopwatch()..start();
    while (!completed && deadline.elapsed < const Duration(seconds: 10)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(
      completed,
      true,
      reason: 'Awaited actual callback completion, not HTTP start',
    );
    if (failure != null) throw failure!;
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    String label, {
    bool stop = false,
  }) async {
    final callback = stop
        ? tester
              .widget<TextButton>(find.widgetWithText(TextButton, label))
              .onPressed!
        : tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, label))
              .onPressed!;
    // Await the real async callback, not a wall-clock sleep or transport start.
    await (callback as Future<void> Function())();
  }

  Future<void> begin(WidgetTester tester) async {
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await settleIO(tester, () => press(tester, '建立明確新 run（不送模型）'));
  }

  testWidgets(
    'enabled fake panel requires cost ack, begin never sends, manual send/stop',
    (tester) async {
      await tester.pumpWidget(panel());
      expect(
        (tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '建立明確新 run（不送模型）'),
        )).onPressed,
        null,
      );
      expect(transport.calls, 0);
      await begin(tester);
      expect(transport.calls, 0);
      await settleIO(tester, () => press(tester, '送出下一筆 S01（會計費）'));
      expect(transport.calls, 1);
      expect(find.text('送出下一筆 S02（會計費）'), findsOneWidget);
      await settleIO(tester, () => press(tester, '停止', stop: true));
      expect(
        (tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '送出下一筆 S02（會計費）'),
        )).onPressed,
        null,
      );
      await tester.pumpWidget(const SizedBox());
      await settleIO(tester, () async {
        await journal.snapshot();
      });
    },
  );
  testWidgets(
    'new page explicit begin uses persisted next ordinal, no auto resume/send',
    (tester) async {
      await tester.runAsync(() async {
        await journal.begin('prior', 'fictional-hash', 1);
        await journal.reserve('prior', 'S01', 0);
        await journal.stop('prior');
      });
      now = 12000;
      await tester.pumpWidget(panel());
      expect(transport.calls, 0);
      await begin(tester);
      expect(find.text('送出下一筆 S02（會計費）'), findsOneWidget);
      expect(transport.calls, 0);
      await tester.pumpWidget(const SizedBox());
      await settleIO(tester, () async {
        await journal.snapshot();
      });
    },
  );
  testWidgets(
    'logout pending response stops without waiting and late success stays stale',
    (tester) async {
      final response = Completer<BenchmarkResponse>();
      transport.response = () => response.future;
      await tester.pumpWidget(panel());
      await begin(tester);
      late Future<void> pendingSend;
      await settleIO(tester, () async {
        pendingSend = press(tester, '送出下一筆 S01（會計費）');
        while (transport.calls == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        session = null;
        boundary.value++;
        // Wait the stop transaction without waiting for pending HTTP.
        await journal.snapshot();
      });
      expect(find.text('已停止；預留不退款，禁止自動續跑'), findsOneWidget);
      await settleIO(tester, () async {
        response.complete(const BenchmarkResponse(200, '{}'));
        await pendingSend;
      });
      late Map<String, dynamic> saved;
      await settleIO(tester, () async {
        saved = await journal.snapshot();
      });
      expect(saved['attempts'][0]['outcome'], 'stale');
      expect(transport.calls, 1);
      await tester.pumpWidget(const SizedBox());
      await settleIO(tester, () async {
        await journal.snapshot();
      });
    },
  );
}
