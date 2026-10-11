import 'services/app_unlock_runtime.dart';
import 'widgets/app_unlock_gate.dart';
import 'widgets/logout_status_boundary.dart';
import 'widgets/account_boundary.dart';
// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/session_timeout_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_dimensions.dart';
import 'theme/app_text_styles.dart';
// 導入所有螢幕
import 'screens/dashboard_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/login_screen.dart';
import 'screens/medication_screen.dart';
import 'screens/records_screen.dart';
import 'screens/health_record_screen.dart';
import 'screens/record_list_screen.dart';
import 'screens/medical_reports_screen.dart';
import 'screens/share_report_screen.dart';
import 'screens/diet_screen.dart';
// 導入 ProfileWrapper
import 'screens/profile_wrapper.dart';

void main() async {
  // 初始化 Flutter 綁定
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 初始化 Firebase
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    debugPrint('✅ Firebase 初始化成功');
  } catch (e) {
    debugPrint('❌ Firebase 初始化失敗: $e');
  }

  try {
    // 初始化通知服務
    await NotificationService().initialize();
    debugPrint('✅ 通知服務初始化成功');
  } catch (e) {
    debugPrint('❌ 通知服務初始化失敗: $e');
  }

  AppUnlockRuntime.instance.start();
  runApp(const HealthManagementApp());
}

class HealthManagementApp extends StatelessWidget {
  const HealthManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppUnlockLifecycle(
      controller: AppUnlockRuntime.instance.controller,
      child: AccountBoundary(
      userIds: FirebaseAuth.instance.authStateChanges().map((user) => user?.uid),
      initialUid: FirebaseAuth.instance.currentUser?.uid,
      child: MaterialApp(
      title: 'HealthPal',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        textTheme: GoogleFonts.notoSansTcTextTheme(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.primary,
          surface: AppColors.surface,
          error: AppColors.error,
        ),
        // 卡片主題（2025 無邊框 + 柔和陰影）
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: AppDimensions.cardBorderRadius,
          ),
          margin: const EdgeInsets.only(bottom: AppDimensions.cardGap),
        ),
        // 輸入框主題
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingMd,
            vertical: AppDimensions.spacingSm,
          ),
          border: OutlineInputBorder(
            borderRadius: AppDimensions.inputBorderRadius,
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppDimensions.inputBorderRadius,
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppDimensions.inputBorderRadius,
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: AppDimensions.inputBorderRadius,
            borderSide: const BorderSide(color: AppColors.error),
          ),
          floatingLabelStyle: AppTextStyles.label.copyWith(color: AppColors.primary),
          hintStyle: AppTextStyles.body.copyWith(color: AppColors.textHint),
        ),
        // 文字選取主題
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppColors.primary,
          selectionColor: AppColors.primary.withValues(alpha: 0.3),
          selectionHandleColor: AppColors.primary,
        ),
        // 底部導航列主題
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          selectedLabelStyle: AppTextStyles.label.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
          unselectedLabelStyle: AppTextStyles.label,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.surface,
          elevation: 8,
        ),
        // 按鈕主題
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingLg,
              vertical: AppDimensions.spacingSm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppDimensions.buttonBorderRadius,
            ),
            textStyle: AppTextStyles.buttonPrimary,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingLg,
              vertical: AppDimensions.spacingSm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppDimensions.buttonBorderRadius,
            ),
            textStyle: AppTextStyles.buttonSecondary,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: AppTextStyles.buttonSecondary,
          ),
        ),
        // Dialog 主題
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppDimensions.dialogBorderRadius,
          ),
          titleTextStyle: AppTextStyles.title,
          contentTextStyle: AppTextStyles.body,
        ),
        // Checkbox 主題
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.border;
          }),
          checkColor: WidgetStateProperty.all(Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        // Radio 主題
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.border;
          }),
        ),
        // Switch 主題
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.disabled;
          }),
          trackColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary.withValues(alpha: 0.5);
            }
            return AppColors.border;
          }),
        ),
        // AppBar 主題
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: AppTextStyles.title.copyWith(fontSize: 22),
          iconTheme: const IconThemeData(
            color: AppColors.textPrimary,
            size: AppDimensions.iconNav,
          ),
        ),
        // Divider 主題
        dividerTheme: const DividerThemeData(
          color: AppColors.border,
          thickness: 1,
          space: 1,
        ),
      ),
      supportedLocales: const [Locale('en', ''), Locale('zh', 'TW')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => LogoutStatusBoundary(
        child: AppUnlockGate(
          controller: AppUnlockRuntime.instance.controller,
          protectedNavigation: ActivityTracker(child: child!),
          loginBuilder: (_) => const LoginScreen(),
        ),
      ),
      initialRoute: '/',
      debugShowCheckedModeBanner: false,
      routes: {
        '/': (context) => const AuthScreen(),
        '/main': (context) => const MainScreen(),
        '/login': (context) => const LoginScreen(),
        '/records': (context) => const RecordListScreen(),
        '/medical-reports': (context) => const MedicalReportsScreen(),
        '/health-records': (context) => const HealthRecordScreen(),
        '/share-report': (context) => const ShareReportScreen(),
      },
    )));
  }
}

/// 認證檢查畫面
/// 根據用戶登入狀態顯示登入畫面或主畫面
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 正在檢查登入狀態
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // 已登入，顯示主畫面
        if (snapshot.hasData && snapshot.data != null) {
          return MainScreen(key: ValueKey(snapshot.data!.uid));
        }

        // 未登入，顯示登入畫面
        return const LoginScreen();
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final _sessionTimeoutService = SessionTimeoutService();

  final List<Widget> _screens = [
    const DashboardScreen(),
    const RecordsScreen(),
    const MedicationScreen(),
    const InsightsScreen(),
    const DietScreen(),
    const ProfileWrapper(),
  ];

  void _onItemTapped(int index) {
    _sessionTimeoutService.recordActivity(); // 記錄用戶活動
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 使用 GestureDetector 追蹤所有用戶互動
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _sessionTimeoutService.recordActivity(),
      onPanDown: (_) => _sessionTimeoutService.recordActivity(),
      onScaleStart: (_) => _sessionTimeoutService.recordActivity(),
      child: Scaffold(
        body: _screens[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: '總覽'),
            BottomNavigationBarItem(icon: Icon(Icons.article), label: '紀錄'),
            BottomNavigationBarItem(icon: Icon(Icons.medication), label: '用藥'),
            BottomNavigationBarItem(icon: Icon(Icons.insights), label: '分析'),
            BottomNavigationBarItem(icon: Icon(Icons.restaurant), label: '飲食'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
          ],
        ),
      ),
    );
  }
}