import 'dart:async';
import 'package:flutter/foundation.dart';

class SessionOperationCancelled implements Exception {}

enum LogoutPhase {
  idle,
  working,
  signedOut,
  authFailed,
  cleanupFailed,
  accountChanged,
}

/// Auth mutations are serialized; logout invalidates queued/interactive logins.
/// No biometric settings or stored credentials are touched here.
class LogoutCoordinator {
  LogoutCoordinator({
    required this.currentUid,
    required this.signOutAuth,
    required this.cleanup,
  });
  final String? Function() currentUid;
  final Future<void> Function() signOutAuth;
  final Future<void> Function() cleanup;
  final phase = ValueNotifier(LogoutPhase.idle);
  final ready = ValueNotifier(true);
  // Published only after a real, current auth mutation succeeds. Restored
  // Firebase sessions never publish a fresh verification.
  final freshSession = ValueNotifier<({String uid, int generation})?>(null);
  int generation = 0;
  Future<void> _authTail = Future.value();
  Future<bool>? _logout;
  final _accountWorkCancels = <void Function()>{};

  bool isCurrent(int token) =>
      token == generation &&
      _logout == null &&
      phase.value != LogoutPhase.cleanupFailed &&
      phase.value != LogoutPhase.working;

  Future<T> signIn<T>(
    Future<T> Function(bool Function() current) operation, {
    int? expectedGeneration,
    bool changesAuth = true,
    String? Function(T value)? verifiedUid,
  }) {
    final token = expectedGeneration ?? generation;
    if (!isCurrent(token)) return Future.error(SessionOperationCancelled());
    phase.value = LogoutPhase.idle;
    final startingUid = currentUid();
    final result = _authTail.then((_) async {
      bool current() => isCurrent(token);
      if (!current() || currentUid() != startingUid) {
        throw SessionOperationCancelled();
      }
      final value = await operation(current);
      if (!current()) throw SessionOperationCancelled();
      // A successful auth mutation invalidates other prepared login attempts.
      if (changesAuth) {
        if (verifiedUid != null &&
            (verifiedUid(value) == null || verifiedUid(value) != currentUid())) {
          throw SessionOperationCancelled();
        }
        generation++;
        _cancelAccountWork();
        final uid = currentUid();
        if (uid != null) {
          freshSession.value = (uid: uid, generation: generation);
        }
      }
      return value;
    });
    _authTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> finishSignIn(
    int token,
    Future<void> Function(bool Function() current) sideEffect,
  ) => signIn(sideEffect, expectedGeneration: token, changesAuth: false);

  /// Network data work never joins the auth/credential queue. Cancellation stops
  /// awaiting and suppresses stale results; it cannot recall a server commit.
  /// Callers must check current() inside transaction retries before writing.
  Future<T> accountWork<T>(
    Future<T> Function(bool Function() current) operation, {
    int? expectedGeneration,
  }) {
    final token = expectedGeneration ?? generation;
    final owner = currentUid();
    bool current() =>
        owner != null && currentUid() == owner && isCurrent(token);
    if (!current()) return Future.error(SessionOperationCancelled());
    final completion = Completer<T>();
    void cancel() {
      _accountWorkCancels.remove(cancel);
      if (!completion.isCompleted) {
        completion.completeError(SessionOperationCancelled());
      }
    }

    _accountWorkCancels.add(cancel);
    Future<T>.sync(() => operation(current)).then(
      (value) {
        _accountWorkCancels.remove(cancel);
        if (completion.isCompleted) return;
        if (current()) {
          completion.complete(value);
        } else {
          cancel();
        }
      },
      onError: (Object error, StackTrace stack) {
        _accountWorkCancels.remove(cancel);
        if (completion.isCompleted) return;
        if (current()) {
          completion.completeError(error, stack);
        } else {
          cancel();
        }
      },
    );
    return completion.future;
  }

  void _cancelAccountWork() {
    for (final cancel in _accountWorkCancels.toList()) {
      cancel();
    }
  }

  Future<bool> signOut() {
    if (_logout != null) return _logout!;
    final completion = Completer<bool>();
    _logout = completion.future;
    ready.value = false;
    generation++;
    freshSession.value = null;
    _cancelAccountWork();
    phase.value = LogoutPhase.working;
    _finish().then((success) {
      _logout = null;
      ready.value = true;
      completion.complete(success);
    });
    return completion.future;
  }

  Future<bool> _finish() async {
    await _authTail;
    try {
      if (currentUid() != null) await signOutAuth();
      if (currentUid() != null) throw StateError('Auth is still signed in');
    } catch (_) {
      phase.value = LogoutPhase.authFailed;
      return false;
    }
    try {
      await cleanup();
      if (currentUid() != null) {
        throw StateError('Account changed during cleanup');
      }
      phase.value = LogoutPhase.signedOut;
      return true;
    } catch (_) {
      phase.value = currentUid() == null
          ? LogoutPhase.cleanupFailed
          : LogoutPhase.accountChanged;
      return false;
    }
  }
}

/// Drain native work before account cleanup; queued stale work never starts.
class AccountNativeQueue {
  Future<void> _tail = Future.value();
  Future<void> get idle => _tail;
  Future<void> run(
    Future<void> Function() operation, {
    required bool Function() isCurrent,
  }) {
    final result = _tail.then((_) async {
      if (isCurrent()) await operation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
