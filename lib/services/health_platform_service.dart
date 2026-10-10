// lib/services/health_platform_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 健康平台整合服務
/// 支援 Apple HealthKit (iOS) 和 Health Connect (Android)
/// 只讀取數據，不寫入
class HealthPlatformService {
  static final HealthPlatformService _instance = HealthPlatformService._internal();
  factory HealthPlatformService() => _instance;
  HealthPlatformService._internal();

  final Health _health = Health();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isAuthorized = false;
  DateTime? _lastSyncTime;

  // 要讀取的健康數據類型
  static const List<HealthDataType> _dataTypes = [
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.HEART_RATE,
    HealthDataType.BLOOD_GLUCOSE,
    HealthDataType.WEIGHT,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_IN_BED,
    HealthDataType.STEPS,
    HealthDataType.WORKOUT,
  ];

  // 只讀取權限
  static final List<HealthDataAccess> _permissions =
      _dataTypes.map((type) => HealthDataAccess.READ).toList();

  /// 檢查是否已授權
  bool get isAuthorized => _isAuthorized;

  /// 最後同步時間
  DateTime? get lastSyncTime => _lastSyncTime;

  /// 取得平台名稱
  String get platformName {
    if (Platform.isIOS) {
      return 'Apple 健康';
    } else if (Platform.isAndroid) {
      return 'Health Connect';
    }
    return '健康平台';
  }

  /// 初始化健康服務
  Future<void> initialize() async {
    try {
      // 配置 Health 套件
      await _health.configure();

      // 檢查之前的授權狀態
      final prefs = await SharedPreferences.getInstance();
      final storedAuthorized = prefs.getBool('health_authorized') ?? false;

      // 如果之前已授權
      if (storedAuthorized) {
        if (Platform.isIOS) {
          // iOS: Apple HealthKit 基於隱私設計，不會告訴 App 讀取權限狀態
          // 因此直接信任儲存的授權狀態，嘗試讀取數據來驗證
          _isAuthorized = true;
          try {
            // 嘗試讀取少量數據來驗證權限是否有效
            final now = DateTime.now();
            final testData = await _health.getHealthDataFromTypes(
              types: [HealthDataType.STEPS],
              startTime: now.subtract(const Duration(days: 1)),
              endTime: now,
            );
            debugPrint('[HealthPlatformService] iOS 權限驗證成功，讀取到 ${testData.length} 筆測試數據');
          } catch (e) {
            // 如果讀取失敗且是授權錯誤，才重置授權狀態
            if (e.toString().contains('Authorization') ||
                e.toString().contains('permission') ||
                e.toString().contains('denied')) {
              _isAuthorized = false;
              await prefs.setBool('health_authorized', false);
              debugPrint('[HealthPlatformService] iOS 權限已失效: $e');
            } else {
              // 其他錯誤（如網路問題）保持授權狀態
              debugPrint('[HealthPlatformService] iOS 讀取測試數據失敗，但保持授權狀態: $e');
            }
          }
        } else {
          // Android: 可以使用 hasPermissions 檢查
          try {
            final hasPermissions = await _health.hasPermissions(
              _dataTypes,
              permissions: _permissions,
            );
            _isAuthorized = hasPermissions ?? false;

            if (!_isAuthorized) {
              await prefs.setBool('health_authorized', false);
              debugPrint('[HealthPlatformService] Android 權限已失效，需重新授權');
            }
          } catch (e) {
            _isAuthorized = false;
            await prefs.setBool('health_authorized', false);
            debugPrint('[HealthPlatformService] Android 權限檢查失敗: $e');
          }
        }
      } else {
        _isAuthorized = false;
      }

      final lastSyncStr = prefs.getString('health_last_sync');
      if (lastSyncStr != null) {
        _lastSyncTime = DateTime.tryParse(lastSyncStr);
      }

      debugPrint('[HealthPlatformService] 初始化完成，授權狀態: $_isAuthorized');
    } catch (e) {
      debugPrint('[HealthPlatformService] 初始化失敗: $e');
    }
  }

