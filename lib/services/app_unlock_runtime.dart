import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_unlock_controller.dart';
import 'auth_service.dart';
import 'biometric_service.dart';
import 'session_timeout_service.dart';

/// One root lifetime, independent of pages being removed by the unlock gate.
class AppUnlockRuntime {
  static final instance = AppUnlockRuntime._();
  AppUnlockRuntime._();
  final timeout = SessionTimeoutService();
  late final controller = AppUnlockController(
    session: AuthService.logout,
    preferences: BiometricService().preferences,
    authenticate: () => BiometricService().authenticate(),
    stopAuthentication: () => BiometricService().stopAuthentication(),
    checkTimeout: () async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final epoch = AuthService.logout.generation;
      await _timeoutReady;
      if (uid != FirebaseAuth.instance.currentUser?.uid ||
          epoch != AuthService.logout.generation) {
        return false;
      }
      return timeout.checkDeadline();
    },
    recordActivity: () => timeout.recordActivity(),
    timeoutSnapshot: () => timeout.deadlineSnapshot,
  );
  Future<void> _timeoutReady = Future.value();
  StreamSubscription<User?>? _auth;
  String? _uid;
  int _epoch = -1;
  bool _started = false;
  void start() {
    if (_started) return;
    _started = true;
    AuthService.logout.phase.addListener(_sync);
    AuthService.logout.ready.addListener(_sync);
    AuthService.logout.freshSession.addListener(_sync);
    _auth = FirebaseAuth.instance.authStateChanges().listen((_) => _sync());
    _sync();
  }

  void _sync() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final epoch = AuthService.logout.generation;
    if (_uid != uid || _epoch != epoch) {
      _uid = uid;
      _epoch = epoch;
      if (uid == null) {
        timeout.onUserLoggedOut();
      } else {
        _timeoutReady = timeout.initialize(onSessionExpired: () {});
        // The gate awaits this same future; consume early errors until it does.
        unawaited(_timeoutReady.then<void>((_) {}, onError: (Object _) {}));
      }
    }
    controller.sync();
  }

  void dispose() {
    _auth?.cancel();
    AuthService.logout.phase.removeListener(_sync);
    AuthService.logout.ready.removeListener(_sync);
    AuthService.logout.freshSession.removeListener(_sync);
    controller.dispose();
    timeout.dispose();
  }
}
