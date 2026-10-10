import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import 'notification_service.dart';

/// 健康警示結果
class HealthAlertResult {
  final bool isOutOfRange;
  final HealthStatus status;
  final String category;
  final String message;
  final String recommendation;
  final bool isCritical;
  final dynamic value;

  HealthAlertResult({
    required this.isOutOfRange,
    required this.status,
    required this.category,
    required this.message,
    required this.recommendation,
    required this.isCritical,
    required this.value,
  });
}

/// 健康警示服務
/// 當記錄的健康數值超出正常範圍時，顯示警示對話框並可選擇推送通知
class HealthAlertService {
  static final HealthAlertService _instance = HealthAlertService._internal();
  factory HealthAlertService() => _instance;
  HealthAlertService._internal();

  // 警示設定快取
  Map<String, bool> _alertSettings = {
    'bloodPressureAlert': true,
    'bloodGlucoseAlert': true,
    'heartRateAlert': true,
  };

  // ============================================================
  // 閾值定義
  // ============================================================
  static const Map<String, Map<String, int>> bloodPressureThresholds = {
    'systolic': {
      'veryLow': 90,
      'low': 90,
      'normalMax': 120,
      'high': 140,
      'veryHigh': 180,
    },
    'diastolic': {
      'veryLow': 60,
      'low': 60,
      'normalMax': 80,
      'high': 90,
      'veryHigh': 120,
    },
  };

  static const Map<String, Map<String, int>> bloodGlucoseThresholds = {
    'fasting': {
      'veryLow': 54,
      'low': 70,
      'normalMax': 100,
      'high': 125,
      'veryHigh': 180,
    },
    'postMeal': {
      'veryLow': 54,
      'low': 70,
      'normalMax': 140,
      'high': 180,
      'veryHigh': 250,
    },
  };

  static const Map<String, int> heartRateThresholds = {
    'veryLow': 40,
    'low': 60,
    'normalMax': 100,
    'high': 120,
    'veryHigh': 150,
  };

  // ============================================================
  // 初始化 - 載入用戶警示設定
  // ============================================================
  Future<void> initialize() async {
    await loadAlertSettings();
  }

