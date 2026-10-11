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
    final medicationFrom = DateTime(now.year, now.month, now.day - 6);
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
              collection == 'medication_logs'
                  ? medicationFrom
                  : now.subtract(Duration(days: days)),
            ),
          )
          .where(date, isLessThanOrEqualTo: Timestamp.fromDate(now))
          .orderBy(date, descending: true)
          .limit(cap)
          .get();
      return snapshot.docs.map((d) => d.data()).toList();
    }

    final values = await Future.wait<Object?>([
      profile(uid),
      records('health_records', 'record_time', 30, 100),
      records('medication_logs', 'intake_time', 7, 51),
      records('diet_records', 'timestamp', 7, 50),
      owner
          .collection('medicine')
          .limit(101)
          .get()
          .then(
            (s) =>
                s.docs.map((d) => {...d.data(), 'medicine_id': d.id}).toList(),
          ),
    ]);
    return {
      'profile': values[0],
      'healthRecords': values[1],
      'medicationLogs': (values[2] as List<Map<String, dynamic>>)
          .take(50)
          .toList(),
      'dietRecords': values[3],
      'medications': (values[4] as List<Map<String, dynamic>>)
          .take(100)
          .toList(),
      'medicationContext': {
        'windowStart': Timestamp.fromDate(medicationFrom),
        'windowEnd': Timestamp.fromDate(now),
        'logsTruncated': (values[2] as List).length > 50,
        'medicationsTruncated': (values[4] as List).length > 100,
      },
    };
  }
}
