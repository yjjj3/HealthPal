import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// 區塊卡片 - 用於包裝一組相關內容
class SectionCard extends StatelessWidget {
  /// 區塊標題
  final String? title;

  /// 標題右側操作按鈕文字
  final String? actionText;

  /// 操作按鈕點擊事件
  final VoidCallback? onActionTap;

  /// 卡片內容
  final Widget child;

  /// 是否顯示邊框
  final bool showBorder;

  /// 內間距
  final EdgeInsets? padding;

  const SectionCard({
    super.key,
    this.title,
    this.actionText,
    this.onActionTap,
    required this.child,
    this.showBorder = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDimensions.cardBorderRadius,
        boxShadow: showBorder ? AppDimensions.cardShadow : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.spacingMd,
                AppDimensions.spacingMd,
                AppDimensions.spacingMd,
                AppDimensions.spacingSm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title!, style: AppTextStyles.title),
                  if (actionText != null)
                    GestureDetector(
                      onTap: onActionTap,
                      child: Text(
                        actionText!,
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // 內容
          Padding(
            padding: padding ?? const EdgeInsets.fromLTRB(
              AppDimensions.spacingMd,
              0,
              AppDimensions.spacingMd,
              AppDimensions.spacingMd,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// 區塊標題元件（用於頁面區塊分隔）
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onActionTap;
  final EdgeInsets? padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onActionTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(
        bottom: AppDimensions.spacingSm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppTextStyles.title),
          if (actionText != null)
            GestureDetector(
              onTap: onActionTap,
              child: Row(
                children: [
                  Text(
                    actionText!,
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 空狀態元件
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? actionText;
  final VoidCallback? onActionTap;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionText,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            Text(
              title,
              style: AppTextStyles.cardTitle,
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: AppDimensions.spacingXs),
              Text(
                description!,
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionText != null && onActionTap != null) ...[
              const SizedBox(height: AppDimensions.spacingMd),
              ElevatedButton(
                onPressed: onActionTap,
                child: Text(actionText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
