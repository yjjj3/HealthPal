class NutritionAnalysis {
  final String foodName;
  final int? estimatedCalories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final int? healthScore; // 1-10
  final String? suggestions;
  final String? portionSize;
  final DateTime? analyzedAt;

  NutritionAnalysis({
    required this.foodName,
    this.estimatedCalories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    this.healthScore,
    this.suggestions,
    this.portionSize,
    this.analyzedAt,
  });

  factory NutritionAnalysis.fromJson(Map<String, dynamic> json) {
    return NutritionAnalysis(
      foodName: json['food_name'] ?? '未知食物',
      estimatedCalories: json['estimated_calories'],
      proteinG: json['protein_g']?.toDouble(),
      carbsG: json['carbs_g']?.toDouble(),
      fatG: json['fat_g']?.toDouble(),
      fiberG: json['fiber_g']?.toDouble(),
      healthScore: json['health_score'],
      suggestions: json['suggestions'],
      portionSize: json['portion_size'],
      analyzedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'food_name': foodName,
      'estimated_calories': estimatedCalories,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'fat_g': fatG,
      'fiber_g': fiberG,
      'health_score': healthScore,
      'suggestions': suggestions,
      'portion_size': portionSize,
      'analyzed_at': analyzedAt?.toIso8601String(),
    };
  }

  // 計算總熱量（用於多種食物）
  static int calculateTotalCalories(List<NutritionAnalysis> analyses) {
    return analyses.fold(
      0,
      (sum, analysis) => sum + (analysis.estimatedCalories ?? 0),
    );
  }

  // 評估飲食平衡
  String get balanceAssessment {
    if (proteinG == null || carbsG == null || fatG == null) {
      return '營養數據不足';
    }

    final proteinPercent = (proteinG! * 4) / (estimatedCalories ?? 1) * 100;
    final carbsPercent = (carbsG! * 4) / (estimatedCalories ?? 1) * 100;
    final fatPercent = (fatG! * 9) / (estimatedCalories ?? 1) * 100;

    if (proteinPercent >= 15 && proteinPercent <= 30 &&
        carbsPercent >= 45 && carbsPercent <= 65 &&
        fatPercent >= 20 && fatPercent <= 35) {
      return '營養均衡';
    } else if (proteinPercent > 30) {
      return '蛋白質偏高';
    } else if (carbsPercent > 65) {
      return '碳水化合物偏高';
    } else if (fatPercent > 35) {
      return '脂肪偏高';
    } else {
      return '營養比例需調整';
    }
  }
}