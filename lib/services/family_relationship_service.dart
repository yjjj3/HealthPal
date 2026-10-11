import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'logout_coordinator.dart';

/// sharedData on users/{owner}/family_members/{viewer} is granted by owner.
class FamilyRelationshipService {
  FamilyRelationshipService({
    FirebaseFirestore? firestore,
    LogoutCoordinator? session,
    String? Function()? currentEmail,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _session = session ?? AuthService.logout,
       _email =
           currentEmail ?? (() => FirebaseAuth.instance.currentUser?.email);
  final FirebaseFirestore _db;
  final LogoutCoordinator _session;
  final String? Function() _email;

  Future<void> acceptInvite(String inviteId) async {
    final uid = _session.currentUid();
    final token = _session.generation;
    if (uid == null) throw StateError('請先登入');
    final inviteRef = _db.collection('family_invites').doc(inviteId);
    await _session.accountWork((current) async {
      await _db.runTransaction((transaction) async {
        void check() {
          if (!current() || _session.currentUid() != uid) {
            throw SessionOperationCancelled();
          }
        }

        check();
        final inviteDoc = await transaction.get(inviteRef);
        final invite = inviteDoc.data();
        if (invite == null || invite['status'] != 'pending') {
          throw StateError('邀請已使用或不存在');
        }
        final expiry = invite['expiresAt'];
        if (expiry is! Timestamp || !expiry.toDate().isAfter(DateTime.now())) {
          throw StateError('邀請已過期，請重新產生');
        }
        final inviterId = invite['invitedBy'] as String;
        if (inviterId == uid) throw StateError('不能接受自己的邀請');
        final me = await transaction.get(_db.collection('users').doc(uid));
        final target = invite['invitedToEmail'] ?? invite['emailOrPhone'];
        if (target != null &&
            target != _email()?.toLowerCase().trim() &&
            target != me.data()?['phoneNumber']) {
          throw StateError('此邀請不是發送給你的');
        }
        final myRef = _db
            .collection('users')
            .doc(uid)
            .collection('family_members')
            .doc(inviterId);
        final theirRef = _db
            .collection('users')
            .doc(inviterId)
            .collection('family_members')
            .doc(uid);
        final myRelationship = await transaction.get(myRef);
        final theirRelationship = await transaction.get(theirRef);
        if (myRelationship.exists || theirRelationship.exists) {
          throw StateError('家庭關係已存在；如需重新綁定，請先由雙方移除舊關係');
        }
        check();
        const noSharing = {'血糖': false, '血壓': false, '用藥': false};
        transaction.update(inviteRef, {
          'status': 'accepted',
          'acceptedBy': uid,
          'respondedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(theirRef, {
          'userId': uid,
          'name': '家人',
          'relation': invite['relation'] ?? '家人',
          'sharedData': noSharing,
          'inviteId': inviteId,
          'isOnline': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        // Accepting does not consent to sharing the recipient's own health data.
        transaction.set(myRef, {
          'userId': inviterId,
          'name': '家人',
          'relation': invite['relation'] ?? '家人',
          'sharedData': noSharing,
          'inviteId': inviteId,
          'isOnline': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    }, expectedGeneration: token);
  }

  Future<void> declineInvite(String inviteId) async {
    final uid = _session.currentUid();
    final token = _session.generation;
    if (uid == null) throw StateError('請先登入');
    await _session.accountWork((current) async {
      void check() {
        if (!current() || _session.currentUid() != uid) {
          throw SessionOperationCancelled();
        }
      }

      check();
      final ref = _db.collection('family_invites').doc(inviteId);
      final original = await ref.get(const GetOptions(source: Source.server));
      check();
      final initial = original.data();
      if (initial == null || initial['status'] != 'pending') {
        throw StateError('邀請已使用或不存在');
      }
      await _db.runTransaction((tx) async {
        check();
        final latest = (await tx.get(ref)).data();
        check();
        if (latest == null ||
            latest['status'] != 'pending' ||
            latest['invitedBy'] != initial['invitedBy'] ||
            latest['createdAt'] != initial['createdAt'] ||
            latest['expiresAt'] != initial['expiresAt']) {
          throw StateError('邀請已變更，請重新載入');
        }
        tx.update(ref, {
          'status': 'declined',
          'acceptedBy': uid,
          'respondedAt': FieldValue.serverTimestamp(),
        });
      });
      check();
    }, expectedGeneration: token);
  }
}
