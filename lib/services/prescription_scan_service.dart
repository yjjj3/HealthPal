// lib/services/prescription_scan_service.dart
// 處方箋智慧辨識服務

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication_model.dart';
import '../models/prescription_model.dart';

class PrescriptionScanService {
  static final PrescriptionScanService _instance =
      PrescriptionScanService._internal();
  factory PrescriptionScanService() => _instance;
  PrescriptionScanService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // OpenAI API 設定
  String get _apiKey => dotenv.env['OPENAI_API_KEY'] ?? '';
  static const String _apiUrl = 'https://api.openai.com/v1/chat/completions';

  // 台灣處方箋專用 Prompt
  static const String _prescriptionPrompt = '''
你是一位專業的台灣醫療處方箋 OCR 辨識系統。請仔細分析這張圖片（可能是處方箋、藥袋、成藥包裝或藥品說明），並提取以下資訊。

【最重要規則 - 文字必須逐字照抄】
- sideEffects、precautions 等警示欄位，必須將圖片上的文字「一字不差」完整複製，絕對不可省略、縮短、摘要或改寫
- 例如圖片寫「未滿12歲不宜使用」，就必須輸出「未滿12歲不宜使用」，不可輸出「不宜使用」
- 例如圖片寫「孕婦及哺乳婦女使用前請先諮詢醫師」，就必須完整輸出，不可縮短
- 所有注意事項、警告、禁忌症文字都必須原文保留，不可任意刪減

辨識來源說明：
1. 台灣醫院處方箋/藥袋：包含中英文藥名、劑量、頻率、服用時機
2. 台灣成藥/OTC 包裝：包含藥品名稱、適應症、用法用量、注意事項、禁忌
3. 藥品說明書：包含詳細的副作用、交互作用、使用禁忌
4. 常見服用時機：飯前、飯後、睡前、需要時
5. 頻率：每天1次、每天2次、每天3次、每6小時、每8小時等

請以 JSON 格式回傳，格式如下：
{
  "medicines": [
    {
      "name": "藥品中文名稱（優先填中文；若圖片上只有英文名則填英文名）",
      "englishName": "藥品英文名稱（如有）",
      "brandName": "商品名/廠牌（如有）",
      "appearance": "藥品外觀描述（顏色、形狀、大小）",
      "dosage": "每次劑量（數字）",
      "unit": "單位（顆、粒、ml、包等）",
      "frequency": "服用頻率（如：每天3次）",
      "timing": "服用時機（飯前/飯後/睡前）",
      "durationDays": 天數（數字，如無則為null）,
      "totalQuantity": 總數量（數字，如無則為null）,
      "clinicalUse": "逐字照抄圖片上的臨床用途/適應症/功效",
      "sideEffects": "逐字照抄圖片上所有副作用文字，多項請用「；」分隔",
      "precautions": "逐字照抄圖片上所有注意事項、警告、禁忌文字，多項請用「；」分隔，絕對不可縮短",
      "storageMethod": "逐字照抄儲存方式（如有）"
    }
  ],
  "hospitalInfo": {
    "hospitalName": "醫院/製造商名稱（如有）",
    "doctorName": "醫師姓名（如有）",
    "departmentName": "科別（如有）",
    "prescriptionDate": "開立日期（YYYY-MM-DD格式，如有）",
    "followUpDate": "回診日期（YYYY-MM-DD格式，如有）"
  },
  "confidence": 0.0到1.0之間的信心度
}

其他提示：
- 如果某個欄位無法辨識，請使用 null
- 數字欄位請確保是數字類型，不是字串
- 日期請轉換為 YYYY-MM-DD 格式
- 如果圖片模糊或無法辨識，請降低 confidence 值
- 如果圖片完全無法辨識任何藥品資訊，請回傳 {"error": "無法辨識藥品資訊", "confidence": 0}
- 成藥包裝、藥袋背面的諮詢電話等資訊可放入 precautions 欄位
''';

