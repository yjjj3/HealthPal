// 修改 lib/services/openai_service.dart
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class OpenAIService {
  static final String? _apiKey = dotenv.env['OPENAI_API_KEY'];
  static const String _apiUrl = 'https://api.openai.com/v1/chat/completions';

  /// 專門為飲食分析設計的方法
  static Future<Map<String, dynamic>> analyzeFoodNutrition({
    required String foodName,
    String? portionSize,
    String? mealType,
    String? preparationMethod,
  }) async {
    try {
      print('🔍 呼叫 OpenAI API 分析食物: $foodName');
      
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
              'role': 'system',
              'content': '''
              你是一位專業的營養師和食物分析專家。請分析用戶提供的食物，返回以下 JSON 格式的營養資訊：
              
              {
                "food_name": "食物名稱",
                "estimated_calories": 數字,
                "protein_g": 數字,
                "carbs_g": 數字,
                "fat_g": 數字,
                "fiber_g": 數字,
                "sodium_mg": 數字,
                "health_score": 數字(1-10),
                "portion": "建議分量",
                "suggestions": ["建議1", "建議2", "建議3"],
                "alternatives": ["替代選擇1", "替代選擇2"],
                "warning": "如果有特殊警告"
              }
              
              注意：
              1. 使用繁體中文
              2. 所有數值都要合理估計
              3. 根據不同食物類型調整估計
              4. 提供實用的建議
              '''
            },
            {
              'role': 'user',
              'content': '''
              請分析以下食物的營養成分：
              
              食物名稱：$foodName
              餐別：${mealType ?? '未指定'}
              分量：${portionSize ?? '未指定'}
              烹調方式：${preparationMethod ?? '未指定'}
              
              請提供詳細的營養分析和健康建議。
              '''
            }
          ],
          'temperature': 0.3,
          'max_tokens': 500,
          'response_format': {'type': 'json_object'}
        }),
      ).timeout(const Duration(seconds: 30));

      print('📊 API 回應狀態碼: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];
        
        print('📄 API 回應內容: $content');
        
        // 解析 JSON
        final Map<String, dynamic> result = jsonDecode(content);
        
        // 添加額外資訊
        result['api_timestamp'] = DateTime.now().toIso8601String();
        result['requested_food'] = foodName;
        
        return result;
      } else if (response.statusCode == 401) {
        throw Exception('API 金鑰無效，請檢查 .env 檔案中的 OPENAI_API_KEY');
      } else if (response.statusCode == 429) {
        throw Exception('請求太頻繁，請稍後再試');
      } else {
        throw Exception('API 錯誤: ${response.statusCode}');
      }
    } on http.ClientException catch (e) {
      throw Exception('網路錯誤: $e');
    } on FormatException catch (e) {
      throw Exception('API 回應格式錯誤: $e');
    } catch (e) {
      throw Exception('分析失敗: $e');
    }
  }
}