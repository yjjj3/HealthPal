import '../models/medication_model.dart';
import 'medication_reminder_planner.dart';
import '../utils/medication_schedule.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/initialization_gate.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

// 判斷是否為 Web 平台
bool get isWeb => identical(0, 0.0);

// 背景訊息處理器（必須是頂層函數）
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 背景收到通知: ${message.notification?.title}');
}

class NotificationService with WidgetsBindingObserver {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final InitializationGate _initialization = InitializationGate();
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSubscription;
  Completer<void>? _settingsReady;
  int _accountGeneration = 0;
  Future<void> _accountReady = Future.value();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _medicineSubscription;
  List<medicine>? _reminderMedications;
  Timer? _reminderTimer;
  final ValueNotifier<String> medicationReminderStatus = ValueNotifier('提醒排程尚未載入');
  late final MedicationReminderScheduler _medicationScheduler = MedicationReminderScheduler(
    pending: () async => (await _localNotifications.pendingNotificationRequests())
        .map((r) => PendingReminder(r.id, r.payload)).toList(),
    cancel: (id) => _localNotifications.cancel(id),
    schedule: (id, request) => request.repeat == 0
      ? scheduleMedicationReminder(id: id, medicineName: request.medication.name,
          dosage: request.medication.dosage, scheduledTime: request.at,
          medicationId: request.medication.medicine_id!, payload: request.payload)
      : scheduleMissedDoseReminder(id: id - request.repeat, medicationName: request.medication.name,
          dosage: request.medication.dosage, scheduledTime: request.at,
          medicationId: request.medication.medicine_id!, reminderCount: request.repeat, payload: request.payload),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _rebuildMedicationReminders();
  }

  Future<void> _rebuildMedicationReminders() async {
    if (isWeb) { medicationReminderStatus.value = 'Web 不支援本機用藥排程'; return; }
    final medications = _reminderMedications;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final generation = _accountGeneration;
    if (medications == null || uid == null) return;
    bool valid() => generation == _accountGeneration && uid == FirebaseAuth.instance.currentUser?.uid;
    try {
      final enabled = isNotificationEnabled('health');
      final plan = await _medicationScheduler.replace(medications, now: DateTime.now(),
        isCurrent: valid, enabled: enabled,
        missedEnabled: _missedDoseSettings['missedDoseEnabled'] == true,
        missedInterval: _missedDoseSettings['missedDoseInterval'] as int? ?? 30,
        missedCount: _missedDoseSettings['missedDoseMaxReminders'] as int? ?? 2);
      if (!valid() || plan == null) return;
      final last = plan.lastScheduled;
      final omittedAt = plan.firstOmitted;
      final missing = omittedAt == null ? '' : '最早未排 ${omittedAt.month}/${omittedAt.day} ${omittedAt.hour}:${omittedAt.minute.toString().padLeft(2, '0')}；可減少漏吃提醒次數以增加涵蓋日期。';
      final end = last == null ? '沒有待發提醒' : '最晚已排至 ${last.month}/${last.day} ${last.hour}:${last.minute.toString().padLeft(2, '0')}';
      medicationReminderStatus.value = !enabled ? '健康提醒已關閉' :
          '本機已排 ${plan.requests.length} 則，$end。' +
          (plan.omitted > 0 ? '容量不足，${plan.omitted} 則尚未排入。$missing' : '') +
          (plan.issues.isNotEmpty ? '部分療程未排程：${plan.issues.join('；')}。' : '') +
          '最多預排30天；容量與其他通知共用，系統可能延後送達。請在已排期限前開啟 App 補排，關閉 App 後無法自動延長。';
    } catch (error) {
      if (valid()) medicationReminderStatus.value = '提醒排程未完成，請檢查通知權限並重新開啟 App；目前無法保證提醒完整。';
      debugPrint('用藥排程未完成: ${error.runtimeType}');
    }
  }

