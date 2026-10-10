// lib/services/session_timeout_service.dart
// 閒置自動登出服務

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionTimeoutService {
  static final SessionTimeoutService _instance = SessionTimeoutService._internal();
  factory SessionTimeoutService() => _instance;
  SessionTimeoutService._internal();

  // 設定常數
  static const String _timeoutEnabledKey = 'session_timeout_enabled';
  static const String _timeoutDurationKey = 'session_timeout_duration';
  static const int defaultTimeoutMinutes = 5; // 預設閒置 5 分鐘

  Timer? _inactivityTimer;
  int _timerGeneration = 0;
  DateTime? _lastActivityTime;
  VoidCallback? _onSessionExpired;

  /// 初始化服務
  Future<void> initialize({required VoidCallback onSessionExpired}) async {
    _onSessionExpired = onSessionExpired;
    _lastActivityTime = DateTime.now();
    await _startInactivityTimer();
    debugPrint('SessionTimeout: Service initialized');
  }

  /// 記錄用戶活動
  void recordActivity() {
    _lastActivityTime = DateTime.now();
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isEnabled = await isTimeoutEnabled();
    if (!isEnabled) return;

    // 確保用戶已登入
    if (FirebaseAuth.instance.currentUser == null) return;

    final timeoutMinutes = await getTimeoutDuration();
    if (generation != _timerGeneration || uid != FirebaseAuth.instance.currentUser?.uid) return;

    _inactivityTimer = Timer.periodic(
      const Duration(seconds: 30), // 每 30 秒檢查一次
      (timer) => _checkInactivity(timeoutMinutes),
    );

    debugPrint('SessionTimeout: Timer started (timeout: $timeoutMinutes minutes)');
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
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // 確保用戶已登入
    if (FirebaseAuth.instance.currentUser == null) {
      _cancelTimer();
      return;
    }

    final isEnabled = await isTimeoutEnabled();
    if (generation != _timerGeneration || uid != FirebaseAuth.instance.currentUser?.uid) return;
    if (!isEnabled) {
      _cancelTimer();
      return;
    }

    final now = DateTime.now();
    final inactivityDuration = now.difference(_lastActivityTime!);

    if (inactivityDuration.inMinutes >= timeoutMinutes) {
      debugPrint('SessionTimeout: Session expired after ${inactivityDuration.inMinutes} minutes of inactivity');
      await _handleSessionExpired();
    }
  }

  /// 處理 Session 過期
  Future<void> _handleSessionExpired() async {
    _cancelTimer();

    try {
      await FirebaseAuth.instance.signOut();
      debugPrint('SessionTimeout: User signed out due to inactivity');
    } catch (e) {
      debugPrint('SessionTimeout: Error signing out: $e');
    }

    _onSessionExpired?.call();
  }

  /// 取消計時器
  void _cancelTimer() {
    _timerGeneration++;
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
    _lastActivityTime = DateTime.now();
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
