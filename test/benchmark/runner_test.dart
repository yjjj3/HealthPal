import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_management_app/services/ai/benchmark/journal.dart';
import 'package:health_management_app/services/ai/benchmark/single_attempt.dart';

class FakeTransport implements BenchmarkTransport {
  int calls = 0;
  Future<BenchmarkResponse> Function()? response;
  @override
  Future<BenchmarkResponse> send(Map<String, dynamic> body, String token) {
    calls++;
    return response?.call() ??
        Future.value(
          BenchmarkResponse(
            200,
            jsonEncode({
              'choices': [],
              'usage': {
                'prompt_tokens': 100,
                'completion_tokens': 20,
                'total_tokens': 120,
              },
              'resolved_model': 'gpt-4o-2024-08-06',
              'finish_reason': 'stop',
            }),
          ),
        );
  }

  @override
  void close() {}
}

void main() {
  late Directory dir;
  late BenchmarkJournal journal;
  late FakeTransport transport;
  BenchmarkSession? session;
  late SingleAttemptBenchmark runner;
  var now = 0;
  const body = {
    'model': 'gpt-4o',
    'max_tokens': 4096,
    'temperature': 0.1,
    'messages': [],
  };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('benchmark-fake-');
    journal = BenchmarkJournal(File('${dir.path}/journal.json'));
    transport = FakeTransport();
    session = const BenchmarkSession('fictional-user', 1);
    now = 0;
    runner = SingleAttemptBenchmark(
      journal: journal,
      transport: transport,
      session: () => session,
      token: () async => 'fake-test-token',
      canAccess: () => true,
      costReady: () => true,
      nowMs: () => now,
      timeout: const Duration(milliseconds: 5),
    );
  });
  tearDown(() async => dir.delete(recursive: true));
  test(
    'flush reserve and response survive new journal; never stores credential',
    () async {
      await runner.begin('run1', 'fictional-owner-hash');
      expect(await runner.attempt('S01', body), 'recorded');
      final saved = await BenchmarkJournal(journal.file).snapshot();
      expect(saved['attempts'][0]['sendBoundaryReached'], true);
      expect(saved['attempts'][0]['raw'], contains('usage'));
      expect(jsonEncode(saved), isNot(contains('fake-test-token')));
    },
  );
  test(
    '20 global reservations survive restart, no refunds or run resume',
    () async {
      await journal.begin('run1', 'fake', 1);
      for (var i = 0; i < 20; i++) {
        await journal.reserve('run1', BenchmarkJournal.samples[i], i * 12000);
      }
      final restarted = BenchmarkJournal(journal.file);
      await expectLater(restarted.begin('run1', 'fake', 1), throwsStateError);
      await restarted.begin('run2', 'fake', 2);
      await expectLater(
        restarted.reserve('run2', 'S01', 240000),
        throwsStateError,
      );
      expect((await restarted.snapshot())['attempts'], hasLength(20));
    },
  );
  test(
    'same-file race serializes and virtual rate gate refuses second send',
    () async {
      await journal.begin('run', 'fake', 1);
      final results = await Future.wait(
        [journal, BenchmarkJournal(journal.file)].map((j) async {
          try {
            await j.reserve('run', 'S01', 0);
            return true;
          } catch (_) {
            return false;
          }
        }),
      );
      expect(results.where((v) => v), hasLength(1));
    },
  );
  test('timeout consumes reserve and stops; no implicit retry', () async {
    transport.response = () => Completer<BenchmarkResponse>().future;
    await runner.begin('run', 'fake');
    expect(await runner.attempt('S01', body), 'timeout');
    expect(transport.calls, 1);
    expect(runner.current, false);
    expect(
      (await journal.snapshot())['attempts'][0]['reservedMicros'],
      BenchmarkJournal.reserveMicros,
    );
  });
  test('429 is one attempt and stops', () async {
    transport.response = () async => const BenchmarkResponse(429, '{}');
    await runner.begin('run', 'fake');
    expect(await runner.attempt('S01', body), 'http_429');
    expect(transport.calls, 1);
  });
  test('same UID new generation while token pending prevents send', () async {
    final token = Completer<String>();
    runner = SingleAttemptBenchmark(
      journal: journal,
      transport: transport,
      session: () => session,
      token: () => token.future,
      canAccess: () => true,
      costReady: () => true,
      nowMs: () => now,
    );
    await runner.begin('run', 'fake');
    final work = runner.attempt('S01', body);
    while ((await journal.snapshot())['attempts'].isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    session = const BenchmarkSession('fictional-user', 2);
    token.complete('fake-test-token');
    expect(await work, 'stale');
    expect(transport.calls, 0);
  });
  test('corrupt ledger never silently resets', () async {
    await journal.file.writeAsString('{broken');
    await expectLater(journal.begin('run', 'fake', 1), throwsFormatException);
    expect(await journal.file.readAsString(), '{broken');
  });
  test('existing empty ledger refuses reset', () async {
    await journal.file.writeAsString('');
    await expectLater(journal.begin('run', 'fake', 1), throwsStateError);
  });
  test('fixed plan rejects reordered sample before reserve', () async {
    await journal.begin('run', 'fake', 1);
    await expectLater(journal.reserve('run', 'S02', 0), throwsStateError);
    expect((await journal.snapshot())['attempts'], isEmpty);
  });
  test('stop while token pending does not wait or refund', () async {
    final token = Completer<String>();
    runner = SingleAttemptBenchmark(
      journal: journal,
      transport: transport,
      session: () => session,
      token: () => token.future,
      canAccess: () => true,
      costReady: () => true,
      nowMs: () => now,
    );
    await runner.begin('run', 'fake');
    final work = runner.attempt('S01', body);
    while ((await journal.snapshot())['attempts'].isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await runner.stop(); // Does not await token/network.
    token.complete('fake-test-token');
    expect(await work, 'stale');
    expect(transport.calls, 0);
    expect((await journal.snapshot())['attempts'], hasLength(1));
  });
  for (final change in ['logout', 'switch', 'lock', 'cost']) {
    test('$change while response pending stops late success', () async {
      var access = true, cost = true;
      final response = Completer<BenchmarkResponse>();
      transport.response = () => response.future;
      runner = SingleAttemptBenchmark(
        journal: journal,
        transport: transport,
        session: () => session,
        token: () async => 'fake-test-token',
        canAccess: () => access,
        costReady: () => cost,
        nowMs: () => now,
      );
      await runner.begin('run', 'fake');
      final work = runner.attempt('S01', body);
      while (transport.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      if (change == 'logout') session = null;
      if (change == 'switch') {
        session = const BenchmarkSession('other-fictional', 2);
      }
      if (change == 'lock') access = false;
      if (change == 'cost') cost = false;
      response.complete(const BenchmarkResponse(200, '{}'));
      expect(await work, 'stale');
      expect(runner.current, false);
      expect((await journal.snapshot())['attempts'][0]['outcome'], 'stale');
    });
  }
  for (final raw in [
    '{}',
    'not-json',
    '{"usage":null}',
    '{"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":3}}',
  ]) {
    test('unverified metering fails closed: $raw', () async {
      transport.response = () async => BenchmarkResponse(200, raw);
      await runner.begin('run', 'fake');
      expect(await runner.attempt('S01', body), 'metering_unverified');
      expect(runner.current, false);
      expect((await journal.snapshot())['attempts'][0]['usage'], null);
    });
  }
  test('cost gate false never opens journal or acquires token', () async {
    runner = SingleAttemptBenchmark(
      journal: journal,
      transport: transport,
      session: () => session,
      token: () async => throw StateError('must not call'),
      canAccess: () => true,
      costReady: () => false,
      nowMs: () => now,
    );
    await expectLater(runner.begin('run', 'fake'), throwsStateError);
    expect(await journal.file.exists(), false);
    expect(transport.calls, 0);
  });

  test('real child processes cannot double reserve same ordinal', () async {
    await journal.begin('race', 'fake', 1);
    final config = jsonDecode(
      await File('.dart_tool/package_config.json').readAsString(),
    );
    final flutter = (config['packages'] as List).singleWhere(
      (p) => p['name'] == 'flutter',
    );
    final root = File(
      '.dart_tool/package_config.json',
    ).absolute.uri.resolve(flutter['rootUri']);
    final sdk = Directory.fromUri(root).parent.parent;
    final dart = '${sdk.path}/bin/cache/dart-sdk/bin/dart';
    final results = await Future.wait(
      List.generate(
        3,
        (_) => Process.run(dart, [
          'test/support/benchmark_journal_worker.dart',
          journal.file.path,
        ]),
      ),
    );
    expect(results.where((r) => r.exitCode == 0), hasLength(1));
    expect(results.where((r) => r.exitCode == 2), hasLength(2));
    expect((await journal.snapshot())['attempts'], hasLength(1));
  });
  test('new explicit run continues global ordinal, not S01', () async {
    await journal.begin('old', 'fake', 1);
    await journal.reserve('old', 'S01', 0);
    await journal.stop('old');
    await BenchmarkJournal(journal.file).begin('new', 'fake', 2);
    await expectLater(journal.reserve('new', 'S01', 12000), throwsStateError);
    expect(await journal.reserve('new', 'S02', 12000), 2);
    expect((await journal.snapshot())['attempts'].map((a) => a['sample']), [
      'S01',
      'S02',
    ]);
  });
  test('slow token does not compress actual sends below 12 seconds', () async {
    await journal.begin('run', 'fake', 1);
    final one = await journal.reserve('run', 'S01', 0);
    await journal.markSending('run', one, 11000);
    final two = await journal.reserve('run', 'S02', 12000);
    await expectLater(journal.markSending('run', two, 12000), throwsStateError);
    expect(
      (await journal.snapshot())['attempts'][1]['sendBoundaryReached'],
      false,
    );
  });
}
