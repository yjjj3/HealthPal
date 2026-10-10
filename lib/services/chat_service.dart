import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 傳送訊息
  Future<void> sendMessage(String chatId, Map<String, dynamic> message) async {
    await _db.collection('chats').doc(chatId)
      .collection('messages')
      .add({
        ...message,
        'timestamp': FieldValue.serverTimestamp(),
      });
  }

  // 即時監聽訊息串
  Stream<QuerySnapshot> getMessages(String chatId) {
    return _db.collection('chats').doc(chatId)
      .collection('messages')
      .orderBy('timestamp', descending: false)
      .snapshots();
  }
}