  /// 請求健康數據權限
  Future<bool> requestAuthorization() async {
    try {
      // 檢查設備是否支援
      final isAvailable = await _health.isHealthConnectAvailable();
      if (Platform.isAndroid && !isAvailable) {
        debugPrint('[HealthPlatformService] Health Connect 不可用');
        return false;
      }

      // 請求權限
      final authorized = await _health.requestAuthorization(
        _dataTypes,
        permissions: _permissions,
      );

      _isAuthorized = authorized;

      // 儲存授權狀態
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('health_authorized', authorized);

      debugPrint('[HealthPlatformService] 授權結果: $authorized');
      return authorized;
    } catch (e) {
      debugPrint('[HealthPlatformService] 請求權限失敗: $e');
      return false;
    }
  }

  /// 檢查特定數據類型的權限狀態
  Future<bool> hasPermission(HealthDataType type) async {
    try {
      final status = await _health.hasPermissions(
        [type],
        permissions: [HealthDataAccess.READ],
      );
      return status ?? false;
    } catch (e) {
      debugPrint('[HealthPlatformService] 檢查權限失敗: $e');
      return false;
    }
  }

  /// 同步健康數據到 Firestore
  Future<SyncResult> syncHealthData({int days = 7}) async {
    if (!_isAuthorized) {
      return SyncResult(
        success: false,
        message: '尚未授權存取健康數據',
        syncedRecords: 0,
      );
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return SyncResult(
        success: false,
        message: '用戶未登入',
        syncedRecords: 0,
      );
    }

    try {
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: days));

      int totalSynced = 0;
      final Map<String, int> syncedByType = {};

      // 讀取各類型的健康數據
      final healthData = await _health.getHealthDataFromTypes(
        types: _dataTypes,
        startTime: startDate,
        endTime: now,
      );

      debugPrint('[HealthPlatformService] 讀取到 ${healthData.length} 筆健康數據');

      // 根據類型分組處理
      final Map<String, List<HealthDataPoint>> groupedData = {};
      for (final point in healthData) {
        final category = _mapTypeToCategory(point.type);
        groupedData.putIfAbsent(category, () => []).add(point);
      }

      // 批次寫入 Firestore
      final batch = _firestore.batch();
      final recordsRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('health_records');

      // 特別處理血壓數據（需要配對收縮壓和舒張壓）
      final systolicPoints = healthData
          .where((p) => p.type == HealthDataType.BLOOD_PRESSURE_SYSTOLIC)
          .toList();
      final diastolicPoints = healthData
          .where((p) => p.type == HealthDataType.BLOOD_PRESSURE_DIASTOLIC)
          .toList();

      // 配對血壓數據（根據時間戳配對）
      for (final systolic in systolicPoints) {
        // 找到時間最接近的舒張壓數據（在 1 分鐘內）
        HealthDataPoint? matchingDiastolic;
        for (final diastolic in diastolicPoints) {
          final timeDiff = systolic.dateFrom.difference(diastolic.dateFrom).inSeconds.abs();
          if (timeDiff < 60) {
            matchingDiastolic = diastolic;
            break;
          }
        }

        if (matchingDiastolic != null) {
          final sourceId = 'bp_${systolic.dateFrom.millisecondsSinceEpoch}';

          // 檢查是否已存在
          final existingQuery = await recordsRef
              .where('source', isEqualTo: 'health_platform')
              .where('source_id', isEqualTo: sourceId)
              .limit(1)
              .get();

          if (existingQuery.docs.isEmpty) {
            final systolicValue = (systolic.value as NumericHealthValue).numericValue.round();
            final diastolicValue = (matchingDiastolic.value as NumericHealthValue).numericValue.round();

            final recordData = {
              'category': '血壓',
              'value': '$systolicValue/$diastolicValue mmHg',
              'unit': 'mmHg',
              'emoji': '❤️',
              'record_time': Timestamp.fromDate(systolic.dateFrom),
              'source': 'health_platform',
              'source_id': sourceId,
              'source_name': systolic.sourceName,
              'created_at': FieldValue.serverTimestamp(),
            };

            final docRef = recordsRef.doc();
            batch.set(docRef, recordData);
            totalSynced++;
            syncedByType['血壓'] = (syncedByType['血壓'] ?? 0) + 1;
          }
        }
      }

