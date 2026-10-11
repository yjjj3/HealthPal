import 'package:flutter_test/flutter_test.dart';
import 'package:health_management_app/services/prescription_scan_service.dart';
import 'medication_567_test.dart' as f;
import 'prescription_session_test.dart' as session;

void main() {
  for (final count in [1, 2]) {
    test(
      'lost acknowledgement then delete all $count medicines never resurrects',
      () async {
        final db = session.AckLossFirestore();
        final service = PrescriptionScanService(
          firestore: db,
          currentUid: () => 'a',
          now: () => f.today,
        );
        final prepared = service.prepareMedications(
          List.generate(count, (i) => f.med(id: 'reserved-$i')),
        );
        await expectLater(service.saveMedications(prepared), throwsStateError);
        final committed = (await db.collection('users/a/medicine').get()).docs;
        expect(committed, hasLength(count));
        for (final doc in committed) {
          await doc.reference.delete();
        }
        await expectLater(service.saveMedications(prepared), throwsStateError);
        expect((await db.collection('users/a/medicine').get()).docs, isEmpty);
      },
    );
  }
  test(
    'lost acknowledgement then partial deletion preserves the survivor',
    () async {
      final db = session.AckLossFirestore();
      final service = PrescriptionScanService(
        firestore: db,
        currentUid: () => 'a',
      );
      final prepared = service.prepareMedications([
        f.med(id: 'first'),
        f.med(id: 'second'),
      ]);
      await expectLater(service.saveMedications(prepared), throwsStateError);
      await db.doc('users/a/medicine/first').delete();
      await db.doc('users/a/medicine/second').update({'total_supply': 3});
      await expectLater(service.saveMedications(prepared), throwsStateError);
      final survivors = (await db.collection('users/a/medicine').get()).docs;
      expect(survivors, hasLength(1));
      expect(survivors.single.data()['total_supply'], 3);
    },
  );
}
