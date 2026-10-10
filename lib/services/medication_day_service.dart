import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/medication_model.dart';

/// Updates today's status without replacing dosage, inventory or other fields.
class MedicationDayService {
  MedicationDayService(this.firestore);
  final FirebaseFirestore firestore;

  Future<medicine?> resetIfNeeded(String uid, String id) {
    final ref = firestore
        .collection('users')
        .doc(uid)
        .collection('medicine')
        .doc(id);
    return firestore.runTransaction<medicine?>((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return null;
      final current = medicine.fromFirestore(snapshot);
      if (!current.shouldResetStatus) return null;
      final reset = current.resetStatus();
      transaction.update(ref, {
        'times_status': reset.times_status,
        'lastUpdated': Timestamp.fromDate(reset.lastUpdated),
      });
      return reset;
    });
  }
}
