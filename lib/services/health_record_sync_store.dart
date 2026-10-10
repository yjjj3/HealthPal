import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// Stable document IDs make retries and concurrent device syncs idempotent.
class HealthRecordSyncStore {
  HealthRecordSyncStore(this.firestore);
  final FirebaseFirestore firestore;

  static String documentId(String sourceId) =>
      'health_${sha256.convert(utf8.encode(sourceId))}';

  Future<void> upsert(
    String uid,
    Map<String, Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) return;
    final ref = firestore
        .collection('users')
        .doc(uid)
        .collection('health_records');
    // Preserve legacy random-ID records rather than duplicating them.
    final existing = await ref
        .where('source', isEqualTo: 'health_platform')
        .get();
    final legacyIds = <String, String>{};
    for (final doc in existing.docs) {
      final source = doc.data()['source_id'];
      if (source is String) legacyIds.putIfAbsent(source, () => doc.id);
    }
    var batch = firestore.batch();
    var count = 0;
    for (final entry in records.entries) {
      final id = legacyIds[entry.key] ?? documentId(entry.key);
      final data = Map<String, dynamic>.from(entry.value);
      if (legacyIds.containsKey(entry.key)) data.remove('created_at');
      batch.set(ref.doc(id), data, SetOptions(merge: true));
      if (++count == 400) {
        await batch.commit();
        batch = firestore.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();
  }
}
