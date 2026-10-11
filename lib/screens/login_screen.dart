import '../services/logout_coordinator.dart';
import 'dart:async';
import 'dart:io';
import '../theme/app_colors.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/login_security_service.dart';
import 'registration_screen.dart';

const Color _primaryColor = AppColors.primary;
const Color _accentColor = AppColors.success;

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        toolbarHeight: 0,
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              // Logo 區域
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF4FC3D0),
                        Color(0xFF45B09A),
                        Color(0xFF5DB8A0),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF45B09A).withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/icon.png', fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'HealthPal',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2E35),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '登入以開始管理您的健康',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 50),
              const _LoginForm(),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '還沒有帳號？',
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const RegistrationScreen(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.center,
                    ),
                    child: const Text(
                      '立即註冊',
                      style: TextStyle(
                        color: _primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm();

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _loginSecurityService = LoginSecurityService();
  String _email = '';
  String _password = '';
  bool _isLoading = false;

  // 登入安全相關狀態
  bool _isAccountLocked = false;
  int _remainingLockoutSeconds = 0;
  Timer? _lockoutTimer;

  // 社交登入狀態
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _isAppleAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkAppleSignInAvailability();
  }

  // 檢查 Apple 登入是否可用
  Future<void> _checkAppleSignInAvailability() async {
    if (Platform.isIOS || Platform.isMacOS) {
      final available = await _authService.isAppleSignInAvailable();
      if (mounted) {
        setState(() {
          _isAppleAvailable = available;
        });
      }
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  // 開始鎖定倒數計時
  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingLockoutSeconds > 0) {
        setState(() {
          _remainingLockoutSeconds--;
        });
      } else {
        timer.cancel();
        setState(() {
          _isAccountLocked = false;
        });
      }
    });
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return '電子郵件為必填欄位';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return '請輸入有效的電子郵件格式';
    }
    return null;
  }

  // 登入處理（Firebase 版本，含完整錯誤處理 + 登入次數限制）
  Future<void> _submitLogin() async {
    var attempt = _authService.sessionGeneration;
    if (!_formKey.currentState!.validate()) return;

    _formKey.currentState!.save();
    final email = _email.trim();

    // 檢查帳號是否被鎖定
    final locked = await _loginSecurityService.isAccountLocked(email);
    if (!mounted || !_authService.isCurrentAttempt(attempt)) return;
    if (locked) {
      final remainingSeconds = await _loginSecurityService
          .getRemainingLockoutSeconds(email);
      if (!mounted || !_authService.isCurrentAttempt(attempt)) return;
      setState(() {
        _isAccountLocked = true;
        _remainingLockoutSeconds = remainingSeconds;
      });
      _startLockoutTimer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '帳號已被暫時鎖定，請等待 ${_loginSecurityService.formatRemainingTime(remainingSeconds)}',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 呼叫 Firebase 登入
      final userCredential = await _authService.signInWithEmail(
        email: email,
        password: _password,
        expectedGeneration: attempt,
      );

      // 登入成功
      attempt = _authService.sessionGeneration;
      if (userCredential?.user != null &&
          _authService.currentUser?.uid == userCredential?.user?.uid &&
          _authService.isCurrentAttempt(attempt)) {
        await AuthService.logout.finishSignIn(attempt, (current) async {
          if (current()) await _loginSecurityService.recordSuccessfulLogin(email);
        });

        if (!mounted || !_authService.isCurrentAttempt(attempt)) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('登入成功'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on SessionOperationCancelled {
      return;
    } catch (e) {
      if (!_authService.isCurrentAttempt(attempt)) return;
      // 記錄登入失敗
      final result = await _loginSecurityService.recordFailedAttempt(email);
      if (!mounted || !_authService.isCurrentAttempt(attempt)) return;

      if (result.isLocked) {
        setState(() {
          _isAccountLocked = true;
          _remainingLockoutSeconds = result.lockoutSeconds;
        });
        _startLockoutTimer();
      }

      // 顯示錯誤訊息（包含剩餘嘗試次數）
      if (mounted) {
        String errorMessage = result.isLocked
            ? result.message
            : '密碼錯誤，還剩 ${result.remainingAttempts} 次嘗試機會';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: result.isLocked ? Colors.red : Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================== 社交登入方法 ====================

  // Google 登入
  Future<void> _signInWithGoogle() async {
    var attempt = _authService.sessionGeneration;
    setState(() => _isGoogleLoading = true);

    try {
      final userCredential = await _authService.signInWithGoogle(
        expectedGeneration: attempt,
      );

      attempt = _authService.sessionGeneration;
      if (userCredential?.user != null &&
          _authService.currentUser?.uid == userCredential?.user?.uid &&
          _authService.isCurrentAttempt(attempt) &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Google 登入成功'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on SessionOperationCancelled {
      return;
    } catch (e) {
      if (!_authService.isCurrentAttempt(attempt)) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  // Apple 登入
  Future<void> _signInWithApple() async {
    var attempt = _authService.sessionGeneration;
    setState(() => _isAppleLoading = true);

    try {
      final userCredential = await _authService.signInWithApple(
        expectedGeneration: attempt,
      );

      attempt = _authService.sessionGeneration;
      if (userCredential?.user != null &&
          _authService.currentUser?.uid == userCredential?.user?.uid &&
          _authService.isCurrentAttempt(attempt) &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Apple 登入成功'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on SessionOperationCancelled {
      return;
    } catch (e) {
      if (!_authService.isCurrentAttempt(attempt)) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAppleLoading = false);
    }
  }

  // 顯示忘記密碼對話框
  void _showForgotPasswordDialog() {
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lock_reset,
                  color: _primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                '重設密碼',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '請輸入您的註冊信箱，我們將發送密碼重設連結給您。',
                style: TextStyle(color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: emailController,
                decoration: InputDecoration(
                  labelText: '電子郵件',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.email, color: _primaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _primaryColor,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: const Text('取消', style: TextStyle(fontSize: 16)),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = emailController.text.trim();
                if (email.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('請輸入電子郵件'),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                  return;
                }

                try {
                  await _authService.sendPasswordResetEmail(email);
                  Navigator.of(dialogContext).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('密碼重設郵件已發送，請檢查您的信箱'),
                        backgroundColor: _accentColor,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 2,
              ),
              child: const Text(
                '發送',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    String? Function(String?)? validator,
    required void Function(String?) onSaved,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          prefixIcon: Icon(icon, color: _primaryColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16.0,
            horizontal: 16.0,
          ),
          fillColor: Colors.white,
          filled: true,
        ),
        keyboardType: keyboardType,
        obscureText: isPassword,
        enabled: !_isLoading,
        validator: validator,
        onSaved: onSaved,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: <Widget>[
          _buildTextField(
            label: '電子郵件',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
            onSaved: (value) => _email = value!,
          ),

          _buildTextField(
            label: '密碼',
            icon: Icons.lock_rounded,
            isPassword: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '請輸入密碼';
              }
              return null;
            },
            onSaved: (value) => _password = value!,
          ),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading ? null : _showForgotPasswordDialog,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Text(
                '忘記密碼？',
                style: TextStyle(
                  color: _primaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // 帳號鎖定警告
          if (_isAccountLocked && _remainingLockoutSeconds > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_clock, color: Colors.red.shade700, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '帳號已被暫時鎖定',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                        Text(
                          '請等待 ${_loginSecurityService.formatRemainingTime(_remainingLockoutSeconds)}',
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: _isAccountLocked
                  ? LinearGradient(
                      colors: [Colors.grey.shade400, Colors.grey.shade500],
                    )
                  : const LinearGradient(
                      colors: [_primaryColor, Color(0xFF3A7BC8)],
                    ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: _isAccountLocked
                  ? null
                  : [
                      BoxShadow(
                        color: _primaryColor.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: ElevatedButton(
              onPressed: (_isLoading || _isAccountLocked) ? null : _submitLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : const Text(
                      '登入',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),

          // ==================== 社交登入區塊 ====================
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '或使用其他方式登入',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300)),
            ],
          ),
          const SizedBox(height: 20),

          // Google 登入按鈕
          _buildSocialLoginButton(
            onPressed: _isGoogleLoading ? null : _signInWithGoogle,
            isLoading: _isGoogleLoading,
            icon: _buildGoogleIcon(),
            label: '使用 Google 帳號登入',
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            borderColor: Colors.grey.shade300,
          ),

          const SizedBox(height: 12),

          // Apple 登入按鈕（僅 iOS 顯示）
          if (_isAppleAvailable)
            _buildSocialLoginButton(
              onPressed: _isAppleLoading ? null : _signInWithApple,
              isLoading: _isAppleLoading,
              icon: const Icon(Icons.apple, size: 24, color: Colors.white),
              label: '使用 Apple 帳號登入',
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              borderColor: Colors.black,
            ),
        ],
      ),
    );
  }

  // 社交登入按鈕建構器
  Widget _buildSocialLoginButton({
    required VoidCallback? onPressed,
    required bool isLoading,
    required Widget icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required Color borderColor,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          side: BorderSide(color: borderColor, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: foregroundColor,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: foregroundColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Google 圖示
  Widget _buildGoogleIcon() {
    return Image.asset('assets/Google_icon.png', width: 22, height: 22);
  }
}
