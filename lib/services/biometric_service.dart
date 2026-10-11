import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'app_unlock_preferences.dart';

/// Biometric session unlock only. Never stores or retrieves login credentials.
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  late final preferences = AppUnlockPreferences(
    read: (key) => _storage.read(key: key),
    write: (key, value) => _storage.write(key: key, value: value),
    delete: (key) => _storage.delete(key: key),
  );
  Future<bool> authenticate() async {
    if (!await _localAuth.isDeviceSupported() ||
        !await _localAuth.canCheckBiometrics ||
        (await _localAuth.getAvailableBiometrics()).isEmpty) {
      return false;
    }
    return _localAuth.authenticate(
      localizedReason: '使用 Face ID／生物辨識解鎖 HealthPal',
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: false,
        useErrorDialogs: false,
      ),
    );
  }

  Future<void> stopAuthentication() async {
    await _localAuth.stopAuthentication();
  }
}
