import 'medication_adherence.dart';
import '../utils/plain_ai_text.dart';
import '../repositories/health_context_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ai_service.dart';

/// AI 小助手「小安」服務
/// 負責處理 AI 對話、讀取用戶健康資料並提供個人化建議
class AIAssistantService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AIService _aiService = AIService.instance;

  // 單例模式
  static final AIAssistantService _instance = AIAssistantService._internal();
  factory AIAssistantService() => _instance;
  AIAssistantService._internal();

  static AIAssistantService get instance => _instance;

  /// 小安的 System Prompt
  String _buildSystemPrompt(Map<String, dynamic> userData) {
    final buffer = StringBuffer();

    buffer.writeln('''
你是「小安」，一個友善、專業的健康管理 AI 助手。

【你的個性】
- 親切溫暖，像一個關心用戶的朋友
- 專業但不死板，用容易理解的語言解釋醫療知識
- 主動關心用戶的健康狀況
- 回答時適度使用表情符號讓對話更親切

【你的能力】
- 根據用戶的健康紀錄提供個人化建議
- 解答關於血壓、血糖、用藥、飲食的問題
- 提醒用戶注意健康數值異常
- 鼓勵用戶維持健康習慣

【重要規則】
1. 使用繁體中文回應
2. 回答要簡潔明瞭，適合手機閱讀（通常 2-4 段）
3. 如果涉及嚴重健康問題，務必建議用戶諮詢醫師
4. 引用用戶的實際健康數據時要說出具體數字
5. 不要使用 Markdown 格式（如 # * -）
6. 服藥依從率只能引用提供的完成率；若資料不完整，不得從操作日誌比例推算百分比

【用戶資料】
''');

    // 加入用戶個人資料
    final profile = userData['profile'] as Map<String, dynamic>?;
    if (profile != null) {
      buffer.writeln('姓名：${profile['fullName'] ?? '用戶'}');
      if (profile['gender'] != null) {
        buffer.writeln('性別：${profile['gender']}');
      }
      if (profile['age'] != null) {
        buffer.writeln('年齡：${profile['age']} 歲');
      }
      if (profile['height'] != null) {
        buffer.writeln('身高：${profile['height']} 公分');
      }
      if (profile['weight'] != null) {
        buffer.writeln('體重：${profile['weight']} 公斤');
      }
      if (profile['chronicDiseases'] != null) {
        final diseases = profile['chronicDiseases'];
        if (diseases is List && diseases.isNotEmpty) {
          buffer.writeln('慢性病史：${diseases.join('、')}');
        } else if (diseases is String && diseases.isNotEmpty) {
          buffer.writeln('慢性病史：$diseases');
        }
      }
      if (profile['allergies'] != null && profile['allergies'].toString().isNotEmpty) {
        buffer.writeln('過敏史：${profile['allergies']}');
      }
      buffer.writeln();
    }

    // 加入近期健康紀錄摘要
    final healthRecords = userData['healthRecords'] as List<Map<String, dynamic>>? ?? [];
    if (healthRecords.isNotEmpty) {
      buffer.writeln('【近期健康紀錄摘要】');

      // 解析血壓數據
      final bpRecords = healthRecords.where((r) => r['category'] == '血壓').toList();
      if (bpRecords.isNotEmpty) {
        final latestBp = bpRecords.first['value'];
        buffer.writeln('最新血壓：$latestBp mmHg');

        // 計算平均值
        int totalSys = 0, totalDia = 0, count = 0;
        for (var record in bpRecords.take(7)) {
          final match = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(record['value'] ?? '');
          if (match != null) {
            totalSys += int.parse(match.group(1)!);
            totalDia += int.parse(match.group(2)!);
            count++;
          }
        }
        if (count > 1) {
          buffer.writeln('近 $count 次平均：${(totalSys / count).round()}/${(totalDia / count).round()} mmHg');
        }
      }

      // 解析血糖數據
      final glucoseRecords = healthRecords.where((r) => r['category'] == '血糖').toList();
      if (glucoseRecords.isNotEmpty) {
        final latestGlucose = glucoseRecords.first['value'];
        buffer.writeln('最新血糖：$latestGlucose mg/dL');

        int total = 0, count = 0;
        for (var record in glucoseRecords.take(7)) {
          final match = RegExp(r'(\d+)').firstMatch(record['value'] ?? '');
          if (match != null) {
            total += int.parse(match.group(1)!);
            count++;
          }
        }
        if (count > 1) {
          buffer.writeln('近 $count 次平均：${(total / count).round()} mg/dL');
        }
      }

      // 解析體重數據
      final weightRecords = healthRecords.where((r) => r['category'] == '體重').toList();
      if (weightRecords.isNotEmpty) {
        final latestWeight = weightRecords.first['value'];
        buffer.writeln('最新體重：$latestWeight kg');
      }

      buffer.writeln();
    }

    // 加入用藥資訊
    final medications = userData['medications'] as List<Map<String, dynamic>>? ?? [];
    if (medications.isNotEmpty) {
      buffer.writeln('【目前用藥】');
      for (var med in medications.take(5)) {
        buffer.writeln('• ${med['name'] ?? '未命名藥物'} (${med['frequency'] ?? '頻率未知'})');
      }
      if (medications.length > 5) {
        buffer.writeln('...還有 ${medications.length - 5} 種藥物');
      }
      buffer.writeln();
    }

    buffer.writeln(calculateMedicationAdherence(userData).summary);

    // 加入飲食紀錄摘要
    final dietRecords = userData['dietRecords'] as List<Map<String, dynamic>>? ?? [];
    if (dietRecords.isNotEmpty) {
      buffer.writeln('【近期飲食】');
      buffer.writeln('共 ${dietRecords.length} 筆飲食紀錄');

      int totalCalories = 0;
      int calorieCount = 0;
      for (var record in dietRecords) {
        if (record['calories'] != null) {
          totalCalories += (record['calories'] as num).toInt();
          calorieCount++;
        }
      }
      if (calorieCount > 0) {
        buffer.writeln('已記錄熱量：$totalCalories 大卡');
      }

      // 列出最近幾筆食物
      final recentFoods = dietRecords.take(3).map((r) => r['foodName'] ?? '未記錄').join('、');
      buffer.writeln('最近吃的：$recentFoods');
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// 收集用戶健康資料
  late final _contextRepository = HealthContextRepository(_firestore);
  Future<Map<String, dynamic>> _collectUserData(String uid) => _contextRepository.collect(uid);
  Future<Map<String,dynamic>?> _getUserProfile(String uid) => _contextRepository.profile(uid);

  /// 發送訊息給小安並取得回應
  /// [message] 用戶的訊息
  /// [conversationHistory] 之前的對話歷史（可選）
  Future<String> sendMessage(String message, {List<Map<String, String>>? conversationHistory}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('請先登入以使用 AI 助手');
    }

    if (!_aiService.isConfigured) {
      throw Exception('AI 功能尚未設定，請聯繫管理員');
    }

    // 收集用戶健康資料
    final userData = await _collectUserData(uid);
    if (_auth.currentUser?.uid != uid) throw StateError('帳號已變更，請重新分析。');

    // 建立 system prompt
    final systemPrompt = _buildSystemPrompt(userData);

    // 組建對話訊息
    final messages = <Map<String, String>>[];

    // 加入 system prompt
    messages.add({
      'role': 'system',
      'content': systemPrompt,
    });

    // 加入對話歷史
    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      // 只保留最近 10 輪對話以控制 token 數量
      final recentHistory = conversationHistory.length > 20
          ? conversationHistory.sublist(conversationHistory.length - 20)
          : conversationHistory;
      messages.addAll(recentHistory);
    }

    // 加入當前用戶訊息
    messages.add({
      'role': 'user',
      'content': message,
    });

    // 呼叫 AI 服務
    try {
      final response = await _aiService.generateConversation(messages);
      if (_auth.currentUser?.uid != uid) throw StateError('帳號已變更。');
      return _cleanResponse(response);
    } catch (e) {
      print('❌ AI 回應失敗: $e');
      rethrow;
    }
  }

  /// 清理 AI 回應
  String _cleanResponse(String text) => plainAIText(text);

  /// 取得小安的歡迎訊息
  Future<String> getWelcomeMessage() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return '嗨！我是小安 👋\n你的專屬健康管理助手。\n\n有任何關於健康的問題都可以問我喔！';
    }

    try {
      final profile = await _getUserProfile(uid);
      final name = profile?['fullName'] ?? '朋友';

      return '嗨 $name！我是小安 👋\n\n我是你的專屬健康管理助手，我可以：\n\n'
          '💓 分析你的血壓、血糖趨勢\n'
          '💊 提醒你用藥注意事項\n'
          '🍽️ 給你飲食建議\n'
          '❓ 回答健康相關問題\n\n'
          '有什麼我可以幫你的嗎？';
    } catch (e) {
      return '嗨！我是小安 👋\n你的專屬健康管理助手。\n\n有任何關於健康的問題都可以問我喔！';
    }
  }

  /// 取得快速問題建議
  List<String> getQuickQuestions() {
    return [
      '我的血壓正常嗎？',
      '今天該吃什麼比較健康？',
      '最近我的健康狀況如何？',
      '我的用藥有什麼要注意的？',
    ];
  }
}
