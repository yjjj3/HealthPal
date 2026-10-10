import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// 健康數據卡片
/// 2025 設計：白色背景 + 柔和陰影，無邊框
/// 使用小圓點或標籤底色表示狀態
///
/// 設計規格：
/// ┌────────────────────────┐
/// │ ●  血壓                 │ ← 左上角小圓點表示狀態顏色
/// │                        │
/// │ 120/80                 │ ← 大數字，Semibold
/// │ mmHg        正常       │ ← 單位小字 + 狀態標籤
/// └────────────────────────┘
class HealthDataCard extends StatelessWidget {
  /// 標題（如：血壓、血糖）
  final String title;

  /// 主要數值（如：120/80）
  final String value;

  /// 單位（如：mmHg、mg/dL）
  final String unit;

  /// 健康狀態
  final HealthStatus status;

  /// 副標題/說明（可選）
  final String? subtitle;

  /// icon（可選，使用線條風格 icon）
  final IconData? icon;

  /// 點擊事件
  final VoidCallback? onTap;

  const HealthDataCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.status,
    this.subtitle,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = AppColors.getStatusColor(status);
    final statusText = AppColors.getStatusText(status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: AppDimensions.cardPadding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDimensions.cardBorderRadius,
          boxShadow: AppDimensions.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題列：狀態圓點 + 標題 + icon
            Row(
              children: [
                // 狀態指示圓點
                Container(
                  width: AppDimensions.statusDot,
                  height: AppDimensions.statusDot,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingXs),
                // 標題
                Text(title, style: AppTextStyles.cardTitle),
                const Spacer(),
                // 可選 icon
                if (icon != null)
                  Icon(
                    icon,
                    size: AppDimensions.iconCard,
                    color: AppColors.textSecondary,
                  ),
              ],
            ),

            const SizedBox(height: AppDimensions.spacingSm),

            // 數值
            Text(value, style: AppTextStyles.dataLarge),

            const SizedBox(height: AppDimensions.spacingXs),

            // 單位 + 狀態標籤
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(unit, style: AppTextStyles.unit),
                // 狀態標籤
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.getStatusLightColor(status),
                    borderRadius: AppDimensions.tagBorderRadius,
                  ),
                  child: Text(
                    statusText,
                    style: AppTextStyles.label.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            // 可選副標題
            if (subtitle != null) ...[
              const SizedBox(height: AppDimensions.spacingXs),
              Text(subtitle!, style: AppTextStyles.caption),
            ],
          ],
        ),
      ),
    );
  }
}

/// 迷你健康數據卡片（用於儀表板網格）
class HealthDataCardMini extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final HealthStatus status;
  final IconData? icon;
  final VoidCallback? onTap;

  const HealthDataCardMini({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.status,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = AppColors.getStatusColor(status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spacingSm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDimensions.cardBorderRadius,
          boxShadow: AppDimensions.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 標題列
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 數值
            Text(value, style: AppTextStyles.dataSmall),
            const SizedBox(height: 2),
            // 單位
            Text(unit, style: AppTextStyles.unit),
          ],
        ),
      ),
    );
  }
}

/// 帶左側色條的健康數據卡片（替代方案）
class HealthDataCardWithBar extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final HealthStatus status;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;

  const HealthDataCardWithBar({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.status,
    this.subtitle,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = AppColors.getStatusColor(status);
    final statusText = AppColors.getStatusText(status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDimensions.cardBorderRadius,
          boxShadow: AppDimensions.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: AppDimensions.cardBorderRadius,
          child: Row(
            children: [
              // 左側狀態色條
              Container(
                width: AppDimensions.statusBarWidth,
                height: double.infinity,
                color: statusColor,
              ),
              // 內容
              Expanded(
                child: Padding(
                  padding: AppDimensions.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 標題
                      Row(
                        children: [
                          Text(title, style: AppTextStyles.cardTitle),
                          const Spacer(),
                          if (icon != null)
                            Icon(
                              icon,
                              size: AppDimensions.iconCard,
                              color: AppColors.textSecondary,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.spacingSm),
                      // 數值
                      Text(value, style: AppTextStyles.dataLarge),
                      const SizedBox(height: AppDimensions.spacingXs),
                      // 單位 + 狀態
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(unit, style: AppTextStyles.unit),
                          Text(
                            statusText,
                            style: AppTextStyles.label.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppDimensions.spacingXs),
                        Text(subtitle!, style: AppTextStyles.caption),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