  // 通知頻道 ID
  static const String _medicationChannelId = 'medication_reminders';
  static const String _healthChannelId = 'health_reminders';
  static const String _activityChannelId = 'activity_alerts';
  static const String _familyChannelId = 'family_alerts';
  static const String _generalChannelId = 'general_notifications';

  // 用戶通知設定快取
  Map<String, bool> _notificationSettings = {
    'all': true,
    'activity': true,
    'health': true,
    'family': false,
    'updates': true,
  };

  // 錯過劑量提醒設定快取
  Map<String, dynamic> _missedDoseSettings = {
    'missedDoseEnabled': true,
    'missedDoseInterval': 30,
    'missedDoseMaxReminders': 2,
  };

  // ============================================================
  // 初始化
  // ============================================================
  Future<void> initialize() => _initialization.run(() async {
    if (isWeb) await _initializeForWeb();
    else await _initializeForMobile();
    WidgetsBinding.instance.addObserver(this);
    _reminderTimer ??= Timer.periodic(const Duration(hours: 1), (_) => _rebuildMedicationReminders());
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      final generation = ++_accountGeneration;
      _medicationScheduler.invalidate();
      _medicineSubscription?.cancel();
      _medicineSubscription = null;
      _reminderMedications = null;
      medicationReminderStatus.value = '提醒排程尚未載入';
      if (_settingsReady?.isCompleted == false) _settingsReady!.complete();
      _settingsSubscription?.cancel();
      _settingsSubscription = null;
      _notificationSettings = {'all': true, 'activity': true, 'health': true, 'family': false, 'updates': true};
      _missedDoseSettings = {'missedDoseEnabled': true, 'missedDoseInterval': 30, 'missedDoseMaxReminders': 2};
      _accountReady = _accountReady.then((_) => _bindNotificationAccount(user, generation)).catchError((Object error) {
        _notificationSettings['all'] = false;
        debugPrint('通知帳號同步失敗: $error');
      });
    });
  });

  Future<void> _bindNotificationAccount(User? user, int generation) async {
    if (generation != _accountGeneration) return;
    // Drain an in-flight native call before clearing a previous account.
    await _medicationScheduler.idle;
    if (generation != _accountGeneration) return;
    // Preserve the same account's scheduled reminders across app restarts.
    final prefs = await SharedPreferences.getInstance();
    final previousUid = prefs.getString('notification_account_uid');
    if (!isWeb && (user == null || previousUid != user.uid)) await _localNotifications.cancelAll();
    if (generation != _accountGeneration) return;
    if (user == null) { await prefs.remove('notification_account_uid'); return; }
    await prefs.setString('notification_account_uid', user.uid);
    if (generation != _accountGeneration) return;
    final settingsReady = Completer<void>();
    _settingsReady = settingsReady;
    _settingsSubscription = FirebaseFirestore.instance.collection('users').doc(user.uid)
      .collection('settings').doc('notifications').snapshots().listen((snapshot) {
        if (generation == _accountGeneration) {
          _applyNotificationSettings(snapshot.data());
          _rebuildMedicationReminders();
        }
        if (!settingsReady.isCompleted) settingsReady.complete();
      }, onError: (Object error) {
        if (generation == _accountGeneration) { _notificationSettings['all'] = false; _rebuildMedicationReminders(); }
        if (!settingsReady.isCompleted) settingsReady.complete();
        debugPrint('通知設定監聽失敗: $error');
      }, onDone: () { if (!settingsReady.isCompleted) settingsReady.complete(); });
    await settingsReady.future;
    if (generation != _accountGeneration) return;
    if (!isWeb) {
      _medicineSubscription = FirebaseFirestore.instance.collection('users').doc(user.uid)
          .collection('medicine').orderBy('name').snapshots().listen((snapshot) {
        if (generation != _accountGeneration) return;
        try {
          _reminderMedications = snapshot.docs.map(medicine.fromFirestore).toList();
          _rebuildMedicationReminders();
        } catch (_) {
          _reminderMedications = null;
          _medicationScheduler.invalidate();
          medicationReminderStatus.value = '藥品資料無法完整解析，舊提醒可能仍存在，請修正藥品資料。';
        }
      }, onError: (Object _) {
        if (generation == _accountGeneration) medicationReminderStatus.value = '用藥同步失敗，可能仍使用舊排程，請重新開啟 App 同步。';
      });
    }
    await _getAndSaveFCMToken();
  }

  // Web 平台初始化
  Future<void> _initializeForWeb() async {
    try {
      // 初始化時區
      tz.initializeTimeZones();

      // 設定背景訊息處理器
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 請求通知權限（Web 版）
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('🌐 Web FCM 權限狀態: ${settings.authorizationStatus}');

      // 設定前景訊息監聽
      _setupForegroundMessageHandler();

      // 取得並儲存 FCM Token
      await _getAndSaveFCMToken();

      // 載入用戶通知設定
      await loadUserNotificationSettings();

      debugPrint('✅ Web 版 NotificationService 初始化完成');
    } catch (e) {
      debugPrint('❌ Web 初始化失敗: $e');
      rethrow;
    }
  }

  // 移動設備初始化
  Future<void> _initializeForMobile() async {
    try {
      // 初始化時區
      tz.initializeTimeZones();

      // 設定背景訊息處理器
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 請求通知權限
      await _requestPermissions();

      // 初始化本地通知
      await _initializeLocalNotifications();

      // 設定前景訊息監聽
      _setupForegroundMessageHandler();

      // 取得並儲存 FCM Token
      await _getAndSaveFCMToken();

      // 載入用戶通知設定
      await loadUserNotificationSettings();

      debugPrint('✅ 移動版 NotificationService 初始化完成');
    } catch (e) {
      debugPrint('❌ 移動版初始化失敗: $e');
      rethrow;
    }
  }

  // ============================================================
  // 請求通知權限（僅移動設備）
  // ============================================================
  Future<void> _requestPermissions() async {
    if (isWeb) return;

    // Firebase Messaging 權限
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('📱 FCM 權限狀態: ${settings.authorizationStatus}');

    // iOS 本地通知權限
    if (Platform.isIOS) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    // Android 13+ 需要額外請求權限
    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }
  }

  // ============================================================
  // 初始化本地通知（僅移動設備）
  // ============================================================
  Future<void> _initializeLocalNotifications() async {
    if (isWeb) return;

    debugPrint('📱 開始初始化本地通知...');

    // Android 設定
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS 設定
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [],
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    final initialized = await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    debugPrint('📱 本地通知初始化結果: $initialized');

    // 建立 Android 通知頻道
    await _createNotificationChannels();

    // 檢查 iOS 通知權限狀態
    if (Platform.isIOS) {
      final iosPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint('📱 iOS 本地通知權限: $granted');
      }
    }
  }

  // ============================================================
  // 建立 Android 通知頻道（僅移動設備）
  // ============================================================
  Future<void> _createNotificationChannels() async {
    if (isWeb) return;

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    // 用藥提醒頻道
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _medicationChannelId,
        '用藥提醒',
        description: '服藥時間提醒通知',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    // 健康提醒頻道
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _healthChannelId,
        '健康提醒',
        description: '血壓、血糖量測提醒',
        importance: Importance.high,
        playSound: true,
      ),
    );

    // 活動提醒頻道
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _activityChannelId,
        '活動提醒',
        description: '運動、步數提醒',
        importance: Importance.defaultImportance,
      ),
    );

    // 家人提醒頻道
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _familyChannelId,
        '家人通知',
        description: '家人健康狀況通知',
        importance: Importance.high,
      ),
    );

    // 一般通知頻道
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _generalChannelId,
        '一般通知',
        description: '應用程式更新和其他通知',
        importance: Importance.defaultImportance,
      ),
    );
  }

  // ============================================================
  // 處理通知點擊
  // ============================================================
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('📲 用戶點擊通知: ${response.payload}');
  }

  // ============================================================
  // 設定前景訊息處理
  // ============================================================
  void _setupForegroundMessageHandler() {
    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔔 前景收到通知: ${message.notification?.title}');

      final notification = message.notification;
      if (notification != null) {
        // 在前景時顯示本地通知（僅移動設備）
        if (!isWeb) {
          showLocalNotification(
            title: notification.title ?? '新通知',
            body: notification.body ?? '',
            payload: message.data.toString(),
          );
        } else {
          // Web 平台可以在控制台顯示或使用瀏覽器通知
          debugPrint('🌐 Web 通知: ${notification.title} - ${notification.body}');
        }
      }
    });
  }

  // ============================================================
  // 取得並儲存 FCM Token
  // ============================================================
  Future<void> _getAndSaveFCMToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _tokenSubscription ??= _fcm.onTokenRefresh.listen((newToken) {
      _saveFCMTokenToFirestore(newToken);
    }, onError: (Object error) { debugPrint('FCM Token 監聽失敗: $error'); });
    try {
      final token = await _fcm.getToken();
      if (token != null && uid != null && uid == FirebaseAuth.instance.currentUser?.uid) {
        await _saveFCMTokenToFirestore(token, expectedUid: uid);
      }
    } catch (e) {
      debugPrint('❌ 取得 FCM Token 失敗: $e');
    }
  }

  Future<void> _saveFCMTokenToFirestore(String token, {String? expectedUid}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (expectedUid != null && expectedUid != user.uid)) return;

    try {
      String platform;
      if (isWeb) {
        platform = 'Web';
      } else if (!isWeb && Platform.isIOS) {
        platform = 'iOS';
      } else if (!isWeb && Platform.isAndroid) {
        platform = 'Android';
      } else {
        platform = 'Unknown';
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'platform': platform,
      }, SetOptions(merge: true));
      
      debugPrint('✅ FCM Token 已儲存到 Firestore');
    } catch (e) {
      debugPrint('❌ 儲存 FCM Token 失敗: $e');
    }
  }

  // ============================================================
  // 載入用戶通知設定
  // ============================================================
  void _applyNotificationSettings(Map<String, dynamic>? data) {
    data ??= {};
    _notificationSettings = {
      'all': data['all'] ?? true, 'activity': data['activity'] ?? true,
      'health': data['health'] ?? true, 'family': data['family'] ?? false,
      'updates': data['updates'] ?? true,
    };
    _missedDoseSettings = {
      'missedDoseEnabled': data['missedDoseEnabled'] ?? true,
      'missedDoseInterval': data['missedDoseInterval'] ?? 30,
      'missedDoseMaxReminders': data['missedDoseMaxReminders'] ?? 2,
    };
  }

  Future<void> loadUserNotificationSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { _applyNotificationSettings(null); return; }
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid)
      .collection('settings').doc('notifications').get();
    if (FirebaseAuth.instance.currentUser?.uid == uid) _applyNotificationSettings(doc.data());
  }

  // ============================================================
  // 檢查特定類型的通知是否啟用
  // ============================================================
  bool isNotificationEnabled(String type) {
    if (!_notificationSettings['all']!) return false;
    return _notificationSettings[type] ?? true;
  }

  // ============================================================
  // 獲取錯過劑量提醒設定
  // ============================================================
  Map<String, dynamic> getMissedDoseSettings() {
    return _missedDoseSettings;
  }

  // ============================================================
  // 取消錯過劑量提醒 - 這是缺失的方法！
  // ============================================================
  Future<void> cancelMissedDoseReminders(int baseId) async {
    debugPrint('🗑️ 嘗試取消漏吃提醒，基礎 ID: $baseId');

    // Web 平台不支援本地通知，直接返回
    if (isWeb) {
      debugPrint('🌐 Web 平台跳過取消漏吃提醒操作');
      return;
    }

    try {
      // 取消所有相關的漏吃提醒（使用 ID 範圍）
      // 「持續提醒」模式最多 50 次
      final cancelCount = 50;

      for (int i = 1; i <= cancelCount; i++) {
        await _localNotifications.cancel(baseId + i);
      }
      debugPrint('✅ 已取消 $cancelCount 個漏吃提醒，基礎 ID: $baseId');
    } catch (e) {
      debugPrint('❌ 取消漏吃提醒失敗: $e');
    }
  }

  // ============================================================
  // 顯示本地通知（僅移動設備）
  // ============================================================
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    String channelId = _generalChannelId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final generation = _accountGeneration;
    await _accountReady;
    if (uid == null || uid != FirebaseAuth.instance.currentUser?.uid || generation != _accountGeneration) return;
    if (isWeb) {
      debugPrint('🌐 Web 平台不支援本地通知: $title - $body');
      return;
    }

    // 檢查總開關
    if (!_notificationSettings['all']!) return;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      _getChannelName(channelId),
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
    
    debugPrint('📱 本地通知已發送: $title');
  }

  String _getChannelName(String channelId) {
    switch (channelId) {
      case _medicationChannelId:
        return '用藥提醒';
      case _healthChannelId:
        return '健康提醒';
      case _activityChannelId:
        return '活動提醒';
      case _familyChannelId:
        return '家人通知';
      default:
        return '一般通知';
    }
  }

  // ============================================================
  // 排程用藥提醒（僅移動設備）
  // ============================================================
  Future<void> scheduleMedicationReminder({
    required int id,
    required String medicineName,
    required String dosage,
    required DateTime scheduledTime,
    required String medicationId,
    String? payload,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final generation = _accountGeneration;
    await _accountReady;
    if (uid == null || uid != FirebaseAuth.instance.currentUser?.uid || generation != _accountGeneration) return;
    if (isWeb) {
      debugPrint('🌐 Web 平台不支援排程通知');
      return;
    }

    if (!isNotificationEnabled('health')) {
      debugPrint('⚠️ 健康提醒已關閉，跳過排程');
      return;
    }

    final androidDetails = const AndroidNotificationDetails(
      _medicationChannelId,
      '用藥提醒',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    if (tzScheduledTime.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint('⚠️ 排程時間已過，跳過: $scheduledTime');
      return;
    }

    await _localNotifications.zonedSchedule(
      id,
      '用藥提醒',
      '該服用 $medicineName $dosage 了',
      tzScheduledTime,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload ?? 'medication|$medicationId',
    );

    debugPrint('✅ 已排程用藥提醒: $medicineName 於 $scheduledTime');
  }

  // ============================================================
  // 排程錯過劑量提醒（僅移動設備）
  // ============================================================
  Future<void> scheduleMissedDoseReminder({
    required int id,
    required String medicationName,
    required String dosage,
    required DateTime scheduledTime,
    required String medicationId,
    int reminderCount = 1,
    String? payload,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final generation = _accountGeneration;
    await _accountReady;
    if (uid == null || uid != FirebaseAuth.instance.currentUser?.uid || generation != _accountGeneration) return;
    if (isWeb) {
      debugPrint('🌐 Web 平台不支援排程通知');
      return;
    }

    // 檢查漏吃提醒是否啟用
    if (!isNotificationEnabled('health') || !_missedDoseSettings['missedDoseEnabled']) {
      debugPrint('⚠️ 漏吃提醒已關閉，跳過排程');
      return;
    }

    // 檢查是否超過最大提醒次數
    final maxReminders = _missedDoseSettings['missedDoseMaxReminders'] as int;
    if (maxReminders > 0 && reminderCount > maxReminders) {
      debugPrint('⚠️ 已達最大提醒次數 ($maxReminders)，不再提醒');
      return;
    }

    final androidDetails = const AndroidNotificationDetails(
      _medicationChannelId,
      '用藥提醒',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    // 每個應服時段保留 50 個漏吃提醒 ID
    final notificationId = id + reminderCount;

    await _localNotifications.zonedSchedule(
      notificationId,
      '漏吃提醒 #$reminderCount',
      '$medicationName ($dosage) 尚未服用，請記得服藥',
      tzScheduledTime,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload ?? 'missed_dose|$medicationId|$reminderCount',
    );

    debugPrint('✅ 已排程漏吃提醒 #$reminderCount: $medicationName, ID: $notificationId');
  }

  // ============================================================
  // 排程健康提醒（僅移動設備）
  // ============================================================
  Future<void> scheduleHealthReminder({
    required int id,
    required String type,
    required DateTime scheduledTime,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final generation = _accountGeneration;
    await _accountReady;
    if (uid == null || uid != FirebaseAuth.instance.currentUser?.uid || generation != _accountGeneration) return;
    if (isWeb) {
      debugPrint('🌐 Web 平台不支援排程通知');
      return;
    }

    if (!isNotificationEnabled('health')) {
      debugPrint('⚠️ 健康提醒已關閉，跳過排程');
      return;
    }

    String title = '';
    String body = '';

    if (type == 'blood_pressure') {
      title = '💖 血壓量測提醒';
      body = '該量測今天的血壓囉！';
    } else if (type == 'blood_glucose') {
      title = '🩸 血糖量測提醒';
      body = '該量測今天的血糖囉！';
    }

    final androidDetails = const AndroidNotificationDetails(
      _healthChannelId,
      '健康提醒',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    await _localNotifications.zonedSchedule(
      id,
      title,
      body,
      tzScheduledTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    _rebuildMedicationReminders(); // Reserve capacity for this non-medication request.
    debugPrint('✅ 已排程健康提醒: $title, 時間: $scheduledTime');
  }

  // ============================================================
  // 測試通知（所有平台）
  // ============================================================
  Future<void> sendTestNotification() async {
    debugPrint('🔔 準備發送測試通知...');
    debugPrint('🔔 當前平台: ${isWeb ? 'Web' : 'Mobile'}');

    if (isWeb) {
      // Web 平台使用瀏覽器通知或控制台輸出
      debugPrint('🎉 Web 測試通知: 通知功能測試成功!');
      return;
    }

    // 移動設備發送本地通知
    final androidDetails = const AndroidNotificationDetails(
      _generalChannelId,
      '一般通知',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    try {
      await _localNotifications.show(
        notificationId,
        '測試通知 🎉',
        '通知功能運作正常！時間: ${DateTime.now().toString().substring(11, 19)}',
        details,
        payload: 'test_notification',
      );
      debugPrint('✅ 測試通知已發送成功！');
    } catch (e) {
      debugPrint('❌ 發送測試通知失敗: $e');
    }
  }

  // ============================================================
  // 其他方法
  // ============================================================
  
  /// Cancel by persisted payload, including old IDs and every missed-dose notification.
  Future<void> cancelMedicationReminders(String medicationId, {String? legacyName}) async {
    if (isWeb) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final generation = _accountGeneration;
    final requests = await _localNotifications.pendingNotificationRequests();
    for (final request in requests) {
      if (uid != FirebaseAuth.instance.currentUser?.uid || generation != _accountGeneration) return;
      if (belongsToMedication(request.payload, medicationId, legacyName: legacyName)) {
        await _localNotifications.cancel(request.id);
      }
    }
  }

  Future<void> cancelNotification(int id) async {
    if (isWeb) return;
    await _localNotifications.cancel(id);
    debugPrint('🗑️ 已取消通知 ID: $id');
  }

  Future<void> cancelAllNotifications() async {
    if (isWeb) return;
    await _localNotifications.cancelAll();
    debugPrint('🗑️ 已取消所有通知');
  }

  Future<void> sendFamilyAlert({
    required String familyMemberName,
    required String alertType,
    required String message,
  }) async {
    if (!isNotificationEnabled('family')) return;
    
    await showLocalNotification(
      title: '家人健康通知 👨‍👩‍👧‍👦',
      body: '$familyMemberName: $message',
      channelId: _familyChannelId,
      payload: 'family_$alertType',
    );
  }

  Future<void> sendActivityReminder({
    required String title,
    required String body,
  }) async {
    if (!isNotificationEnabled('activity')) return;
    
    await showLocalNotification(
      title: title,
      body: body,
      channelId: _activityChannelId,
      payload: 'activity',
    );
  }
}