  // ============================================================
  // 解析 QR Code URL 取得藥品代碼
  // ============================================================
  String? parseQRCodeUrl(String qrCodeData) {
    try {
      // 檢查是否為長庚醫院的藥品查詢 URL
      // 例如: https://www.cgmh.org.tw/tw/Services/DrugSearch?keyword=PGC051M
      final uri = Uri.tryParse(qrCodeData);
      if (uri == null) {
        debugPrint('QR Code 不是有效的 URL: $qrCodeData');
        return null;
      }

      // 取得 keyword 參數（藥品代碼）
      final keyword = uri.queryParameters['keyword'];
      if (keyword != null && keyword.isNotEmpty) {
        debugPrint('解析到藥品代碼: $keyword');
        return keyword;
      }

      // 嘗試其他常見的參數名稱
      final drugCode =
          uri.queryParameters['drugCode'] ??
          uri.queryParameters['code'] ??
          uri.queryParameters['id'];
      if (drugCode != null && drugCode.isNotEmpty) {
        return drugCode;
      }

      // 如果 URL 路徑最後一段看起來像藥品代碼
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final lastSegment = pathSegments.last;
        // 藥品代碼通常是英數字組合
        if (RegExp(r'^[A-Za-z0-9]+$').hasMatch(lastSegment)) {
          return lastSegment;
        }
      }

      debugPrint('無法從 URL 解析藥品代碼: $qrCodeData');
      return null;
    } catch (e) {
      debugPrint('解析 QR Code 失敗: $e');
      return null;
    }
  }

  // ============================================================
  // 使用 OpenAI Vision API 辨識處方箋圖片
  // ============================================================
  Future<Map<String, dynamic>> recognizePrescriptionImage(
    File imageFile,
  ) async {
    try {
      if (_apiKey.isEmpty) {
        throw Exception('OpenAI API Key 未設定');
      }

      // 讀取圖片並轉換為 Base64
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final mimeType = _getMimeType(imageFile.path);

      debugPrint('開始辨識處方箋圖片...');

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': _prescriptionPrompt},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:$mimeType;base64,$base64Image',
                    'detail': 'high',
                  },
                },
              ],
            },
          ],
          'max_tokens': 4096,
          'temperature': 0.1,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;

        // 解析 JSON 回應
        return _parseAIResponse(content);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception('API 錯誤: ${errorData['error']['message']}');
      }
    } catch (e) {
      debugPrint('辨識處方箋失敗: $e');
      rethrow;
    }
  }

  // ============================================================
  // 批次辨識多張處方箋圖片
  // ============================================================
  Future<List<PrescriptionMedicine>> recognizeMultipleImages(
    List<File> imageFiles,
  ) async {
    final List<PrescriptionMedicine> allMedicines = [];

    for (int i = 0; i < imageFiles.length; i++) {
      debugPrint('辨識第 ${i + 1}/${imageFiles.length} 張圖片...');

      try {
        final result = await recognizePrescriptionImage(imageFiles[i]);

        if (result.containsKey('medicines')) {
          final medicinesList = result['medicines'] as List<dynamic>;
          for (final medicineData in medicinesList) {
            final medicine = PrescriptionMedicine.fromJson(
              medicineData as Map<String, dynamic>,
            );
            allMedicines.add(medicine);
          }
        }
      } catch (e) {
        debugPrint('辨識第 ${i + 1} 張圖片失敗: $e');
        // 繼續處理下一張
      }
    }

    return allMedicines;
  }

  // ============================================================
  // 從 Uint8List 辨識圖片（用於相機預覽）
  // ============================================================
  Future<Map<String, dynamic>> recognizePrescriptionFromBytes(
    Uint8List imageBytes,
  ) async {
    try {
      if (_apiKey.isEmpty) {
        throw Exception('OpenAI API Key 未設定');
      }

      final base64Image = base64Encode(imageBytes);

      debugPrint('開始辨識處方箋圖片（從記憶體）...');

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': _prescriptionPrompt},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image',
                    'detail': 'high',
                  },
                },
              ],
            },
          ],
          'max_tokens': 4096,
          'temperature': 0.1,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        return _parseAIResponse(content);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception('API 錯誤: ${errorData['error']['message']}');
      }
    } catch (e) {
      debugPrint('辨識處方箋失敗: $e');
      rethrow;
    }
  }

  // ============================================================
  // 解析 AI 回應
  // ============================================================
  Map<String, dynamic> _parseAIResponse(String content) {
    try {
      // 移除可能的 markdown 程式碼區塊標記
      String jsonString = content.trim();
      if (jsonString.startsWith('```json')) {
        jsonString = jsonString.substring(7);
      } else if (jsonString.startsWith('```')) {
        jsonString = jsonString.substring(3);
      }
      if (jsonString.endsWith('```')) {
        jsonString = jsonString.substring(0, jsonString.length - 3);
      }
      jsonString = jsonString.trim();

      final result = jsonDecode(jsonString) as Map<String, dynamic>;
      debugPrint('成功解析 AI 回應');
      return result;
    } catch (e) {
      debugPrint('解析 AI 回應失敗: $e');
      debugPrint('原始回應: $content');
      return {'error': '無法解析 AI 回應', 'rawContent': content, 'confidence': 0.0};
    }
  }

  // ============================================================
  // 取得 MIME 類型
  // ============================================================
  String _getMimeType(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  // ============================================================
  // 儲存處方箋到 Firestore
  // ============================================================
  Future<String> savePrescription(Prescription prescription) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('用戶未登入');
    }

    try {
      final docRef = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('prescriptions')
          .add(prescription.toFirestore());

      debugPrint('處方箋已儲存: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('儲存處方箋失敗: $e');
      rethrow;
    }
  }

  // ============================================================
  // 將處方箋藥品轉換為用藥模型
  // ============================================================
  Future<List<medicine>> convertToMedications(
    List<PrescriptionMedicine> prescriptionMedicines,
    MealTimeSettings mealTimeSettings, {
    Map<int, String>? sources,
  }) async {
    final List<medicine> medications = [];

    for (int i = 0; i < prescriptionMedicines.length; i++) {
      final pm = prescriptionMedicines[i];
      // 計算服用時間
      final reminderTimes = mealTimeSettings.calculateReminderTimes(
        timing: pm.timing,
        frequency: pm.frequency,
      );

      // 解析每次劑量
      int pillsPerDose = 1;
      final dosageMatch = RegExp(r'(\d+)').firstMatch(pm.dosage);
      if (dosageMatch != null) {
        pillsPerDose = int.tryParse(dosageMatch.group(1)!) ?? 1;
      }

      final medName = (pm.name.isNotEmpty)
          ? pm.name
          : (pm.englishName ?? pm.name);
      final med = medicine(
        name: medName,
        dosage: '${pm.dosage} ${pm.unit}',
        unit: pm.unit,
        total_supply: pm.totalQuantity,
        total_pills: pillsPerDose,
        frequency: pm.frequency,
        times_of_day_list: reminderTimes,
        times_status: List<bool>.filled(reminderTimes.length, false),
        instruction: pm.timing,
        route: pm.route,
        remaining_days: pm.durationDays,
        start_date: pm.startDate,
        duration_days: pm.durationDays,
        reminderEnabled: true,
        source: sources?[i],
        clinicalUse: pm.clinicalUse,
        sideEffects: pm.sideEffects,
        precautions: pm.precautions,
        storageMethod: pm.storageMethod,
        appearance: pm.appearance,
      );

      medications.add(med);
    }

    return medications;
  }

  // ============================================================
  // 儲存用藥到 Firestore
  // ============================================================
  Future<void> saveMedications(List<medicine> medications) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('用戶未登入');
    }

    final batch = _firestore.batch();
    final medicineCollection = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('medicine');

    for (final med in medications) {
      final docRef = medicineCollection.doc();
      batch.set(docRef, med.toFirestore());
    }

    await batch.commit();
    debugPrint('已儲存 ${medications.length} 種藥品');
  }

  // ============================================================
  // 用餐時間設定管理
  // ============================================================
  static const String _mealTimeSettingsKey = 'meal_time_settings';

  Future<MealTimeSettings> loadMealTimeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_mealTimeSettingsKey);

      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return MealTimeSettings.fromJson(json);
      }
    } catch (e) {
      debugPrint('載入用餐時間設定失敗: $e');
    }

    return MealTimeSettings(); // 回傳預設值
  }

  Future<void> saveMealTimeSettings(MealTimeSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _mealTimeSettingsKey,
        jsonEncode(settings.toJson()),
      );
      debugPrint('用餐時間設定已儲存');
    } catch (e) {
      debugPrint('儲存用餐時間設定失敗: $e');
      rethrow;
    }
  }

  // ============================================================
  // 查詢醫院藥品資訊（可選，需要醫院開放 API）
  // ============================================================
  Future<Map<String, dynamic>?> fetchDrugInfo(
    String drugCode, {
    String hospital = 'cgmh', // 預設長庚
  }) async {
    try {
      // 長庚醫院藥品查詢（這是示範，實際上需要確認 API 是否開放）
      if (hospital == 'cgmh') {
        final url =
            'https://www.cgmh.org.tw/tw/Services/DrugSearch?keyword=$drugCode';

        // 注意：這裡只是示範，實際上可能需要解析 HTML 或使用正式 API
        debugPrint('查詢藥品資訊: $url');

        // 目前先回傳 null，表示不使用外部 API
        return null;
      }

      return null;
    } catch (e) {
      debugPrint('查詢藥品資訊失敗: $e');
      return null;
    }
  }
}
