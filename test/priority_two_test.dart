import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_management_app/services/live_query_window.dart';
import 'package:health_management_app/utils/initialization_gate.dart';
import 'package:health_management_app/utils/data_error_message.dart';

void main() {
  test('initialization coalesces concurrent calls and stays ready', () async {
    final gate = InitializationGate();
    final done = Completer<void>();
    var calls = 0;
    Future<void> init() {
      calls++;
      return done.future;
    }

    final first = gate.run(init);
    final second = gate.run(init);
    expect(calls, 1);
    done.complete();
    await Future.wait([first, second]);
    await gate.run(init);
    expect(calls, 1);
  });

  test(
    'initialization retries synchronous and asynchronous failures',
    () async {
      final gate = InitializationGate();
      await expectLater(
        gate.run(() => throw StateError('sync')),
        throwsStateError,
      );
      await expectLater(
        gate.run(() async => throw StateError('async')),
        throwsStateError,
      );
      var calls = 0;
      await gate.run(() async {
        calls++;
      });
      await gate.run(() async {
        calls++;
      });
      expect(calls, 1);
    },
  );

  test(
    'live window expands without losing inserts, updates, or deletes',
    () async {
      final db = FakeFirebaseFirestore();
      final records = db.collection('records');
      for (var i = 0; i < 7; i++) {
        await records.doc('$i').set({'time': i, 'value': i});
      }
      final window = LiveQueryWindow(
        records.orderBy('time', descending: true),
        pageSize: 3,
      );
      final events = StreamIterator(window.stream);
      expect(await events.moveNext(), true);
      expect(events.current.docs.map((d) => d.id), ['6', '5', '4']);
      expect(window.hasMore, true);
      await window.loadMore();
      expect(await events.moveNext(), true);
      expect(events.current.docs.map((d) => d.id), [
        '6',
        '5',
        '4',
        '3',
        '2',
        '1',
      ]);
      await records.doc('8').set({'time': 8, 'value': 8});
      expect(await events.moveNext(), true);
      expect(events.current.docs.map((d) => d.id), [
        '8',
        '6',
        '5',
        '4',
        '3',
        '2',
      ]);
      await records.doc('6').update({'value': 60});
      expect(await events.moveNext(), true);
      expect(
        events.current.docs.firstWhere((d) => d.id == '6').data()['value'],
        60,
      );
      await records.doc('8').delete();
      expect(await events.moveNext(), true);
      expect(events.current.docs.map((d) => d.id), [
        '6',
        '5',
        '4',
        '3',
        '2',
        '1',
      ]);
      await window.loadMore();
      expect(await events.moveNext(), true);
      expect(events.current.docs, hasLength(7));
      expect(window.hasMore, false);
      await events.cancel();
      await window.dispose();
    },
  );

  test(
    'late subscribers receive latest snapshot and share one live window',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('records/one').set({'time': 1});
      var changes = 0;
      final window = LiveQueryWindow(
        db.collection('records').orderBy('time'),
        onChanged: () => changes++,
      );
      final first = StreamIterator(window.stream);
      expect(await first.moveNext(), true);
      final second = StreamIterator(window.stream);
      expect(await second.moveNext(), true);
      expect(second.current.docs.single.id, 'one');
      expect(changes, 1);
      await db.doc('records/two').set({'time': 2});
      expect(await first.moveNext(), true);
      expect(await second.moveNext(), true);
      expect(first.current.docs, hasLength(2));
      expect(second.current.docs, hasLength(2));
      expect(changes, 2);
      await first.cancel();
      await second.cancel();
      await window.dispose();
      await db.doc('records/three').set({'time': 3});
      await Future<void>.delayed(Duration.zero);
      expect(changes, 2);
    },
  );

  test(
    'server category filter can reach older records beyond the first page',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 8; i++) {
        await db.doc('records/$i').set({
          'time': i,
          'category': i < 2 ? '體重' : '血壓',
        });
      }
      final window = LiveQueryWindow(
        db
            .collection('records')
            .where('category', isEqualTo: '體重')
            .orderBy('time', descending: true),
        pageSize: 3,
      );
      final event = await window.stream.first;
      expect(event.docs.map((d) => d.id), ['1', '0']);
      expect(window.hasMore, false);
      await window.dispose();
    },
  );

  test('disposing during refresh does not reopen the source', () async {
    final db = FakeFirebaseFirestore();
    final window = LiveQueryWindow(db.collection('records'));
    final first = window.stream.first;
    await first;
    final refresh = window.refresh();
    await window.dispose();
    await refresh;
    expect(await window.stream.toList(), isEmpty);
  });

  test('permission and network errors are distinct from empty data', () {
    final permission = dataErrorMessage(
      FirebaseException(plugin: 'firestore', code: 'permission-denied'),
    );
    final network = dataErrorMessage(
      FirebaseException(plugin: 'firestore', code: 'unavailable'),
    );
    expect(permission, contains('權限'));
    expect(network, contains('網路'));
    expect(permission, isNot(network));
  });
}
