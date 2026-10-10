import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'ai_client.dart';

class AIConfig {
  static const gateway = String.fromEnvironment('AI_GATEWAY_URL');
  static String get developmentKey =>
      kDebugMode ? const String.fromEnvironment('OPENAI_API_KEY') : '';
  static bool get usesGateway => gateway.trim().isNotEmpty;
  static bool get isConfigured =>
      usesGateway ||
      (developmentKey.isNotEmpty &&
          developmentKey != 'your_openai_api_key_here');
  static final client = AIClient(
    apiKey: () => developmentKey,
    endpoint: usesGateway
        ? gateway
        : 'https://api.openai.com/v1/chat/completions',
    authorization: usesGateway ? _idToken : null,
    currentIdentity: usesGateway
        ? () => FirebaseAuth.instance.currentUser?.uid
        : null,
  );
  static Future<String> _idToken() async {
    final uri = Uri.tryParse(gateway);
    final localDebug =
        kDebugMode &&
        uri?.scheme == 'http' &&
        ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri?.host);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && !localDebug)) {
      throw const AIException('configuration', 'AI 後端網址必須使用 HTTPS。');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null)
      throw const AIException('authentication', '請先登入以使用 AI 功能。');
    final token = await user.getIdToken();
    if (token == null || FirebaseAuth.instance.currentUser?.uid != user.uid)
      throw const AIException('authentication', '登入狀態已變更，請重新分析。');
    return token;
  }
}
