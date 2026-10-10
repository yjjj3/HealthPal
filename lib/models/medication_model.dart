// lib/models/medication_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class medicine {
  final String? medicine_id;
  final String name;
  final String dosage;
  final String unit;
  final int total_supply;
  final int total_pills;
  final String frequency;
  final List<DateTime> times_of_day_list;
  final List<bool> times_status;
  final String instruction;
  final String route;
  final int remaining_days;
  final DateTime start_date;
  final int duration_days;
  final DateTime lastUpdated;
  final bool reminderEnabled;
  final String? source;          // 來源（藥局/醫院）
  final String? clinicalUse;    // 臨床用途
  final String? sideEffects;    // 副作用
  final String? precautions;    // 注意事項
  final String? storageMethod;  // 儲存方式
  final String? appearance;     // 藥品外觀

  medicine({
    this.medicine_id,
    required this.name,
    required this.dosage,
    required this.unit,
    required this.total_supply,
    required this.total_pills,
    required this.frequency,
    required this.times_of_day_list,
    required this.times_status,
    required this.instruction,
    required this.route,
    required this.remaining_days,
    required this.start_date,
    required this.duration_days,
    DateTime? lastUpdated,
    this.reminderEnabled = true,
    this.source,
    this.clinicalUse,
    this.sideEffects,
    this.precautions,
    this.storageMethod,
    this.appearance,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  // ----------------------------------------------------
  // 根據總劑量、頻率、單次劑量計算剩餘天數
  // ----------------------------------------------------
  int get remaining_days_calculated {
    if (total_supply <= 0 || total_pills <= 0) return 0;

    int frequencyCount = 1;
    if (frequency.contains('1次')) {
      frequencyCount = 1;
    } else if (frequency.contains('2次')) {
      frequencyCount = 2;
    } else if (frequency.contains('3次')) {
      frequencyCount = 3;
    } 

    int dailyDosage = frequencyCount * total_pills;
    if (dailyDosage <= 0) return 0;
    
    return total_supply ~/ dailyDosage;
  }

  // ----------------------------------------------------
  // 檢查是否需要重置用藥狀態（新功能）
  // ----------------------------------------------------
  bool get shouldResetStatus {
    final now = DateTime.now();
    final lastUpdateDate = DateTime(lastUpdated.year, lastUpdated.month, lastUpdated.day);
    final currentDate = DateTime(now.year, now.month, now.day);
    
    return currentDate.isAfter(lastUpdateDate);
  }

  // ----------------------------------------------------
  // 重置用藥狀態的方法（新功能）
  // ----------------------------------------------------
  medicine resetStatus() {
    return copyWith(
      times_status: List<bool>.filled(times_status.length, false),
      lastUpdated: DateTime.now(),
    );
  }
  
  // ----------------------------------------------------
  // Firestore 轉換
  // ----------------------------------------------------
  factory medicine.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data()!;
    
    List<DateTime> timesList = (data['times_of_day_list'] as List<dynamic>?)
        ?.map((ts) => (ts as Timestamp).toDate())
        .toList() ?? [];
        
    List<bool> statusList = (data['times_status'] as List<dynamic>?)
        ?.map((s) => s as bool)
        .toList() ?? [];
        
    DateTime startDate = (data['start_date'] as Timestamp?)?.toDate() ?? DateTime.now();
    
    // 新增：lastUpdated 字段
    DateTime lastUpdated = (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now();

    // 新增：reminderEnabled 字段
    bool reminderEnabled = data['reminderEnabled'] as bool? ?? true;

    return medicine(
      medicine_id: snapshot.id,
      name: data['name'] as String? ?? '未命名藥品',
      dosage: data['dosage'] as String? ?? '1 顆',
      unit: data['unit'] as String? ?? '顆',
      frequency: data['frequency'] as String? ?? '每天1次',
      instruction: data['instruction'] as String? ?? '飯後',
      route: data['route'] as String? ?? '口服',
      total_supply: (data['total_supply'] is int)
          ? data['total_supply'] as int
          : (data['total_supply'] as num?)?.toInt() ?? 0,
      total_pills: (data['total_pills'] is int)
          ? data['total_pills'] as int
          : (data['total_pills'] as num?)?.toInt() ?? 1,
      remaining_days: (data['remaining_days'] is int)
          ? data['remaining_days'] as int
          : (data['remaining_days'] as num?)?.toInt() ?? 0,
      duration_days: (data['duration_days'] is int)
          ? data['duration_days'] as int
          : (data['duration_days'] as num?)?.toInt() ?? 0,
      times_of_day_list: timesList,
      times_status: statusList,
      start_date: startDate,
      lastUpdated: lastUpdated,
      reminderEnabled: reminderEnabled,
      source: data['source'] as String?,
      clinicalUse: data['clinicalUse'] as String?,
      sideEffects: data['sideEffects'] as String?,
      precautions: data['precautions'] as String?,
      storageMethod: data['storageMethod'] as String?,
      appearance: data['appearance'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      "name": name,
      "dosage": dosage,
      "unit": unit,
      "total_supply": total_supply,
      "total_pills": total_pills,
      "frequency": frequency,
      "times_of_day_list": times_of_day_list.map((dt) => Timestamp.fromDate(dt)).toList(),
      "times_status": times_status,
      "instruction": instruction,
      "route": route,
      "remaining_days": remaining_days,
      "start_date": Timestamp.fromDate(start_date),
      "duration_days": duration_days,
      "lastUpdated": Timestamp.fromDate(lastUpdated),
      "reminderEnabled": reminderEnabled,
      if (source != null) "source": source,
      if (clinicalUse != null) "clinicalUse": clinicalUse,
      if (sideEffects != null) "sideEffects": sideEffects,
      if (precautions != null) "precautions": precautions,
      if (storageMethod != null) "storageMethod": storageMethod,
      if (appearance != null) "appearance": appearance,
    };
  }

  // ----------------------------------------------------
  // copyWith (添加 lastUpdated, reminderEnabled)
  // ----------------------------------------------------
  medicine copyWith({
    String? medicine_id,
    String? name,
    String? dosage,
    String? unit,
    int? total_supply,
    int? total_pills,
    String? frequency,
    List<DateTime>? times_of_day_list,
    List<bool>? times_status,
    String? instruction,
    String? route,
    int? remaining_days,
    DateTime? start_date,
    int? duration_days,
    DateTime? lastUpdated,
    bool? reminderEnabled,
    String? source,
    String? clinicalUse,
    String? sideEffects,
    String? precautions,
    String? storageMethod,
    String? appearance,
  }) {
    return medicine(
      medicine_id: medicine_id ?? this.medicine_id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      unit: unit ?? this.unit,
      total_supply: total_supply ?? this.total_supply,
      total_pills: total_pills ?? this.total_pills,
      frequency: frequency ?? this.frequency,
      times_of_day_list: times_of_day_list ?? this.times_of_day_list,
      times_status: times_status ?? this.times_status,
      instruction: instruction ?? this.instruction,
      route: route ?? this.route,
      remaining_days: remaining_days ?? this.remaining_days,
      start_date: start_date ?? this.start_date,
      duration_days: duration_days ?? this.duration_days,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      source: source ?? this.source,
      clinicalUse: clinicalUse ?? this.clinicalUse,
      sideEffects: sideEffects ?? this.sideEffects,
      precautions: precautions ?? this.precautions,
      storageMethod: storageMethod ?? this.storageMethod,
      appearance: appearance ?? this.appearance,
    );
  }
}