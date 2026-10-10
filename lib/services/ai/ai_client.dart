import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AIException implements Exception {
  const AIException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Bounded requests, reusable policy, and injectable transport for offline tests.
class AIClient {
  AIClient({
    required this.apiKey,
    http.Client Function()? clientFactory,
    this.endpoint = 'https://api.openai.com/v1/chat/completions',
    this.timeout = const Duration(seconds: 45),
    this.maxConcurrent = 2,
    this.maxQueued = 8,
    Future<void> Function(Duration)? delay,
    this.authorization,
    this.currentIdentity,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _delay = delay ?? Future<void>.delayed;
  final String Function() apiKey;
  final Future<String> Function()? authorization;
  final String? Function()? currentIdentity;
  final String endpoint;
  final Duration timeout;
  final int maxConcurrent;
  final int maxQueued;
  final http.Client Function() _clientFactory;
  final Future<void> Function(Duration) _delay;
  int _active = 0;
  final List<Completer<void>> _queue = [];

  Future<String> complete({
    required List<Map<String, dynamic>> messages,
    int maxTokens = 1500,
    double temperature = 0.3,
    Map<String, dynamic>? responseFormat,
  }) async {
    final identity = currentIdentity?.call();
    if (_active >= maxConcurrent) {
      if (_queue.length >= maxQueued)
        throw const AIException('busy', 'AI 工作已滿，請稍後再試。');
      final ready = Completer<void>();
      _queue.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      if (currentIdentity != null && identity != currentIdentity!())
        throw const AIException('authentication', '帳號已變更，請重新分析。');
      final key = authorization != null
          ? await authorization!()
          : apiKey().trim();
      if (currentIdentity != null && identity != currentIdentity!())
        throw const AIException('authentication', '帳號已變更，請重新分析。');
      if (key.isEmpty || key == 'your_openai_api_key_here') {
        throw const AIException('configuration', 'AI 功能尚未設定，請確認服務設定。');
      }
      final body = jsonEncode({
        'model': 'gpt-4o',
        'messages': messages,
        'max_tokens': maxTokens,
        'temperature': temperature,
        if (responseFormat != null) 'response_format': responseFormat,
      });
      final watch = Stopwatch()..start();
      for (var attempt = 0; attempt < 2; attempt++) {
        if (currentIdentity != null && identity != currentIdentity!())
          throw const AIException('authentication', '帳號已變更，請重新分析。');
        final remaining = timeout - watch.elapsed;
        if (remaining <= Duration.zero)
          throw const AIException('timeout', 'AI 請求超時，請稍後重試。');
        final client = _clientFactory();
        late http.Response response;
        try {
          response = await client
              .post(
                Uri.parse(endpoint),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $key',
                },
                body: body,
              )
              .timeout(remaining);
        } on TimeoutException {
          throw const AIException('timeout', 'AI 請求超時，請稍後重試。');
        } on http.ClientException {
          throw const AIException('network', 'AI 連線失敗，請確認網路後重試。');
        } finally {
          client.close();
        }
        // Retry only an explicit rate-limit rejection; never resend timed-out work.
        if (response.statusCode == 429 &&
            attempt == 0 &&
            !_isQuotaError(response)) {
          final seconds =
              int.tryParse(response.headers['retry-after'] ?? '') ?? 1;
          final wait = Duration(seconds: seconds.clamp(1, 5));
          if (watch.elapsed + wait >= timeout) break;
          await _delay(wait);
          continue;
        }
        if (response.statusCode != 200) throw _statusError(response);
        if (currentIdentity != null && identity != currentIdentity!())
          throw const AIException('authentication', '帳號已變更，請重新分析。');
        return _content(response.body);
      }
      throw const AIException('rate_limit', 'AI 請求次數過多，請稍後重試。');
    } finally {
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }

  bool _isQuotaError(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      return data is Map &&
          data['error'] is Map &&
          data['error']['code'] == 'insufficient_quota';
    } catch (_) {
      return false;
    }
  }

  AIException _statusError(http.Response response) {
    if (response.statusCode == 429 && _isQuotaError(response))
      return const AIException('quota', 'AI 服務額度不足，請聯絡管理者。');
    return switch (response.statusCode) {
      401 || 403 => const AIException('authorization', 'AI 服務授權失敗，請聯絡管理者。'),
      429 => const AIException('rate_limit', 'AI 請求次數過多，請稍後重試。'),
      _ => const AIException('server', 'AI 服務暫時無法使用，請稍後重試。'),
    };
  }

  String _content(String body) {
    try {
      final data = jsonDecode(body);
      if (data is! Map ||
          data['choices'] is! List ||
          (data['choices'] as List).isEmpty) {
        throw const FormatException();
      }
      final choice = data['choices'][0];
      if (choice is! Map || choice['message'] is! Map)
        throw const FormatException();
      final message = choice['message'] as Map;
      if (message['refusal'] != null)
        throw const AIException('refusal', 'AI 無法處理這項要求，請調整輸入。');
      if (choice['finish_reason'] == 'length')
        throw const AIException('truncated', 'AI 回應不完整，請減少輸入後重試。');
      if (choice['finish_reason'] == 'content_filter')
        throw const AIException('refusal', 'AI 無法處理這項要求，請調整輸入。');
      final content = message['content'];
      if (content is! String || content.trim().isEmpty)
        throw const FormatException();
      return content;
    } on AIException {
      rethrow;
    } catch (_) {
      throw const AIException('invalid_response', 'AI 回應格式不正確，請重試。');
    }
  }
}
