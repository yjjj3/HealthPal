import 'dart:convert';
import 'dart:io';
import 'ai/ai_config.dart';
import '../models/ai/nutrition_analysis.dart';
import 'ai/ai_client.dart';
import 'ai/ai_prompts.dart';

/// Facade for the shared, injectable AI transport and validated domain responses.
class AIService {
  AIService({required AIClient client}) : _client = client;
  static final instance = AIService(client: AIConfig.client);
  final AIClient _client;
  bool get isConfigured =>
      _client.authorization != null ||
      (_client.apiKey().trim().isNotEmpty &&
          _client.apiKey() != 'your_openai_api_key_here');
  void initialize() {
    if (!isConfigured) throw const AIException('configuration', 'AI 功能尚未設定。');
  }

  Future<String> generateResponse(String prompt) => _client.complete(
    messages: [
      {'role': 'system', 'content': AIPrompts.health},
      {'role': 'user', 'content': prompt},
    ],
    temperature: 0.7,
  );
  Future<String> generateConversation(List<Map<String, String>> messages) =>
      _client.complete(
        messages: messages.map((m) => Map<String, dynamic>.of(m)).toList(),
        temperature: 0.7,
      );
  Future<String> analyzeFoodByName(String foodName, String mealType) async {
    final content = await _client.complete(
      messages: [
        {'role': 'system', 'content': AIPrompts.nutrition},
        {'role': 'user', 'content': '食物：$foodName；餐別：$mealType'},
      ],
      responseFormat: NutritionAnalysis.responseFormat,
    );
    return jsonEncode(NutritionAnalysis.parse(content).toJson());
  }

  Future<String> analyzeFood(File imageFile, String mealType) async {
    final bytes = await imageFile.readAsBytes();
    final image = validatedImage(bytes);
    final content = await _client.complete(
      messages: [
        {'role': 'system', 'content': AIPrompts.nutrition},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '餐別：$mealType，估算圖片中食物的營養。'},
            image,
          ],
        },
      ],
      responseFormat: NutritionAnalysis.responseFormat,
    );
    return jsonEncode(NutritionAnalysis.parse(content).toJson());
  }

  Future<Map<String, dynamic>?> estimateNutritionByName(
    String foodName,
    String mealType,
  ) async {
    final data = NutritionAnalysis.parse(
      await analyzeFoodByName(foodName, mealType),
    ).toJson();
    if (data['is_food'] == false)
      return {...data, 'error': data['error_message']};
    return {
      ...data,
      'calories': data['estimated_calories'],
      'protein': data['protein_g'],
      'carbs': data['carbs_g'],
      'fat': data['fat_g'],
      'portion': data['estimated_portion'],
    };
  }
}

/// Detect actual bytes rather than trusting the file extension or assuming JPEG.
Map<String, dynamic> validatedImage(List<int> bytes, {String detail = 'low'}) {
  if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024)
    throw const FormatException('圖片必須介於 1 byte 與 10 MB。');
  String? mime;
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff)
    mime = 'image/jpeg';
  if (bytes.length >= 8 &&
      const [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ].asMap().entries.every((e) => bytes[e.key] == e.value))
    mime = 'image/png';
  if (bytes.length >= 6 &&
      ['GIF89a', 'GIF87a'].contains(String.fromCharCodes(bytes.take(6))))
    mime = 'image/gif';
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP')
    mime = 'image/webp';
  if (mime == null)
    throw const FormatException('不支援的圖片格式，請使用 JPEG、PNG、GIF 或 WebP。');
  return {
    'type': 'image_url',
    'image_url': {
      'url': 'data:$mime;base64,${base64Encode(bytes)}',
      'detail': detail,
    },
  };
}
