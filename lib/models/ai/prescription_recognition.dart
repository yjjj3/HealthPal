import 'validated_json.dart';

class PrescriptionRecognition {
  PrescriptionRecognition._(this.data);
  final Map<String, dynamic> data;
  factory PrescriptionRecognition.parse(String content) {
    final data = decodeAIObject(content);
    if (data['error'] != null)
      throw FormatException(requiredText(data, 'error'));
    final confidence = nonNegativeNumber(data, 'confidence');
    if (confidence > 1) throw const FormatException('辨識信心度必須介於 0 到 1。');
    final medicines = data['medicines'];
    if (medicines is! List || medicines.isEmpty || medicines.length > 100)
      throw const FormatException('沒有可確認的藥品，請重新拍攝或手動新增。');
    final validated = <Map<String, dynamic>>[];
    for (final item in medicines) {
      if (item is! Map<String, dynamic>)
        throw const FormatException('藥品資料格式錯誤。');
      for (final key in textFields) {
        if (item[key] != null && item[key] is! String)
          throw FormatException('$key 必須是文字。');
      }
      if ((item['name'] as String? ?? '').trim().isEmpty &&
          (item['englishName'] as String? ?? '').trim().isEmpty)
        throw const FormatException('藥品名稱無法辨識，請重新確認。');
      for (final key in ['durationDays', 'totalQuantity']) {
        if (item[key] != null) {
          final number = nonNegativeNumber(item, key);
          if (key == 'durationDays' && number != number.roundToDouble())
            throw const FormatException('療程天數必須是整數。');
        }
      }
      validated.add({
        ...item,
        'name': (item['name'] as String? ?? '').trim().isNotEmpty
            ? item['name']
            : item['englishName'],
        'confidence': confidence,
      });
    }
    final hospital = data['hospitalInfo'];
    if (hospital != null && hospital is! Map<String, dynamic>)
      throw const FormatException('醫院資料格式錯誤。');
    if (hospital is Map<String, dynamic>) {
      for (final key in hospitalFields) {
        if (hospital[key] != null && hospital[key] is! String)
          throw FormatException('$key 必須是文字。');
      }
      for (final key in ['prescriptionDate', 'followUpDate']) {
        final value = hospital[key];
        if (value != null) {
          final parsed = DateTime.tryParse(value);
          if (parsed == null ||
              !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
              parsed.toIso8601String().substring(0, 10) != value)
            throw FormatException('$key 日期無效。');
        }
      }
    }
    return PrescriptionRecognition._({...data, 'medicines': validated});
  }
  static const textFields = [
    'name',
    'englishName',
    'brandName',
    'appearance',
    'dosage',
    'unit',
    'frequency',
    'timing',
    'route',
    'clinicalUse',
    'sideEffects',
    'precautions',
    'storageMethod',
  ];
  static const hospitalFields = [
    'hospitalName',
    'doctorName',
    'departmentName',
    'prescriptionDate',
    'followUpDate',
  ];
  static final responseFormat = structuredFormat(
    'prescription_recognition',
    strictObject({
      'medicines': {
        'type': 'array',
        'items': strictObject({
          for (final key in textFields)
            key: {
              'type': ['string', 'null'],
            },
          'durationDays': {
            'type': ['integer', 'null'],
          },
          'totalQuantity': {
            'type': ['number', 'null'],
          },
        }),
      },
      'hospitalInfo': strictObject({
        for (final key in hospitalFields)
          key: {
            'type': ['string', 'null'],
          },
      }),
      'confidence': {'type': 'number'},
      'error': {
        'type': ['string', 'null'],
      },
    }),
  );
}