      // 特別處理步數數據（按日期合併）
      final stepsPoints = healthData
          .where((p) => p.type == HealthDataType.STEPS)
          .toList();

      if (stepsPoints.isNotEmpty) {
        // 按日期分組步數
        final Map<String, int> stepsByDay = {};
        final Map<String, DateTime> dayDates = {};

        for (final point in stepsPoints) {
          final dateKey = '${point.dateFrom.year}-${point.dateFrom.month.toString().padLeft(2, '0')}-${point.dateFrom.day.toString().padLeft(2, '0')}';
          final steps = (point.value as NumericHealthValue).numericValue.toInt();
          stepsByDay[dateKey] = (stepsByDay[dateKey] ?? 0) + steps;
          // 記錄該日期的 DateTime（用於 record_time）
          dayDates[dateKey] ??= DateTime(point.dateFrom.year, point.dateFrom.month, point.dateFrom.day, 12, 0);
        }

        // 為每一天創建一筆步數記錄
        for (final entry in stepsByDay.entries) {
          final dateKey = entry.key;
          final totalSteps = entry.value;
          final sourceId = 'steps_$dateKey';

          // 檢查是否已存在該日期的步數記錄
          final existingQuery = await recordsRef
              .where('source', isEqualTo: 'health_platform')
              .where('source_id', isEqualTo: sourceId)
              .limit(1)
              .get();

          if (existingQuery.docs.isEmpty) {
            final recordData = {
              'category': '運動',
              'value': '步行 $totalSteps 步',
              'unit': '步',
              'emoji': '🚶',
              'record_time': Timestamp.fromDate(dayDates[dateKey]!),
              'source': 'health_platform',
              'source_id': sourceId,
              'source_name': 'Apple 健康',
              'created_at': FieldValue.serverTimestamp(),
            };

            final docRef = recordsRef.doc();
            batch.set(docRef, recordData);
            totalSynced++;
            syncedByType['運動'] = (syncedByType['運動'] ?? 0) + 1;
          }
        }
      }

      // 處理其他類型的數據
      for (final entry in groupedData.entries) {
        final category = entry.key;
        final points = entry.value;

        // 跳過血壓（上面已處理）和步數（已按日期合併）
        if (category == '血壓') continue;

        for (final point in points) {
          // 跳過步數，因為上面已經按日期合併處理了
          if (point.type == HealthDataType.STEPS) continue;

          // 檢查是否已存在相同時間的記錄
          final existingQuery = await recordsRef
              .where('source', isEqualTo: 'health_platform')
              .where('source_id', isEqualTo: _generateSourceId(point))
              .limit(1)
              .get();

          if (existingQuery.docs.isEmpty) {
            final recordData = _convertToRecordData(point, category);
            if (recordData != null) {
              final docRef = recordsRef.doc();
              batch.set(docRef, recordData);
              totalSynced++;
              syncedByType[category] = (syncedByType[category] ?? 0) + 1;
            }
          }
        }
      }

      await batch.commit();

      // 更新最後同步時間
      _lastSyncTime = now;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('health_last_sync', now.toIso8601String());

      debugPrint('[HealthPlatformService] 同步完成，共 $totalSynced 筆記錄');

