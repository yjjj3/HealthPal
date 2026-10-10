import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessageService {
  ChatMessageService(this.firestore);
  final FirebaseFirestore firestore;

  Future<void> sendOnce({
    required String chatId,
    required String messageId,
    required String senderId,
    required String recipientId,
    required String senderName,
    required String text,
  }) async {
    final chat = firestore.collection('chats').doc(chatId);
    final message = chat.collection('messages').doc(messageId);
    await firestore.runTransaction((transaction) async {
      if ((await transaction.get(message)).exists) return;
      transaction.set(message, {
        'text': text,
        'senderId': senderId,
        'senderName': senderName,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'text',
      });
      transaction.update(chat, {
        'lastMessage': text.length > 20 ? '${text.substring(0, 20)}...' : text,
        'lastTime': FieldValue.serverTimestamp(),
        'unread.$recipientId': FieldValue.increment(1),
      });
    });
  }
}
