import 'medication_adherence.dart';
import '../utils/plain_ai_text.dart';
import '../repositories/health_context_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'ai_service.dart';

/// 健康 AI 分析器
/// 負責從 Firestore 撈取用戶資料並生成 AI 健康建議
class HealthAIAnalyzer {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AIService _aiService = AIService.instance;

  /// System Prompt - 定義 AI 的角色和回應格式
  static const String _systemPrompt = '''
你是健康管理AI助手。請用繁體中文回應。

【重要規則】
1. 你必須在回應中直接引用用戶提供的具體數值
2. 如果有數據，必須說出具體數字（例如：「您的平均血壓為125/82 mmHg」）
3. 如果某項沒有數據，明確說明「目前沒有此項紀錄」
4. 不要使用Markdown符號（如 # * -）

【回應格式】
📊 資料摘要
列出你收到的所有具體數值（血壓平均值、血糖平均值、體重變化、飲食熱量等）

💓 血壓分析
引用具體血壓數值，說明是否正常，給出建議

🩸 血糖分析
引用具體血糖數值，說明是否正常，給出建議

⚖️ 體重分析
引用具體體重數值與變化，給出建議

🍽️ 飲食分析
引用飲食紀錄筆數、總熱量、最近食物等，評估飲食習慣是否均衡，給出建議

💊 用藥情況
依提供的應服時段與最終狀態說明用藥紀錄；資料不完整時不得推算依從率百分比

🎯 行動建議
根據上述數據（包含飲食），提出3點具體可執行的建議

提醒：以上僅供參考，請諮詢專業醫師。
''';

  /// 取得用戶的健康分析報告
  Future<String> getHealthAnalysis() async {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      throw Exception('請先登入以取得健康分析');
    }

    // 檢查 API Key 是否已設定
    if (!_aiService.isConfigured) {
      throw Exception('AI 功能尚未設定，請聯繫管理員');
    }

    // 收集用戶資料
    final userData = await _collectUserData(uid);
    if (_auth.currentUser?.uid != uid) throw StateError('帳號已變更，請重新分析。');

    // 組合 prompt
    final prompt = _buildPrompt(userData);

    // 呼叫 AI 取得分析結果
    final response = await _aiService.generateResponse(prompt);
    if (_auth.currentUser?.uid != uid) throw StateError('帳號已變更。');

