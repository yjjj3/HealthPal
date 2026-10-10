// lib/models/prescription_model.dart
// 處方箋資料模型

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 單一藥品資料模型（從處方箋辨識而來）
class PrescriptionMedicine {
  final String? id;
  final String drugCode;           // 藥品代碼（從 QR Code 取得）
  final String name;               // 藥品名稱（中文）
  final String? englishName;       // 藥品名稱（英文）
  final String? brandName;         // 商品名/廠牌
  final String? appearance;        // 藥品外觀描述
  final String dosage;             // 劑量（每次幾顆/ml）
  final String unit;               // 單位（顆、ml、包等）
  final String frequency;          // 頻率（每天幾次）
  final String timing;             // 服用時機（飯前/飯後/睡前）
  final int durationDays;          // 天數
  final int totalQuantity;         // 總數量
  final String route;              // 給藥途徑
  final DateTime startDate;        // 開始日期
  final String? clinicalUse;       // 臨床用途
  final String? sideEffects;       // 副作用
  final String? precautions;       // 注意事項
  final String? storageMethod;     // 儲存方式
  final DateTime? followUpDate;    // 預約回診日期
  final DateTime? expiryDate;      // 建議用完日期
  final String? imageUrl;          // 處方箋圖片 URL
  final double confidence;         // AI 辨識信心度 (0.0 - 1.0)

  PrescriptionMedicine({
    this.id,
    required this.drugCode,
    required this.name,
    this.englishName,
    this.brandName,
    this.appearance,
    required this.dosage,
    required this.unit,
    required this.frequency,
    required this.timing,
    required this.durationDays,
    required this.totalQuantity,
    this.route = '口服',
    DateTime? startDate,
    this.clinicalUse,
    this.sideEffects,
    this.precautions,
    this.storageMethod,
    this.followUpDate,
    this.expiryDate,
    this.imageUrl,
    this.confidence = 0.0,
  }) : startDate = startDate ?? DateTime.now();

  factory PrescriptionMedicine.fromJson(Map<String, dynamic> json) {
    // 安全轉換函數：處理可能是 int 或 String 的欄位
    String? safeString(dynamic value) {
      if (value == null) return null;
      return value.toString();
    }

    int safeInt(dynamic value, int defaultValue) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    return PrescriptionMedicine(
      id: safeString(json['id']),
      drugCode: safeString(json['drugCode']) ?? '',
      name: safeString(json['name']) ?? '未知藥品',
      englishName: safeString(json['englishName']),
      brandName: safeString(json['brandName']),
      appearance: safeString(json['appearance']),
      dosage: safeString(json['dosage']) ?? '1',
      unit: safeString(json['unit']) ?? '顆',
      frequency: safeString(json['frequency']) ?? '每天1次',
      timing: safeString(json['timing']) ?? '飯後',
      durationDays: safeInt(json['durationDays'], 7),
      totalQuantity: safeInt(json['totalQuantity'], 0),
      route: safeString(json['route']) ?? '口服',
      startDate: json['startDate'] != null ? DateTime.tryParse(json['startDate'].toString()) : null,
      clinicalUse: safeString(json['clinicalUse']),
      sideEffects: safeString(json['sideEffects']),
      precautions: safeString(json['precautions']),
      storageMethod: safeString(json['storageMethod']),
      followUpDate: json['followUpDate'] != null
          ? DateTime.tryParse(json['followUpDate'].toString())
          : null,
      expiryDate: json['expiryDate'] != null
          ? DateTime.tryParse(json['expiryDate'].toString())
          : null,
      imageUrl: safeString(json['imageUrl']),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'drugCode': drugCode,
      'name': name,
      'englishName': englishName,
      'brandName': brandName,
      'appearance': appearance,
      'dosage': dosage,
      'unit': unit,
      'frequency': frequency,
      'timing': timing,
      'durationDays': durationDays,
      'totalQuantity': totalQuantity,
      'route': route,
      'startDate': startDate.toIso8601String(),
      'clinicalUse': clinicalUse,
      'sideEffects': sideEffects,
      'precautions': precautions,
      'storageMethod': storageMethod,
      'followUpDate': followUpDate?.toIso8601String(),
      'expiryDate': expiryDate?.toIso8601String(),
      'imageUrl': imageUrl,
      'confidence': confidence,
    };
  }

