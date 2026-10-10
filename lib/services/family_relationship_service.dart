import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// sharedData on users/{owner}/family_members/{viewer} is granted by owner.
class FamilyRelationshipService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> acceptInvite(String inviteId) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('請先登入');
    final inviteRef = _db.collection('family_invites').doc(inviteId);
    await _db.runTransaction((transaction) async {
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
      if (inviterId == user.uid) throw StateError('不能接受自己的邀請');
      final me = await transaction.get(_db.collection('users').doc(user.uid));
      final inviter = await transaction.get(
        _db.collection('users').doc(inviterId),
      );
      final target = invite['invitedToEmail'] ?? invite['emailOrPhone'];
      if (target != null &&
          target != user.email?.toLowerCase().trim() &&
          target != me.data()?['phoneNumber']) {
        throw StateError('此邀請不是發送給你的');
      }
      final myRef = _db
          .collection('users')
          .doc(user.uid)
          .collection('family_members')
          .doc(inviterId);
      final theirRef = _db
          .collection('users')
          .doc(inviterId)
          .collection('family_members')
          .doc(user.uid);
      final myRelationship = await transaction.get(myRef);
      final theirRelationship = await transaction.get(theirRef);
      if (myRelationship.exists || theirRelationship.exists) {
        throw StateError('家庭關係已存在；如需重新綁定，請先由雙方移除舊關係');
      }
      final shared = Map<String, dynamic>.from(invite['sharedData'] ?? {});
      final noSharing = {for (final key in shared.keys) key: false};
      transaction.update(inviteRef, {
        'status': 'accepted',
        'acceptedBy': user.uid,
        'respondedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(theirRef, {
        'userId': user.uid,
        'name': me.data()?['fullName'] ?? '家人',
        'email': user.email ?? '',
        'relation': invite['relation'] ?? '家人',
        'sharedData': shared,
        'inviteId': inviteId,
        'isOnline': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Accepting does not consent to sharing the recipient's own health data.
      transaction.set(myRef, {
        'userId': inviterId,
        'name':
            inviter.data()?['fullName'] ??
            invite['inviterName'] ??
            invite['name'] ??
            '家人',
        'email': inviter.data()?['email'] ?? '',
        'relation': invite['relation'] ?? '家人',
        'sharedData': noSharing,
        'inviteId': inviteId,
        'isOnline': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> declineInvite(String inviteId) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('請先登入');
    await _db.collection('family_invites').doc(inviteId).update({
      'status': 'declined',
      'acceptedBy': user.uid,
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }
}
