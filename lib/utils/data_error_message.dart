import 'package:firebase_core/firebase_core.dart';

String dataErrorMessage(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return '沒有讀取或儲存這項資料的權限，請確認帳號與分享設定。';
      case 'unauthenticated':
        return '登入已失效，請重新登入。';
      case 'unavailable':
      case 'deadline-exceeded':
        return '連線暫時中斷，請確認網路後重試。';
      case 'failed-precondition':
        return '資料查詢設定尚未就緒，請稍後重試或聯絡管理者。';
    }
  }
  return '資料處理失敗，請重試。';
}