    // 清理回應中的 Markdown 格式
    return _cleanMarkdown(response);
  }

  /// 清理 Markdown 格式符號
  String _cleanMarkdown(String text) => plainAIText(text);

  /// 收集用戶所有健康相關資料
  late final _contextRepository = HealthContextRepository(_firestore);
  Future<Map<String, dynamic>> _collectUserData(String uid) => _contextRepository.collect(uid);

  /// 解析健康紀錄中的數值
  /// 資料格式: {category: '血壓', value: '120/80', unit: 'mmHg', ...}
  Map<String, dynamic> _parseHealthRecord(Map<String, dynamic> record) {
    final category = record['category'] as String? ?? '';
    final value = record['value'] as String? ?? '';

    int? systolic, diastolic, glucose;
    double? weight;

    switch (category) {
      case '血壓':
        final bpMatch = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(value);
        if (bpMatch != null) {
          systolic = int.tryParse(bpMatch.group(1)!);
          diastolic = int.tryParse(bpMatch.group(2)!);
        }
        break;
      case '血糖':
        final glucoseMatch = RegExp(r'(\d+)').firstMatch(value);
        if (glucoseMatch != null) {
          glucose = int.tryParse(glucoseMatch.group(1)!);
        }
        break;
      case '體重':
        final weightMatch = RegExp(r'([\d.]+)').firstMatch(value);
        if (weightMatch != null) {
          weight = double.tryParse(weightMatch.group(1)!);
        }
        break;
    }

    return {
      'category': category,
      'value': value,
      'systolic': systolic,
      'diastolic': diastolic,
      'glucose': glucose,
      'weight': weight,
      'record_time': record['record_time'],
    };
  }

  /// 組建發送給 AI 的完整 prompt
  String _buildPrompt(Map<String, dynamic> userData) {
    final buffer = StringBuffer();

    // 加入 system prompt
    buffer.writeln(_systemPrompt);
    buffer.writeln('\n---\n');
    buffer.writeln('用戶健康資料：\n');

    // 個人資料
    final profile = userData['profile'] as Map<String, dynamic>?;
    if (profile != null) {
      buffer.writeln('【基本資料】');
      buffer.writeln('姓名：${profile['fullName'] ?? '未提供'}');
      buffer.writeln('性別：${profile['gender'] ?? '未提供'}');
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
        }
      }
      if (profile['allergies'] != null &&
          profile['allergies'].toString().isNotEmpty) {
        buffer.writeln('過敏史：${profile['allergies']}');
      }
      buffer.writeln();
    }

    // 健康紀錄 - 使用正確的解析方式
    final healthRecords =
        userData['healthRecords'] as List<Map<String, dynamic>>? ?? [];

    if (healthRecords.isNotEmpty) {
      buffer.writeln('【近30天健康紀錄】');

      // 解析所有紀錄
      final parsedRecords = healthRecords.map(_parseHealthRecord).toList();

      // 血壓數據
      final bpRecords = parsedRecords
          .where((r) => r['systolic'] != null && r['diastolic'] != null)
          .toList();
      if (bpRecords.isNotEmpty) {
        buffer.writeln('\n血壓紀錄（${bpRecords.length} 筆）：');
        for (var record in bpRecords.take(5)) {
          final time = _formatTimestamp(record['record_time']);
          buffer.writeln('$time: ${record['systolic']}/${record['diastolic']} mmHg');
        }

        // 計算平均值
        final sysList = bpRecords.map((r) => r['systolic'] as int).toList();
        final diaList = bpRecords.map((r) => r['diastolic'] as int).toList();
        final avgSys = (sysList.reduce((a, b) => a + b) / sysList.length).round();
        final avgDia = (diaList.reduce((a, b) => a + b) / diaList.length).round();
        buffer.writeln('平均血壓：$avgSys/$avgDia mmHg');
      } else {
        buffer.writeln('\n血壓紀錄：無數據');
      }

      // 血糖數據
      final glucoseRecords = parsedRecords
          .where((r) => r['glucose'] != null)
          .toList();
      if (glucoseRecords.isNotEmpty) {
        buffer.writeln('\n血糖紀錄（${glucoseRecords.length} 筆）：');
        for (var record in glucoseRecords.take(5)) {
          final time = _formatTimestamp(record['record_time']);
          buffer.writeln('$time: ${record['glucose']} mg/dL');
        }

        // 計算平均值
        final glucoseList = glucoseRecords.map((r) => r['glucose'] as int).toList();
        final avgGlucose = (glucoseList.reduce((a, b) => a + b) / glucoseList.length).round();
        buffer.writeln('平均血糖：$avgGlucose mg/dL');
      } else {
        buffer.writeln('\n血糖紀錄：無數據');
      }

      // 體重數據
      final weightRecords = parsedRecords
          .where((r) => r['weight'] != null)
          .toList();
      if (weightRecords.isNotEmpty) {
        buffer.writeln('\n體重紀錄（${weightRecords.length} 筆）：');
        final firstWeight = weightRecords.last['weight'] as double;
        final lastWeight = weightRecords.first['weight'] as double;
        buffer.writeln('最早紀錄：${firstWeight.toStringAsFixed(1)} kg');
        buffer.writeln('最新紀錄：${lastWeight.toStringAsFixed(1)} kg');
        final change = lastWeight - firstWeight;
        buffer.writeln('變化：${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} kg');
      } else {
        buffer.writeln('\n體重紀錄：無數據');
      }

      buffer.writeln();
    } else {
      buffer.writeln('【健康紀錄】');
      buffer.writeln('近30天內無健康紀錄數據\n');
    }

    // 藥物與用藥紀錄
    final medications =
        userData['medications'] as List<Map<String, dynamic>>? ?? [];

    if (medications.isNotEmpty) {
      buffer.writeln('【目前用藥】');
      for (var med in medications) {
        buffer.writeln('${med['name'] ?? '未命名藥物'}');
        if (med['frequency'] != null) {
          buffer.writeln('  頻率：${med['frequency']}');
        }
      }
      buffer.writeln();
    }

    buffer.writeln(calculateMedicationAdherence(userData).summary);

    // 飲食紀錄
    final dietRecords =
        userData['dietRecords'] as List<Map<String, dynamic>>? ?? [];
    if (dietRecords.isNotEmpty) {
      buffer.writeln('【近7天飲食紀錄】');
      buffer.writeln('共 ${dietRecords.length} 筆紀錄');

      // 統計各餐別
      final mealCounts = <String, int>{};
      int totalCalories = 0;
      int calorieCount = 0;

      for (var record in dietRecords) {
        final mealType = record['mealType'] ?? '其他';
        mealCounts[mealType] = (mealCounts[mealType] ?? 0) + 1;

        if (record['calories'] != null) {
          totalCalories += (record['calories'] as num).toInt();
          calorieCount++;
        }
      }

      mealCounts.forEach((type, count) {
        buffer.writeln('$type：$count 次');
      });

      if (calorieCount > 0) {
        buffer.writeln('已記錄熱量：$totalCalories 大卡（$calorieCount 筆）');
      }

      // 列出最近幾筆食物
      buffer.writeln('\n最近食物：');
      for (var record in dietRecords.take(5)) {
        buffer.writeln('${record['foodName'] ?? '未記錄'}');
      }
      buffer.writeln();
    } else {
      buffer.writeln('【飲食紀錄】');
      buffer.writeln('近7天內無飲食紀錄\n');
    }

    buffer.writeln('---\n');
    buffer.writeln('【重要指示】');
    buffer.writeln('請務必在你的回應中引用上述的具體數值。');
    buffer.writeln('例如：如果用戶平均血壓是125/82，你必須在回應中說「您的平均血壓為125/82 mmHg」。');
    buffer.writeln('如果某項沒有數據，請明確說「目前沒有XX紀錄」。');
    buffer.writeln('不要給出籠統的建議，要根據實際數據給出針對性建議。');

    return buffer.toString();
  }

  /// 格式化 Firestore Timestamp
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '未知時間';

    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      return '未知時間';
    }

    return DateFormat('MM/dd HH:mm').format(dateTime);
  }
}
