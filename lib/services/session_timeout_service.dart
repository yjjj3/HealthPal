import 'auth_service.dart';
// lib/services/session_timeout_service.dart
// 閒置自動登出服務

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionTimeoutService {
  static final SessionTimeoutService _instance =
      SessionTimeoutService._internal();
  factory SessionTimeoutService() => _instance;
  SessionTimeoutService._internal()
    : _currentUid = (() => FirebaseAuth.instance.currentUser?.uid),
      _signOut = (() => AuthService.logout.signOut()),
      _now = DateTime.now;

  SessionTimeoutService.forTesting({
    required String? Function() currentUid,
    required Future<bool> Function() signOut,
    DateTime Function()? now,
  }) : _currentUid = currentUid,
       _signOut = signOut,
       _now = now ?? DateTime.now;

  final String? Function() _currentUid;
  final Future<bool> Function() _signOut;
  final DateTime Function() _now;

  // 設定常數
  static const String _timeoutEnabledKey = 'session_timeout_enabled';
  static const String _timeoutDurationKey = 'session_timeout_duration';
  static const int defaultTimeoutMinutes = 5; // 預設閒置 5 分鐘

  Timer? _inactivityTimer;
  int _timerGeneration = 0;
  DateTime? _lastActivityTime;
  bool? _loadedEnabled;
  int? _loadedMinutes;
  VoidCallback? _onSessionExpired;

  /// 初始化服務
  Future<void> initialize({required VoidCallback onSessionExpired}) async {
    _onSessionExpired = onSessionExpired;
    _lastActivityTime = _now();
    await _startInactivityTimer();
    debugPrint('SessionTimeout: Service initialized');
  }

  /// 記錄用戶活動
  void recordActivity() {
    _lastActivityTime = _now();
    _resetInactivityTimer();
  }

  /// 檢查是否啟用閒置登出
  Future<bool> isTimeoutEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_timeoutEnabledKey) ?? true; // 預設啟用
  }

  /// 設定是否啟用閒置登出
  Future<void> setTimeoutEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_timeoutEnabledKey, enabled);

    if (enabled) {
      await _startInactivityTimer();
    } else {
      _cancelTimer();
      _loadedEnabled = prefs.getBool(_timeoutEnabledKey) == false
          ? false
          : null;
    }

    debugPrint('SessionTimeout: Timeout ${enabled ? "enabled" : "disabled"}');
  }

  /// 取得閒置時間設定（分鐘）
  Future<int> getTimeoutDuration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_timeoutDurationKey) ?? defaultTimeoutMinutes;
  }

  /// 設定閒置時間（分鐘）
  Future<void> setTimeoutDuration(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timeoutDurationKey, minutes);
    await _startInactivityTimer();
    debugPrint('SessionTimeout: Timeout set to $minutes minutes');
  }

  /// 開始閒置計時器
  Future<void> _startInactivityTimer() async {
    _cancelTimer();
    final generation = _timerGeneration;
    final uid = _currentUid();
    final isEnabled = await isTimeoutEnabled();
    if (generation != _timerGeneration || uid != _currentUid() || uid == null) {
      return;
    }
    final timeoutMinutes = isEnabled
        ? await getTimeoutDuration()
        : defaultTimeoutMinutes;
    if (generation != _timerGeneration || uid != _currentUid()) return;
    _loadedEnabled = isEnabled;
    _loadedMinutes = timeoutMinutes;
    if (!isEnabled) return;

    _inactivityTimer = Timer.periodic(
      const Duration(seconds: 30), // 每 30 秒檢查一次
      (timer) => _checkInactivity(timeoutMinutes),
    );

    debugPrint(
      'SessionTimeout: Timer started (timeout: $timeoutMinutes minutes)',
    );
  }

  /// 重置閒置計時器
  void _resetInactivityTimer() {
    // 只更新最後活動時間，不重啟計時器
    // 計時器會持續運行並檢查
  }

  /// 檢查閒置狀態
  Future<void> _checkInactivity(int timeoutMinutes) async {
    if (_lastActivityTime == null) return;
    final generation = _timerGeneration;
    final uid = _currentUid();

    // 確保用戶已登入
    if (_currentUid() == null) {
      _cancelTimer();
      return;
    }

    final isEnabled = await isTimeoutEnabled();
    if (generation != _timerGeneration || uid != _currentUid()) return;
    if (!isEnabled) {
      _cancelTimer();
      return;
    }

    final now = _now();
    final inactivityDuration = now.difference(_lastActivityTime!);

    if (inactivityDuration.inMinutes >= timeoutMinutes) {
      debugPrint(
        'SessionTimeout: Session expired after ${inactivityDuration.inMinutes} minutes of inactivity',
      );
      await expireSession();
    }
  }

  /// Uses already loaded settings and current wall time; null fails closed.
  /// This avoids tearing down navigation for a short native system prompt.
  bool? get deadlineSnapshot {
    if (_currentUid() == null || _loadedEnabled == null) return null;
    if (_loadedEnabled == false) return true;
    if (_lastActivityTime == null || _loadedMinutes == null) return null;
    final elapsed = _now().difference(_lastActivityTime!);
    return !elapsed.isNegative && elapsed < Duration(minutes: _loadedMinutes!);
  }

  /// Resume/unlock checks wall time before any activity resets the deadline.
  Future<bool> checkDeadline() async {
    final generation = _timerGeneration;
    final uid = _currentUid();
    if (uid == null) return false;
    final enabled = await isTimeoutEnabled();
    final minutes = await getTimeoutDuration();
    if (generation != _timerGeneration || uid != _currentUid()) return false;
    if (enabled &&
        _lastActivityTime != null &&
        _now().difference(_lastActivityTime!) >= Duration(minutes: minutes)) {
      await expireSession();
      return false;
    }
    return true;
  }

  /// 處理 Session 過期
  Future<bool> expireSession() async {
    _cancelTimer();

    final expired = _onSessionExpired;
    final uid = _currentUid();
    final success = await _signOut();
    if (success) {
      expired?.call();
    } else if (uid != null && uid == _currentUid()) {
      // Keep timeout protection alive after an auth failure; do not claim logout.
      _lastActivityTime = _now();
      await _startInactivityTimer();
    }
    return success;
  }

  /// 取消計時器
  void _cancelTimer() {
    _timerGeneration++;
    _loadedEnabled = null;
    _loadedMinutes = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  /// 停止服務
  void dispose() {
    _cancelTimer();
    _onSessionExpired = null;
    debugPrint('SessionTimeout: Service disposed');
  }

  /// 用戶登入時啟動
  Future<void> onUserLoggedIn() async {
    _lastActivityTime = _now();
    await _startInactivityTimer();
  }

  /// 用戶登出時停止
  void onUserLoggedOut() {
    _cancelTimer();
    _lastActivityTime = null;
  }
}

/// 活動追蹤包裝器 Widget
/// 用於包裝 App 根節點，追蹤用戶互動
class ActivityTracker extends StatelessWidget {
  final Widget child;
  final SessionTimeoutService _sessionService = SessionTimeoutService();

  ActivityTracker({super.key, required this.child});

  void _onUserActivity() {
    _sessionService.recordActivity();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _onUserActivity,
      onPanDown: (_) => _onUserActivity(),
      onScaleStart: (_) => _onUserActivity(),
      child: child,
    );
  }
}
