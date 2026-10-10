// lib/services/record_data_converter.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/record_data.dart';

class RecordDataConverter {
  // 将 RecordsScreen 的数据转换为 HealthRecordScreen 的 RecordData 格式
  static RecordData? convertFromRecordDocument(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;

      final category = data['category'] as String?;
      final value = data['value'] as String?;
      final recordTime = data['record_time'] as Timestamp?;
      
      if (recordTime == null) return null;

      final record = RecordData(
        id: doc.id,
        category: category ?? '未知',
        value: value ?? '',
        unit: _getDefaultUnit(category),
        emoji: _getCategoryEmoji(category),
        recordTime: recordTime.toDate(),
        notes: '',
        // 其他字段初始化为 null
        systolicBloodPressure: null,
        diastolicBloodPressure: null,
        bloodGlucose: null,
        weight: null,
        sleepHours: null,
      );

      // 根据类别解析数值
      return _parseValueByCategory(record, category, value);
    } catch (e) {
      print('转换记录数据失败: $e');
      return null;
    }
  }

  static RecordData _parseValueByCategory(
      RecordData record, String? category, String? value) {
    if (category == null || value == null) return record;

    switch (category) {
      case '血壓':
        final bpValues = _parseBloodPressure(value);
        return record.copyWith(
          systolicBloodPressure: bpValues['systolic'],
          diastolicBloodPressure: bpValues['diastolic'],
        );
      
      case '血糖':
        final glucose = _parseNumber(value);
        return record.copyWith(bloodGlucose: glucose);
      
      case '體重':
        final weight = _parseNumber(value);
        return record.copyWith(weight: weight?.toDouble());
      
      case '睡眠':
        final sleep = _parseNumber(value);
        return record.copyWith(sleepHours: sleep?.toDouble());
      
      default:
        return record;
    }
  }

  static Map<String, int?> _parseBloodPressure(String value) {
    try {
      // 处理 "120/80 mmHg" 格式
      final cleanValue = value.replaceAll('mmHg', '').trim();
      final parts = cleanValue.split('/');
      
      if (parts.length == 2) {
        return {
          'systolic': int.tryParse(parts[0].trim()),
          'diastolic': int.tryParse(parts[1].trim()),
        };
      }
    } catch (e) {
      print('解析血压值失败: $e');
    }
    return {'systolic': null, 'diastolic': null};
  }

  static int? _parseNumber(String value) {
    try {
      // 提取数字部分
      final regex = RegExp(r'(\d+\.?\d*)');
      final match = regex.firstMatch(value);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    } catch (e) {
      print('解析数字失败: $e');
    }
    return null;
  }

  static String _getDefaultUnit(String? category) {
    switch (category) {
      case '血壓':
        return 'mmHg';
      case '血糖':
        return 'mg/dL';
      case '體重':
        return 'kg';
      default:
        return '';
    }
  }

  static String _getCategoryEmoji(String? category) {
    switch (category) {
      case '血壓':
        return '💓';
      case '血糖':
        return '🩸';
      case '體重':
        return '⚖️';
      default:
        return '📋';
    }
  }
}