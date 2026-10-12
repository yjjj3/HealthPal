import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ai/benchmark/runtime.dart';
import '../services/ai/benchmark/single_attempt.dart';
import '../services/app_unlock_runtime.dart';
import '../services/auth_service.dart';

/// No automatic sends, retries, resume, or production entry point.
class AIBenchmarkScreen extends StatelessWidget {
  const AIBenchmarkScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!benchmarkEnabled) {
      return const Scaffold(body: Center(child: Text('離線準備入口未啟用')));
    }
    return BenchmarkPanel(
      create: (costReady) => BenchmarkRuntime.create(costReady: costReady),
      boundary: Listenable.merge([
        AuthService.logout.phase,
        AppUnlockRuntime.instance.controller,
      ]),
    );
  }
}

/// Injectable controls; this widget has no credentials or transport of its own.
/// The sole production route is the compile-time guarded screen above.
class BenchmarkPanel extends StatefulWidget {
  const BenchmarkPanel({super.key, required this.create, this.boundary});
  final BenchmarkHandle Function(bool Function() costReady) create;
  final Listenable? boundary;
  @override
  State<BenchmarkPanel> createState() => _BenchmarkPanelState();
}

class _BenchmarkPanelState extends State<BenchmarkPanel> {
  BenchmarkHandle? _runtime;
  bool _ack = false, _busy = false;
  int _index = 0;
  String _status = '尚未開始；模型呼叫 0 次（本頁）';
  @override
  void initState() {
    super.initState();
    widget.boundary?.addListener(_boundary);
  }

  void _boundary() {
    if (_runtime != null && !_runtime!.runner.current) {
      unawaited(_stop());
    }
  }

  Future<void> _stop() async {
    final runtime = _runtime;
    _ack = false;
    if (mounted) {
      setState(() {
        _status = '已停止；預留不退款，禁止自動續跑';
      });
    }
    try {
      await runtime?.runner.stop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = '清理 journal 失敗；仍拒絕後續送出';
        });
      }
    }
  }

  Future<void> _begin() async {
    if (!_ack || _busy || _runtime != null) return;
    setState(() {
      _busy = true;
    });
    try {
      final runtime = widget.create(() => mounted && _ack);
      _runtime = runtime;
      await runtime.runner.begin(
        'manual-${DateTime.now().microsecondsSinceEpoch}',
        runtime.ownerHash,
      );
      final snapshot = await runtime.runner.journal.snapshot();
      if (mounted && runtime.runner.current) {
        setState(() {
          _index = (snapshot['attempts'] as List).length;
          _status = '準備完成；每次需手動送出，至少間隔 12 秒';
        });
      }
    } catch (_) {
      await _stop();
      if (mounted) {
        setState(() {
          _status = '啟動失敗；檢查登入、解鎖、endpoint 與 journal';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _send() async {
    final runtime = _runtime;
    if (_busy ||
        runtime == null ||
        !runtime.runner.current ||
        _index >= benchmarkPlan.length) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final sample = benchmarkPlan[_index];
      final outcome = await runtime.runner.attempt(
        sample,
        benchmarkBody(sample),
      );
      if (mounted && runtime.runner.current) {
        setState(() {
          _index++;
          _status = '$sample: $outcome（回應保存，不代表辨識正確）';
        });
      } else if (mounted) {
        setState(() {
          _status = '已停止；結果保留於本機 journal';
        });
      }
    } catch (_) {
      await _stop();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.boundary?.removeListener(_boundary);
    final runtime = _runtime;
    if (runtime != null) {
      unawaited(runtime.runner.stop().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('合成處方 benchmark（debug）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('非真實處方／不得醫療使用。不是一般掃描；最多 20 次 actual attempts，失敗亦計入。'),
          const Text(
            '條件預留：每次 NT17.32608；API 上界 NT346.5216，雲端 NT200、安全留白 NT300。FX40／倍率1.2 是門檻而非實際帳單。',
          ),
          CheckboxListTile(
            value: _ack,
            onChanged: _busy || _runtime != null
                ? null
                : (v) => setState(() {
                    _ack = v ?? false;
                  }),
            title: const Text(
              '已取得本次 live 授權並核對 gpt-4o 價格、FX≤40、稅費倍率≤1.2、雲端支出≤NT200；NT1000總上限條件仍成立',
            ),
          ),
          Text(_status),
          FilledButton(
            onPressed: _ack && !_busy && _runtime == null ? _begin : null,
            child: const Text('建立明確新 run（不送模型）'),
          ),
          FilledButton(
            onPressed:
                !_busy &&
                    (_runtime?.runner.current ?? false) &&
                    _index < benchmarkPlan.length
                ? _send
                : null,
            child: Text(
              _index < benchmarkPlan.length
                  ? '送出下一筆 ${benchmarkPlan[_index]}（會計費）'
                  : '已完成本頁計畫',
            ),
          ),
          TextButton(
            onPressed: _runtime != null ? _stop : null,
            child: const Text('停止'),
          ),
          const Text(
            '沒有自動重試或續跑。重開頁面須建立新 run，但本機固定實驗累計 cap 不重置。usage 估算不是含稅／雲端實際帳單；tokenizer 尚未驗證。',
          ),
        ],
      ),
    );
  }
}
