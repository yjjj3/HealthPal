// lib/services/login_security_service.dart
// 登入安全服務 - 處理登入失敗次數限制

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginSecurityService {
  static final LoginSecurityService _instance = LoginSecurityService._internal();
  factory LoginSecurityService() => _instance;
  LoginSecurityService._internal();

  // 設定常數
  static const int maxFailedAttempts = 5; // 最大失敗次數
  static const int lockoutDurationMinutes = 15; // 鎖定時間（分鐘）
  static const String _failedAttemptsKey = 'login_failed_attempts';
  static const String _lockoutEndTimeKey = 'login_lockout_end_time';
  static const String _lastFailedEmailKey = 'login_last_failed_email';

  /// 檢查帳號是否被鎖定
  Future<bool> isAccountLocked(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final lastFailedEmail = prefs.getString(_lastFailedEmailKey);

    // 如果是不同的 email，不受之前鎖定影響
    if (lastFailedEmail != email) {
      return false;
    }

    final lockoutEndTime = prefs.getInt(_lockoutEndTimeKey);
    if (lockoutEndTime == null) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < lockoutEndTime) {
      return true;
    }

    // 鎖定時間已過，清除鎖定狀態
    await _clearLockout();
    return false;
  }

  /// 取得剩餘鎖定時間（秒）
  Future<int> getRemainingLockoutSeconds(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final lastFailedEmail = prefs.getString(_lastFailedEmailKey);

    if (lastFailedEmail != email) return 0;

    final lockoutEndTime = prefs.getInt(_lockoutEndTimeKey);
    if (lockoutEndTime == null) return 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = ((lockoutEndTime - now) / 1000).ceil();
    return remaining > 0 ? remaining : 0;
  }

  /// 取得剩餘嘗試次數
  Future<int> getRemainingAttempts(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final lastFailedEmail = prefs.getString(_lastFailedEmailKey);

    // 如果是不同的 email，給予完整嘗試次數
    if (lastFailedEmail != email) {
      return maxFailedAttempts;
    }

    final failedAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
    return maxFailedAttempts - failedAttempts;
  }

  /// 記錄登入失敗
  Future<LoginAttemptResult> recordFailedAttempt(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final lastFailedEmail = prefs.getString(_lastFailedEmailKey);

    int failedAttempts;
    if (lastFailedEmail != email) {
      // 新的 email，重置計數
      failedAttempts = 1;
      await prefs.setString(_lastFailedEmailKey, email);
    } else {
      failedAttempts = (prefs.getInt(_failedAttemptsKey) ?? 0) + 1;
    }

    await prefs.setInt(_failedAttemptsKey, failedAttempts);

    debugPrint('Login Security: Failed attempt $failedAttempts/$maxFailedAttempts for $email');

    if (failedAttempts >= maxFailedAttempts) {
      // 達到最大失敗次數，鎖定帳號
      final lockoutEndTime = DateTime.now()
          .add(Duration(minutes: lockoutDurationMinutes))
          .millisecondsSinceEpoch;
      await prefs.setInt(_lockoutEndTimeKey, lockoutEndTime);

      debugPrint('Login Security: Account locked for $lockoutDurationMinutes minutes');

      return LoginAttemptResult(
        isLocked: true,
        remainingAttempts: 0,
        lockoutSeconds: lockoutDurationMinutes * 60,
        message: '登入失敗次數過多，帳號已被暫時鎖定 $lockoutDurationMinutes 分鐘',
      );
    }

    final remaining = maxFailedAttempts - failedAttempts;
    return LoginAttemptResult(
      isLocked: false,
      remainingAttempts: remaining,
      lockoutSeconds: 0,
      message: '密碼錯誤，還剩 $remaining 次嘗試機會',
    );
  }

  /// 登入成功，清除失敗記錄
  Future<void> recordSuccessfulLogin(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final lastFailedEmail = prefs.getString(_lastFailedEmailKey);

    if (lastFailedEmail == email) {
      await _clearLockout();
    }

    debugPrint('Login Security: Successful login, cleared failed attempts for $email');
  }

  /// 清除鎖定狀態
  Future<void> _clearLockout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_lockoutEndTimeKey);
    await prefs.remove(_lastFailedEmailKey);
  }

  /// 格式化剩餘時間顯示
  String formatRemainingTime(int seconds) {
    if (seconds <= 0) return '';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '$minutes 分 $secs 秒';
    }
    return '$secs 秒';
  }
}

/// 登入嘗試結果
class LoginAttemptResult {
  final bool isLocked;
  final int remainingAttempts;
  final int lockoutSeconds;
  final String message;

  LoginAttemptResult({
    required this.isLocked,
    required this.remainingAttempts,
    required this.lockoutSeconds,
    required this.message,
  });
}