  Future<void> loadAlertSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('health_alerts')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _alertSettings = {
          'bloodPressureAlert': data['bloodPressureAlert'] ?? true,
          'bloodGlucoseAlert': data['bloodGlucoseAlert'] ?? true,
          'heartRateAlert': data['heartRateAlert'] ?? true,
        };
        debugPrint('✅ 健康警示設定已載入: $_alertSettings');
      }
    } catch (e) {
      debugPrint('❌ 載入警示設定失敗: $e');
    }
  }

  Future<void> saveAlertSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('health_alerts')
          .set(_alertSettings, SetOptions(merge: true));
      debugPrint('✅ 健康警示設定已儲存');
    } catch (e) {
      debugPrint('❌ 儲存警示設定失敗: $e');
    }
  }

  bool isAlertEnabled(String type) {
    return _alertSettings[type] ?? true;
  }

  void setAlertEnabled(String type, bool enabled) {
    _alertSettings[type] = enabled;
    saveAlertSettings();
  }

  Map<String, bool> get alertSettings => Map.from(_alertSettings);

  // ============================================================
  // 檢查血壓值
  // ============================================================
  HealthAlertResult checkBloodPressure(int systolic, int diastolic) {
    if (!isAlertEnabled('bloodPressureAlert')) {
      return HealthAlertResult(
        isOutOfRange: false,
        status: HealthStatus.normal,
        category: '血壓',
        message: '',
        recommendation: '',
        isCritical: false,
        value: '$systolic/$diastolic',
      );
    }

    final sysThresholds = bloodPressureThresholds['systolic']!;
    final diaThresholds = bloodPressureThresholds['diastolic']!;

    HealthStatus status = HealthStatus.normal;
    bool isCritical = false;
    String message = '';
    String recommendation = '';

    // 檢查收縮壓
    if (systolic >= sysThresholds['veryHigh']! ||
        diastolic >= diaThresholds['veryHigh']!) {
      status = HealthStatus.veryHigh;
      isCritical = true;
      message = '血壓嚴重偏高！收縮壓 $systolic / 舒張壓 $diastolic mmHg';
      recommendation = '請立即休息，如持續偏高請盡快就醫。';
    } else if (systolic >= sysThresholds['high']! ||
        diastolic >= diaThresholds['high']!) {
      status = HealthStatus.high;
      message = '血壓偏高。收縮壓 $systolic / 舒張壓 $diastolic mmHg';
      recommendation = '建議休息 5-10 分鐘後再測量一次，並注意飲食和作息。';
    } else if (systolic < sysThresholds['veryLow']! ||
        diastolic < diaThresholds['veryLow']!) {
      status = HealthStatus.veryLow;
      isCritical = true;
      message = '血壓過低！收縮壓 $systolic / 舒張壓 $diastolic mmHg';
      recommendation = '請立即坐下或躺下，如有頭暈請盡快就醫。';
    } else if (systolic < sysThresholds['low']! ||
        diastolic < diaThresholds['low']!) {
      status = HealthStatus.low;
      message = '血壓偏低。收縮壓 $systolic / 舒張壓 $diastolic mmHg';
      recommendation = '建議多喝水、適量攝取鹽分，注意是否有頭暈症狀。';
    }

    return HealthAlertResult(
      isOutOfRange: status != HealthStatus.normal,
      status: status,
      category: '血壓',
      message: message,
      recommendation: recommendation,
      isCritical: isCritical,
      value: '$systolic/$diastolic',
    );
  }

  // ============================================================
  // 檢查血糖值
  // ============================================================
  HealthAlertResult checkBloodGlucose(int glucose, {String? timing}) {
    if (!isAlertEnabled('bloodGlucoseAlert')) {
      return HealthAlertResult(
        isOutOfRange: false,
        status: HealthStatus.normal,
        category: '血糖',
        message: '',
        recommendation: '',
        isCritical: false,
        value: glucose,
      );
    }

    // 根據測量時機選擇閾值
    final isFasting = timing == 'fasting' || timing == 'before_meal';
    final thresholds = isFasting
        ? bloodGlucoseThresholds['fasting']!
        : bloodGlucoseThresholds['postMeal']!;
    final timingLabel = isFasting ? '空腹/餐前' : '餐後';

    HealthStatus status = HealthStatus.normal;
    bool isCritical = false;
    String message = '';
    String recommendation = '';

    if (glucose >= thresholds['veryHigh']!) {
      status = HealthStatus.veryHigh;
      isCritical = true;
      message = '血糖嚴重偏高！$timingLabel血糖 $glucose mg/dL';
      recommendation = '請立即就醫檢查，可能需要調整用藥。';
    } else if (glucose >= thresholds['high']!) {
      status = HealthStatus.high;
      message = '血糖偏高。$timingLabel血糖 $glucose mg/dL';
      recommendation = '建議控制飲食，減少碳水化合物攝取，並諮詢醫生。';
    } else if (glucose <= thresholds['veryLow']!) {
      status = HealthStatus.veryLow;
      isCritical = true;
      message = '血糖過低！$timingLabel血糖 $glucose mg/dL';
      recommendation = '請立即補充糖分（如糖果、果汁），如症狀未改善請就醫。';
    } else if (glucose < thresholds['low']!) {
      status = HealthStatus.low;
      message = '血糖偏低。$timingLabel血糖 $glucose mg/dL';
      recommendation = '建議適量補充食物，注意是否有頭暈、冒汗等症狀。';
    }

    return HealthAlertResult(
      isOutOfRange: status != HealthStatus.normal,
      status: status,
      category: '血糖',
      message: message,
      recommendation: recommendation,
      isCritical: isCritical,
      value: glucose,
    );
  }

  // ============================================================
  // 檢查心率
  // ============================================================
  HealthAlertResult checkHeartRate(int heartRate) {
    if (!isAlertEnabled('heartRateAlert')) {
      return HealthAlertResult(
        isOutOfRange: false,
        status: HealthStatus.normal,
        category: '心率',
        message: '',
        recommendation: '',
        isCritical: false,
        value: heartRate,
      );
    }

    HealthStatus status = HealthStatus.normal;
    bool isCritical = false;
    String message = '';
    String recommendation = '';

    if (heartRate >= heartRateThresholds['veryHigh']!) {
      status = HealthStatus.veryHigh;
      isCritical = true;
      message = '心率過快！$heartRate bpm';
      recommendation = '請立即休息，如伴隨胸悶、呼吸困難請盡快就醫。';
    } else if (heartRate >= heartRateThresholds['high']!) {
      status = HealthStatus.high;
      message = '心率偏快。$heartRate bpm';
      recommendation = '建議休息一下，避免劇烈運動和刺激性飲品。';
    } else if (heartRate <= heartRateThresholds['veryLow']!) {
      status = HealthStatus.veryLow;
      isCritical = true;
      message = '心率過慢！$heartRate bpm';
      recommendation = '如非運動員體質，請盡快就醫檢查。';
    } else if (heartRate < heartRateThresholds['low']!) {
      status = HealthStatus.low;
      message = '心率偏慢。$heartRate bpm';
      recommendation = '如無運動習慣但心率偏慢，建議諮詢醫生。';
    }

    return HealthAlertResult(
      isOutOfRange: status != HealthStatus.normal,
      status: status,
      category: '心率',
      message: message,
      recommendation: recommendation,
      isCritical: isCritical,
      value: heartRate,
    );
  }

  // ============================================================
  // 顯示警示對話框
  // ============================================================
  Future<void> showAlertDialog(BuildContext context, HealthAlertResult result) async {
    if (!result.isOutOfRange) return;

    final statusColor = AppColors.getStatusColor(result.status);
    final statusLightColor = AppColors.getStatusLightColor(result.status);
    final statusText = AppColors.getStatusText(result.status);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: statusLightColor,
            shape: BoxShape.circle,
          ),
          child: Icon(
            result.isCritical ? Icons.warning_rounded : Icons.info_rounded,
            color: statusColor,
            size: 36,
          ),
        ),
        title: Text(
          '${result.category}$statusText',
          style: TextStyle(
            color: statusColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.message,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.recommendation,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 發送危險值推送通知
  // ============================================================
  Future<void> sendCriticalNotification(HealthAlertResult result) async {
    if (!result.isCritical) return;

    final notificationService = NotificationService();
    await notificationService.showLocalNotification(
      title: '⚠️ ${result.category}異常警示',
      body: result.message,
      channelId: 'health_reminders',
      payload: 'health_alert_${result.category}',
    );
  }
}
