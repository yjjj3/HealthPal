import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_management_app/services/app_unlock_preferences.dart';
import 'package:health_management_app/services/app_unlock_controller.dart';
import 'package:health_management_app/services/logout_coordinator.dart';
import 'package:health_management_app/services/session_timeout_service.dart';
import 'package:health_management_app/widgets/app_unlock_gate.dart';
import 'package:health_management_app/widgets/app_unlock_settings.dart';
import 'package:health_management_app/widgets/logout_status_boundary.dart';

class Harness {
  String? uid = 'fake-a';
  DateTime clock = DateTime(2026, 10, 12);
  final data = <String, String>{};
  bool storageError = false, writeError = false, verifyError = false;
  bool authResult = true, authError = false, timeoutAllowed = true;
  bool signOutError = false, cleanupError = false;
  int authCalls = 0, cleanupCalls = 0, activities = 0;
  Future<bool> Function()? prompt;
  Future<bool> Function()? deadline;
  bool? Function()? snapshot;
  Future<void> Function()? cleanup;
  Future<void> Function()? writing;
  Future<void> Function()? reading;
  late final preferences = AppUnlockPreferences(
    read: (key) async {
      if (key.startsWith('app_unlock_')) await reading?.call();
      if (storageError) throw StateError('synthetic read failure');
      if (verifyError && key.startsWith('app_unlock_')) return 'false';
      return data[key];
    },
    write: (key, value) async {
      await writing?.call();
      if (writeError) throw StateError('synthetic write failure');
      data[key] = value;
    },
    delete: (key) async {
      if (storageError) throw StateError('synthetic migration failure');
      data.remove(key);
    },
  );
  late final session = LogoutCoordinator(
    currentUid: () => uid,
    signOutAuth: () async {
      if (signOutError) throw StateError('synthetic signout failure');
      uid = null;
    },
    cleanup: () async {
      cleanupCalls++;
      if (cleanupError) throw StateError('synthetic cleanup failure');
      await cleanup?.call();
    },
  );
  late final lock = AppUnlockController(
    session: session,
    preferences: preferences,
    authenticate: () async {
      authCalls++;
      if (authError) throw StateError('synthetic biometric error');
      return prompt == null ? authResult : await prompt!();
    },
    stopAuthentication: () async {},
    checkTimeout: () async =>
        deadline == null ? timeoutAllowed : await deadline!(),
    recordActivity: () => activities++,
    timeoutSnapshot: () => snapshot?.call(),
    now: () => clock,
  );
  Future<void> start({bool enabled = false}) async {
    if (enabled) data['app_unlock_v1_fake-a'] = 'true';
    lock.sync();
    await settle();
  }

