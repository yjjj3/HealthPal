import 'package:flutter/material.dart';
import 'app_colors.dart';

/// HealthPal - 統一字體系統
/// 使用 SF Pro Display 字體，數字使用 Semibold/Bold 突出重要數據
class AppTextStyles {
  AppTextStyles._();

  static const String _fontFamily = 'SF Pro Display';

  // ============ 標題層級 ============

  /// 大標題 - 24px Bold
  /// 用於：頁面標題（健康分析、我的用藥）
  static const TextStyle headline = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  /// 標題 - 18px Semibold
  /// 用於：區塊標題（今日待辦、健康趨勢）
  static const TextStyle title = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// 卡片標題 - 16px Medium
  /// 用於：卡片內標題（血壓、血糖）
  static const TextStyle cardTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  // ============ 內文層級 ============

  /// 內文 - 15px Regular
  /// 用於：一般內容
  static const TextStyle body = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  /// 內文次要 - 15px Regular（次要顏色）
  static const TextStyle bodySecondary = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  /// 輔助文字 - 13px Regular
  /// 用於：時間、說明文字
  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  /// 標籤 - 12px Medium
  /// 用於：Tag、狀態標籤
  static const TextStyle label = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.3,
  );

  // ============ 數據展示 ============

  /// 大數據 - 28px Bold
  /// 用於：健康數據主要數值（血壓、血糖等）
  static const TextStyle dataLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  /// 中數據 - 22px Semibold
  /// 用於：次要數據
  static const TextStyle dataMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  /// 小數據 - 18px Semibold
  static const TextStyle dataSmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  /// 單位文字 - 12px Regular
  /// 用於：mmHg、mg/dL 等單位
  static const TextStyle unit = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.3,
  );

  // ============ 按鈕文字 ============

  /// 主要按鈕 - 16px Semibold
  static const TextStyle buttonPrimary = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    height: 1.2,
  );

  /// 次要按鈕 - 14px Medium
  static const TextStyle buttonSecondary = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.primary,
    height: 1.2,
  );

  // ============ 輔助方法 ============

  /// 創建帶狀態顏色的標籤樣式
  static TextStyle statusLabel(HealthStatus status) {
    return label.copyWith(
      color: AppColors.getStatusColor(status),
      fontWeight: FontWeight.w600,
    );
  }

  /// 創建帶自定義顏色的數據樣式
  static TextStyle dataWithColor(Color color, {bool large = true}) {
    return (large ? dataLarge : dataMedium).copyWith(color: color);
  }
}
