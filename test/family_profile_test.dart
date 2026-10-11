import 'package:health_management_app/services/session_timeout_service.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_management_app/services/family_profile_service.dart';
import 'package:health_management_app/services/family_relationship_service.dart';
import 'package:health_management_app/services/logout_coordinator.dart';
import 'package:health_management_app/screens/family_health_screen.dart';
import 'package:health_management_app/widgets/family_share_settings.dart';
import 'medication_boundary_test.dart' as boundary;

LogoutCoordinator session(
  String? Function() uid,
  Future<void> Function() signOut,
) => LogoutCoordinator(
  currentUid: uid,
  signOutAuth: signOut,
  cleanup: () async {},
);
Future<void> seed(FakeFirebaseFirestore db) async {
  await db.doc('users/owner').set({
    'fullName': 'Synthetic name',
    'email': 'owner@example.com',
    'phoneNumber': 'synthetic-phone',
    'allergies': 'synthetic-allergy',
    'chronicDiseases': <String>[],
  });
  for (final viewer in ['viewer', 'other']) {
    await db.doc('users/owner/family_members/$viewer').set({
      'userId': viewer,
      'inviteId': 'invite',
      'sharedData': {},
    });
    await db.doc('users/$viewer/family_members/owner').set({
      'userId': 'owner',
      'inviteId': 'invite',
      'sharedData': {},
    });
  }
}

