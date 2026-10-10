import 'ai_service.dart';

/// Compatibility facade; all AI requests share transport, validation and policy.
class OpenAIService {
  static Future<Map<String, dynamic>> analyzeFoodNutrition({
    required String foodName,
    String? portionSize,
    String? mealType,
    String? preparationMethod,
  }) async {
    final result = await AIService.instance.estimateNutritionByName(
      '$foodName，份量：${portionSize ?? "未提供"}，烹調：${preparationMethod ?? "未提供"}',
      mealType ?? '未指定',
    );
    return result!;
  }
}
