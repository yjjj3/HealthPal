import 'medication_history.dart';
// lib/services/prescription_scan_service.dart
// 處方箋智慧辨識服務

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'ai/ai_config.dart';
import '../models/ai/prescription_recognition.dart';
import 'prescription_medication_mapper.dart';
import 'ai/ai_client.dart';
import 'ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication_model.dart';
import '../models/prescription_model.dart';

class PrescriptionScanService {
  static final PrescriptionScanService _instance =
      PrescriptionScanService._internal();
  factory PrescriptionScanService({
    FirebaseFirestore? firestore,
    String? Function()? currentUid,
    AIClient? client,
    DateTime Function()? now,
  }) {
    if (firestore == null &&
        currentUid == null &&
        client == null &&
        now == null)
      return _instance;
    return PrescriptionScanService._internal(
      firestore: firestore,
      currentUid: currentUid,
      client: client,
      now: now,
    );
  }
  PrescriptionScanService._internal({
    FirebaseFirestore? firestore,
    String? Function()? currentUid,
    AIClient? client,
    DateTime Function()? now,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _uidProvider =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _client = client ?? AIConfig.client,
       _now = now ?? DateTime.now;
  final FirebaseFirestore _firestore;
  final String? Function() _uidProvider;
  final AIClient _client;
  final DateTime Function() _now;

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
      "route": "給藥途徑（如口服、外用，不明則為null）",
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
- 完全無法辨識時 medicines=[]、confidence=0、error="無法辨識藥品資訊"；成功時 error=null。不要猜測未知劑量、頻率或單位。
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
  ) async => recognizePrescriptionFromBytes(await imageFile.readAsBytes());

  // ============================================================
  // 批次辨識多張處方箋圖片
  // ============================================================
  Future<List<PrescriptionMedicine>> recognizeMultipleImages(
    List<File> imageFiles,
  ) async {
    final List<PrescriptionMedicine> allMedicines = [];

    for (int i = 0; i < imageFiles.length; i++) {
      debugPrint('辨識第 ${i + 1}/${imageFiles.length} 張圖片...');

      final result = await recognizePrescriptionImage(imageFiles[i]);
      allMedicines.addAll(
        (result['medicines'] as List).map(
          (m) => PrescriptionMedicine.fromJson(m as Map<String, dynamic>),
        ),
      );
    }

    return allMedicines;
  }

  // ============================================================
  // 從 Uint8List 辨識圖片（用於相機預覽）
  // ============================================================
  Future<Map<String, dynamic>> recognizePrescriptionFromBytes(
    Uint8List imageBytes,
  ) async {
    final image = validatedImage(imageBytes, detail: 'high');
    final content = await _client.complete(
      messages: [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _prescriptionPrompt},
            image,
          ],
        },
      ],
      maxTokens: 4096,
      temperature: 0.1,
      responseFormat: PrescriptionRecognition.responseFormat,
    );
    return PrescriptionRecognition.parse(content).data;
  }

  // ============================================================
  // 儲存處方箋到 Firestore
  // ============================================================
  Future<String> savePrescription(Prescription prescription) async {
    final uid = _uidProvider();
    if (uid == null) {
      throw Exception('用戶未登入');
    }

    try {
      final docRef = await _firestore
          .collection('users')
          .doc(uid)
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
  }) async => PrescriptionMedicationMapper.convert(
    prescriptionMedicines,
    mealTimeSettings,
    sources: sources,
  );

  // ============================================================
  // 儲存用藥到 Firestore
  // ============================================================
  List<medicine> prepareMedications(List<medicine> medications) => medications
      .map(
        (med) => med.copyWith(
          medicine_id:
              med.medicine_id ?? _firestore.collection('reserved').doc().id,
        ),
      )
      .toList();

  Future<List<medicine>> saveMedications(
    List<medicine> medications, {
    String? expectedUid,
    bool Function()? isActive,
  }) async {
    final uid = expectedUid ?? _uidProvider();
    bool active() =>
        uid != null && _uidProvider() == uid && (isActive?.call() ?? true);
    if (!active()) throw StateError('帳號或頁面已變更，請重新確認處方。');
    final prepared = prepareMedications(medications);
    final refs = prepared
        .map(
          (m) => _firestore
              .collection('users')
              .doc(uid)
              .collection('medicine')
              .doc(m.medicine_id),
        )
        .toList();
    if (refs.map((r) => r.id).toSet().length != refs.length) {
      throw StateError('藥品文件 ID 重複。');
    }
    if (prepared.isEmpty) {
      return [];
    }
    final ids = refs.map((r) => r.id).toList()..sort();
    final receiptRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('prescription_save_${ids.first}');
    final createdAt = _now();
    return _firestore.runTransaction((tx) async {
      final receipt = await tx.get(receiptRef);
      final snapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in refs) {
        snapshots.add(await tx.get(ref));
      }
      if (!active()) throw StateError('帳號或頁面已變更，處方未送出。');
      if (receipt.exists) {
        final recordedIds = receipt.data()?['medicine_ids'];
        if (recordedIds is! List ||
            recordedIds.length != ids.length ||
            List.generate(
              ids.length,
              (i) => recordedIds[i] == ids[i],
            ).contains(false)) {
          throw StateError('處方提交紀錄不一致，請核對用藥清單。');
        }
        if (!snapshots.every((s) => s.exists)) {
          throw StateError('此批處方已儲存，部分或全部藥品已刪除；重試不會重新新增，請核對用藥清單。');
        }
        return snapshots.map(medicine.fromFirestore).toList();
      }
      final receiptData = {
        'medicine_ids': ids,
        'committed_at': Timestamp.fromDate(createdAt),
      };
      if (snapshots.any((s) => s.exists)) {
        if (!snapshots.every((s) => s.exists)) {
          throw StateError('處方文件不完整，請核對用藥清單。');
        }
        // A commit may succeed while its acknowledgement is lost. Never
        // overwrite live stock/history when retrying the same reserved IDs.
        tx.set(receiptRef, receiptData);
        return snapshots.map(medicine.fromFirestore).toList();
      }
      tx.set(receiptRef, receiptData);
      for (var i = 0; i < prepared.length; i++) {
        tx.set(refs[i], medicationCreationData(prepared[i], createdAt));
      }
      return prepared;
    });
  }

  // ============================================================
  // 用餐時間設定管理
  // ============================================================
  static const String _mealTimeSettingsKey = 'meal_time_settings';

  Future<MealTimeSettings> loadMealTimeSettings() async {
    final owner = _uidProvider();
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = _uidProvider();
      if (uid == null || uid != owner) throw StateError('帳號已變更。');
      final jsonString = prefs.getString('${_mealTimeSettingsKey}_$uid');

      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        if (_uidProvider() != owner) throw StateError('帳號已變更。');
        return MealTimeSettings.fromJson(json);
      }
    } catch (e) {
      debugPrint('載入用餐時間設定失敗: $e');
    }

    return MealTimeSettings(); // 回傳預設值
  }

  Future<void> saveMealTimeSettings(
    MealTimeSettings settings, {
    String? expectedUid,
  }) async {
    final uid = expectedUid ?? _uidProvider();
    if (uid == null || uid != _uidProvider()) throw StateError('帳號已變更。');
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_uidProvider() != uid) throw StateError('帳號已變更。');
      await prefs.setString(
        '${_mealTimeSettingsKey}_$uid',
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
