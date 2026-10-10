import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 導入 FirebaseAuth
// 假設 ProfileScreen 和 UserProfile 都在 profile_screen.dart 中定義
import 'profile_screen.dart'; 

// =================================================================
// ProfileWrapper：負責身份驗證和資料載入
// =================================================================
class ProfileWrapper extends StatefulWidget {
  const ProfileWrapper({super.key});

  @override
  State<ProfileWrapper> createState() => _ProfileWrapperState();
}

class _ProfileWrapperState extends State<ProfileWrapper> {
  // 檢查用戶是否已登入
  final User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    // 1. 檢查是否有登入用戶 (雖然 main.dart 已經確保了匿名登入，但這是好習慣)
    if (currentUser == null) {
      // 理論上不會到達這裡，但作為保護
      return const Center(child: Text('應用程式初始化中...請稍候。'));
    }

    // 🚨 這是關鍵的修改：使用當前登入用戶的 UID
    final String currentUserId = currentUser!.uid;
    
    // 2. 建立 Firestore 文件參考
    final DocumentReference<Map<String, dynamic>> profileRef = 
        FirebaseFirestore.instance.collection('users').doc(currentUserId);
    
    // 3. 使用 FutureBuilder 讀取一次資料
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: profileRef.get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('載入資料錯誤: ${snapshot.error}'),
          );
        }

        // 檢查文件是否存在
        if (snapshot.hasData && snapshot.data!.exists) {
          // 資料存在：將 Firestore 資料轉換為 UserProfile 物件
          try {
             final userProfile = UserProfile.fromFirestore(snapshot.data!);
             return ProfileScreen(userProfile: userProfile);
          } catch (e) {
             // 處理轉換錯誤，例如資料欄位不完整
             debugPrint('UserProfile 轉換失敗: $e');
             return const Center(
               child: Text('資料格式錯誤，請編輯以修正個人資料。'),
             );
          }
        } else {
          // 資料不存在：第一次使用的使用者，提示建立個人資料
          // 💡 這裡將會顯示您想要修復的訊息
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text(
                '找不到此使用者的個人資料，請先編輯資料。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          );
        }
      },
    );
  }
}
