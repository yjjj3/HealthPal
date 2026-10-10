// lib/models/record_data.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class RecordData {
  final DateTime recordTime;
  final int? systolicBloodPressure;
  final int? diastolicBloodPressure;
  final int? bloodGlucose;
  final double? weight; // 新增體重欄位
  final double? sleepHours; // 新增睡眠時數欄位
  final String recordId;
  final String type; 

  const RecordData({
    required this.recordTime,
    this.systolicBloodPressure,
    this.diastolicBloodPressure,
    this.bloodGlucose,
    this.weight,
    this.sleepHours,
    required this.recordId,
    required this.type,
  });

  // 輔助函式：解析血壓字串 (例如 "110/20 mmHg")
  static (int?, int?) _parseBloodPressure(String? bp) {
    if (bp == null) return (null, null);
    
    final cleanBp = bp.split(' ')[0];
    final parts = cleanBp.split('/');
    
    if (parts.length == 2) {
      final sys = int.tryParse(parts[0].trim());
      final dia = int.tryParse(parts[1].trim());
      return (sys, dia);
    }
    return (null, null);
  }

  // 輔助函式：解析血糖字串 (例如 "150 mg/dL")
  static int? _parseBloodGlucose(String? bg) {
    if (bg == null) return null;
    
    final cleanBg = bg.split(' ')[0]; 
    return int.tryParse(cleanBg.trim());
  }

  // 新增：解析體重字串 (例如 "65.5 kg" 或 "65.5 公斤")
  static double? _parseWeight(String? weight) {
    if (weight == null) return null;
    
    final cleanWeight = weight.replaceAll('kg', '').replaceAll('公斤', '').trim();
    return double.tryParse(cleanWeight);
  }

  // 新增：解析睡眠時數字串 (例如 "7.5 小時" 或 "7.5 hrs")
  static double? _parseSleepHours(String? sleep) {
    if (sleep == null) return null;
    
    final cleanSleep = sleep.replaceAll('小時', '').replaceAll('hrs', '').replaceAll('hr', '').trim();
    return double.tryParse(cleanSleep);
  }

  // 核心：從 Firestore Document 構造 RecordData
  factory RecordData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      throw Exception("Document data was null for ID: ${doc.id}");
    }

    final Timestamp timestamp = data['recordTime'] as Timestamp? ?? Timestamp.fromDate(DateTime.now());
    
    final String type = data['type'] as String? ?? '未知'; 
    final String? value = data['value'] as String?; 

    int? sys, dia, glu;
    double? weight, sleepHours;

    // 根據您 Firestore 中的 Type 欄位值來解析數據
    if (type == '血壓') {
        (sys, dia) = _parseBloodPressure(value);
    } else if (type == '血糖') {
        glu = _parseBloodGlucose(value);
    } else if (type == '體重') {
        weight = _parseWeight(value);
    } else if (type == '睡眠') {
        sleepHours = _parseSleepHours(value);
    }

    return RecordData(
      recordId: doc.id,
      recordTime: timestamp.toDate(),
      systolicBloodPressure: sys, 
      diastolicBloodPressure: dia, 
      bloodGlucose: glu,
      weight: weight,
      sleepHours: sleepHours,
      type: type,
    );
  }
}