class DelayedFirestore extends boundary.RetryFirestore {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    entered.complete();
    await release.future;
    return super.runTransaction(
      handler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

class FailOnceProfileService extends FamilyProfileService {
  FailOnceProfileService({
    required FirebaseFirestore firestore,
    required LogoutCoordinator session,
  }) : super(firestore: firestore, session: session);
  bool fail = true;
  @override
  Future<void> save(
    String viewer,
    Map<String, bool> consent,
    Map<String, bool> records, {
    String? expectedInviteId,
  }) {
    if (fail) {
      fail = false;
      return Future.error(StateError('synthetic failure'));
    }
    return super.save(
      viewer,
      consent,
      records,
      expectedInviteId: expectedInviteId,
    );
  }
}

class DelayedSettings extends FamilyProfileService {
  DelayedSettings({
    required FirebaseFirestore firestore,
    required LogoutCoordinator session,
  }) : super(firestore: firestore, session: session);
  final result = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> loadSettings(String viewer) => result.future;
}

// Model native Firestore completion remaining pending while offline. No release.
class PendingNetwork {
  final entered = Completer<void>();
  final never = Completer<void>();
  Future<void> wait() {
    if (!entered.isCompleted) entered.complete();
    return never.future;
  }
}

class OfflineFirestore extends boundary.RetryFirestore {
  final network = PendingNetwork();

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    await network.wait();
    return super.runTransaction(
      handler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

class WatchedRetryFirestore extends boundary.RetryFirestore {
  final finished = Completer<void>();
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    try {
      return await super.runTransaction(
        handler,
        timeout: timeout,
        maxAttempts: maxAttempts,
      );
    } finally {
      if (!finished.isCompleted) finished.complete();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('missing/unknown/non-boolean consent defaults off', () {
    final keys = FamilyProfileService.fields.keys;
    expect(
      FamilyProfileService.choices(null, keys).values.every((v) => !v),
      true,
    );
    final value = FamilyProfileService.choices({
      'allergies': 'true',
      'fullName': 1,
      'unknown': true,
      'email': true,
    }, keys);
    expect(value['email'], true);
    expect(value['allergies'], false);
    expect(value['fullName'], false);
    expect(value.containsKey('unknown'), false);
  });
  test('projection is per viewer and revoke replaces all old values', () async {
    final db = FakeFirebaseFirestore();
    await seed(db);
    final service = FamilyProfileService(
      firestore: db,
      session: session(() => 'owner', () async {}),
    );
    await service.save('viewer', {'allergies': true}, {});
    await service.save('other', {'email': true}, {});
    expect((await service.ref('owner', 'viewer').get()).data()!['values'], {
      'allergies': 'synthetic-allergy',
    });
    expect((await service.ref('owner', 'other').get()).data()!['values'], {
      'email': 'owner@example.com',
    });
    await service.save('viewer', {}, {});
    await service.save('viewer', {}, {});
    expect(
      (await service.ref('owner', 'viewer').get()).data()!['values'],
      isEmpty,
    );
    expect(
      (await service.ref('owner', 'other').get()).data()!['values'],
      isNotEmpty,
    );
    expect(
      () => service.save('viewer', {'unknown': true}, {}),
      throwsArgumentError,
    );
  });
  test('old grant cannot revive after member removal/rebinding', () async {
    final db = FakeFirebaseFirestore();
    await seed(db);
    final service = FamilyProfileService(
      firestore: db,
      session: session(() => 'owner', () async {}),
    );
    expect((await service.loadSettings('viewer'))['consent'], isNull);
    await service.save('viewer', {'email': true}, {'血糖': true});
    await db.doc('users/owner/family_members/viewer').delete();
    await expectLater(service.save('viewer', {}, {}), throwsStateError);
    await db.doc('users/owner/family_members/viewer').set({
      'inviteId': 'new-invite',
    });
    expect((await service.loadSettings('viewer'))['consent'], isNull);
  });
  test(
    'transaction retry projects current private values, not a stale UI copy',
    () async {
      final db = boundary.RetryFirestore();
      await seed(db);
      db.conflict = () =>
          db.doc('users/owner').update({'allergies': 'synthetic-new'});
      final service = FamilyProfileService(
        firestore: db,
        session: session(() => 'owner', () async {}),
      );
      await service.save('viewer', {'allergies': true}, {});
      expect((await service.ref('owner', 'viewer').get()).data()!['values'], {
        'allergies': 'synthetic-new',
      });
    },
  );
  test(
    'logout invalidates a blocked sharing write before any commit',
    () async {
      final db = DelayedFirestore();
      await seed(db);
      String? uid = 'owner';
      final auth = session(() => uid, () async {
        uid = null;
      });
      final service = FamilyProfileService(firestore: db, session: auth);
      final save = service.save('viewer', {'email': true}, {});
      final assertion = expectLater(
        save,
        throwsA(isA<SessionOperationCancelled>()),
      );
      await db.entered.future;
      final logout = auth.signOut();
      db.release.complete();
      await assertion;
      expect(await logout, true);
      expect((await service.ref('owner', 'viewer').get()).exists, false);
      expect((await db.doc('users/viewer').get()).exists, false);
    },
  );
  test(
    'invite acceptance needs no inviter private profile and grants nothing',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/viewer').set({'fullName': 'Synthetic recipient'});
      await db.doc('family_invites/invite').set({
        'invitedBy': 'owner',
        'inviteCode': 'fake',
        'status': 'pending',
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 1)),
        ),
        'sharedData': {'血糖': true},
      });
      final service = FamilyRelationshipService(
        firestore: db,
        session: session(() => 'viewer', () async {}),
        currentEmail: () => null,
      );
      await service.acceptInvite('invite');
      expect((await db.doc('users/owner').get()).exists, false);
      for (final path in [
        'users/owner/family_members/viewer',
        'users/viewer/family_members/owner',
      ]) {
        final data = (await db.doc(path).get()).data()!;
        expect(
          (data['sharedData'] as Map).values.every((v) => v == false),
          true,
        );
        expect(data['name'], '家人');
        expect(data.containsKey('email'), false);
      }
    },
  );
  testWidgets('missing sharing doc shows all checkboxes off', (tester) async {
    final db = FakeFirebaseFirestore();
    await seed(db);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FamilyShareSettings(
            viewer: 'viewer',
            service: FamilyProfileService(
              firestore: db,
              session: session(() => 'owner', () async {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((tile) => tile.value == false),
      true,
    );
    expect(find.textContaining('姓名與 email 也可不分享'), findsOneWidget);
  });
  testWidgets(
    'health page never falls back to private profile and clears on revoke/switch',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      String? uid = 'viewer';
      final changes = StreamController<String?>.broadcast(sync: true);
      final service = FamilyProfileService(
        firestore: db,
        session: session(() => 'owner', () async {}),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyHealthScreen(
            userId: 'owner',
            firestore: db,
            currentUid: () => uid,
            accountChanges: changes.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic name'), findsNothing);
      expect(find.text('synthetic-allergy'), findsNothing);
      expect(find.text('未分享'), findsWidgets);
      await service.save('viewer', {'allergies': true}, {});
      await tester.pumpAndSettle();
      expect(find.text('synthetic-allergy'), findsOneWidget);
      expect(find.text('Synthetic name'), findsNothing);
      await service.save('viewer', {}, {});
      await tester.pumpAndSettle();
      expect(find.text('synthetic-allergy'), findsNothing);
      await service.save('viewer', {'allergies': true}, {});
      await tester.pumpAndSettle();
      await db.doc('users/viewer/family_members/owner').delete();
      await tester.pumpAndSettle();
      expect(find.text('synthetic-allergy'), findsNothing);
      uid = 'other';
      changes.add(uid);
      await tester.pumpAndSettle();
      expect(find.textContaining('帳號已變更'), findsOneWidget);
      expect(find.text('synthetic-allergy'), findsNothing);
      uid = 'viewer';
      changes.add(uid);
      await tester.pumpAndSettle();
      expect(find.text('synthetic-allergy'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await changes.close();
    },
  );
  test('member removal during transaction retry prevents sharing', () async {
    final db = boundary.RetryFirestore();
    await seed(db);
    db.conflict = () => db.doc('users/owner/family_members/viewer').delete();
    final service = FamilyProfileService(
      firestore: db,
      session: session(() => 'owner', () async {}),
    );
    await expectLater(
      service.save('viewer', {'email': true}, {}),
      throwsStateError,
    );
    expect((await service.ref('owner', 'viewer').get()).exists, false);
  });
  testWidgets(
    'save failure stays visible and retry writes only selected fields',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      final service = FailOnceProfileService(
        firestore: db,
        session: session(() => 'owner', () async {}),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      FamilyShareSettings(viewer: 'viewer', service: service),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('過敏史'));
      await tester.tap(find.text('過敏史'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('儲存分享設定'));
      await tester.tap(find.text('儲存分享設定'));
      await tester.pumpAndSettle();
      expect(find.textContaining('儲存失敗'), findsOneWidget);
      expect((await service.ref('owner', 'viewer').get()).exists, false);
      await tester.ensureVisible(find.text('儲存分享設定'));
      await tester.tap(find.text('儲存分享設定'));
      await tester.pumpAndSettle();
      expect(find.byType(FamilyShareSettings), findsNothing);
      expect((await service.ref('owner', 'viewer').get()).data()!['values'], {
        'allergies': 'synthetic-allergy',
      });
    },
  );
  testWidgets('late settings response cannot restore consent after logout', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await seed(db);
    String? uid = 'owner';
    final auth = session(() => uid, () async {
      uid = null;
    });
    final service = DelayedSettings(firestore: db, session: auth);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FamilyShareSettings(viewer: 'viewer', service: service),
        ),
      ),
    );
    await tester.pump();
    await auth.signOut();
    service.result.complete({
      'version': 1,
      'consent': {'email': true},
    });
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((tile) => tile.value == false),
      true,
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(find.textContaining('帳號已變更'), findsOneWidget);
  });
  test(
    'member removal deletes own projection and preserves unrelated viewer',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      final service = FamilyProfileService(
        firestore: db,
        session: session(() => 'owner', () async {}),
      );
      await service.save('viewer', {'email': true}, {});
      await service.save('other', {'allergies': true}, {});
      await service.removeMember('viewer', expectedInviteId: 'invite');
      expect(
        (await db.doc('users/owner/family_members/viewer').get()).exists,
        false,
      );
      expect(
        (await db.doc('users/viewer/family_members/owner').get()).exists,
        false,
      );
      expect((await service.ref('owner', 'viewer').get()).exists, false);
      expect((await service.ref('owner', 'other').get()).exists, true);
    },
  );
  testWidgets(
    'switch away and back before settings resolve cannot adopt a new epoch',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      String? uid = 'owner';
      final auth = session(() => uid, () async {
        uid = null;
      });
      final service = DelayedSettings(firestore: db, session: auth);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FamilyShareSettings(viewer: 'viewer', service: service),
          ),
        ),
      );
      await tester.pump();
      await auth.signIn((_) async {
        uid = 'other';
      });
      await auth.signIn((_) async {
        uid = 'owner';
      });
      service.result.complete({
        'version': 1,
        'consent': {'email': true},
      });
      await tester.pump();
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .any((tile) => tile.value == true),
        false,
      );
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
    },
  );
  test(
    'a version-only legacy document with no relationship version is not consent',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      await db.doc('users/owner/family_members/viewer').set({
        'userId': 'viewer',
      });
      await db.doc('users/owner/shared_profile/viewer').set({
        'version': 1,
        'consent': {'email': true},
      });
      final service = FamilyProfileService(
        firestore: db,
        session: session(() => 'owner', () async {}),
      );
      expect((await service.loadSettings('viewer'))['consent'], isNull);
    },
  );
  for (final decline in [false, true]) {
    test(
      'never-resolving ${decline ? "decline" : "remove"} must not delay actual signOut',
      () async {
        final db = OfflineFirestore();
        await seed(db);
        await db.doc('family_invites/invite').set({
          'invitedBy': 'synthetic-inviter',
          'status': 'pending',
          'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 1)),
          ),
        });
        String? uid = 'owner';
        var calls = 0;
        var reportedSuccess = false;
        Object? operationError;
        final auth = session(() => uid, () async {
          calls++;
          uid = null;
        });
        final operation = decline
            ? FamilyRelationshipService(
                firestore: db,
                session: auth,
                currentEmail: () => null,
              ).declineInvite('invite')
            : FamilyProfileService(
                firestore: db,
                session: auth,
              ).removeMember('viewer', expectedInviteId: 'invite');
        operation.then<void>(
          (_) {
            reportedSuccess = true;
          },
          onError: (Object error) {
            operationError = error;
          },
        );
        await db.network.entered.future.timeout(
          const Duration(milliseconds: 500),
        );
        if (decline) {
          final timeout = SessionTimeoutService.forTesting(
            currentUid: () => uid,
            signOut: auth.signOut,
          );
          await timeout.expireSession().timeout(
            const Duration(milliseconds: 500),
          );
          timeout.dispose();
        } else {
          expect(
            await auth.signOut().timeout(const Duration(milliseconds: 500)),
            true,
          );
        }
        await Future<void>.delayed(Duration.zero);
        expect(calls, 1);
        expect(uid, isNull);
        expect(reportedSuccess, false);
        expect(operationError, isA<SessionOperationCancelled>());
        expect(
          db.network.never.isCompleted,
          false,
        ); // Never release the network gate.
        await auth.signIn((_) async {
          uid = 'owner';
        });
        expect(uid, 'owner');
        expect(reportedSuccess, false);
      },
    );
  }
  testWidgets('late settings error preserves account-changed message', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    String? uid = 'owner';
    final auth = session(() => uid, () async {
      uid = null;
    });
    final service = DelayedSettings(firestore: db, session: auth);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FamilyShareSettings(viewer: 'viewer', service: service),
        ),
      ),
    );
    await tester.pump();
    await auth.signOut();
    service.result.completeError(StateError('synthetic late error'));
    await tester.pumpAndSettle();
    expect(find.textContaining('帳號已變更'), findsOneWidget);
    expect(find.textContaining('無法載入分享設定'), findsNothing);
  });
  test(
    'old removal retry cannot delete a rebound relationship in the same session',
    () async {
      final db = boundary.RetryFirestore();
      await seed(db);
      final service = FamilyProfileService(
        firestore: db,
        session: session(() => 'owner', () async {}),
      );
      db.conflict = () async {
        await db.doc('users/owner/family_members/viewer').update({
          'inviteId': 'new-invite',
        });
        await db.doc('users/viewer/family_members/owner').update({
          'inviteId': 'new-invite',
        });
        await db.doc('users/owner/shared_profile/viewer').set({
          'inviteId': 'new-invite',
          'version': 1,
          'consent': {},
          'values': {},
          'records': {},
        });
      };
      await expectLater(
        service.removeMember('viewer', expectedInviteId: 'invite'),
        throwsStateError,
      );
      expect(
        (await db.doc('users/owner/family_members/viewer').get())
            .data()!['inviteId'],
        'new-invite',
      );
      expect(
        (await db.doc('users/viewer/family_members/owner').get()).exists,
        true,
      );
      expect(
        (await service.ref('owner', 'viewer').get()).data()!['inviteId'],
        'new-invite',
      );
      await expectLater(
        service.save('viewer', {'email': true}, {}, expectedInviteId: 'invite'),
        throwsStateError,
      );
    },
  );
  for (final nextUid in ['owner', 'other']) {
    for (final remove in [true, false]) {
      test(
        'late ${remove ? "remove" : "sharing"} retry after logout/login $nextUid leaves new grant untouched',
        () async {
          final db = WatchedRetryFirestore();
          await seed(db);
          String? uid = 'owner';
          final auth = session(() => uid, () async {
            uid = null;
          });
          final service = FamilyProfileService(firestore: db, session: auth);
          db.conflict = () async {
            expect(await auth.signOut(), true);
            await auth.signIn((_) async {
              uid = nextUid;
            });
            await db.doc('users/owner/family_members/viewer').update({
              'inviteId': 'new-invite',
            });
            await db.doc('users/viewer/family_members/owner').update({
              'inviteId': 'new-invite',
            });
            await db.doc('users/owner/shared_profile/viewer').set({
              'inviteId': 'new-invite',
              'version': 1,
              'consent': {},
              'values': {},
              'records': {},
            });
          };
          final operation = remove
              ? service.removeMember('viewer', expectedInviteId: 'invite')
              : service.save('viewer', {'email': true}, {});
          await expectLater(
            operation,
            throwsA(isA<SessionOperationCancelled>()),
          );
          await db.finished.future;
          expect(uid, nextUid);
          expect(
            (await db.doc('users/owner/family_members/viewer').get())
                .data()!['inviteId'],
            'new-invite',
          );
          expect(
            (await service.ref('owner', 'viewer').get()).data()!['values'],
            isEmpty,
          );
        },
      );
    }
  }
  test(
    'late decline retry after new login cannot overwrite acceptance',
    () async {
      final db = WatchedRetryFirestore();
      await db.doc('family_invites/invite').set({
        'invitedBy': 'owner',
        'status': 'pending',
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 1)),
        ),
      });
      String? uid = 'viewer';
      final auth = session(() => uid, () async {
        uid = null;
      });
      final service = FamilyRelationshipService(
        firestore: db,
        session: auth,
        currentEmail: () => null,
      );
      db.conflict = () async {
        expect(await auth.signOut(), true);
        await auth.signIn((_) async {
          uid = 'viewer';
        });
        await db.doc('family_invites/invite').update({
          'status': 'accepted',
          'acceptedBy': 'viewer',
        });
      };
      await expectLater(
        service.declineInvite('invite'),
        throwsA(isA<SessionOperationCancelled>()),
      );
      await db.finished.future;
      expect(
        (await db.doc('family_invites/invite').get()).data()!['status'],
        'accepted',
      );
    },
  );
  testWidgets('cancelled settings load is distinct from a current failure', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final auth = session(() => 'owner', () async {});
    final service = DelayedSettings(firestore: db, session: auth);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FamilyShareSettings(viewer: 'viewer', service: service),
        ),
      ),
    );
    service.result.completeError(SessionOperationCancelled());
    await tester.pumpAndSettle();
    expect(find.textContaining('載入已取消'), findsOneWidget);
    expect(find.textContaining('無法載入分享設定'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });
  test(
    'older sharing retry cannot revive a newer withdrawal in the same login epoch',
    () async {
      final db = boundary.RetryFirestore();
      await seed(db);
      final service = FamilyProfileService(
        firestore: db,
        session: session(() => 'owner', () async {}),
      );
      db.conflict = () => db.doc('users/owner/shared_profile/viewer').set({
        'version': 1,
        'inviteId': 'invite',
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1),
        'consent': {},
        'values': {},
        'records': {},
      });
      await expectLater(
        service.save('viewer', {'email': true}, {}),
        throwsStateError,
      );
      expect(
        (await service.ref('owner', 'viewer').get()).data()!['values'],
        isEmpty,
      );
    },
  );
  test(
    'legacy removal with explicitly missing version can clear only legacy relationships',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/owner/family_members/viewer').set({
        'userId': 'viewer',
      });
      await db.doc('users/viewer/family_members/owner').set({
        'userId': 'owner',
      });
      final service = FamilyProfileService(
        firestore: db,
        session: session(() => 'owner', () async {}),
      );
      await service.removeMember('viewer', expectedInviteId: null);
      expect(
        (await db.doc('users/owner/family_members/viewer').get()).exists,
        false,
      );
      expect(
        (await db.doc('users/viewer/family_members/owner').get()).exists,
        false,
      );
    },
  );
  test('null version from an old page must not adopt a newer rebind', () async {
    final db = FakeFirebaseFirestore();
    await seed(db);
    final service = FamilyProfileService(
      firestore: db,
      session: session(() => 'owner', () async {}),
    );
    await expectLater(
      service.removeMember('viewer', expectedInviteId: null),
      throwsStateError,
    );
    expect(
      (await db.doc('users/owner/family_members/viewer').get()).exists,
      true,
    );
  });
}
