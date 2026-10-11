import 'logout_coordinator.dart';
import 'notification_service.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';

class AuthService {
  static final logout = LogoutCoordinator(
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    signOutAuth: () => FirebaseAuth.instance.signOut(),
    cleanup: () => NotificationService().clearAfterSignOut(),
  );
  int get sessionGeneration => logout.generation;
  bool isCurrentAttempt(int token) => logout.isCurrent(token);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // 取得當前用戶
  User? get currentUser => _auth.currentUser;

  // 監聽驗證狀態
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 電子郵件註冊
  Future<UserCredential?> signUpWithEmail({
    required String email,
    required String password,
    int? expectedGeneration,
  }) async {
    try {
      UserCredential userCredential = await logout.signIn<UserCredential>(
        (_) => _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        ),
        expectedGeneration: expectedGeneration,
        verifiedUid: (credential) => credential.user?.uid,
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // 電子郵件登入
  Future<UserCredential?> signInWithEmail({
    required String email,
    required String password,
    int? expectedGeneration,
  }) async {
    try {
      UserCredential userCredential = await logout.signIn<UserCredential>(
        (_) =>
            _auth.signInWithEmailAndPassword(email: email, password: password),
        expectedGeneration: expectedGeneration,
        verifiedUid: (credential) => credential.user?.uid,
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // 登出
  Future<bool> signOut() => logout.signOut();

  // 發送密碼重置郵件
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // 刪除帳號
  Future<void> deleteAccount() async {
    try {
      await _auth.currentUser?.delete();
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // ==================== Google 登入 ====================

  /// Google 登入
  Future<UserCredential?> signInWithGoogle({int? expectedGeneration}) async {
    final token = expectedGeneration ?? sessionGeneration;
    if (!isCurrentAttempt(token)) throw SessionOperationCancelled();
    try {
      // 觸發 Google 登入流程
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (!isCurrentAttempt(token)) throw SessionOperationCancelled();
      if (googleUser == null) {
        // 用戶取消登入
        return null;
      }

      // 取得認證資訊
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (!isCurrentAttempt(token)) throw SessionOperationCancelled();
      // 建立 Firebase 憑證
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 使用憑證登入 Firebase
      return await logout.signIn<UserCredential>(
        (_) => _auth.signInWithCredential(credential),
        expectedGeneration: token,
        verifiedUid: (credential) => credential.user?.uid,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } on SessionOperationCancelled {
      rethrow;
    } catch (e) {
      throw 'Google 登入失敗: $e';
    }
  }

  /// 登出 Google
  Future<void> signOutGoogle() async {
    await _googleSignIn.signOut();
  }

  // ==================== Apple 登入 ====================

  /// 產生隨機 nonce 字串
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// 將 nonce 進行 SHA256 雜湊
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Apple 登入
  Future<UserCredential?> signInWithApple({int? expectedGeneration}) async {
    final token = expectedGeneration ?? sessionGeneration;
    if (!isCurrentAttempt(token)) throw SessionOperationCancelled();
    // 只在 iOS/macOS 上支援
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw 'Apple 登入僅支援 iOS 和 macOS 裝置';
    }

    try {
      // 產生 nonce
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      // 請求 Apple 授權
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      if (!isCurrentAttempt(token)) throw SessionOperationCancelled();
      // 建立 Firebase 憑證
      final oauthCredential = OAuthProvider(
        'apple.com',
      ).credential(idToken: appleCredential.identityToken, rawNonce: rawNonce);

      // 使用憑證登入 Firebase
      final userCredential = await logout.signIn<UserCredential>(
        (_) => _auth.signInWithCredential(oauthCredential),
        expectedGeneration: token,
        verifiedUid: (credential) => credential.user?.uid,
      );

      // 如果是首次登入，更新用戶顯示名稱
      if (isCurrentAttempt(sessionGeneration) &&
          _auth.currentUser?.uid == userCredential.user?.uid &&
          (appleCredential.givenName != null ||
              appleCredential.familyName != null)) {
        final displayName = [
          appleCredential.familyName ?? '',
          appleCredential.givenName ?? '',
        ].where((s) => s.isNotEmpty).join();

        if (displayName.isNotEmpty) {
          final completionToken = sessionGeneration;
          await logout.finishSignIn(completionToken, (current) async {
            if (current()) await userCredential.user?.updateDisplayName(displayName);
          });
        }
      }

      return userCredential;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // 用戶取消登入
        return null;
      }
      throw 'Apple 登入失敗: ${e.message}';
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } on SessionOperationCancelled {
      rethrow;
    } catch (e) {
      throw 'Apple 登入失敗: $e';
    }
  }

  /// 檢查 Apple 登入是否可用
  Future<bool> isAppleSignInAvailable() async {
    // 需要 Apple Developer Program 付費帳號才能使用
    return false;
  }

  // 錯誤處理
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return '密碼強度不足，請使用至少 6 個字元的密碼';
      case 'email-already-in-use':
        return '此電子郵件已被註冊';
      case 'user-not-found':
        return '找不到此帳號';
      case 'wrong-password':
        return '密碼錯誤';
      case 'invalid-email':
        return '電子郵件格式不正確';
      case 'user-disabled':
        return '此帳號已被停用';
      case 'too-many-requests':
        return '嘗試次數過多，請稍後再試';
      case 'operation-not-allowed':
        return '此登入方式未啟用';
      case 'invalid-credential':
        return '登入憑證無效';
      default:
        return '登入失敗: ${e.message ?? "未知錯誤"}';
    }
  }
}