  factory PrescriptionMedicine.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PrescriptionMedicine(
      id: doc.id,
      drugCode: data['drugCode'] as String? ?? '',
      name: data['name'] as String? ?? '未知藥品',
      englishName: data['englishName'] as String?,
      brandName: data['brandName'] as String?,
      appearance: data['appearance'] as String?,
      dosage: data['dosage'] as String? ?? '1',
      unit: data['unit'] as String? ?? '顆',
      frequency: data['frequency'] as String? ?? '每天1次',
      timing: data['timing'] as String? ?? '飯後',
      route: data['route'] as String? ?? '口服',
      startDate: data['startDate'] != null ? DateTime.tryParse(data['startDate'].toString()) ?? DateTime.now() : DateTime.now(),
      durationDays: (data['durationDays'] as num?)?.toInt() ?? 7,
      totalQuantity: (data['totalQuantity'] as num?)?.toInt() ?? 0,
      clinicalUse: data['clinicalUse'] as String?,
      sideEffects: data['sideEffects'] as String?,
      precautions: data['precautions'] as String?,
      storageMethod: data['storageMethod'] as String?,
      followUpDate: data['followUpDate'] != null
          ? (data['followUpDate'] as Timestamp).toDate()
          : null,
      expiryDate: data['expiryDate'] != null
          ? (data['expiryDate'] as Timestamp).toDate()
          : null,
      imageUrl: data['imageUrl'] as String?,
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'drugCode': drugCode,
      'name': name,
      'englishName': englishName,
      'brandName': brandName,
      'appearance': appearance,
      'dosage': dosage,
      'unit': unit,
      'frequency': frequency,
      'timing': timing,
      'durationDays': durationDays,
      'totalQuantity': totalQuantity,
      'clinicalUse': clinicalUse,
      'sideEffects': sideEffects,
      'precautions': precautions,
      'storageMethod': storageMethod,
      'followUpDate': followUpDate != null
          ? Timestamp.fromDate(followUpDate!)
          : null,
      'expiryDate': expiryDate != null
          ? Timestamp.fromDate(expiryDate!)
          : null,
      'imageUrl': imageUrl,
      'confidence': confidence,
    };
  }

  PrescriptionMedicine copyWith({
    String? id,
    String? drugCode,
    String? name,
    String? englishName,
    String? brandName,
    String? appearance,
    String? dosage,
    String? unit,
    String? frequency,
    String? timing,
    int? durationDays,
    int? totalQuantity,
    String? route,
    DateTime? startDate,
    String? clinicalUse,
    String? sideEffects,
    String? precautions,
    String? storageMethod,
    DateTime? followUpDate,
    DateTime? expiryDate,
    String? imageUrl,
    double? confidence,
  }) {
    return PrescriptionMedicine(
      id: id ?? this.id,
      drugCode: drugCode ?? this.drugCode,
      name: name ?? this.name,
      englishName: englishName ?? this.englishName,
      brandName: brandName ?? this.brandName,
      appearance: appearance ?? this.appearance,
      dosage: dosage ?? this.dosage,
      unit: unit ?? this.unit,
      frequency: frequency ?? this.frequency,
      timing: timing ?? this.timing,
      durationDays: durationDays ?? this.durationDays,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      route: route ?? this.route,
      startDate: startDate ?? this.startDate,
      clinicalUse: clinicalUse ?? this.clinicalUse,
      sideEffects: sideEffects ?? this.sideEffects,
      precautions: precautions ?? this.precautions,
      storageMethod: storageMethod ?? this.storageMethod,
      followUpDate: followUpDate ?? this.followUpDate,
      expiryDate: expiryDate ?? this.expiryDate,
      imageUrl: imageUrl ?? this.imageUrl,
      confidence: confidence ?? this.confidence,
    );
  }
}

