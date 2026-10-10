import 'package:flutter/material.dart';

/// HealthPal - 統一色彩系統
/// 根據 UI 改進建議，一個頁面最多出現 3 種主要顏色
class AppColors {
  AppColors._();

  // ============ 主色系 ============
  /// 主色（品牌色）- icon 藍綠色
  static const Color primary = Color(0xFF35B5D1);

  /// 主色淺（背景用）
  static const Color primaryLight = Color(0xFFE0F7FA);

  /// 主色深（按下狀態）
  static const Color primaryDark = Color(0xFF2196A8);

  // ============ 狀態顏色（2025 降低飽和度）============
  /// 成功/正常 - 綠色
  static const Color success = Color(0xFF22C55E);
  static const Color successLight = Color(0xFFDCFCE7);

  /// 警告/偏高 - 紅色（與登出按鈕同色）
  static const Color warning = Color(0xFFEF4444);
  static const Color warningLight = Color(0xFFFEF2F2);

  /// 危險/異常 - 紅色
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEF2F2);

  /// 偏低 - 藍色
  static const Color low = Color(0xFF3B82F6);
  static const Color lowLight = Color(0xFFEFF6FF);

  // ============ 中性色 ============
  /// 頁面背景 - 帶藍調的灰白
  static const Color background = Color(0xFFF5F7FA);

  /// 卡片背景 - 白色
  static const Color surface = Color(0xFFFFFFFF);

  /// 主要文字 - 深灰
  static const Color textPrimary = Color(0xFF1E293B);

  /// 次要文字 - 中灰
  static const Color textSecondary = Color(0xFF64748B);

  /// 輔助文字 - 淺灰
  static const Color textHint = Color(0xFF94A3B8);

  /// 分隔線/邊框 - 淺灰
  static const Color border = Color(0xFFE2E8F0);

  /// 禁用狀態
  static const Color disabled = Color(0xFFCBD5E1);

  // ============ 健康類別顏色 ============
  /// 心率 - 粉紅色
  static const Color heartRate = Color(0xFFE91E63);
  static const Color heartRateLight = Color(0xFFFCE4EC);

  /// 睡眠 - 紫色
  static const Color sleep = Color(0xFF8B5CF6);
  static const Color sleepLight = Color(0xFFF3E8FF);

  /// 運動 - 橘色
  static const Color exercise = Color(0xFFFF5722);
  static const Color exerciseLight = Color(0xFFFBE9E7);

  // ============ 健康狀態顏色映射 ============
  /// 根據健康狀態返回對應顏色
  static Color getStatusColor(HealthStatus status) {
    switch (status) {
      case HealthStatus.normal:
        return success;
      case HealthStatus.high:
        return warning;
      case HealthStatus.veryHigh:
        return error;
      case HealthStatus.low:
        return low;
      case HealthStatus.veryLow:
        return error;
    }
  }

  /// 根據健康狀態返回對應淺色背景
  static Color getStatusLightColor(HealthStatus status) {
    switch (status) {
      case HealthStatus.normal:
        return successLight;
      case HealthStatus.high:
        return warningLight;
      case HealthStatus.veryHigh:
        return errorLight;
      case HealthStatus.low:
        return lowLight;
      case HealthStatus.veryLow:
        return errorLight;
    }
  }

  /// 根據健康狀態返回中文文字
  static String getStatusText(HealthStatus status) {
    switch (status) {
      case HealthStatus.normal:
        return '正常';
      case HealthStatus.high:
        return '偏高';
      case HealthStatus.veryHigh:
        return '過高';
      case HealthStatus.low:
        return '偏低';
      case HealthStatus.veryLow:
        return '過低';
    }
  }
}

/// 健康狀態枚舉
enum HealthStatus {
  normal,
  high,
  veryHigh,
  low,
  veryLow,
}
