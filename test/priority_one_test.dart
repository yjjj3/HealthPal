import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_management_app/services/medication_day_service.dart';
import 'package:health_management_app/services/health_record_sync_store.dart';
import 'package:health_management_app/services/chat_message_service.dart';

void main() {
  test(
    'daily reset preserves inventory and later intake is not reset again',
    () async {
      final db = FakeFirebaseFirestore();
      final ref = db.doc('users/alice/medicine/pill');
      await ref.set({
        'name': 'test',
        'frequency': '每天1次',
        'times_status': [true],
        'times_of_day_list': [Timestamp.now()],
        'total_supply': 19,
        'lastUpdated': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 1)),
        ),
        'custom_field': 'preserve',
      });
      final service = MedicationDayService(db);
      expect(await service.resetIfNeeded('alice', 'pill'), isNotNull);
      var data = (await ref.get()).data()!;
      expect(data['times_status'], [false]);
      expect(data['total_supply'], 19);
      expect(data['custom_field'], 'preserve');
      await ref.update({
        'times_status': [true],
        'total_supply': 18,
      });
      expect(await service.resetIfNeeded('alice', 'pill'), isNull);
      data = (await ref.get()).data()!;
      expect(data['times_status'], [true]);
      expect(data['total_supply'], 18);
      expect(await service.resetIfNeeded('alice', 'deleted'), isNull);
    },
  );

  test(
    'repeated health sync updates steps without duplicating documents',
    () async {
      final db = FakeFirebaseFirestore();
      final store = HealthRecordSyncStore(db);
      Map<String, Map<String, dynamic>> steps(int value) => {
        'steps_today': {
          'source': 'health_platform',
          'source_id': 'steps_today',
          'category': '運動',
          'value': value,
          'created_at': FieldValue.serverTimestamp(),
        },
      };
      await store.upsert('alice', steps(100));
      await store.upsert('alice', steps(300));
      final docs =
          (await db.collection('users/alice/health_records').get()).docs;
      expect(docs, hasLength(1));
      expect(docs.single.id, HealthRecordSyncStore.documentId('steps_today'));
      expect(docs.single.data()['value'], 300);
    },
  );

  test('health sync preserves legacy IDs and creation timestamps', () async {
    final db = FakeFirebaseFirestore();
    final oldTime = Timestamp.fromDate(DateTime(2025));
    await db.doc('users/alice/health_records/legacy').set({
      'source': 'health_platform',
      'source_id': 'steps_today',
      'created_at': oldTime,
    });
    await HealthRecordSyncStore(db).upsert('alice', {
      'steps_today': {
        'source': 'health_platform',
        'source_id': 'steps_today',
        'value': 400,
        'created_at': FieldValue.serverTimestamp(),
      },
    });
    final docs = (await db.collection('users/alice/health_records').get()).docs;
    expect(docs, hasLength(1));
    expect(docs.single.id, 'legacy');
    expect(docs.single.data()['created_at'], oldTime);
    expect(docs.single.data()['value'], 400);
  });

  test('health sync handles more than one write chunk', () async {
    final db = FakeFirebaseFirestore();
    await HealthRecordSyncStore(db).upsert('alice', {
      for (var i = 0; i < 805; i++)
        'sample_$i': {'source': 'health_platform', 'source_id': 'sample_$i'},
    });
    expect(
      (await db.collection('users/alice/health_records').get()).docs,
      hasLength(805),
    );
  });

  test(
    'retrying a message ID does not duplicate message or unread count',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('chats/alice_bob').set({
        'members': ['alice', 'bob'],
        'unread': {'bob': 0},
      });
      final service = ChatMessageService(db);
      Future<void> send() => service.sendOnce(
        chatId: 'alice_bob',
        messageId: 'retry-id',
        senderId: 'alice',
        recipientId: 'bob',
        senderName: 'Alice',
        text: 'hello',
      );
      await send();
      await send();
      expect(
        (await db.collection('chats/alice_bob/messages').get()).docs,
        hasLength(1),
      );
      final chat = (await db.doc('chats/alice_bob').get()).data()!;
      expect(chat['lastMessage'], 'hello');
      expect(chat['unread']['bob'], 1);
    },
  );
}
