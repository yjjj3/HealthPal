import 'package:flutter/widgets.dart';
import 'app_unlock_preferences.dart';
import 'logout_coordinator.dart';

enum AppAccess { checking, signedOut, unlocked, locked, failed }

/// Lives above protected navigation; all async results bind to UID + auth epoch.
class AppUnlockController extends ChangeNotifier {
  AppUnlockController({
    required this.session,
    required this.preferences,
    required this.authenticate,
    required this.stopAuthentication,
    required this.checkTimeout,
    required this.recordActivity,
    this.timeoutSnapshot,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    session.phase.addListener(sync);
    session.ready.addListener(sync);
    session.freshSession.addListener(sync);
  }
  final LogoutCoordinator session;
  final AppUnlockPreferences preferences;
  final Future<bool> Function() authenticate;
  final Future<void> Function() stopAuthentication;
  final Future<bool> Function() checkTimeout;
  final VoidCallback recordActivity;
  final bool? Function()? timeoutSnapshot;
  final DateTime Function() now;
  AppAccess access = AppAccess.checking;
  bool? enabled;
  String? message;
  bool busy = false;
  String? _uid;
  int _epoch = -1;
  int _revision = 0;
  int _attempt = 0;
  bool _foreground = true;
  bool _prompt = false;
  int? _promptOwner;
  bool _disposed = false;
  DateTime? _away;
  Future<void>? _resumeWork;
  bool _freshPermit = false;
  bool _settingPending = false;
  int _resumeTicket = 0;
  AppAccess? _resumeTarget;
  int? _loadingRevision;

  bool get permitsProtected =>
      access == AppAccess.unlocked &&
      _uid != null &&
      _uid == session.currentUid() &&
      _epoch == session.generation &&
      session.isCurrent(_epoch) &&
      session.phase.value != LogoutPhase.authFailed;
  bool get permitsLogin =>
      access == AppAccess.signedOut &&
      session.currentUid() == null &&
      session.phase.value != LogoutPhase.working &&
      session.phase.value != LogoutPhase.cleanupFailed;
  bool _current(int revision) =>
      !_disposed &&
      revision == _revision &&
      _uid == session.currentUid() &&
      _epoch == session.generation &&
      session.isCurrent(_epoch);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void sync() {
    final uid = session.currentUid();
    final epoch = session.generation;
    if (uid == _uid && epoch == _epoch) {
      if (access == AppAccess.checking && session.isCurrent(epoch)) {
        _load(_revision);
      }
      _changed();
      return;
    }
    _uid = uid;
    _epoch = epoch;
    _revision++;
    _attempt++;
    _resumeTicket++;
    _resumeTarget = null;
    if (_prompt) {
      _prompt = false;
      _promptOwner = null;
      stopAuthentication().catchError((Object _) {});
    }
    busy = false;
    _settingPending = false;
    enabled = null;
    _away = null;
    access = AppAccess.checking;
    message = null;
    final fresh = session.freshSession.value;
    _freshPermit = fresh?.uid == uid && fresh?.generation == epoch;
    _changed();
    _load(_revision);
  }

  Future<void> _load(int revision) async {
    if (_loadingRevision == revision) return;
    _loadingRevision = revision;
    try {
      await preferences.migrate();
      if (!_current(revision)) {
        if (_loadingRevision == revision) _loadingRevision = null;
        return;
      }
      final uid = _uid;
      final selected = uid == null ? false : await preferences.enabled(uid);
      if (!_current(revision)) {
        if (_loadingRevision == revision) _loadingRevision = null;
        return;
      }
      final deadlineAllowed = uid == null || await checkTimeout();
      if (!_current(revision)) {
        if (_loadingRevision == revision) _loadingRevision = null;
        return;
      }
      enabled = selected;
      final awayLock =
          selected &&
          (_away != null &&
              now().difference(_away!) >= const Duration(seconds: 60));
      final next = uid == null
          ? AppAccess.signedOut
          : session.phase.value != LogoutPhase.authFailed &&
                deadlineAllowed &&
                !awayLock &&
                (!selected || _freshPermit)
          ? AppAccess.unlocked
          : AppAccess.locked;
      if (_resumeTarget == null) {
        access = next;
      } else {
        _resumeTarget = next;
      }
      _freshPermit = false;
      message = null;
    } catch (_) {
      if (!_current(revision)) {
        if (_loadingRevision == revision) _loadingRevision = null;
        return;
      }
      access = AppAccess.failed;
      message = '無法讀取解鎖設定或清除舊快登資料。請重試，暫不開放資料。';
    }
    if (_loadingRevision == revision) _loadingRevision = null;
    _changed();
  }

  Future<void> reload() async {
    access = AppAccess.checking;
    message = null;
    _changed();
    await _load(++_revision);
  }

  Future<bool> _biometric(int revision, int attempt) async {
    _prompt = true;
    _promptOwner = attempt;
    try {
      return await authenticate() &&
          _current(revision) &&
          attempt == _attempt &&
          _foreground;
    } finally {
      if (_promptOwner == attempt) {
        _prompt = false;
        _promptOwner = null;
      }
    }
  }

  /// Enabling requires both biometric proof and explicit user confirmation.
  /// No success is reported until the per-UID setting has been read back.
  Future<bool> setEnabled(
    bool value, {
    required Future<bool> Function() confirm,
  }) async {
    if (!permitsProtected || busy) return false;
    final revision = _revision;
    final attempt = ++_attempt;
    final uid = _uid!;
    busy = true;
    message = null;
    _changed();
    try {
      if (!await checkTimeout() || !_current(revision)) return false;
      if (value) {
        if (!await _biometric(revision, attempt)) {
          if (_current(revision)) message = '生物辨識已取消、失敗或不可用，未啟用 App 解鎖。';
          return false;
        }
        if (!await confirm()) return false;
      }
      if (!_current(revision) || attempt != _attempt || !_foreground) {
        return false;
      }
      if (!await checkTimeout() || !_current(revision)) return false;
      _settingPending = true;
      await preferences.setEnabled(uid, value);
      if (!_current(revision) || attempt != _attempt) {
        return false;
      }
      // A confirmed write belongs to this session even if it finished away.
      enabled = value;
      final allowed = await checkTimeout();
      if (!_current(revision) || attempt != _attempt) return false;
      final elapsed = _away == null ? Duration.zero : now().difference(_away!);
      final next = !allowed || (value && elapsed >= const Duration(seconds: 60))
          ? AppAccess.locked
          : AppAccess.unlocked;
      access = next;
      if (_resumeTarget != null) _resumeTarget = next;
      // Configuration completion is not user activity after leaving the app.
      if (allowed &&
          _foreground &&
          _away == null &&
          next == AppAccess.unlocked) {
        recordActivity();
      }
      if (_foreground) _away = null;
      return allowed;
    } catch (_) {
      if (_current(revision)) {
        enabled = null;
        access = AppAccess.failed;
        if (_resumeTarget != null) _resumeTarget = AppAccess.failed;
        message = '解鎖設定未能確認儲存，暫不開放資料。請重試讀取。';
      }
      return false;
    } finally {
      if (_current(revision)) {
        busy = false;
        _settingPending = false;
        _changed();
      }
    }
  }

  Future<bool> unlock() async {
    if (session.phase.value == LogoutPhase.authFailed) {
      message = '登出尚未完成，請重試重新登入／登出；不以解鎖取代清理。';
      _changed();
      return false;
    }
    if (access != AppAccess.locked || busy || !_foreground) return false;
    final revision = _revision;
    final attempt = ++_attempt;
    busy = true;
    message = null;
    _changed();
    try {
      if (!await checkTimeout() || !_current(revision) || attempt != _attempt) {
        return false;
      }
      final verified = await _biometric(revision, attempt);
      // The OS can freeze timers while the prompt/background is active.
      if (!verified ||
          !await checkTimeout() ||
          !_current(revision) ||
          attempt != _attempt ||
          !_foreground) {
        if (_current(revision)) message = '驗證已取消、失敗或不可用。可重試或重新登入。';
        return false;
      }
      access = AppAccess.unlocked;
      _away = null;
      recordActivity();
      return true;
    } catch (_) {
      if (_current(revision)) message = '解鎖失敗，資料仍鎖定。可重試或重新登入。';
      return false;
    } finally {
      if (_current(revision)) {
        busy = false;
        _changed();
      }
    }
  }

  Future<bool> loginAgain() async {
    // Even when auth becomes null early, permitsLogin stays false until cleanup.
    return session.signOut();
  }

  void lifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (_prompt && _away == null) return; // Face ID's own inactive/resumed.
      if (_uid != null) {
        final elapsed = _away == null
            ? Duration.zero
            : now().difference(_away!);
        if (enabled == true && elapsed >= const Duration(seconds: 60)) {
          access = AppAccess.locked;
          if (!_settingPending) _attempt++;
        }
        // Hide navigation synchronously before awaiting the timeout deadline.
        _resumeTarget ??= access;
        if (enabled == true && elapsed >= const Duration(seconds: 60)) {
          _resumeTarget = AppAccess.locked;
        }
        final ticket = ++_resumeTicket;
        // Only an already verified, current session with a known live wall-
        // clock deadline can retain navigation during this asynchronous check.
        if (_settingPending ||
            access != AppAccess.unlocked ||
            timeoutSnapshot?.call() != true) {
          access = AppAccess.checking;
        }
        _changed();
        final revision = _revision;
        _resumeWork = () async {
          try {
            final allowed = await checkTimeout();
            if (ticket != _resumeTicket || !_current(revision)) return;
            if (_foreground && allowed && !_settingPending) {
              access = _resumeTarget ?? AppAccess.locked;
              _resumeTarget = null;
              _away = null;
            } else if (_foreground && !allowed) {
              access = AppAccess.locked;
              message = '閒置期限已到，登出未完成。請重試重新登入。';
            }
          } catch (_) {
            if (_current(revision) && ticket == _resumeTicket) {
              _resumeTarget = null;
              access = AppAccess.failed;
              message = '無法核對閒置期限，暫不開放資料。';
            }
          }
          _changed();
        }();
      }
      return;
    }
    if (state == AppLifecycleState.inactive && _prompt) return;
    _foreground = false;
    _away ??= now();
    if (_settingPending) {
      access = AppAccess.checking;
      if (_resumeTarget != null) _resumeTarget = AppAccess.checking;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      if (_prompt) {
        _attempt++;
        if (enabled == true) access = AppAccess.locked;
        stopAuthentication().catchError((Object _) {});
      }
    }
    _changed();
  }

  Future<void> get resumed => _resumeWork ?? Future.value();
  @override
  void dispose() {
    _disposed = true;
    _revision++;
    session.phase.removeListener(sync);
    session.ready.removeListener(sync);
    session.freshSession.removeListener(sync);
    super.dispose();
  }
}
