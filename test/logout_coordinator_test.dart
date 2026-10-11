import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_management_app/services/session_timeout_service.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:health_management_app/widgets/logout_status_boundary.dart';
import 'package:health_management_app/services/logout_coordinator.dart';

void main() {
  for (final lateFailure in [false, true]) {
    test(
      'cancelled data work ignores late ${lateFailure ? "error" : "ack"} without blocking new auth',
      () async {
        String? uid = 'fake-a';
        final network = Completer<void>();
        final c = LogoutCoordinator(
          currentUid: () => uid,
          signOutAuth: () async {
            uid = null;
          },
          cleanup: () async {},
        );
        var staleEffect = false;
        final old = c.accountWork((current) async {
          await network.future;
          if (current()) staleEffect = true;
        });
        final cancelled = expectLater(
          old,
          throwsA(isA<SessionOperationCancelled>()),
        );
        expect(await c.signOut(), true);
        await cancelled;
        await c.signIn((_) async {
          uid = 'fake-b';
        });
        expect(await c.accountWork((_) async => 'new result'), 'new result');
        if (lateFailure) {
          network.completeError(StateError('synthetic late failure'));
        } else {
          network.complete();
        }
        await Future<void>.delayed(Duration.zero);
        expect(uid, 'fake-b');
        expect(staleEffect, false);
        expect(c.phase.value, LogoutPhase.idle);
      },
    );
  }

  test(
    'signOut failure keeps auth and never reports cleanup/success',
    () async {
      var cleaned = false;
      final c = LogoutCoordinator(
        currentUid: () => 'fake-a',
        signOutAuth: () async => throw StateError('fake failure'),
        cleanup: () async {
          cleaned = true;
        },
      );
      expect(await c.signOut(), isFalse);
      expect(c.phase.value, LogoutPhase.authFailed);
      expect(cleaned, isFalse);
    },
  );
  test(
    'manual and timeout share one pending logout; retry clears failure',
    () async {
      String? uid = 'fake-a';
      final gate = Completer<void>();
      var calls = 0;
      var fail = true;
      final c = LogoutCoordinator(
        currentUid: () => uid,
        signOutAuth: () async {
          calls++;
          await gate.future;
          uid = null;
        },
        cleanup: () async {
          if (fail) throw StateError('fake cancel failure');
        },
      );
      final first = c.signOut();
      expect(identical(first, c.signOut()), isTrue);
      gate.complete();
      expect(await first, isFalse);
      expect(uid, isNull);
      expect(c.phase.value, LogoutPhase.cleanupFailed);
      fail = false;
      expect(await c.signOut(), isTrue);
      expect(calls, 1);
    },
  );
  test(
    'in-flight Firebase login drains before signOut; queued login rejected',
    () async {
      String? uid;
      final gate = Completer<void>();
      final c = LogoutCoordinator(
        currentUid: () => uid,
        signOutAuth: () async {
          uid = null;
        },
        cleanup: () async {},
      );
      final login = c.signIn((_) async {
        await gate.future;
        uid = 'fake-a';
      });
      await Future<void>.delayed(Duration.zero);
      final stale = c.signIn((_) async {
        fail('queued login must not start');
      });
      final loginError = expectLater(
        login,
        throwsA(isA<SessionOperationCancelled>()),
      );
      final staleError = expectLater(
        stale,
        throwsA(isA<SessionOperationCancelled>()),
      );
      final logout = c.signOut();
      gate.complete();
      await loginError;
      await staleError;
      expect(await logout, isTrue);
      expect(uid, isNull);
    },
  );
  test(
    'late provider/biometric result does not delay logout or start Firebase',
    () async {
      String? uid;
      final gate = Completer<void>();
      final c = LogoutCoordinator(
        currentUid: () => uid,
        signOutAuth: () async {
          uid = null;
        },
        cleanup: () async {},
      );
      final token = c.generation;
      Future<void> provider() async {
        await gate.future;
        await c.signIn((_) async {
          uid = 'fake-a';
        }, expectedGeneration: token);
      }

      final login = provider();
      final error = expectLater(
        login,
        throwsA(isA<SessionOperationCancelled>()),
      );
      expect(await c.signOut(), isTrue);
      gate.complete();
      await error;
      expect(uid, isNull);
    },
  );
  test('new account during cleanup is not reported as signed out', () async {
    String? uid = 'fake-a';
    final c = LogoutCoordinator(
      currentUid: () => uid,
      signOutAuth: () async {
        uid = null;
      },
      cleanup: () async {
        uid = 'fake-b';
      },
    );
    expect(await c.signOut(), isFalse);
    expect(c.phase.value, LogoutPhase.accountChanged);
    expect(uid, 'fake-b');
  });
  test(
    'native drain waits in-flight call; stale queued call skipped; failure visible',
    () async {
      final q = AccountNativeQueue();
      final gate = Completer<void>();
      var valid = true;
      final events = <String>[];
      final started = q.run(() async {
        events.add('start');
        await gate.future;
        events.add('end');
      }, isCurrent: () => valid);
      await Future<void>.delayed(Duration.zero);
      final stale = q.run(() async {
        events.add('stale');
      }, isCurrent: () => valid);
      valid = false;
      final cleanup = q.idle.then((_) {
        events.add('clear');
      });
      expect(events, ['start']);
      gate.complete();
      await started;
      await stale;
      await cleanup;
      expect(events, ['start', 'end', 'clear']);
      await expectLater(
        q.run(() async => throw StateError('fake'), isCurrent: () => true),
        throwsStateError,
      );
      await q.idle;
    },
  );
  testWidgets('auth failure keeps signed-in page and offers retry', (
    tester,
  ) async {
    final c = LogoutCoordinator(
      currentUid: () => 'fake-a',
      signOutAuth: () async => throw StateError('fake'),
      cleanup: () async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LogoutStatusBoundary(
          coordinator: c,
          child: const Scaffold(body: Text('fake signed-in page')),
        ),
      ),
    );
    expect(await c.signOut(), isFalse);
    await tester.pump();
    expect(find.text('登出失敗，帳號仍登入，請重試。'), findsOneWidget);
    expect(find.text('fake signed-in page'), findsOneWidget);
    expect(find.text('已登出，通知已清除。'), findsNothing);
  });
  testWidgets(
    'cleanup failure is visible after auth navigation; retry completion visible',
    (tester) async {
      String? uid = 'fake-a';
      var failCleanup = true;
      final auth = ValueNotifier<String?>(uid);
      final c = LogoutCoordinator(
        currentUid: () => uid,
        signOutAuth: () async {
          uid = null;
          auth.value = null;
        },
        cleanup: () async {
          if (failCleanup) throw StateError('fake native');
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LogoutStatusBoundary(
            coordinator: c,
            child: ValueListenableBuilder<String?>(
              valueListenable: auth,
              builder: (_, user, _) => Scaffold(
                body: Text(user == null ? 'fake login' : 'fake account'),
              ),
            ),
          ),
        ),
      );
      expect(await c.signOut(), isFalse);
      await tester.pump();
      expect(find.text('fake login'), findsOneWidget);
      expect(find.text('帳號已登出，但通知清理未完成，請重試清理。'), findsOneWidget);
      await expectLater(
        c.signIn((_) async {
          uid = 'fake-b';
        }),
        throwsA(isA<SessionOperationCancelled>()),
      );
      failCleanup = false;
      await tester.tap(find.text('重試'));
      await tester.pumpAndSettle();
      expect(find.text('已登出，通知已清除。'), findsOneWidget);
      auth.dispose();
    },
  );
  test('queued second sign-in cannot overwrite first account', () async {
    String? uid;
    final gate = Completer<void>();
    final c = LogoutCoordinator(
      currentUid: () => uid,
      signOutAuth: () async {
        uid = null;
      },
      cleanup: () async {},
    );
    final first = c.signIn((_) async {
      await gate.future;
      uid = 'fake-a';
    });
    final second = c.signIn((_) async {
      uid = 'fake-b';
    });
    final error = expectLater(
      second,
      throwsA(isA<SessionOperationCancelled>()),
    );
    gate.complete();
    await first;
    await error;
    expect(uid, 'fake-a');
  });
  test(
    'actual timeout service does not announce auth failure and can retry',
    () async {
      SharedPreferences.setMockInitialValues({});
      String? uid = 'fake-a';
      var failAuth = true;
      var expired = 0;
      final c = LogoutCoordinator(
        currentUid: () => uid,
        signOutAuth: () async {
          if (failAuth) throw StateError('fake');
          uid = null;
        },
        cleanup: () async {},
      );
      final timeout = SessionTimeoutService.forTesting(
        currentUid: () => uid,
        signOut: c.signOut,
      );
      await timeout.initialize(
        onSessionExpired: () {
          expired++;
        },
      );
      await timeout.expireSession();
      expect(expired, 0);
      expect(uid, 'fake-a');
      failAuth = false;
      await timeout.expireSession();
      expect(expired, 1);
      expect(uid, isNull);
      timeout.dispose();
    },
  );
  test(
    'actual timeout and manual logout merge while native cleanup is pending',
    () async {
      SharedPreferences.setMockInitialValues({});
      String? uid = 'fake-a';
      var calls = 0;
      final gate = Completer<void>();
      final c = LogoutCoordinator(
        currentUid: () => uid,
        signOutAuth: () async {
          calls++;
          uid = null;
        },
        cleanup: () => gate.future,
      );
      final timeout = SessionTimeoutService.forTesting(
        currentUid: () => uid,
        signOut: c.signOut,
      );
      await timeout.initialize(onSessionExpired: () {});
      final manual = c.signOut();
      final expiry = timeout.expireSession();
      gate.complete();
      await expiry;
      expect(await manual, isTrue);
      expect(calls, 1);
      timeout.dispose();
    },
  );
  test(
    'successful login invalidates a previously prepared provider result',
    () async {
      String? uid;
      final c = LogoutCoordinator(
        currentUid: () => uid,
        signOutAuth: () async {
          uid = null;
        },
        cleanup: () async {},
      );
      final oldProviderToken = c.generation;
      await c.signIn((_) async {
        uid = 'fake-a';
      });
      await expectLater(
        c.signIn((_) async {
          uid = 'fake-b';
        }, expectedGeneration: oldProviderToken),
        throwsA(isA<SessionOperationCancelled>()),
      );
      expect(uid, 'fake-a');
    },
  );
  test(
    'credential storage drains before logout; new account cannot overlap',
    () async {
      String? uid = 'fake-a';
      final gate = Completer<void>();
      final events = <String>[];
      final c = LogoutCoordinator(
        currentUid: () => uid,
        signOutAuth: () async {
          events.add('signOut');
          uid = null;
        },
        cleanup: () async {},
      );
      final storage = c.finishSignIn(c.generation, (_) async {
        events.add('write');
        await gate.future;
        events.add('written');
      });
      await Future<void>.delayed(Duration.zero);
      final error = expectLater(
        storage,
        throwsA(isA<SessionOperationCancelled>()),
      );
      final logout = c.signOut();
      await expectLater(
        c.signIn((_) async {
          uid = 'fake-b';
        }),
        throwsA(isA<SessionOperationCancelled>()),
      );
      expect(events, ['write']);
      gate.complete();
      await error;
      expect(await logout, isTrue);
      expect(events, ['write', 'written', 'signOut']);
    },
  );
  testWidgets(
    'account change warning cannot retry logout against new account',
    (tester) async {
      String? uid = 'fake-a';
      var authCalls = 0;
      final c = LogoutCoordinator(
        currentUid: () => uid,
        signOutAuth: () async {
          authCalls++;
          uid = null;
        },
        cleanup: () async {
          uid = 'fake-b';
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LogoutStatusBoundary(
            coordinator: c,
            child: const Scaffold(body: Text('fake new account')),
          ),
        ),
      );
      expect(await c.signOut(), isFalse);
      await tester.pump();
      expect(find.text('帳號已變更，舊登出清理已停止；請核對通知。'), findsOneWidget);
      expect(find.text('重試'), findsNothing);
      expect(uid, 'fake-b');
      expect(authCalls, 1);
    },
  );
}
