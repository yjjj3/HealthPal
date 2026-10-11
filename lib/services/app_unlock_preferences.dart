/// Device-local, per-UID consent. Legacy login secrets are deleted, never read
/// for authentication or converted into consent. Storage errors fail closed.
class AppUnlockPreferences {
  AppUnlockPreferences({
    required this.read,
    required this.write,
    required this.delete,
  });
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final Future<void> Function(String key) delete;
  Future<void> _tail = Future.value();
  bool _migrated = false;
  static const legacyKeys = [
    'user_email',
    'user_credential',
    'biometric_enabled',
  ];
  String _key(String uid) => 'app_unlock_v1_$uid';

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _migrate() async {
    if (_migrated) return;
    for (final key in legacyKeys) {
      await delete(key);
      if (await read(key) != null) {
        throw StateError('Legacy cleanup incomplete');
      }
    }
    _migrated = true;
  }

  Future<void> migrate() => _serial(_migrate);

  Future<bool> enabled(String uid) => _serial(() async {
    await _migrate();
    final value = await read(_key(uid));
    if (value == null || value == 'false') return false;
    if (value == 'true') return true;
    throw StateError('Invalid unlock preference');
  });

  Future<void> setEnabled(String uid, bool enabled) => _serial(() async {
    await _migrate();
    final value = enabled.toString();
    await write(_key(uid), value);
    if (await read(_key(uid)) != value) {
      throw StateError('Unlock preference was not verified');
    }
  });
}
