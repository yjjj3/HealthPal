import 'validated_json.dart';

class NutritionAnalysis {
  NutritionAnalysis._(this.data);
  final Map<String, dynamic> data;
  bool get isFood => data['is_food'] == true;
  factory NutritionAnalysis.parse(String content) =>
      NutritionAnalysis.fromJson(decodeAIObject(content));
  factory NutritionAnalysis.fromJson(Map<String, dynamic> data) {
    if (data['is_food'] is! bool) throw const FormatException('缺少有效的食物判斷。');
    if (data['is_food'] == false) {
      return NutritionAnalysis._({
        'is_food': false,
        'error_message': requiredText(data, 'error_message'),
      });
    }
    final normalized = <String, dynamic>{'is_food': true};
    for (final key in [
      'food_name',
      'estimated_portion',
      'category',
      'suggestions',
    ]) {
      normalized[key] = requiredText(data, key);
    }
    for (final key in ['estimated_calories', 'protein_g', 'carbs_g', 'fat_g']) {
      normalized[key] = nonNegativeNumber(data, key);
    }
    final score = nonNegativeNumber(data, 'health_score');
    if (score < 1 || score > 10 || score != score.roundToDouble())
      throw const FormatException('健康評分必須介於 1 到 10。');
    normalized['health_score'] = score.toInt();
    if (data['fiber_g'] != null)
      normalized['fiber_g'] = nonNegativeNumber(data, 'fiber_g');
    return NutritionAnalysis._(normalized);
  }
  Map<String, dynamic> toJson() => Map.of(data);
  static final responseFormat = structuredFormat(
    'nutrition_analysis',
    strictObject({
      'is_food': {'type': 'boolean'},
      for (final key in [
        'food_name',
        'estimated_portion',
        'category',
        'suggestions',
        'error_message',
      ])
        key: {
          'type': ['string', 'null'],
        },
      for (final key in [
        'estimated_calories',
        'protein_g',
        'carbs_g',
        'fat_g',
        'fiber_g',
        'health_score',
      ])
        key: {
          'type': ['number', 'null'],
        },
    }),
  );
}
