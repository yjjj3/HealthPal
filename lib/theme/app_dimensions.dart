import 'package:flutter/material.dart';

/// HealthPal - 統一間距與圓角系統
/// 使用 8px 倍數作為基礎間距單位
class AppDimensions {
  AppDimensions._();

  // ============ 基礎間距單位 ============
  static const double unit = 8.0;

  // ============ 間距 (Spacing) ============

  /// 元素內間距（icon 與文字）- 8px
  static const double spacingXs = 8.0;

  /// 小間距 - 12px
  static const double spacingSm = 12.0;

  /// 卡片內間距 - 16px
  static const double spacingMd = 16.0;

  /// 區塊之間 - 24px
  static const double spacingLg = 24.0;

  /// 大區塊間距 - 32px
  static const double spacingXl = 32.0;

  /// 頁面左右邊距 - 20px
  static const double pagePadding = 20.0;

  /// 卡片之間的間距 - 12px
  static const double cardGap = 12.0;

  // ============ 圓角 (Border Radius) ============

  /// 卡片圓角 - 16px
  static const double radiusCard = 16.0;

  /// 按鈕圓角 - 12px
  static const double radiusButton = 12.0;

  /// 輸入框圓角 - 10px
  static const double radiusInput = 10.0;

  /// Tag 標籤圓角 - 8px
  static const double radiusTag = 8.0;

  /// 小圖示背景圓角 - 10px
  static const double radiusIcon = 10.0;

  /// Dialog 彈窗圓角 - 20px
  static const double radiusDialog = 20.0;

  /// 狀態指示圓點 - 完全圓形
  static const double radiusCircle = 999.0;

  // ============ Icon 大小 ============

  /// 導航列 icon - 24px
  static const double iconNav = 24.0;

  /// 卡片內 icon - 20px
  static const double iconCard = 20.0;

  /// 按鈕內 icon - 18px
  static const double iconButton = 18.0;

  /// 小 icon - 16px
  static const double iconSmall = 16.0;

  /// 狀態指示圓點 - 8px
  static const double statusDot = 8.0;

  // ============ 卡片樣式（2025 柔和陰影）============

  /// 卡片陰影 - 2025 柔和風格
  /// shadow: 0 2px 8px rgba(0,0,0,0.06)
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// 輕微陰影
  static List<BoxShadow> get lightShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 1),
        ),
      ];

  /// 強調陰影（懸浮/按下狀態）
  static List<BoxShadow> get elevatedShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  /// 左側狀態色條寬度
  static const double statusBarWidth = 4.0;

  // ============ 便利方法 ============

  /// 頁面內容的 EdgeInsets
  static const EdgeInsets pagePaddingH = EdgeInsets.symmetric(
    horizontal: pagePadding,
  );

  /// 卡片內 padding
  static const EdgeInsets cardPadding = EdgeInsets.all(spacingMd);

  /// 區塊間距
  static const EdgeInsets sectionPadding = EdgeInsets.only(bottom: spacingLg);

  /// 標準圓角
  static BorderRadius get cardBorderRadius =>
      BorderRadius.circular(radiusCard);

  static BorderRadius get buttonBorderRadius =>
      BorderRadius.circular(radiusButton);

  static BorderRadius get inputBorderRadius =>
      BorderRadius.circular(radiusInput);

  static BorderRadius get tagBorderRadius =>
      BorderRadius.circular(radiusTag);

  static BorderRadius get dialogBorderRadius =>
      BorderRadius.circular(radiusDialog);
}
