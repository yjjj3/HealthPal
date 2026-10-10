import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 生物辨識認證服務
/// 支援 Face ID / Touch ID / 指紋辨識
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // 安全儲存的 key 常量
  static const String _keyBiometricEnabled = 'biometric_enabled';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserCredential = 'user_credential';

  /// 檢查裝置是否支援生物辨識
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException catch (e) {
      debugPrint('檢查裝置支援失敗: $e');
      return false;
    }
  }

  /// 檢查是否有已註冊的生物辨識資料
  Future<bool> canCheckBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } on PlatformException catch (e) {
      debugPrint('檢查生物辨識可用性失敗: $e');
      return false;
    }
  }

  /// 取得可用的生物辨識類型
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException catch (e) {
      debugPrint('取得生物辨識類型失敗: $e');
      return [];
    }
  }

  /// 取得生物辨識類型的顯示名稱
  String getBiometricTypeName(List<BiometricType> types) {
    if (types.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (types.contains(BiometricType.fingerprint)) {
      return '指紋辨識';
    } else if (types.contains(BiometricType.iris)) {
      return '虹膜辨識';
    } else if (types.contains(BiometricType.strong) ||
               types.contains(BiometricType.weak)) {
      return '生物辨識';
    }
    return '生物辨識';
  }

  /// 執行生物辨識認證
  Future<bool> authenticate({
    String reason = '請使用生物辨識驗證身份',
  }) async {
    try {
      // 先檢查是否可用
      final canCheck = await canCheckBiometrics();
      final isSupported = await isDeviceSupported();

      if (!canCheck || !isSupported) {
        debugPrint('生物辨識不可用');
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('生物辨識認證失敗: ${e.message}');
      return false;
    }
  }

  /// 檢查用戶是否已啟用生物辨識登入
  Future<bool> isBiometricLoginEnabled() async {
    try {
      final value = await _secureStorage.read(key: _keyBiometricEnabled);
      return value == 'true';
    } catch (e) {
      debugPrint('讀取生物辨識設定失敗: $e');
      return false;
    }
  }

  /// 啟用或停用生物辨識登入
  Future<bool> setBiometricLoginEnabled(bool enabled) async {
    try {
      await _secureStorage.write(
        key: _keyBiometricEnabled,
        value: enabled.toString(),
      );
      return true;
    } catch (e) {
      debugPrint('儲存生物辨識設定失敗: $e');
      return false;
    }
  }

  /// 儲存用戶憑證（用於生物辨識登入後自動登入）
  Future<bool> saveUserCredentials(String email, String password) async {
    try {
      await _secureStorage.write(key: _keyUserEmail, value: email);
      await _secureStorage.write(key: _keyUserCredential, value: password);
      return true;
    } catch (e) {
      debugPrint('儲存用戶憑證失敗: $e');
      return false;
    }
  }

  /// 取得已儲存的用戶 Email
  Future<String?> getSavedEmail() async {
    try {
      return await _secureStorage.read(key: _keyUserEmail);
    } catch (e) {
      debugPrint('讀取用戶 Email 失敗: $e');
      return null;
    }
  }

  /// 取得已儲存的用戶憑證
  Future<String?> getSavedCredential() async {
    try {
      return await _secureStorage.read(key: _keyUserCredential);
    } catch (e) {
      debugPrint('讀取用戶憑證失敗: $e');
      return null;
    }
  }

  /// 清除已儲存的用戶憑證
  Future<void> clearUserCredentials() async {
    try {
      await _secureStorage.delete(key: _keyUserEmail);
      await _secureStorage.delete(key: _keyUserCredential);
      await _secureStorage.delete(key: _keyBiometricEnabled);
    } catch (e) {
      debugPrint('清除用戶憑證失敗: $e');
    }
  }

  /// 檢查是否有已儲存的憑證可供生物辨識登入使用
  Future<bool> hasStoredCredentials() async {
    final email = await getSavedEmail();
    final credential = await getSavedCredential();
    return email != null &&
           email.isNotEmpty &&
           credential != null &&
           credential.isNotEmpty;
  }

  /// 執行生物辨識登入流程
  /// 返回 (email, password) 或 null
  Future<(String, String)?> authenticateAndGetCredentials() async {
    // 先檢查是否啟用
    final isEnabled = await isBiometricLoginEnabled();
    if (!isEnabled) {
      debugPrint('生物辨識登入未啟用');
      return null;
    }

    // 檢查是否有儲存的憑證
    final hasCredentials = await hasStoredCredentials();
    if (!hasCredentials) {
      debugPrint('沒有儲存的憑證');
      return null;
    }

    // 執行生物辨識認證
    final authenticated = await authenticate(
      reason: '使用生物辨識登入HealthPal',
    );

    if (!authenticated) {
      debugPrint('生物辨識認證失敗');
      return null;
    }

    // 取得儲存的憑證
    final email = await getSavedEmail();
    final credential = await getSavedCredential();

    if (email != null && credential != null) {
      return (email, credential);
    }

    return null;
  }
}
