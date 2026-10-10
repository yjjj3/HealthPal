import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

/// 主畫面小工具服務
/// 負責更新 iOS/Android 小工具的健康數據
class HomeWidgetService {
  // TODO: 請將此 ID 改成你在 Xcode 設定的 App Group ID
  // 例如：group.com.yourbundleid.healthmanager
  static const String _appGroupId = 'group.com.yunju.healthmanager';
  static const String _iOSWidgetName = 'HealthWidget';
  static const String _androidWidgetName = 'HealthWidgetProvider';

  static final HomeWidgetService _instance = HomeWidgetService._internal();
  factory HomeWidgetService() => _instance;
  HomeWidgetService._internal();

  /// 初始化小工具服務
  Future<void> initialize() async {
    try {
      // 設定 App Group ID (iOS 需要)
      await HomeWidget.setAppGroupId(_appGroupId);

      // 註冊互動回調
      HomeWidget.registerInteractivityCallback(backgroundCallback);

      debugPrint('✅ HomeWidgetService 初始化成功');
    } catch (e) {
      debugPrint('❌ HomeWidgetService 初始化失敗: $e');
    }
  }

  /// 背景更新回調
  @pragma('vm:entry-point')
  static Future<void> backgroundCallback(Uri? uri) async {
    if (uri?.host == 'updateWidget') {
      await HomeWidgetService().updateWidget();
    }
  }

  /// 更新小工具數據
  Future<void> updateWidget() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('⚠️ 無法更新小工具：用戶未登入');
      return;
    }

    try {
      final healthData = await _getLatestHealthData(user.uid);

      // 儲存數據到小工具存儲
      await HomeWidget.saveWidgetData<int>(
        'bp_systolic',
        healthData['bpSystolic'] as int?,
      );
      await HomeWidget.saveWidgetData<int>(
        'bp_diastolic',
        healthData['bpDiastolic'] as int?,
      );
      await HomeWidget.saveWidgetData<int>(
        'glucose',
        healthData['glucose'] as int?,
      );
      await HomeWidget.saveWidgetData<int>(
        'heart_rate',
        healthData['heartRate'] as int?,
      );
      await HomeWidget.saveWidgetData<String>(
        'last_updated',
        DateFormat('MM/dd HH:mm').format(DateTime.now()),
      );
      await HomeWidget.saveWidgetData<String>(
        'bp_time',
        healthData['bpTime'] as String?,
      );
      await HomeWidget.saveWidgetData<String>(
        'glucose_time',
        healthData['glucoseTime'] as String?,
      );

      // 請求小工具更新
      await HomeWidget.updateWidget(
        iOSName: _iOSWidgetName,
        androidName: _androidWidgetName,
      );

      debugPrint('✅ 小工具數據已更新');
    } catch (e) {
      debugPrint('❌ 更新小工具失敗: $e');
    }
  }

  /// 獲取最新健康數據
  Future<Map<String, dynamic>> _getLatestHealthData(String uid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('health_records')
        .orderBy('record_time', descending: true)
        .limit(20)
        .get();

    int? bpSystolic;
    int? bpDiastolic;
    int? glucose;
    int? heartRate;
    String? bpTime;
    String? glucoseTime;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final category = data['category'] as String?;
      final recordTime = (data['record_time'] as Timestamp?)?.toDate();
      final timeStr = recordTime != null
          ? DateFormat('MM/dd HH:mm').format(recordTime)
          : null;

      if (category == '血壓' && bpSystolic == null) {
        // 解析血壓值
        final value = data['value'] as String?;
        if (value != null && value.contains('/')) {
          final parts = value.replaceAll(RegExp(r'[^\d/]'), '').split('/');
          if (parts.length >= 2) {
            bpSystolic = int.tryParse(parts[0]);
            bpDiastolic = int.tryParse(parts[1]);
            bpTime = timeStr;
          }
        }
        // 也嘗試從心率欄位獲取
        final hr = data['heart_rate'];
        if (hr != null && heartRate == null) {
          heartRate = hr is int ? hr : int.tryParse(hr.toString());
        }
      } else if (category == '血糖' && glucose == null) {
        final value = data['value'] as String?;
        if (value != null) {
          glucose = int.tryParse(value.replaceAll(RegExp(r'[^\d]'), ''));
          glucoseTime = timeStr;
        }
      } else if (category == '心率' && heartRate == null) {
        final value = data['value'] as String?;
        if (value != null) {
          heartRate = int.tryParse(value.replaceAll(RegExp(r'[^\d]'), ''));
        }
      }

      // 如果所有數據都已獲取，提前結束
      if (bpSystolic != null && glucose != null && heartRate != null) {
        break;
      }
    }

    return {
      'bpSystolic': bpSystolic,
      'bpDiastolic': bpDiastolic,
      'glucose': glucose,
      'heartRate': heartRate,
      'bpTime': bpTime,
      'glucoseTime': glucoseTime,
    };
  }

  /// 清除小工具數據（用戶登出時呼叫）
  Future<void> clearWidget() async {
    try {
      await HomeWidget.saveWidgetData<int>('bp_systolic', null);
      await HomeWidget.saveWidgetData<int>('bp_diastolic', null);
      await HomeWidget.saveWidgetData<int>('glucose', null);
      await HomeWidget.saveWidgetData<int>('heart_rate', null);
      await HomeWidget.saveWidgetData<String>('last_updated', null);
      await HomeWidget.saveWidgetData<String>('bp_time', null);
      await HomeWidget.saveWidgetData<String>('glucose_time', null);

      await HomeWidget.updateWidget(
        iOSName: _iOSWidgetName,
        androidName: _androidWidgetName,
      );

      debugPrint('✅ 小工具數據已清除');
    } catch (e) {
      debugPrint('❌ 清除小工具失敗: $e');
    }
  }
}
