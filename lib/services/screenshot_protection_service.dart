import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 截圖保護服務
/// 防止敏感健康資料被截圖或螢幕錄影
class ScreenshotProtectionService {
  static const _channel = MethodChannel('com.example.health_management_app/screenshot_protection');
  static const String _enabledKey = 'screenshot_protection_enabled';

  // 單例模式
  static final ScreenshotProtectionService _instance = ScreenshotProtectionService._internal();
  factory ScreenshotProtectionService() => _instance;
  ScreenshotProtectionService._internal();

  bool _isEnabled = true; // 預設開啟保護

  /// 初始化截圖保護服務
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_enabledKey) ?? true;

    // 根據設定啟用或停用保護
    await _applyProtection();

    // 監聽截圖事件（主要用於 iOS）
    _channel.setMethodCallHandler(_handleMethodCall);

    debugPrint('📸 截圖保護服務初始化完成，保護狀態: $_isEnabled');
  }

  /// 處理來自原生端的方法呼叫
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onScreenshotDetected':
        debugPrint('⚠️ 偵測到截圖！');
        // 可以在這裡添加額外的處理邏輯，例如記錄日誌
        return null;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'Screenshot protection: ${call.method} not implemented',
        );
    }
  }

  /// 檢查截圖保護是否已啟用
  Future<bool> isProtectionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  /// 設定截圖保護開關
  Future<void> setProtectionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    _isEnabled = enabled;
    await _applyProtection();
    debugPrint('📸 截圖保護已${enabled ? "啟用" : "停用"}');
  }

  /// 應用截圖保護設定到原生層
  Future<void> _applyProtection() async {
    try {
      await _channel.invokeMethod('setProtectionEnabled', {'enabled': _isEnabled});
    } on PlatformException catch (e) {
      debugPrint('❌ 無法設定截圖保護: ${e.message}');
    } on MissingPluginException {
      // 在不支援的平台上（如 Web）靜默失敗
      debugPrint('ℹ️ 此平台不支援截圖保護');
    }
  }

  /// 暫時停用保護（例如用戶需要截圖分享報告時）
  Future<void> temporarilyDisable() async {
    if (!_isEnabled) return;

    try {
      await _channel.invokeMethod('setProtectionEnabled', {'enabled': false});
      debugPrint('📸 截圖保護暫時停用');
    } on PlatformException catch (e) {
      debugPrint('❌ 無法暫停截圖保護: ${e.message}');
    }
  }

  /// 恢復保護
  Future<void> restoreProtection() async {
    if (!_isEnabled) return;

    try {
      await _channel.invokeMethod('setProtectionEnabled', {'enabled': true});
      debugPrint('📸 截圖保護已恢復');
    } on PlatformException catch (e) {
      debugPrint('❌ 無法恢復截圖保護: ${e.message}');
    }
  }
}