/// 完整處方箋資料模型（包含多個藥品）
class Prescription {
  final String? id;
  final String hospitalName;        // 醫院名稱
  final String? doctorName;         // 醫生姓名
  final String? departmentName;     // 科別
  final DateTime prescriptionDate;  // 開立日期
  final DateTime? followUpDate;     // 回診日期
  final List<PrescriptionMedicine> medicines;  // 藥品列表
  final List<String> imageUrls;     // 處方箋圖片 URLs
  final DateTime createdAt;         // 建立時間
  final String? notes;              // 備註

  Prescription({
    this.id,
    required this.hospitalName,
    this.doctorName,
    this.departmentName,
    required this.prescriptionDate,
    this.followUpDate,
    required this.medicines,
    required this.imageUrls,
    DateTime? createdAt,
    this.notes,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Prescription.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Prescription(
      id: doc.id,
      hospitalName: data['hospitalName'] as String? ?? '未知醫院',
      doctorName: data['doctorName'] as String?,
      departmentName: data['departmentName'] as String?,
      prescriptionDate: data['prescriptionDate'] != null
          ? (data['prescriptionDate'] as Timestamp).toDate()
          : DateTime.now(),
      followUpDate: data['followUpDate'] != null
          ? (data['followUpDate'] as Timestamp).toDate()
          : null,
      medicines: (data['medicines'] as List<dynamic>?)
              ?.map((m) => PrescriptionMedicine.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      imageUrls: (data['imageUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      notes: data['notes'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'hospitalName': hospitalName,
      'doctorName': doctorName,
      'departmentName': departmentName,
      'prescriptionDate': Timestamp.fromDate(prescriptionDate),
      'followUpDate': followUpDate != null
          ? Timestamp.fromDate(followUpDate!)
          : null,
      'medicines': medicines.map((m) => m.toJson()).toList(),
      'imageUrls': imageUrls,
      'createdAt': Timestamp.fromDate(createdAt),
      'notes': notes,
    };
  }

  Prescription copyWith({
    String? id,
    String? hospitalName,
    String? doctorName,
    String? departmentName,
    DateTime? prescriptionDate,
    DateTime? followUpDate,
    List<PrescriptionMedicine>? medicines,
    List<String>? imageUrls,
    DateTime? createdAt,
    String? notes,
  }) {
    return Prescription(
      id: id ?? this.id,
      hospitalName: hospitalName ?? this.hospitalName,
      doctorName: doctorName ?? this.doctorName,
      departmentName: departmentName ?? this.departmentName,
      prescriptionDate: prescriptionDate ?? this.prescriptionDate,
      followUpDate: followUpDate ?? this.followUpDate,
      medicines: medicines ?? this.medicines,
      imageUrls: imageUrls ?? this.imageUrls,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
    );
  }
}

/// 用餐時間設定模型
class MealTimeSettings {
  final TimeOfDay breakfastTime;    // 早餐時間
  final TimeOfDay lunchTime;        // 午餐時間
  final TimeOfDay dinnerTime;       // 晚餐時間
  final TimeOfDay bedTime;          // 睡前時間
  final int beforeMealMinutes;      // 飯前提前分鐘數
  final int afterMealMinutes;       // 飯後延後分鐘數

  MealTimeSettings({
    TimeOfDay? breakfastTime,
    TimeOfDay? lunchTime,
    TimeOfDay? dinnerTime,
    TimeOfDay? bedTime,
    this.beforeMealMinutes = 30,
    this.afterMealMinutes = 30,
  })  : breakfastTime = breakfastTime ?? const TimeOfDay(hour: 7, minute: 30),
        lunchTime = lunchTime ?? const TimeOfDay(hour: 12, minute: 0),
        dinnerTime = dinnerTime ?? const TimeOfDay(hour: 18, minute: 30),
        bedTime = bedTime ?? const TimeOfDay(hour: 22, minute: 0);

  factory MealTimeSettings.fromJson(Map<String, dynamic> json) {
    return MealTimeSettings(
      breakfastTime: _parseTimeOfDay(json['breakfastTime']),
      lunchTime: _parseTimeOfDay(json['lunchTime']),
      dinnerTime: _parseTimeOfDay(json['dinnerTime']),
      bedTime: _parseTimeOfDay(json['bedTime']),
      beforeMealMinutes: json['beforeMealMinutes'] as int? ?? 30,
      afterMealMinutes: json['afterMealMinutes'] as int? ?? 30,
    );
  }

  static TimeOfDay? _parseTimeOfDay(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) {
      return TimeOfDay(
        hour: value['hour'] as int? ?? 0,
        minute: value['minute'] as int? ?? 0,
      );
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'breakfastTime': {'hour': breakfastTime.hour, 'minute': breakfastTime.minute},
      'lunchTime': {'hour': lunchTime.hour, 'minute': lunchTime.minute},
      'dinnerTime': {'hour': dinnerTime.hour, 'minute': dinnerTime.minute},
      'bedTime': {'hour': bedTime.hour, 'minute': bedTime.minute},
      'beforeMealMinutes': beforeMealMinutes,
      'afterMealMinutes': afterMealMinutes,
    };
  }

  /// 根據服用時機計算實際提醒時間
  List<DateTime> calculateReminderTimes({
    required String timing,
    required String frequency,
  }) {
    final List<DateTime> times = [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final isBefore = timing.contains('飯前') || timing.contains('餐前');
    final isBedtime = timing.contains('睡前');
    final int offset = isBefore ? -beforeMealMinutes : afterMealMinutes;

    DateTime mealTime(TimeOfDay t) => DateTime(
          today.year, today.month, today.day, t.hour, t.minute,
        ).add(Duration(minutes: offset));

    // 睡前：固定一次
    if (isBedtime) {
      times.add(DateTime(today.year, today.month, today.day, bedTime.hour, bedTime.minute));
      return times;
    }

    // 指定餐次（早餐/午餐/晚餐）
    if (timing.startsWith('早餐')) {
      times.add(mealTime(breakfastTime));
      return times;
    }
    if (timing.startsWith('午餐')) {
      times.add(mealTime(lunchTime));
      return times;
    }
    if (timing.startsWith('晚餐')) {
      times.add(mealTime(dinnerTime));
      return times;
    }

    // 未指定餐次：根據頻率決定用哪幾餐
    int timesPerDay = 1;
    if (frequency.contains('4次') || frequency.contains('四次')) {
      timesPerDay = 4;
    } else if (frequency.contains('3次') || frequency.contains('三次')) {
      timesPerDay = 3;
    } else if (frequency.contains('2次') || frequency.contains('二次') || frequency.contains('兩次')) {
      timesPerDay = 2;
    }

    times.add(mealTime(breakfastTime));
    if (timesPerDay >= 2) times.add(mealTime(dinnerTime));
    if (timesPerDay >= 3) times.add(mealTime(lunchTime));
    if (timesPerDay >= 4) times.add(mealTime(bedTime));

    return times;
  }

  MealTimeSettings copyWith({
    TimeOfDay? breakfastTime,
    TimeOfDay? lunchTime,
    TimeOfDay? dinnerTime,
    TimeOfDay? bedTime,
    int? beforeMealMinutes,
    int? afterMealMinutes,
  }) {
    return MealTimeSettings(
      breakfastTime: breakfastTime ?? this.breakfastTime,
      lunchTime: lunchTime ?? this.lunchTime,
      dinnerTime: dinnerTime ?? this.dinnerTime,
      bedTime: bedTime ?? this.bedTime,
      beforeMealMinutes: beforeMealMinutes ?? this.beforeMealMinutes,
      afterMealMinutes: afterMealMinutes ?? this.afterMealMinutes,
    );
  }
}
