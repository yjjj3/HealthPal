// lib/models/record_data.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class RecordData {
  final String id;
  final String category;
  final String value;
  final String unit;
  final String emoji;
  final DateTime recordTime;
  final String? notes;
  
  // 解析後的數值字段
  final int? systolicBloodPressure;
  final int? diastolicBloodPressure;
  final int? bloodGlucose;
  final double? weight;
  final double? sleepHours;
  final int? exerciseMinutes;
  final String? exerciseType;

  // 血糖測量時機
  final String? glucoseTiming;

  // 血糖測量時機選項
  static const List<Map<String, String>> glucoseTimingOptions = [
    {'value': 'fasting', 'label': '空腹'},
    {'value': 'before_meal', 'label': '餐前'},
    {'value': 'after_meal', 'label': '餐後'},
    {'value': 'bedtime', 'label': '睡前'},
    {'value': 'random', 'label': '隨機'},
  ];

  // 取得時機標籤
  String? get glucoseTimingLabel {
    if (glucoseTiming == null) return null;
    final option = glucoseTimingOptions.firstWhere(
      (o) => o['value'] == glucoseTiming,
      orElse: () => {'label': glucoseTiming!},
    );
    return option['label'];
  }

  RecordData({
    required this.id,
    required this.category,
    required this.value,
    required this.unit,
    required this.emoji,
    required this.recordTime,
    this.notes,
    this.systolicBloodPressure,
    this.diastolicBloodPressure,
    this.bloodGlucose,
    this.weight,
    this.sleepHours,
    this.exerciseMinutes,
    this.exerciseType,
    this.glucoseTiming,
  });

  factory RecordData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    print('[RecordData] 解析記錄數據: $data');
    
    // 處理記錄時間
    DateTime recordTime;
    if (data['record_time'] is Timestamp) {
      recordTime = (data['record_time'] as Timestamp).toDate();
    } else if (data['timestamp'] is Timestamp) {
      recordTime = (data['timestamp'] as Timestamp).toDate();
    } else if (data['created_at'] is Timestamp) {
      recordTime = (data['created_at'] as Timestamp).toDate();
    } else {
      recordTime = DateTime.now();
    }
    
    // 獲取基本字段
    final category = data['category'] as String? ?? '未知';
    final valueString = data['value'] as String? ?? '';
    final unit = data['unit'] as String? ?? '';
    final emoji = data['emoji'] as String? ?? '📋';
    final notes = data.containsKey('notes') ? data['notes'] as String? : null;
    final glucoseTiming = data.containsKey('glucose_timing') ? data['glucose_timing'] as String? : null;
    
    print('[RecordData] 基本字段: category=$category, value=$valueString, unit=$unit');
    
    // 解析數值
    final parsedValues = _parseValues(category, valueString);
    
    return RecordData(
      id: doc.id,
      category: category,
      value: valueString,
      unit: unit,
      emoji: emoji,
      recordTime: recordTime,
      notes: notes,
      systolicBloodPressure: parsedValues['systolic'],
      diastolicBloodPressure: parsedValues['diastolic'],
      bloodGlucose: parsedValues['glucose'],
      weight: parsedValues['weight'],
      sleepHours: parsedValues['sleep'],
      exerciseMinutes: parsedValues['exerciseMinutes'],
      exerciseType: parsedValues['exerciseType'],
      glucoseTiming: glucoseTiming,
    );
  }

  static Map<String, dynamic> _parseValues(String category, String valueString) {
    int? systolic, diastolic, glucose, exerciseMinutes;
    double? weight, sleep;
    String? exerciseType;
    
    try {
      switch (category) {
        case '血壓':
          // 解析 "120/80 mmHg" 格式
          final bpMatch = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(valueString);
          if (bpMatch != null) {
            systolic = int.tryParse(bpMatch.group(1)!);
            diastolic = int.tryParse(bpMatch.group(2)!);
            print('[RecordData] 解析血壓: $systolic/$diastolic');
          }
          break;
          
        case '血糖':
          // 解析 "100 mg/dL" 格式
          final glucoseMatch = RegExp(r'(\d+)').firstMatch(valueString);
          if (glucoseMatch != null) {
            glucose = int.tryParse(glucoseMatch.group(1)!);
            print('[RecordData] 解析血糖: $glucose');
          }
          break;
          
        case '體重':
          // 解析 "70 kg" 格式
          final weightMatch = RegExp(r'([\d.]+)').firstMatch(valueString);
          if (weightMatch != null) {
            weight = double.tryParse(weightMatch.group(1)!);
            print('[RecordData] 解析體重: $weight');
          }
          break;

        case '睡眠':
          // 解析 "7.5 小時" 格式
          final sleepMatch = RegExp(r'([\d.]+)').firstMatch(valueString);
          if (sleepMatch != null) {
            sleep = double.tryParse(sleepMatch.group(1)!);
            print('[RecordData] 解析睡眠: $sleep');
          }
          break;

        case '運動':
          // 解析 "跑步 30 分鐘" 格式
          final exerciseMatch = RegExp(r'(.+?)\s+(\d+)').firstMatch(valueString);
          if (exerciseMatch != null) {
            exerciseType = exerciseMatch.group(1)!;
            exerciseMinutes = int.tryParse(exerciseMatch.group(2)!);
            print('[RecordData] 解析運動: $exerciseType $exerciseMinutes 分鐘');
          }
          break;
      }
    } catch (e) {
      print('[RecordData] 解析數值失敗: $e');
    }

    return {
      'systolic': systolic,
      'diastolic': diastolic,
      'glucose': glucose,
      'weight': weight,
      'sleep': sleep,
      'exerciseMinutes': exerciseMinutes,
      'exerciseType': exerciseType,
    };
  }

  RecordData copyWith({
    String? id,
    String? category,
    String? value,
    String? unit,
    String? emoji,
    DateTime? recordTime,
    String? notes,
    int? systolicBloodPressure,
    int? diastolicBloodPressure,
    int? bloodGlucose,
    double? weight,
    double? sleepHours,
    int? exerciseMinutes,
    String? exerciseType,
    String? glucoseTiming,
  }) {
    return RecordData(
      id: id ?? this.id,
      category: category ?? this.category,
      value: value ?? this.value,
      unit: unit ?? this.unit,
      emoji: emoji ?? this.emoji,
      recordTime: recordTime ?? this.recordTime,
      notes: notes ?? this.notes,
      systolicBloodPressure: systolicBloodPressure ?? this.systolicBloodPressure,
      diastolicBloodPressure: diastolicBloodPressure ?? this.diastolicBloodPressure,
      bloodGlucose: bloodGlucose ?? this.bloodGlucose,
      weight: weight ?? this.weight,
      sleepHours: sleepHours ?? this.sleepHours,
      exerciseMinutes: exerciseMinutes ?? this.exerciseMinutes,
      exerciseType: exerciseType ?? this.exerciseType,
      glucoseTiming: glucoseTiming ?? this.glucoseTiming,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'value': value,
      'unit': unit,
      'emoji': emoji,
      'notes': notes,
      'record_time': Timestamp.fromDate(recordTime),
      if (glucoseTiming != null) 'glucose_timing': glucoseTiming,
    };
  }

  @override
  String toString() {
    return 'RecordData{id: $id, category: $category, value: $value, systolic: $systolicBloodPressure, diastolic: $diastolicBloodPressure, glucose: $bloodGlucose, glucoseTiming: $glucoseTiming, weight: $weight, sleep: $sleepHours, exerciseType: $exerciseType, exerciseMinutes: $exerciseMinutes, time: $recordTime}';
  }
}