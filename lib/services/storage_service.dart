import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // 上傳圖片（回傳圖片 URL）
  Future<String> uploadImage(String uid, File imageFile, String folder) async {
    final ref = _storage.ref().child('$folder/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putFile(imageFile);
    return await ref.getDownloadURL();
  }
}
