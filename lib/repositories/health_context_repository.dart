import 'package:cloud_firestore/cloud_firestore.dart';

/// Bounded AI context collection. A failed read is never represented as empty data.
class HealthContextRepository {
  HealthContextRepository(this.firestore, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final FirebaseFirestore firestore;
  final DateTime Function() _now;
  Future<Map<String, dynamic>?> profile(String uid) async =>
      (await firestore.collection('users').doc(uid).get()).data();
  Future<Map<String, dynamic>> collect(String uid) async {
    final owner = firestore.collection('users').doc(uid);
    final now = _now();
    Future<List<Map<String, dynamic>>> records(
      String collection,
      String date,
      int days,
      int cap,
    ) async {
      final snapshot = await owner
          .collection(collection)
          .where(
            date,
            isGreaterThanOrEqualTo: Timestamp.fromDate(
              now.subtract(Duration(days: days)),
            ),
          )
          .orderBy(date, descending: true)
          .limit(cap)
          .get();
      return snapshot.docs.map((d) => d.data()).toList();
    }

    final values = await Future.wait<Object?>([
      profile(uid),
      records('health_records', 'record_time', 30, 100),
      records('medication_logs', 'intake_time', 7, 50),
      records('diet_records', 'timestamp', 7, 50),
      owner
          .collection('medicine')
          .limit(100)
          .get()
          .then((s) => s.docs.map((d) => d.data()).toList()),
    ]);
    return {
      'profile': values[0],
      'healthRecords': values[1],
      'medicationLogs': values[2],
      'dietRecords': values[3],
      'medications': values[4],
    };
  }
}
