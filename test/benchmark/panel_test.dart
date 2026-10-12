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
    await tester.runAsync(action);
    await tester.pumpAndSettle();
  }

  Future<void> begin(WidgetTester tester) async {
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await settleIO(tester, () async {
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '建立明確新 run（不送模型）'),
          )
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
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
      await settleIO(tester, () async {
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '送出下一筆 S01（會計費）'),
            )
            .onPressed!();
        for (var i = 0; i < 100 && transport.calls == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(transport.calls, 1);
      expect(find.text('送出下一筆 S02（會計費）'), findsOneWidget);
      await settleIO(tester, () async {
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '停止'))
            .onPressed!();
      });
      expect(
        (tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '送出下一筆 S02（會計費）'),
        )).onPressed,
        null,
      );
      await tester.pumpWidget(const SizedBox());
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
    },
  );
  testWidgets(
    'logout pending response stops without waiting and late success stays stale',
    (tester) async {
      final response = Completer<BenchmarkResponse>();
      transport.response = () => response.future;
      await tester.pumpWidget(panel());
      await begin(tester);
      await settleIO(tester, () async {
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '送出下一筆 S01（會計費）'),
            )
            .onPressed!();
        while (transport.calls == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        session = null;
        boundary.value++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(find.text('已停止；預留不退款，禁止自動續跑'), findsOneWidget);
      await settleIO(tester, () async {
        response.complete(const BenchmarkResponse(200, '{}'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      final saved = await tester.runAsync(journal.snapshot);
      expect(saved!['attempts'][0]['outcome'], 'stale');
      expect(transport.calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
