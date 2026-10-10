import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// 用藥卡片狀態
enum MedicationStatus {
  pending,   // 待服用
  taken,     // 已服用
  skipped,   // 已跳過
  overdue,   // 已逾時
}

/// 用藥卡片
///
/// 設計規格：
/// ┌────────────────────────┐
/// │ 💊  服用 VC (1顆)        │ ← 統一風格的藥丸 icon
/// │ 上午 08:00 · 每天1次    │
/// │                 [完成]  │ ← 按鈕改成填滿的主色
/// └────────────────────────┘
class MedicationCard extends StatelessWidget {
  /// 藥品名稱
  final String name;

  /// 劑量說明（如：1顆、2片）
  final String dosage;

  /// 服用時間（如：上午 08:00）
  final String time;

  /// 頻率（如：每天1次）
  final String frequency;

  /// 用藥狀態
  final MedicationStatus status;

  /// 完成按鈕點擊
  final VoidCallback? onComplete;

  /// 跳過按鈕點擊
  final VoidCallback? onSkip;

  /// 卡片點擊（查看詳情）
  final VoidCallback? onTap;

  const MedicationCard({
    super.key,
    required this.name,
    required this.dosage,
    required this.time,
    required this.frequency,
    this.status = MedicationStatus.pending,
    this.onComplete,
    this.onSkip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
            // 第一列：藥丸 icon + 藥品名稱與劑量
            Row(
              children: [
                // 藥丸 icon 背景
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getStatusBackgroundColor(),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusIcon),
                  ),
                  child: Icon(
                    Icons.medication_outlined,
                    size: AppDimensions.iconCard,
                    color: _getStatusColor(),
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingSm),
                // 藥品資訊
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '服用 $name ($dosage)',
                        style: AppTextStyles.cardTitle,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$time · $frequency',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                // 狀態標籤（已完成/已跳過）
                if (status != MedicationStatus.pending)
                  _buildStatusBadge(),
              ],
            ),

            // 如果是待服用狀態，顯示操作按鈕
            if (status == MedicationStatus.pending) ...[
              const SizedBox(height: AppDimensions.spacingSm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 跳過按鈕
                  if (onSkip != null)
                    TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.spacingSm,
                          vertical: AppDimensions.spacingXs,
                        ),
                      ),
                      child: const Text('跳過'),
                    ),
                  const SizedBox(width: AppDimensions.spacingXs),
                  // 完成按鈕
                  if (onComplete != null)
                    ElevatedButton(
                      onPressed: onComplete,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.spacingMd,
                          vertical: AppDimensions.spacingXs,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppDimensions.buttonBorderRadius,
                        ),
                      ),
                      child: const Text('完成'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    String text;
    Color bgColor;
    Color textColor;

    switch (status) {
      case MedicationStatus.taken:
        text = '已服用';
        bgColor = AppColors.successLight;
        textColor = AppColors.success;
        break;
      case MedicationStatus.skipped:
        text = '已跳過';
        bgColor = AppColors.border;
        textColor = AppColors.textSecondary;
        break;
      case MedicationStatus.overdue:
        text = '已逾時';
        bgColor = AppColors.errorLight;
        textColor = AppColors.error;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppDimensions.tagBorderRadius,
      ),
      child: Text(
        text,
        style: AppTextStyles.label.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (status) {
      case MedicationStatus.pending:
        return AppColors.primary;
      case MedicationStatus.taken:
        return AppColors.success;
      case MedicationStatus.skipped:
        return AppColors.textSecondary;
      case MedicationStatus.overdue:
        return AppColors.error;
    }
  }

  Color _getStatusBackgroundColor() {
    switch (status) {
      case MedicationStatus.pending:
        return AppColors.primaryLight;
      case MedicationStatus.taken:
        return AppColors.successLight;
      case MedicationStatus.skipped:
        return AppColors.border;
      case MedicationStatus.overdue:
        return AppColors.errorLight;
    }
  }
}

/// 簡化版用藥提醒卡片（用於儀表板）
class MedicationReminderCard extends StatelessWidget {
  final String title;
  final int pendingCount;
  final int completedCount;
  final VoidCallback? onTap;

  const MedicationReminderCard({
    super.key,
    this.title = '今日用藥',
    required this.pendingCount,
    required this.completedCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = pendingCount + completedCount;
    final allDone = pendingCount == 0 && total > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: AppDimensions.cardPadding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDimensions.cardBorderRadius,
          boxShadow: AppDimensions.cardShadow,
        ),
        child: Row(
          children: [
            // 藥丸 icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: allDone ? AppColors.successLight : AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppDimensions.radiusIcon),
              ),
              child: Icon(
                allDone ? Icons.check_circle_outline : Icons.medication_outlined,
                size: 24,
                color: allDone ? AppColors.success : AppColors.primary,
              ),
            ),
            const SizedBox(width: AppDimensions.spacingSm),
            // 資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.cardTitle),
                  const SizedBox(height: 4),
                  Text(
                    allDone
                        ? '已完成全部 $total 項'
                        : '還有 $pendingCount 項待服用',
                    style: AppTextStyles.caption.copyWith(
                      color: allDone ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // 箭頭
            Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
              size: AppDimensions.iconCard,
            ),
          ],
        ),
      ),
    );
  }
}