      return SyncResult(
        success: true,
        message: '成功同步 $totalSynced 筆健康記錄',
        syncedRecords: totalSynced,
        syncedByType: syncedByType,
      );
    } catch (e) {
      debugPrint('[HealthPlatformService] 同步失敗: $e');
      return SyncResult(
        success: false,
        message: '同步失敗：$e',
        syncedRecords: 0,
      );
    }
  }

  /// 讀取特定類型的健康數據（不寫入 Firestore）
  Future<List<HealthDataPoint>> readHealthData(
    HealthDataType type, {
    int days = 7,
  }) async {
    if (!_isAuthorized) return [];

    try {
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: days));

      final data = await _health.getHealthDataFromTypes(
        types: [type],
        startTime: startDate,
        endTime: now,
      );

      return data;
    } catch (e) {
      debugPrint('[HealthPlatformService] 讀取數據失敗: $e');
      return [];
    }
  }

  /// 取得健康數據摘要
  Future<Map<String, dynamic>> getHealthSummary({int days = 7}) async {
    if (!_isAuthorized) return {};

    try {
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: days));

      final healthData = await _health.getHealthDataFromTypes(
        types: _dataTypes,
        startTime: startDate,
        endTime: now,
      );

      final summary = <String, dynamic>{};

      // 計算步數總和
      final stepsData = healthData.where((p) => p.type == HealthDataType.STEPS);
      if (stepsData.isNotEmpty) {
        int totalSteps = 0;
        for (final point in stepsData) {
          totalSteps += (point.value as NumericHealthValue).numericValue.toInt();
        }
        summary['steps'] = {
          'total': totalSteps,
          'average': totalSteps ~/ days,
          'count': stepsData.length,
        };
      }

      // 血壓平均
      final systolicData = healthData.where(
        (p) => p.type == HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      );
      final diastolicData = healthData.where(
        (p) => p.type == HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
      );
      if (systolicData.isNotEmpty && diastolicData.isNotEmpty) {
        double avgSystolic = 0;
        double avgDiastolic = 0;
        for (final point in systolicData) {
          avgSystolic += (point.value as NumericHealthValue).numericValue;
        }
        for (final point in diastolicData) {
          avgDiastolic += (point.value as NumericHealthValue).numericValue;
        }
        avgSystolic /= systolicData.length;
        avgDiastolic /= diastolicData.length;
        summary['blood_pressure'] = {
          'avg_systolic': avgSystolic.round(),
          'avg_diastolic': avgDiastolic.round(),
          'count': systolicData.length,
        };
      }

      // 血糖平均
      final glucoseData = healthData.where(
        (p) => p.type == HealthDataType.BLOOD_GLUCOSE,
      );
      if (glucoseData.isNotEmpty) {
        double avgGlucose = 0;
        for (final point in glucoseData) {
          avgGlucose += (point.value as NumericHealthValue).numericValue;
        }
        avgGlucose /= glucoseData.length;
        summary['blood_glucose'] = {
          'average': avgGlucose.round(),
          'count': glucoseData.length,
        };
      }

      // 最新體重
      final weightData = healthData.where(
        (p) => p.type == HealthDataType.WEIGHT,
      ).toList();
      if (weightData.isNotEmpty) {
        weightData.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
        final latestWeight = (weightData.first.value as NumericHealthValue).numericValue;
        summary['weight'] = {
          'latest': latestWeight,
          'count': weightData.length,
        };
      }

      // 睡眠平均
      final sleepData = healthData.where(
        (p) => p.type == HealthDataType.SLEEP_ASLEEP ||
               p.type == HealthDataType.SLEEP_IN_BED,
      );
      if (sleepData.isNotEmpty) {
        double totalSleepMinutes = 0;
        int sleepSessions = 0;
        for (final point in sleepData) {
          final duration = point.dateTo.difference(point.dateFrom).inMinutes;
          totalSleepMinutes += duration;
          sleepSessions++;
        }
        summary['sleep'] = {
          'avg_hours': (totalSleepMinutes / sleepSessions / 60).toStringAsFixed(1),
          'count': sleepSessions,
        };
      }

      // 心率平均
      final heartRateData = healthData.where(
        (p) => p.type == HealthDataType.HEART_RATE,
      );
      if (heartRateData.isNotEmpty) {
        double avgHeartRate = 0;
        for (final point in heartRateData) {
          avgHeartRate += (point.value as NumericHealthValue).numericValue;
        }
        avgHeartRate /= heartRateData.length;
        summary['heart_rate'] = {
          'average': avgHeartRate.round(),
          'count': heartRateData.length,
        };
      }

      return summary;
    } catch (e) {
      debugPrint('[HealthPlatformService] 取得摘要失敗: $e');
      return {};
    }
  }

  /// 撤銷授權
  Future<void> revokeAuthorization() async {
    try {
      await _health.revokePermissions();
      _isAuthorized = false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('health_authorized', false);
      await prefs.remove('health_last_sync');

      debugPrint('[HealthPlatformService] 已撤銷授權');
    } catch (e) {
      debugPrint('[HealthPlatformService] 撤銷授權失敗: $e');
    }
  }

  // 將 HealthDataType 對應到 App 的類別名稱
  String _mapTypeToCategory(HealthDataType type) {
    switch (type) {
      case HealthDataType.BLOOD_PRESSURE_SYSTOLIC:
      case HealthDataType.BLOOD_PRESSURE_DIASTOLIC:
        return '血壓';
      case HealthDataType.HEART_RATE:
        return '心率';
      case HealthDataType.BLOOD_GLUCOSE:
        return '血糖';
      case HealthDataType.WEIGHT:
        return '體重';
      case HealthDataType.SLEEP_ASLEEP:
      case HealthDataType.SLEEP_IN_BED:
        return '睡眠';
      case HealthDataType.STEPS:
      case HealthDataType.WORKOUT:
        return '運動';
      default:
        return '其他';
    }
  }

  // 生成唯一的來源 ID（用於避免重複同步）
  String _generateSourceId(HealthDataPoint point) {
    return '${point.type.name}_${point.dateFrom.millisecondsSinceEpoch}';
  }

  // 將 HealthDataPoint 轉換為 Firestore 記錄格式
  Map<String, dynamic>? _convertToRecordData(
    HealthDataPoint point,
    String category,
  ) {
    final value = point.value;
    String valueStr = '';
    String unit = '';
    String? emoji;

    switch (point.type) {
      case HealthDataType.BLOOD_PRESSURE_SYSTOLIC:
        // 血壓需要配對處理，這裡先跳過，由配對邏輯處理
        return null;
      case HealthDataType.BLOOD_PRESSURE_DIASTOLIC:
        return null;
      case HealthDataType.BLOOD_GLUCOSE:
        final glucose = (value as NumericHealthValue).numericValue;
        // 轉換為 mg/dL（如果單位是 mmol/L）
        final glucoseMgDl = point.unit == HealthDataUnit.MILLIGRAM_PER_DECILITER
            ? glucose
            : glucose * 18; // mmol/L to mg/dL
        valueStr = '${glucoseMgDl.round()} mg/dL';
        unit = 'mg/dL';
        emoji = '🩸';
        break;
      case HealthDataType.WEIGHT:
        final weight = (value as NumericHealthValue).numericValue;
        valueStr = '${weight.toStringAsFixed(1)} kg';
        unit = 'kg';
        emoji = '⚖️';
        break;
      case HealthDataType.SLEEP_ASLEEP:
      case HealthDataType.SLEEP_IN_BED:
        final duration = point.dateTo.difference(point.dateFrom);
        final hours = duration.inMinutes / 60;
        valueStr = '${hours.toStringAsFixed(1)} 小時';
        unit = '小時';
        emoji = '😴';
        break;
      case HealthDataType.STEPS:
        final steps = (value as NumericHealthValue).numericValue.toInt();
        valueStr = '步行 $steps 步';
        unit = '步';
        emoji = '🚶';
        break;
      case HealthDataType.WORKOUT:
        final duration = point.dateTo.difference(point.dateFrom);
        valueStr = '運動 ${duration.inMinutes} 分鐘';
        unit = '分鐘';
        emoji = '🏃';
        break;
      case HealthDataType.HEART_RATE:
        final heartRate = (value as NumericHealthValue).numericValue.round();
        valueStr = '$heartRate bpm';
        unit = 'bpm';
        emoji = '💓';
        break;
      default:
        return null;
    }

    return {
      'category': category,
      'value': valueStr,
      'unit': unit,
      'emoji': emoji,
      'record_time': Timestamp.fromDate(point.dateFrom),
      'source': 'health_platform',
      'source_id': _generateSourceId(point),
      'source_name': point.sourceName,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}

/// 同步結果
class SyncResult {
  final bool success;
  final String message;
  final int syncedRecords;
  final Map<String, int>? syncedByType;

  SyncResult({
    required this.success,
    required this.message,
    required this.syncedRecords,
    this.syncedByType,
  });
}