  Future<void> login(String newUid) async {
    await session.signIn((_) async {
      uid = newUid;
    });
    lock.sync();
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.value();
    }
  }

  Future<void> away(
    int seconds, {
    AppLifecycleState state = AppLifecycleState.paused,
  }) async {
    lock.lifecycle(state);
    clock = clock.add(Duration(seconds: seconds));
    lock.lifecycle(AppLifecycleState.resumed);
    await lock.resumed;
  }

  void dispose() => lock.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'default OFF and legacy true is not consent; old secrets deleted',
    () async {
      final h = Harness();
      h.data.addAll({
        'user_email': 'fake@example.com',
        'user_credential': 'synthetic-only',
        'biometric_enabled': 'true',
      });
      await h.start();
      expect(h.lock.permitsProtected, true);
      expect(h.lock.enabled, false);
      expect(h.data.keys, isEmpty);
      await h.away(60);
      expect(h.lock.permitsProtected, true);
      h.dispose();
    },
  );
  test(
    'enable requires proof then explicit confirmation and verified storage; disable keeps UID choices',
    () async {
      final h = Harness();
      await h.start();
      var confirms = 0;
      h.authResult = false;
      expect(
        await h.lock.setEnabled(
          true,
          confirm: () async {
            confirms++;
            return true;
          },
        ),
        false,
      );
      expect(confirms, 0);
      expect(h.lock.enabled, false);
      h.authResult = true;
      expect(await h.lock.setEnabled(true, confirm: () async => false), false);
      expect(h.lock.enabled, false);
      expect(await h.lock.setEnabled(true, confirm: () async => true), true);
      expect(h.data['app_unlock_v1_fake-a'], 'true');
      expect(
        await h.lock.setEnabled(
          false,
          confirm: () async => throw StateError('must not prompt'),
        ),
        true,
      );
      expect(h.data['app_unlock_v1_fake-a'], 'false');
      h.dispose();
    },
  );
  for (final failure in ['write', 'verify', 'migration', 'read']) {
    test(
      '$failure failure never reports enabled/unlocked; retry safe',
      () async {
        final h = Harness();
        if (failure == 'migration') h.storageError = true;
        await h.start();
        if (failure == 'migration') {
          expect(h.lock.access, AppAccess.failed);
        } else if (failure == 'read') {
          h.storageError = true;
          await h.lock.reload();
          expect(h.lock.access, AppAccess.failed);
        } else {
          h.writeError = failure == 'write';
          h.verifyError = failure == 'verify';
          expect(
            await h.lock.setEnabled(true, confirm: () async => true),
            false,
          );
          expect(h.lock.access, AppAccess.failed);
        }
        expect(h.lock.permitsProtected, false);
        expect(h.lock.message, isNotNull);
        h.storageError = h.writeError = h.verifyError = false;
        await h.lock.reload();
        if (h.data['app_unlock_v1_fake-a'] == 'true') {
          expect(h.lock.access, AppAccess.locked);
        } else {
          expect(h.lock.permitsProtected, true);
        }
        h.dispose();
      },
    );
  }
  for (final provider in ['Email', 'Google']) {
    test(
      '$provider fresh login unlocks same generation but restored session locks',
      () async {
        final h = Harness();
        await h.start(enabled: true);
        expect(h.lock.access, AppAccess.locked);
        await h.session.signOut();
        h.lock.sync();
        await h.settle();
        expect(h.lock.permitsLogin, true);
        await h.login('fake-a');
        expect(h.lock.permitsProtected, true);
        expect(h.authCalls, 0);
        await h.away(60);
        expect(h.lock.access, AppAccess.locked);
        h.dispose();
      },
    );
  }
  for (final seconds in [59, 60]) {
    test('$seconds second background boundary and repeated resume', () async {
      final h = Harness();
      await h.start();
      await h.lock.setEnabled(true, confirm: () async => true);
      await h.away(seconds);
      expect(h.lock.permitsProtected, seconds == 59);
      if (seconds == 60) {
        expect(await h.lock.unlock(), true);
        expect(h.activities, 2);
        h.lock.lifecycle(AppLifecycleState.resumed);
        await h.lock.resumed;
        expect(h.lock.permitsProtected, true);
      }
      h.dispose();
    });
  }
  test(
    'external system inactive short prompt does not lock; long inactive locks',
    () async {
      final h = Harness();
      await h.start();
      await h.lock.setEnabled(true, confirm: () async => true);
      await h.away(5, state: AppLifecycleState.inactive);
      expect(h.lock.permitsProtected, true);
      await h.away(60, state: AppLifecycleState.inactive);
      expect(h.lock.access, AppAccess.locked);
      h.dispose();
    },
  );
  test(
    'Face ID inactive/resumed lifecycle cannot loop-lock its own successful prompt',
    () async {
      final h = Harness();
      await h.start(enabled: true);
      h.prompt = () async {
        h.lock.lifecycle(AppLifecycleState.inactive);
        h.clock = h.clock.add(const Duration(seconds: 65));
        h.lock.lifecycle(AppLifecycleState.resumed);
        return true;
      };
      expect(await h.lock.unlock(), true);
      expect(h.lock.permitsProtected, true);
      h.lock.lifecycle(AppLifecycleState.resumed);
      await h.lock.resumed;
      expect(h.lock.permitsProtected, true);
      expect(h.authCalls, 1);
      h.dispose();
    },
  );
  for (final kind in ['cancel', 'unavailable', 'error']) {
    test('$kind leaves lock retryable without data', () async {
      final h = Harness();
      await h.start(enabled: true);
      h.authResult = false;
      h.authError = kind == 'error';
      expect(await h.lock.unlock(), false);
      expect(h.lock.permitsProtected, false);
      expect(h.lock.message, isNotNull);
      h.authResult = true;
      h.authError = false;
      expect(await h.lock.unlock(), true);
      h.dispose();
    });
  }
  test(
    'actual pause during biometric discards result and never unlocks',
    () async {
      final h = Harness();
      await h.start(enabled: true);
      final pending = Completer<bool>();
      h.prompt = () => pending.future;
      final result = h.lock.unlock();
      await h.settle();
      h.lock.lifecycle(AppLifecycleState.paused);
      pending.complete(true);
      expect(await result, false);
      expect(h.lock.permitsProtected, false);
      h.clock = h.clock.add(const Duration(seconds: 60));
      h.lock.lifecycle(AppLifecycleState.resumed);
      await h.lock.resumed;
      expect(h.lock.access, AppAccess.locked);
      h.dispose();
    },
  );
  test(
    'fallback waits for real auth and cleanup; both failures stay denied',
    () async {
      final h = Harness();
      await h.start(enabled: true);
      h.signOutError = true;
      expect(await h.lock.loginAgain(), false);
      expect(h.uid, 'fake-a');
      expect(h.lock.permitsProtected, false);
      expect(h.lock.permitsLogin, false);
      h.signOutError = false;
      h.cleanupError = true;
      expect(await h.lock.loginAgain(), false);
      h.lock.sync();
      await h.settle();
      expect(h.uid, null);
      expect(h.lock.permitsLogin, false);
      h.cleanupError = false;
      expect(await h.lock.loginAgain(), true);
      await h.settle();
      expect(h.lock.permitsLogin, true);
      h.dispose();
    },
  );
  test('auth null while cleanup pending cannot mount login', () async {
    final h = Harness();
    await h.start(enabled: true);
    final pending = Completer<void>();
    h.cleanup = () => pending.future;
    final result = h.lock.loginAgain();
    await h.settle();
    h.lock.sync();
    await h.settle();
    expect(h.lock.permitsLogin, false);
    pending.complete();
    expect(await result, true);
    await h.settle();
    expect(h.lock.permitsLogin, true);
    h.dispose();
  });
  for (final target in ['fake-b', 'fake-a']) {
    test('late biometric result cannot unlock $target new epoch', () async {
      final h = Harness();
      await h.start(enabled: true);
      final pending = Completer<bool>();
      h.prompt = () => pending.future;
      final old = h.lock.unlock();
      await h.settle();
      await h.session.signOut();
      await h.login(target);
      h.data['app_unlock_v1_$target'] = 'true';
      await h.lock.reload();
      expect(h.lock.access, AppAccess.locked);
      pending.complete(true);
      expect(await old, false);
      expect(h.lock.permitsProtected, false);
      h.dispose();
    });
  }
  test('late confirmation does not write for new account', () async {
    final h = Harness();
    await h.start();
    final pending = Completer<bool>();
    final old = h.lock.setEnabled(true, confirm: () => pending.future);
    await h.settle();
    await h.session.signOut();
    await h.login('fake-b');
    pending.complete(true);
    expect(await old, false);
    expect(h.data['app_unlock_v1_fake-a'], isNull);
    expect(h.data['app_unlock_v1_fake-b'], isNull);
    h.dispose();
  });
  test('timeout wins resume before activity and wins pending unlock', () async {
    final h = Harness();
    await h.start(enabled: true);
    h.timeoutAllowed = false;
    expect(await h.lock.unlock(), false);
    expect(h.authCalls, 0);
    expect(h.activities, 0);
    h.timeoutAllowed = true;
    final pending = Completer<bool>();
    h.prompt = () => pending.future;
    final old = h.lock.unlock();
    await h.settle();
    await h.session.signOut();
    pending.complete(true);
    expect(await old, false);
    expect(h.activities, 0);
    h.dispose();
  });
  test(
    'wall-clock five minute expiry survives frozen timer and retains real signOut',
    () async {
      SharedPreferences.setMockInitialValues({});
      var clock = DateTime(2026, 10, 12);
      String? uid = 'fake-a';
      var calls = 0;
      final timeout = SessionTimeoutService.forTesting(
        currentUid: () => uid,
        signOut: () async {
          calls++;
          uid = null;
          return true;
        },
        now: () => clock,
      );
      await timeout.initialize(onSessionExpired: () {});
      clock = clock.add(const Duration(minutes: 5));
      expect(await timeout.checkDeadline(), false);
      expect(calls, 1);
      expect(uid, null);
      timeout.dispose();
    },
  );
  test(
    'repeated resume with pending deadline preserves correct target',
    () async {
      final h = Harness();
      await h.start();
      await h.lock.setEnabled(true, confirm: () async => true);
      final first = Completer<bool>(), second = Completer<bool>();
      var calls = 0;
      h.deadline = () => calls++ == 0 ? first.future : second.future;
      h.lock.lifecycle(AppLifecycleState.paused);
      h.clock = h.clock.add(const Duration(seconds: 60));
      h.lock.lifecycle(AppLifecycleState.resumed);
      h.lock.lifecycle(AppLifecycleState.resumed);
      expect(h.lock.permitsProtected, false);
      second.complete(true);
      await h.lock.resumed;
      expect(h.lock.access, AppAccess.locked);
      first.complete(true);
      await h.settle();
      expect(h.lock.access, AppAccess.locked);
      h.dispose();
    },
  );
  test(
    'configuration confirmation after timeout cannot enable or report success',
    () async {
      final h = Harness();
      await h.start();
      expect(
        await h.lock.setEnabled(
          true,
          confirm: () async {
            h.timeoutAllowed = false;
            return true;
          },
        ),
        false,
      );
      expect(h.data['app_unlock_v1_fake-a'], isNull);
      expect(h.lock.enabled, false);
      h.dispose();
    },
  );
  test(
    'failed disable stays denied until successful read resolves stored choice',
    () async {
      final h = Harness();
      await h.start(enabled: true);
      await h.lock.unlock();
      h.writeError = true;
      expect(await h.lock.setEnabled(false, confirm: () async => false), false);
      expect(h.lock.permitsProtected, false);
      expect(h.data['app_unlock_v1_fake-a'], 'true');
      h.writeError = false;
      await h.lock.reload();
      expect(h.lock.access, AppAccess.locked);
      h.dispose();
    },
  );
  test(
    'legacy deletion readback failure never inherits old enabled choice',
    () async {
      final prefs = AppUnlockPreferences(
        read: (key) async => key == 'biometric_enabled' ? 'true' : null,
        write: (_, _) async {},
        delete: (_) async {},
      );
      await expectLater(prefs.enabled('fake-a'), throwsStateError);
    },
  );
  test('invalid stored new preference fails closed', () async {
    final h = Harness();
    h.data['app_unlock_v1_fake-a'] = 'unknown';
    await h.start();
    expect(h.lock.access, AppAccess.failed);
    expect(h.lock.permitsProtected, false);
    h.dispose();
  });
  test(
    'UID preferences independent and old legacy flag never grants new account',
    () async {
      final h = Harness();
      await h.start();
      await h.lock.setEnabled(true, confirm: () async => true);
      await h.session.signOut();
      await h.login('fake-b');
      expect(h.lock.enabled, false);
      expect(h.data['app_unlock_v1_fake-a'], 'true');
      await h.away(60);
      expect(h.lock.permitsProtected, true);
      h.dispose();
    },
  );
  test(
    'late old prompt cannot clear lifecycle ownership of new prompt',
    () async {
      final h = Harness();
      await h.start(enabled: true);
      final oldPrompt = Completer<bool>();
      h.prompt = () => oldPrompt.future;
      final old = h.lock.unlock();
      await h.settle();
      await h.session.signOut();
      await h.login('fake-a');
      await h.lock.reload();
      final newPrompt = Completer<bool>();
      h.prompt = () => newPrompt.future;
      final fresh = h.lock.unlock();
      await h.settle();
      oldPrompt.complete(true);
      expect(await old, false);
      h.lock.lifecycle(AppLifecycleState.inactive);
      h.clock = h.clock.add(const Duration(seconds: 65));
      h.lock.lifecycle(AppLifecycleState.resumed);
      newPrompt.complete(true);
      expect(await fresh, true);
      expect(h.lock.permitsProtected, true);
      h.dispose();
    },
  );
  test('wall-clock timeout failure does not fake logout or unlock', () async {
    SharedPreferences.setMockInitialValues({});
    var clock = DateTime(2026, 10, 12);
    var calls = 0;
    final timeout = SessionTimeoutService.forTesting(
      currentUid: () => 'fake-a',
      signOut: () async {
        calls++;
        return false;
      },
      now: () => clock,
    );
    await timeout.initialize(onSessionExpired: () {});
    clock = clock.add(const Duration(minutes: 5));
    expect(await timeout.checkDeadline(), false);
    expect(calls, 1);
    timeout.dispose();
  });
  for (final brokenKey in AppUnlockPreferences.legacyKeys) {
    test(
      'legacy cleanup failure at $brokenKey blocks then retry removes all keys',
      () async {
        final data = {
          for (final key in AppUnlockPreferences.legacyKeys)
            key: 'synthetic-only',
        };
        var fail = true;
        final prefs = AppUnlockPreferences(
          read: (key) async => data[key],
          write: (key, value) async {
            data[key] = value;
          },
          delete: (key) async {
            if (fail && key == brokenKey) {
              throw StateError('synthetic cleanup failure');
            }
            data.remove(key);
          },
        );
        await expectLater(prefs.enabled('fake-a'), throwsStateError);
        fail = false;
        expect(await prefs.enabled('fake-a'), false);
        expect(data, isEmpty);
      },
    );
  }
  test(
    'duplicate unlock and setting taps produce one prompt and one committed choice',
    () async {
      final h = Harness();
      await h.start(enabled: true);
      final pending = Completer<bool>();
      h.prompt = () => pending.future;
      final first = h.lock.unlock();
      await h.settle();
      expect(await h.lock.unlock(), false);
      expect(h.authCalls, 1);
      pending.complete(true);
      expect(await first, true);
      final confirm = Completer<bool>();
      h.prompt = null;
      final change = h.lock.setEnabled(true, confirm: () => confirm.future);
      await h.settle();
      expect(await h.lock.setEnabled(false, confirm: () async => true), false);
      confirm.complete(true);
      expect(await change, true);
      expect(h.data['app_unlock_v1_fake-a'], 'true');
      h.dispose();
    },
  );
  test(
    'failed real logout cannot be replaced by successful biometric unlock',
    () async {
      final h = Harness();
      await h.start(enabled: true);
      h.signOutError = true;
      expect(await h.lock.loginAgain(), false);
      await h.settle();
      expect(await h.lock.unlock(), false);
      expect(h.lock.permitsProtected, false);
      expect(h.authCalls, 0);
      h.dispose();
    },
  );
  test(
    'deadline read failure stays closed during resume and can recover',
    () async {
      final h = Harness();
      await h.start();
      h.deadline = () async => throw StateError('synthetic deadline failure');
      await h.away(59);
      expect(h.lock.access, AppAccess.failed);
      expect(h.lock.permitsProtected, false);
      h.deadline = null;
      await h.lock.reload();
      expect(h.lock.permitsProtected, true);
      h.dispose();
    },
  );
  for (final failure in [false, true]) {
    testWidgets(
      'settings UI requires confirmation and verified write (failure=$failure)',
      (tester) async {
        final h = Harness();
        await h.start();
        h.writeError = failure;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AppUnlockSettings(controller: h.lock)),
          ),
        );
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          false,
        );
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(find.text('啟用 App 解鎖？'), findsOneWidget);
        expect(h.data['app_unlock_v1_fake-a'], isNull);
        await tester.tap(find.text('確認啟用'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          !failure,
        );
        expect(
          find.text(failure ? '解鎖設定未能確認儲存，暫不開放資料。請重試讀取。' : 'App 解鎖已啟用'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        h.dispose();
      },
    );
  }
  testWidgets(
    'restoration cannot mount previously protected routes while locked',
    (tester) async {
      final h = Harness();
      await h.start(enabled: true);
      await h.lock.unlock();
      var built = 0;
      await tester.pumpWidget(
        MaterialApp(
          restorationScopeId: 'fake-app',
          initialRoute: '/',
          routes: {
            '/': (_) {
              built++;
              return const Text('private root');
            },
            '/saved': (_) {
              built++;
              return const Text('private restored');
            },
          },
          builder: (context, child) => AppUnlockGate(
            controller: h.lock,
            protectedNavigation: child!,
            loginBuilder: (_) => const Text('login'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .restorablePushNamed('/saved');
      await tester.pumpAndSettle();
      expect(find.text('private restored'), findsOneWidget);
      await h.away(60);
      await tester.pumpAndSettle();
      final before = built;
      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(built, before);
      expect(find.text('private restored'), findsNothing);
      expect(find.text('App 已鎖定'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      h.dispose();
    },
  );
  test(
    'fresh proof UID must match auth result, not a later external account',
    () async {
      final h = Harness();
      await h.start(enabled: true);
      await expectLater(
        h.session.signIn((_) async {
          h.uid = 'fake-b';
          return 'fake-a';
        }, verifiedUid: (result) => result),
        throwsA(isA<SessionOperationCancelled>()),
      );
      expect(h.session.freshSession.value, isNull);
      h.data['app_unlock_v1_fake-b'] = 'true';
      h.lock.sync();
      await h.settle();
      expect(h.lock.access, AppAccess.locked);
      h.dispose();
    },
  );
  test(
    'deadline snapshot uses wall time, preserves OFF, unknown before loading',
    () async {
      SharedPreferences.setMockInitialValues({});
      var clock = DateTime(2026, 10, 12);
      final timeout = SessionTimeoutService.forTesting(
        currentUid: () => 'fake-a',
        signOut: () async => false,
        now: () => clock,
      );
      expect(timeout.deadlineSnapshot, isNull);
      await timeout.initialize(onSessionExpired: () {});
      expect(timeout.deadlineSnapshot, true);
      clock = clock.add(const Duration(minutes: 5));
      expect(timeout.deadlineSnapshot, false);
      await timeout.setTimeoutEnabled(false);
      expect(timeout.deadlineSnapshot, true);
      timeout.dispose();
    },
  );
  testWidgets(
    '59-second resume keeps navigation only with known unexpired deadline',
    (tester) async {
      final h = Harness();
      await h.start(enabled: true);
      await h.lock.unlock();
      h.snapshot = () => true;
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (_) => const Text('root'),
            '/draft': (_) => const Text('existing draft'),
          },
          builder: (context, child) => AppUnlockGate(
            controller: h.lock,
            protectedNavigation: child!,
            loginBuilder: (_) => const Text('login'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/draft');
      await tester.pumpAndSettle();
      final deadline = Completer<bool>();
      h.deadline = () => deadline.future;
      h.lock.lifecycle(AppLifecycleState.paused);
      h.clock = h.clock.add(const Duration(seconds: 59));
      h.lock.lifecycle(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('existing draft'), findsOneWidget);
      deadline.complete(true);
      await h.lock.resumed;
      await tester.pumpAndSettle();
      expect(find.text('existing draft'), findsOneWidget);
      h.snapshot = () => false;
      h.deadline = () async => false;
      await h.away(1);
      await tester.pump();
      expect(find.text('existing draft'), findsNothing);
      expect(h.lock.permitsProtected, false);
      await tester.pumpWidget(const SizedBox());
      h.dispose();
    },
  );
  for (final afterResume in [false, true]) {
    test(
      'F1 confirmed enable spanning background, completion afterResume=$afterResume',
      () async {
        final h = Harness();
        await h.start();
        final gate = Completer<void>();
        h.writing = () => gate.future;
        final change = h.lock.setEnabled(true, confirm: () async => true);
        await h.settle();
        h.lock.lifecycle(AppLifecycleState.paused);
        h.clock = h.clock.add(const Duration(seconds: 60));
        if (afterResume) {
          h.lock.lifecycle(AppLifecycleState.resumed);
          await h.lock.resumed;
        }
        gate.complete();
        await change;
        if (!afterResume) {
          h.lock.lifecycle(AppLifecycleState.resumed);
          await h.lock.resumed;
        }
        expect(h.data['app_unlock_v1_fake-a'], 'true');
        expect(h.lock.enabled, true);
        expect(h.lock.permitsProtected, false);
        expect(h.activities, 0);
        h.dispose();
      },
    );
  }
  for (final value in [true, false]) {
    for (final seconds in [59, 60]) {
      for (final timing in ['background', 'afterResume']) {
        test(
          'confirmed setting $value/$seconds/$timing reconciles pending state',
          () async {
            final h = Harness();
            await h.start(enabled: !value);
            if (!value) await h.lock.unlock();
            final activities = h.activities;
            final gate = Completer<void>();
            h.writing = () => gate.future;
            final change = h.lock.setEnabled(value, confirm: () async => true);
            await h.settle();
            h.lock.lifecycle(AppLifecycleState.inactive);
            h.lock.lifecycle(AppLifecycleState.paused);
            h.clock = h.clock.add(Duration(seconds: seconds));
            if (timing == 'afterResume') {
              h.lock.lifecycle(AppLifecycleState.resumed);
              await h.lock.resumed;
              expect(h.lock.permitsProtected, false);
            }
            gate.complete();
            expect(await change, true);
            if (timing == 'background') {
              h.lock.lifecycle(AppLifecycleState.resumed);
              await h.lock.resumed;
            }
            expect(h.lock.enabled, value);
            expect(h.lock.permitsProtected, !(value && seconds >= 60));
            expect(h.activities, activities);
            h.dispose();
          },
        );
      }
    }
    for (final failure in ['write', 'readback']) {
      test(
        'pending $value $failure failure remains closed across resume',
        () async {
          final h = Harness();
          await h.start(enabled: !value);
          if (!value) await h.lock.unlock();
          final gate = Completer<void>();
          h.writing = () => gate.future;
          final change = h.lock.setEnabled(value, confirm: () async => true);
          await h.settle();
          h.lock.lifecycle(AppLifecycleState.paused);
          h.clock = h.clock.add(const Duration(seconds: 60));
          h.lock.lifecycle(AppLifecycleState.resumed);
          await h.lock.resumed;
          h.writeError = failure == 'write';
          h.storageError = failure == 'readback';
          gate.complete();
          expect(await change, false);
          expect(h.lock.enabled, isNull);
          expect(h.lock.access, AppAccess.failed);
          expect(h.lock.permitsProtected, false);
          h.dispose();
        },
      );
    }
    for (final target in ['fake-a', 'fake-b']) {
      test(
        'pending $value completion does not change $target new epoch',
        () async {
          final h = Harness();
          await h.start(enabled: !value);
          if (!value) await h.lock.unlock();
          final gate = Completer<void>();
          h.writing = () => gate.future;
          final change = h.lock.setEnabled(value, confirm: () async => true);
          await h.settle();
          await h.session.signOut();
          final login = h.login(target);
          await h.settle();
          gate.complete();
          expect(await change, false);
          await login;
          await h.settle();
          expect(h.lock.enabled, target == 'fake-a' ? value : false);
          expect(h.lock.permitsProtected, true);
          h.dispose();
        },
      );
    }
  }
  for (final value in [true, false]) {
    test('confirmed $value readback and delayed resume reconcile', () async {
      final h = Harness();
      await h.start(enabled: !value);
      if (!value) await h.lock.unlock();
      final activities = h.activities;
      final readback = Completer<void>();
      h.reading = () => readback.future;
      final change = h.lock.setEnabled(value, confirm: () async => true);
      await h.settle();
      expect(h.data['app_unlock_v1_fake-a'], '$value');
      h.lock.lifecycle(AppLifecycleState.paused);
      h.clock = h.clock.add(const Duration(seconds: 60));
      final resumeDeadline = Completer<bool>();
      var checks = 0;
      h.deadline = () async =>
          ++checks == 1 ? await resumeDeadline.future : true;
      h.lock.lifecycle(AppLifecycleState.resumed);
      expect(h.lock.permitsProtected, false);
      readback.complete();
      expect(await change, true);
      expect(h.lock.enabled, value);
      expect(h.lock.permitsProtected, !value);
      resumeDeadline.complete(true);
      await h.lock.resumed;
      expect(h.lock.permitsProtected, !value);
      expect(h.activities, activities);
      h.dispose();
    });
  }
  test(
    'pending enable completion after five-minute expiry is not activity',
    () async {
      final h = Harness();
      await h.start();
      final gate = Completer<void>();
      h.writing = () => gate.future;
      final change = h.lock.setEnabled(true, confirm: () async => true);
      await h.settle();
      h.lock.lifecycle(AppLifecycleState.paused);
      h.clock = h.clock.add(const Duration(minutes: 5));
      h.timeoutAllowed = false;
      h.lock.lifecycle(AppLifecycleState.resumed);
      await h.lock.resumed;
      gate.complete();
      expect(await change, false);
      expect(h.lock.enabled, true);
      expect(h.lock.permitsProtected, false);
      expect(h.activities, 0);
      h.dispose();
    },
  );
  for (final route in ['/main', '/records', '/restored-sensitive']) {
    testWidgets(
      'global gate does not build $route before unlock or when signed out',
      (tester) async {
        final h = Harness();
        await h.start(enabled: true);
        var built = 0;
        await tester.pumpWidget(
          MaterialApp(
            initialRoute: route,
            restorationScopeId: 'fake-restoration',
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) {
                built++;
                return const Text('sensitive');
              },
            ),
            builder: (context, child) => LogoutStatusBoundary(
              coordinator: h.session,
              child: AppUnlockGate(
                controller: h.lock,
                protectedNavigation: child!,
                loginBuilder: (_) => const Text('ordinary login'),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(built, 0);
        expect(find.text('sensitive'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(built, 0);
        await h.lock.unlock();
        await tester.pumpAndSettle();
        expect(built, greaterThan(0));
        await h.lock.loginAgain();
        await tester.pumpAndSettle();
        expect(find.text('ordinary login'), findsOneWidget);
        expect(find.text('sensitive'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        h.dispose();
      },
    );
  }
}
