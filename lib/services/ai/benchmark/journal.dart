import 'dart:convert';
import 'dart:io';

/// One fixed experiment ledger across users/process restarts. No credentials.
/// File lock protects processes; the shared tail also serializes descriptors in
/// the same Dart isolate (POSIX record locks alone do not serialize these).
class BenchmarkJournal {
  BenchmarkJournal(this.file);
  final File file;
  static final Map<String, Future<void>> _tails = {};
  static const experiment = 'healthpal-synthetic-20261012-v1';
  static const maxAttempts = 20;
  static const samples = [
    'S01',
    'S02',
    'S03',
    'S04',
    'S05',
    'S06',
    'S07',
    'S08',
    'S09',
    'S10',
    'S11',
    'S12',
    'S13',
    'S14',
    'S15',
    'S16',
    'S03',
    'S11',
    'S12',
    'S16',
  ];
  static const reserveMicros = 17326080; // NT17.32608, context*FX40*1.2.
  static const modelBudgetMicros = 500000000; // NT1000 - cloud200 - safety300.

  Future<T> _transaction<T>(T Function(Map<String, dynamic>) action) {
    final key = file.absolute.path;
    final previous = _tails[key] ?? Future<void>.value();
    final work = previous.then((_) async {
      await file.parent.create(recursive: true);
      final handle = await File(
        "${file.path}.lock",
      ).open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.blockingExclusive);
        final exists = await file.exists();
        final bytes = exists ? await file.readAsBytes() : <int>[];
        if (exists && bytes.isEmpty) {
          throw StateError('Empty existing ledger; refusing reset');
        }
        final data = bytes.isEmpty
            ? <String, dynamic>{
                'experiment': experiment,
                'runs': [],
                'attempts': [],
              }
            : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        if (data['experiment'] != experiment ||
            data['runs'] is! List ||
            data['attempts'] is! List) {
          throw StateError('Journal invalid; refusing reset');
        }
        final result = action(data);
        final encoded = utf8.encode(jsonEncode(data));
        // Lock lives in a separate stable inode. A torn ledger fails closed.
        await file.writeAsBytes(encoded, flush: true); // Before every send.
        return result;
      } finally {
        await handle.unlock();
        await handle.close();
      }
    });
    _tails[key] = work.then<void>((_) {}, onError: (Object _) {});
    return work;
  }

  Future<void> begin(
    String runId,
    String ownerHash,
    int generation,
  ) => _transaction((d) {
    final runs = d['runs'] as List;
    if (runs.any((r) => r['id'] == runId)) {
      throw StateError('Run cannot resume');
    }
    // Opening a new explicit run retires crashed/pending runs without refund.
    for (final run in runs) {
      run['state'] = 'stopped';
    }
    runs.add({
      'id': runId,
      'ownerHash': ownerHash,
      'generation': generation,
      'state': 'running',
    });
  });

  Future<int> reserve(String runId, String sample, int nowMs) =>
      _transaction((d) {
        final run = (d['runs'] as List).singleWhere((r) => r['id'] == runId);
        if (run['state'] != 'running') throw StateError('Run stopped');
        final attempts = d['attempts'] as List;
        final total = attempts.fold<int>(
          0,
          (n, a) => n + (a['reservedMicros'] as int),
        );
        if (attempts.length >= maxAttempts ||
            total + reserveMicros > modelBudgetMicros) {
          throw StateError('Experiment cap reached');
        }
        if (attempts.isNotEmpty &&
            nowMs - (attempts.last['startedMs'] as int) < 12000) {
          throw StateError('Rate gate: next attempt not yet due');
        }
        if (sample != samples[attempts.length]) {
          throw StateError('Not the next frozen sample');
        }
        final id = attempts.length + 1;
        attempts.add({
          'id': id,
          'runId': runId,
          'sample': sample,
          'reservedMicros': reserveMicros,
          'startedMs': nowMs,
          'sendBoundaryReached': false,
          'outcome': 'reserved',
          'raw': null,
          'usage': null,
          'resolved_model': null,
          'finish_reason': null,
          'latencyMs': null,
        });
        return id;
      });

  Future<bool> markSending(String runId, int id, int nowMs) =>
      _transaction((d) {
        final run = (d['runs'] as List).singleWhere((r) => r['id'] == runId);
        final row = (d['attempts'] as List).singleWhere(
          (a) => a['id'] == id && a['runId'] == runId,
        );
        if (run['state'] != 'running' || row['sendBoundaryReached'] == true) {
          return false;
        }
        final sent = (d['attempts'] as List)
            .where((a) => a['sendBoundaryReached'] == true)
            .toList();
        if (sent.isNotEmpty && nowMs - (sent.last['sentMs'] as int) < 12000) {
          throw StateError('Actual send rate gate');
        }
        row['sentMs'] = nowMs;
        row['sendBoundaryReached'] = true;
        return true;
      });

  Future<void> record(
    String runId,
    int id,
    Map<String, dynamic> result,
  ) => _transaction((d) {
    final row = (d['attempts'] as List).singleWhere(
      (a) => a['id'] == id && a['runId'] == runId,
    );
    // Only explicit non-secret response fields, never request/token/headers.
    for (final key in [
      'outcome',
      'raw',
      'usage',
      'resolved_model',
      'finish_reason',
      'latencyMs',
      'usageEstimateMicros',
    ]) {
      if (result.containsKey(key)) row[key] = result[key];
    }
  });
  Future<void> stop(String runId) => _transaction((d) {
    for (final run in d['runs']) {
      if (run['id'] == runId) run['state'] = 'stopped';
    }
  });
  Future<Map<String, dynamic>> snapshot() =>
      _transaction((d) => jsonDecode(jsonEncode(d)) as Map<String, dynamic>);
}
