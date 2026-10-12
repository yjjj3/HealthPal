import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'journal.dart';

class BenchmarkSession {
  const BenchmarkSession(this.uid, this.generation);
  final String uid;
  final int generation;
}

class BenchmarkResponse {
  const BenchmarkResponse(this.status, this.body);
  final int status;
  final String body;
}

abstract interface class BenchmarkTransport {
  Future<BenchmarkResponse> send(Map<String, dynamic> body, String token);
  void close();
}

/// One gateway send, no redirects/retries. Never persists/logs Authorization.
class GatewayBenchmarkTransport implements BenchmarkTransport {
  GatewayBenchmarkTransport(this.endpoint, {http.Client Function()? factory})
    : _factory = factory ?? http.Client.new;
  final Uri endpoint;
  final http.Client Function() _factory;
  http.Client? _active;
  @override
  Future<BenchmarkResponse> send(
    Map<String, dynamic> body,
    String token,
  ) async {
    if (_active != null) throw StateError('Only one HTTP attempt at a time');
    final client = _active = _factory();
    try {
      final request = http.Request('POST', endpoint)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        })
        ..body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await client.send(request),
      );
      return BenchmarkResponse(response.statusCode, response.body);
    } finally {
      client.close();
      if (identical(_active, client)) _active = null;
    }
  }

  @override
  void close() {
    _active?.close();
  }
}

class BenchmarkHandle {
  const BenchmarkHandle(this.runner, this.ownerHash);
  final SingleAttemptBenchmark runner;
  final String ownerHash;
}

class SingleAttemptBenchmark {
  SingleAttemptBenchmark({
    required this.journal,
    required this.transport,
    required this.session,
    required this.token,
    required this.canAccess,
    required this.costReady,
    required this.nowMs,
    this.validateRequest,
    this.timeout = const Duration(seconds: 65),
  });
  final BenchmarkJournal journal;
  final BenchmarkTransport transport;
  final BenchmarkSession? Function() session;
  final Future<String> Function() token;
  final bool Function() canAccess, costReady;
  final int Function() nowMs;
  final Duration timeout;
  final bool Function(String sample, Map<String, dynamic> body)?
  validateRequest;
  BenchmarkSession? _owner;
  String? _run;
  bool _stopped = true, _busy = false;
  bool get current {
    final s = session();
    return !_stopped &&
        s != null &&
        _owner != null &&
        s.uid == _owner!.uid &&
        s.generation == _owner!.generation &&
        canAccess() &&
        costReady();
  }

  Future<void> begin(String runId, String ownerHash) async {
    final s = session();
    if (s == null || !canAccess() || !costReady() || _busy) {
      throw StateError('Session/cost gate not ready');
    }
    _owner = s;
    _run = runId;
    _stopped = false;
    _busy = true;
    try {
      await journal.begin(runId, ownerHash, s.generation);
      if (!current) {
        await stop();
        throw StateError('Session changed');
      }
    } catch (_) {
      _stopped = true;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<String> attempt(String sample, Map<String, dynamic> body) async {
    if (!current || _busy || _run == null) throw StateError('Runner not ready');
    // Fixed cost profile cannot be used for arbitrary models/tools/payload types.
    if (body['model'] != 'gpt-4o' ||
        body['max_tokens'] != 4096 ||
        body['temperature'] != 0.1 ||
        body.keys.any(
          (k) => ![
            'model',
            'messages',
            'max_tokens',
            'temperature',
            'response_format',
          ].contains(k),
        )) {
      throw StateError('Request outside reviewed cost contract');
    }
    if (validateRequest != null && !validateRequest!(sample, body)) {
      throw StateError('Not a frozen benchmark sample');
    }
    _busy = true;
    final run = _run!;
    int? id;
    final started = nowMs();
    var outcome = 'error';
    try {
      id = await journal.reserve(run, sample, started);
      if (!current) throw StateError('Session changed');
      final credential = await token().timeout(timeout);
      if (!current || credential.isEmpty) {
        throw StateError('Session changed or token unavailable');
      }
      if (!await journal.markSending(run, id, nowMs()) || !current) {
        throw StateError('Stopped before send');
      }
      final response = await transport.send(body, credential).timeout(timeout);
      final result = <String, dynamic>{
        'raw': response.body,
        'latencyMs': nowMs() - started,
      };
      if (!current) {
        outcome = 'stale';
      } else if (response.status != 200) {
        outcome = 'http_${response.status}';
      } else {
        Map<String, dynamic>? data;
        try {
          data = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}
        final u = data?['usage'];
        bool count(dynamic v) =>
            v is num &&
            v.isFinite &&
            v == v.roundToDouble() &&
            v >= 0 &&
            v <= 9007199254740991;
        final valid =
            u is Map &&
            count(u['prompt_tokens']) &&
            count(u['completion_tokens']) &&
            count(u['total_tokens']) &&
            u['prompt_tokens'] + u['completion_tokens'] == u['total_tokens'] &&
            u['prompt_tokens'] <= 128000 &&
            u['completion_tokens'] <= 4096 &&
            u['total_tokens'] <= 128000;
        final model = data?['resolved_model'];
        final modelOk = [
          'gpt-4o-2024-08-06',
          'gpt-4o-2024-11-20',
        ].contains(model);
        if (valid) {
          result['usage'] = {
            'prompt_tokens': u['prompt_tokens'],
            'completion_tokens': u['completion_tokens'],
            'total_tokens': u['total_tokens'],
          };
          // Usage-based estimate at reviewed prices/FX threshold, not invoice.
          result['usageEstimateMicros'] =
              ((u['prompt_tokens'] * 2.5 + u['completion_tokens'] * 10) * 48)
                  .ceil();
        }
        result['resolved_model'] = modelOk ? model : null;
        result['finish_reason'] =
            [
              'stop',
              'length',
              'content_filter',
              'tool_calls',
              'function_call',
            ].contains(data?['finish_reason'])
            ? data!['finish_reason']
            : null;
        outcome = valid && modelOk && result['finish_reason'] == 'stop'
            ? 'recorded'
            : 'metering_unverified';
        if (result['usageEstimateMicros'] is int &&
            (result['usageEstimateMicros'] as int) >
                BenchmarkJournal.reserveMicros) {
          outcome = 'cost_exceeded';
        }
      }
      result['outcome'] = outcome;
      await journal.record(run, id, result);
      if (outcome != 'recorded') await stop();
      return outcome;
    } catch (e) {
      transport.close();
      outcome = current && e is TimeoutException
          ? 'timeout'
          : current
          ? 'error'
          : 'stale';
      _stopped = true;
      try {
        if (id != null) {
          await journal.record(run, id, {
            'outcome': outcome,
            'latencyMs': nowMs() - started,
          });
        }
      } catch (_) {
        /* A broken ledger stays fail closed; never reset it. */
      }
      try {
        await stop();
      } catch (_) {
        /* Already stopped in memory. */
      }
      return outcome;
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    _stopped = true;
    transport.close();
    final run = _run;
    if (run != null) await journal.stop(run);
  }
}
