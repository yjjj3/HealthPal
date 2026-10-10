import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 健康類別群組
enum CategoryGroup {
  vital,      // 生命徵象
  body,       // 身體數據
  lifestyle,  // 生活習慣
  nutrition,  // 營養攝取
}

/// 輸入類型
enum InputType {
  singleNumber,   // 單一數值 (心率、血糖、體溫等)
  dualNumber,     // 雙數值 (血壓)
  slider,         // 滑桿 (睡眠、運動時長)
  dropdown,       // 下拉選單 + 數值 (運動類型)
  water,          // 水分攝取專用
}

/// 健康類別定義
class HealthCategory {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final CategoryGroup group;
  final InputType inputType;
  final String unit;
  final String defaultValue;
  final double? minValue;
  final double? maxValue;
  final int? divisions;
  final String? hintText;
  final String? normalRangeHint;
  final List<String>? dropdownOptions;
  final bool hasTimingOptions;

  const HealthCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.group,
    required this.inputType,
    required this.unit,
    required this.defaultValue,
    this.minValue,
    this.maxValue,
    this.divisions,
    this.hintText,
    this.normalRangeHint,
    this.dropdownOptions,
    this.hasTimingOptions = false,
  });
}

/// 健康類別註冊表 - 集中管理所有類別
class HealthCategoryRegistry {
  static final List<HealthCategory> _categories = [
    // ===== 生命徵象 =====
    const HealthCategory(
      id: 'blood_pressure',
      name: '血壓',
      icon: Icons.favorite_rounded,
      color: AppColors.error,
      group: CategoryGroup.vital,
      inputType: InputType.dualNumber,
      unit: 'mmHg',
      defaultValue: '120/80',
      hintText: '收縮壓/舒張壓',
      normalRangeHint: '正常範圍：90-120/60-80 mmHg',
    ),
    const HealthCategory(
      id: 'heart_rate',
      name: '心率',
      icon: Icons.monitor_heart_rounded,
      color: AppColors.heartRate,
      group: CategoryGroup.vital,
      inputType: InputType.singleNumber,
      unit: 'bpm',
      defaultValue: '72',
      hintText: '每分鐘心跳次數',
      normalRangeHint: '正常靜息心率：60-100 bpm',
      minValue: 30,
      maxValue: 220,
    ),
    const HealthCategory(
      id: 'blood_glucose',
      name: '血糖',
      icon: Icons.water_drop_rounded,
      color: AppColors.warning,
      group: CategoryGroup.vital,
      inputType: InputType.singleNumber,
      unit: 'mg/dL',
      defaultValue: '100',
      hintText: '血糖值',
      normalRangeHint: '空腹：70-100，餐後2小時：<140 mg/dL',
      minValue: 20,
      maxValue: 600,
      hasTimingOptions: true,
    ),
    const HealthCategory(
      id: 'blood_oxygen',
      name: '血氧',
      icon: Icons.air_rounded,
      color: Color(0xFF2196F3),
      group: CategoryGroup.vital,
      inputType: InputType.singleNumber,
      unit: '%',
      defaultValue: '98',
      hintText: '血氧飽和度',
      normalRangeHint: '正常範圍：95-100%',
      minValue: 70,
      maxValue: 100,
    ),
    const HealthCategory(
      id: 'body_temperature',
      name: '體溫',
      icon: Icons.thermostat_rounded,
      color: Color(0xFFFF7043),
      group: CategoryGroup.vital,
      inputType: InputType.singleNumber,
      unit: '°C',
      defaultValue: '36.5',
      hintText: '體溫',
      normalRangeHint: '正常範圍：36.1-37.2°C',
      minValue: 34.0,
      maxValue: 42.0,
    ),

    // ===== 身體數據 =====
    const HealthCategory(
      id: 'weight',
      name: '體重',
      icon: Icons.monitor_weight_rounded,
      color: AppColors.primary,
      group: CategoryGroup.body,
      inputType: InputType.singleNumber,
      unit: 'kg',
      defaultValue: '70',
      hintText: '體重',
      minValue: 20,
      maxValue: 300,
    ),
    const HealthCategory(
      id: 'body_fat',
      name: '體脂肪',
      icon: Icons.percent_rounded,
      color: Color(0xFF8D6E63),
      group: CategoryGroup.body,
      inputType: InputType.singleNumber,
      unit: '%',
      defaultValue: '20',
      hintText: '體脂肪率',
      normalRangeHint: '男性：10-20%，女性：18-28%',
      minValue: 3,
      maxValue: 60,
    ),
    const HealthCategory(
      id: 'waist',
      name: '腰圍',
      icon: Icons.straighten_rounded,
      color: Color(0xFF7E57C2),
      group: CategoryGroup.body,
      inputType: InputType.singleNumber,
      unit: 'cm',
      defaultValue: '80',
      hintText: '腰圍',
      normalRangeHint: '男性：<90cm，女性：<80cm',
      minValue: 40,
      maxValue: 200,
    ),

    // ===== 生活習慣 =====
    const HealthCategory(
      id: 'sleep',
      name: '睡眠',
      icon: Icons.bedtime_rounded,
      color: AppColors.sleep,
      group: CategoryGroup.lifestyle,
      inputType: InputType.slider,
      unit: '小時',
      defaultValue: '7',
      minValue: 0,
      maxValue: 14,
      divisions: 28,
      normalRangeHint: '建議成人睡眠：7-9 小時',
    ),
    const HealthCategory(
      id: 'exercise',
      name: '運動',
      icon: Icons.directions_run_rounded,
      color: AppColors.exercise,
      group: CategoryGroup.lifestyle,
      inputType: InputType.dropdown,
      unit: '分鐘',
      defaultValue: '30',
      minValue: 5,
      maxValue: 180,
      divisions: 35,
      dropdownOptions: ['跑步', '走路', '騎車', '游泳', '瑜珈', '重訓', '球類運動', '其他'],
    ),
    // ===== 營養攝取 =====
    const HealthCategory(
      id: 'water',
      name: '水分',
      icon: Icons.local_drink_rounded,
      color: Color(0xFF29B6F6),
      group: CategoryGroup.nutrition,
      inputType: InputType.water,
      unit: 'ml',
      defaultValue: '250',
      hintText: '飲水量',
      normalRangeHint: '建議每日：2000-2500 ml',
    ),
    const HealthCategory(
      id: 'calories',
      name: '卡路里',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFFF5722),
      group: CategoryGroup.nutrition,
      inputType: InputType.singleNumber,
      unit: 'kcal',
      defaultValue: '500',
      hintText: '攝取卡路里',
      minValue: 0,
      maxValue: 10000,
    ),
  ];

  /// 獲取所有類別
  static List<HealthCategory> get all => _categories;

  /// 依群組獲取類別
  static List<HealthCategory> byGroup(CategoryGroup group) {
    return _categories.where((c) => c.group == group).toList();
  }

  /// 依 ID 獲取類別
  static HealthCategory? byId(String id) {
    try {
      return _categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 依名稱獲取類別
  static HealthCategory? byName(String name) {
    try {
      return _categories.firstWhere((c) => c.name == name);
    } catch (_) {
      return null;
    }
  }

  /// 獲取群組名稱
  static String getGroupName(CategoryGroup group) {
    switch (group) {
      case CategoryGroup.vital:
        return '生命徵象';
      case CategoryGroup.body:
        return '身體數據';
      case CategoryGroup.lifestyle:
        return '生活習慣';
      case CategoryGroup.nutrition:
        return '營養攝取';
    }
  }

  /// 獲取群組圖標
  static IconData getGroupIcon(CategoryGroup group) {
    switch (group) {
      case CategoryGroup.vital:
        return Icons.monitor_heart_outlined;
      case CategoryGroup.body:
        return Icons.accessibility_new_rounded;
      case CategoryGroup.lifestyle:
        return Icons.self_improvement_rounded;
      case CategoryGroup.nutrition:
        return Icons.restaurant_rounded;
    }
  }

  /// 獲取所有類別名稱（用於向後相容）
  static List<String> get allNames => _categories.map((c) => c.name).toList();

  /// 傳統方法：依名稱獲取圖標
  static IconData getIcon(String categoryName) {
    return byName(categoryName)?.icon ?? Icons.assignment_rounded;
  }

  /// 傳統方法：依名稱獲取顏色
  static Color getColor(String categoryName) {
    return byName(categoryName)?.color ?? AppColors.textSecondary;
  }

  /// 傳統方法：依名稱獲取預設值
  static Map<String, String> getDefaultValueParts(String categoryName) {
    final category = byName(categoryName);
    if (category == null) {
      return {'value': '', 'unit': ''};
    }
    return {'value': category.defaultValue, 'unit': category.unit};
  }
}
