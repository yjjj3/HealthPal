// lib/utils/password_validator.dart
// 共用密碼驗證工具

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 密碼強度等級
enum PasswordStrength {
  weak,
  medium,
  strong,
}

/// 密碼驗證結果
class PasswordValidationResult {
  final bool isValid;
  final String? errorMessage;
  final PasswordStrength strength;
  final List<PasswordRequirement> requirements;

  const PasswordValidationResult({
    required this.isValid,
    this.errorMessage,
    required this.strength,
    required this.requirements,
  });
}

/// 密碼要求項目
class PasswordRequirement {
  final String description;
  final bool isMet;

  const PasswordRequirement({
    required this.description,
    required this.isMet,
  });
}

/// 密碼驗證器
class PasswordValidator {
  /// 最小密碼長度
  static const int minLength = 8;

  /// 驗證密碼並返回詳細結果
  static PasswordValidationResult validate(String? password) {
    if (password == null || password.isEmpty) {
      return PasswordValidationResult(
        isValid: false,
        errorMessage: '密碼為必填欄位',
        strength: PasswordStrength.weak,
        requirements: _getRequirements(''),
      );
    }

    final requirements = _getRequirements(password);
    final allMet = requirements.every((r) => r.isMet);
    final strength = _calculateStrength(password, requirements);

    if (!allMet) {
      // 找出第一個未滿足的要求作為錯誤訊息
      final firstUnmet = requirements.firstWhere((r) => !r.isMet);
      return PasswordValidationResult(
        isValid: false,
        errorMessage: firstUnmet.description,
        strength: strength,
        requirements: requirements,
      );
    }

    return PasswordValidationResult(
      isValid: true,
      errorMessage: null,
      strength: strength,
      requirements: requirements,
    );
  }

  /// 簡單驗證（用於 FormField validator）
  static String? validateSimple(String? password) {
    final result = validate(password);
    return result.errorMessage;
  }

  /// 取得密碼要求列表
  static List<PasswordRequirement> _getRequirements(String password) {
    return [
      PasswordRequirement(
        description: '密碼必須至少 $minLength 個字元',
        isMet: password.length >= minLength,
      ),
      PasswordRequirement(
        description: '密碼必須包含英文字母',
        isMet: RegExp(r'[A-Za-z]').hasMatch(password),
      ),
      PasswordRequirement(
        description: '密碼必須包含數字',
        isMet: RegExp(r'[0-9]').hasMatch(password),
      ),
    ];
  }

  /// 計算密碼強度
  static PasswordStrength _calculateStrength(
    String password,
    List<PasswordRequirement> requirements,
  ) {
    final metCount = requirements.where((r) => r.isMet).length;
    final hasSpecialChar = RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
    final hasUpperAndLower =
        RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password);

    // 基本要求都沒滿足
    if (metCount < requirements.length) {
      return PasswordStrength.weak;
    }

    // 滿足基本要求 + 額外條件
    if (password.length >= 12 && hasSpecialChar && hasUpperAndLower) {
      return PasswordStrength.strong;
    }

    if (password.length >= 10 || hasSpecialChar || hasUpperAndLower) {
      return PasswordStrength.medium;
    }

    return PasswordStrength.weak;
  }

  /// 取得強度對應的顏色
  static Color getStrengthColor(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.weak:
        return AppColors.error;
      case PasswordStrength.medium:
        return Colors.orange;
      case PasswordStrength.strong:
        return AppColors.success;
    }
  }

  /// 取得強度對應的文字
  static String getStrengthText(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.weak:
        return '弱';
      case PasswordStrength.medium:
        return '中';
      case PasswordStrength.strong:
        return '強';
    }
  }

  /// 取得強度進度值 (0.0 - 1.0)
  static double getStrengthProgress(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.weak:
        return 0.33;
      case PasswordStrength.medium:
        return 0.66;
      case PasswordStrength.strong:
        return 1.0;
    }
  }
}

/// 密碼強度指示器 Widget
class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({
    super.key,
    required this.password,
  });

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) {
      return const SizedBox.shrink();
    }

    final result = PasswordValidator.validate(password);
    final strength = result.strength;
    final color = PasswordValidator.getStrengthColor(strength);
    final text = PasswordValidator.getStrengthText(strength);
    final progress = PasswordValidator.getStrengthProgress(strength);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '密碼強度：$text',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...result.requirements.map((req) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    req.isMet ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: req.isMet ? AppColors.success : Colors.grey[400],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    req.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: req.isMet ? AppColors.success : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
