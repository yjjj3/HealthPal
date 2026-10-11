import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'logout_coordinator.dart';

/// Each viewer gets only explicitly selected values, never the private profile.
class FamilyProfileService {
  FamilyProfileService({
    FirebaseFirestore? firestore,
    LogoutCoordinator? session,
  }) : db = firestore ?? FirebaseFirestore.instance,
       session = session ?? AuthService.logout;
  final FirebaseFirestore db;
  final LogoutCoordinator session;

  static const fields = <String, String>{
    'fullName': '姓名',
    'email': '電子郵件',
    'phoneNumber': '電話',
    'dateOfBirth': '生日',
    'gender': '性別',
    'bloodType': '血型',
    'height': '身高',
    'weight': '體重',
    'chronicDiseases': '慢性病史',
    'allergies': '過敏史',
  };
  static const recordFields = <String, String>{
    '血糖': '血糖記錄',
    '血壓': '血壓記錄',
    '用藥': '用藥資料',
  };

  static Map<String, bool> choices(Object? raw, Iterable<String> keys) {
    return {for (final key in keys) key: raw is Map && raw[key] == true};
  }

  DocumentReference<Map<String, dynamic>> ref(String owner, String viewer) => db
      .collection('users')
      .doc(owner)
      .collection('shared_profile')
      .doc(viewer);

  Future<Map<String, dynamic>> loadSettings(String viewer) async {
    final owner = session.currentUid();
    final token = session.generation;
    if (owner == null || !session.isCurrent(token)) {
      throw SessionOperationCancelled();
    }
    final doc = await ref(owner, viewer).get();
    final relation = await db
        .collection('users')
        .doc(owner)
        .collection('family_members')
        .doc(viewer)
        .get();
    if (owner != session.currentUid() || !session.isCurrent(token)) {
      throw SessionOperationCancelled();
    }
    // Missing/legacy projection is not consent, but retain current relationship intent.
    final inviteId = relation.data()?['inviteId'];
    if (!relation.exists || inviteId is! String) return {};
    return doc.data()?['version'] == 1 && doc.data()?['inviteId'] == inviteId
        ? doc.data()!
        : {'inviteId': inviteId};
  }

  Future<void> removeMember(
    String viewer, {
    required String? expectedInviteId,
  }) {
    final owner = session.currentUid();
    final token = session.generation;
    if (owner == null || owner == viewer) throw StateError('請選擇有效家人');
    return session.accountWork((current) async {
      void check() {
        if (!current() || session.currentUid() != owner) {
          throw SessionOperationCancelled();
        }
      }

      check();
      final own = db
          .collection('users')
          .doc(owner)
          .collection('family_members')
          .doc(viewer);
      final initial = await own.get(const GetOptions(source: Source.server));
      check();
      if (!initial.exists) return;
      final inviteId = expectedInviteId;
      if (initial.data()?['inviteId'] != inviteId) {
        throw StateError('家庭關係已變更，請重新載入');
      }
      // Transactions fail offline instead of enqueuing unconditional deletes.
      // Every retry remains tied to the original relationship and login epoch.
      await db.runTransaction((tx) async {
        check();
        final member = await tx.get(own);
        final projection = await tx.get(ref(owner, viewer));
        check();
        if (!member.exists) return;
        if (member.data()?['inviteId'] != inviteId) {
          throw StateError('家庭關係已變更，請重新載入');
        }
        tx.delete(own);
        tx.delete(
          db
              .collection('users')
              .doc(viewer)
              .collection('family_members')
              .doc(owner),
        );
        if (projection.exists && projection.data()?['inviteId'] == inviteId) {
          tx.delete(ref(owner, viewer));
        }
      });
      check();
    }, expectedGeneration: token);
  }

  Future<void> save(
    String viewer,
    Map<String, bool> consent,
    Map<String, bool> records, {
    String? expectedInviteId,
  }) {
    if (consent.keys.any((key) => !fields.containsKey(key)) ||
        records.keys.any((key) => !recordFields.containsKey(key))) {
      throw ArgumentError('未知分享欄位');
    }
    final owner = session.currentUid();
    final token = session.generation;
    if (owner == null || owner == viewer) {
      throw StateError('請登入並選擇有效家人');
    }
    final selected = choices(consent, fields.keys);
    final selectedRecords = choices(records, recordFields.keys);
    return session.accountWork((current) async {
      void check() {
        if (!current() || session.currentUid() != owner) {
          throw SessionOperationCancelled();
        }
      }

      check();
      final relationRef = db
          .collection('users')
          .doc(owner)
          .collection('family_members')
          .doc(viewer);
      final initial = await relationRef.get(
        const GetOptions(source: Source.server),
      );
      check();
      final inviteId = expectedInviteId ?? initial.data()?['inviteId'];
      if (!initial.exists ||
          inviteId is! String ||
          initial.data()?['inviteId'] != inviteId) {
        throw StateError('家庭關係已變更或移除，請重新載入');
      }
      final originalProjection = await ref(
        owner,
        viewer,
      ).get(const GetOptions(source: Source.server));
      check();
      final originalStamp = originalProjection.data()?['updatedAt'];
      if (originalProjection.exists && originalStamp is! Timestamp) {
        throw StateError('分享資料版本無法確認，請重新綁定');
      }
      await db.runTransaction((tx) async {
        check();
        final own = db.collection('users').doc(owner);
        final relation = own.collection('family_members').doc(viewer);
        final profile = await tx.get(own);
        final member = await tx.get(relation);
        final latestProjection = await tx.get(ref(owner, viewer));
        check();
        if (latestProjection.exists != originalProjection.exists ||
            latestProjection.data()?['updatedAt'] != originalStamp) {
          throw StateError('分享設定已變更，請重新載入；不覆蓋較新的撤回');
        }
        if (!member.exists || member.data()?['inviteId'] != inviteId) {
          throw StateError('家庭關係已變更或移除，請重新載入');
        }
        final source = profile.data() ?? {};
        final values = <String, dynamic>{
          for (final key in fields.keys)
            if (selected[key] == true && source[key] != null) key: source[key],
        };
        // Replace the entire document: revocation removes old values.
        tx.set(ref(owner, viewer), {
          'version': 1,
          'inviteId': inviteId,
          'consent': selected,
          'values': values,
          'records': selectedRecords,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(relation, {'sharedData': selectedRecords});
      });
      check();
    }, expectedGeneration: token);
  }
}
