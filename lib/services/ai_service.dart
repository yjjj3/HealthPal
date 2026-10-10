import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:dart_openai/dart_openai.dart';

/// AI 服務類別
/// 負責與 OpenAI ChatGPT API 通訊
class AIService {
  static AIService? _instance;
  bool _isInitialized = false;
  String? _apiKey;

  AIService._();

  /// 取得 AIService 單例
  static AIService get instance {
    _instance ??= AIService._();
    return _instance!;
  }

  /// 初始化 OpenAI
  void initialize() {
    if (_isInitialized) return;

    final apiKey = dotenv.env['OPENAI_API_KEY'];

    if (apiKey == null || apiKey.isEmpty || apiKey == 'your_openai_api_key_here') {
      throw Exception('請在 .env 檔案中設定有效的 OPENAI_API_KEY');
    }

    _apiKey = apiKey;
    OpenAI.apiKey = apiKey;
    _isInitialized = true;
  }

  /// 分析食物圖片並返回營養資訊（使用直接 HTTP 呼叫）
  /// [imageFile] 要分析的圖片檔案
  /// [mealType] 餐別（早餐/午餐/晚餐/點心）
  /// 回傳 AI 分析的營養資訊 JSON 字串
  Future<String> analyzeFood(File imageFile, String mealType) async {
    print('========== 圖片分析流程開始 ==========');
    print('⏱️ [1/6] 檢查 AI 服務初始化狀態...');

    if (!_isInitialized) {
      print('⚙️ AI 服務未初始化，正在初始化...');
      initialize();
    }
    print('✅ [1/6] AI 服務已初始化');

    try {
      // 讀取圖片並轉換為 base64
      print('⏱️ [2/6] 讀取圖片檔案...');
      print('   📁 檔案路徑: ${imageFile.path}');

      final fileExists = await imageFile.exists();
      print('   📄 檔案存在: $fileExists');

      if (!fileExists) {
        throw Exception('圖片檔案不存在');
      }

      final fileSize = await imageFile.length();
      print('   📊 檔案大小: ${(fileSize / 1024).toStringAsFixed(2)} KB');

      final bytes = await imageFile.readAsBytes();
      print('✅ [2/6] 圖片讀取完成，共 ${bytes.length} bytes');

      print('⏱️ [3/6] 轉換圖片為 Base64...');
      final base64Image = base64Encode(bytes);
      print('✅ [3/6] Base64 轉換完成，長度: ${base64Image.length} 字元');

      // 判斷圖片類型
      print('⏱️ [4/6] 判斷圖片類型...');
      final extension = imageFile.path.split('.').last.toLowerCase();
      String mimeType;
      switch (extension) {
        case 'png':
          mimeType = 'image/png';
          break;
        case 'gif':
          mimeType = 'image/gif';
          break;
        case 'webp':
          mimeType = 'image/webp';
          break;
        default:
          mimeType = 'image/jpeg';
      }
      print('✅ [4/6] 圖片類型: $mimeType (副檔名: $extension)');

      print('⏱️ [5/6] 發送請求到 OpenAI API...');
      print('   🤖 模型: gpt-4o-mini');
      print('   🍽️ 餐別: $mealType');
      print('   ⏳ 超時設定: 60 秒');
      print('📤 正在發送圖片到 OpenAI API...');

      // 使用直接 HTTP 呼叫以正確傳送圖片格式
      final requestBody = {
        'model': 'gpt-4o',
        'messages': [
          {
            'role': 'system',
            'content': '''你是一位專業的營養師，專門分析食物圖片並估算營養成分。
請用繁體中文回應。

首先判斷圖片中是否有食物或飲料。

如果圖片中【沒有食物或飲料】（例如：人物、風景、動物、物品、文字等），請回傳：
{
  "is_food": false,
  "error_message": "這張圖片似乎不是食物照片，請上傳食物或飲料的照片以進行營養分析。"
}

如果圖片中【有食物或飲料】，請分析並回傳：
{
  "is_food": true,
  "food_name": "所有食物名稱（多個食物用「、」分隔，例如：拿鐵咖啡、火腿三明治）",
  "estimated_calories": 數字（所有食物的總熱量，單位：大卡）,
  "protein_g": 數字（總蛋白質，單位：克）,
  "carbs_g": 數字（總碳水化合物，單位：克）,
  "fat_g": 數字（總脂肪，單位：克）,
  "fiber_g": 數字（總纖維，單位：克）,
  "health_score": 數字（1-10的健康評分，請根據下方標準嚴格評分）,
  "estimated_portion": "各食物份量（例如：咖啡1杯、三明治1份）",
  "category": "主要食物分類（主食/蛋白質/蔬菜/水果/點心/飲料/其他）",
  "suggestions": "簡短的飲食建議"
}

重要規則：
1. 必須先判斷是否為食物，is_food 欄位必填
2. estimated_portion 格式為「食物名+數量+量詞」，多個用「、」分隔
3. 量詞範例：份、個、碗、杯、片、隻、塊
4. 營養數值必須是所有食物加總後的總計
5. health_score 健康評分標準（請嚴格遵守，不要都給5分）：
   - 9-10分：純天然蔬果、低脂蛋白質、全穀類
   - 7-8分：均衡餐點、適量調味的健康食物
   - 5-6分：一般餐點、營養尚可但有改善空間
   - 3-4分：高油高鹽、加工食品、速食
   - 1-2分：純垃圾食物、高糖飲料、油炸零食

請只回傳 JSON，不要有其他文字。'''
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': '請分析這張食物圖片的營養成分。這是$mealType。'
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:$mimeType;base64,$base64Image',
                  'detail': 'low'  // 使用低解析度以加快處理
                }
              }
            ]
          }
        ],
        'max_tokens': 1000,
        'temperature': 0.3
      };

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('請求超時，請檢查網路連線後重試');
        },
      );

      print('✅ [5/6] 收到 OpenAI API 回應！');
      print('   📊 狀態碼: ${response.statusCode}');

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(response.body);
        final errorMessage = errorBody['error']?['message'] ?? '未知錯誤';
        print('❌ API 錯誤: $errorMessage');
        throw Exception('API 錯誤 (${response.statusCode}): $errorMessage');
      }

      print('⏱️ [6/6] 解析 API 回應...');
      final responseBody = jsonDecode(response.body);
      final content = responseBody['choices']?[0]?['message']?['content'];

      if (content == null || content.isEmpty) {
        print('❌ [6/6] 錯誤：AI 回應為空');
        throw Exception('AI 回應為空');
      }

      print('   📝 文字內容長度: ${content.length} 字元');
      print('✅ [6/6] 解析完成！');
      print('========== 圖片分析流程完成 ==========');
      print('✅ 圖片分析成功！');
      print('📋 分析結果: $content');
      return content;
    } catch (e) {
      print('========== 圖片分析流程失敗 ==========');
      print('❌ 圖片分析錯誤: $e');
      print('🔍 錯誤類型: ${e.runtimeType}');
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('timeout') || errorMsg.contains('超時')) {
        print('⏰ 判定為：超時錯誤');
        throw Exception('請求超時，請檢查網路連線後重試');
      }
      if (errorMsg.contains('401') || errorMsg.contains('api_key') || errorMsg.contains('api key') || errorMsg.contains('invalid_api_key')) {
        print('🔑 判定為：API Key 錯誤');
        throw Exception('API Key 無效，請確認您的 OPENAI_API_KEY 設定');
      }
      if (errorMsg.contains('429') || (errorMsg.contains('rate') && errorMsg.contains('limit'))) {
        print('🚫 判定為：請求限制錯誤');
        throw Exception('API 請求次數已達上限，請稍後再試');
      }
      if (errorMsg.contains('quota') || errorMsg.contains('insufficient') || errorMsg.contains('billing')) {
        print('💰 判定為：額度不足錯誤');
        throw Exception('API 額度不足，請檢查您的 OpenAI 帳戶餘額');
      }
      if (errorMsg.contains('403') || errorMsg.contains('access')) {
        print('🚫 判定為：存取權限錯誤');
        throw Exception('沒有權限使用此模型，請檢查您的 OpenAI 帳戶');
      }
      if (errorMsg.contains('network') || errorMsg.contains('connection') || errorMsg.contains('socket')) {
        print('🌐 判定為：網路錯誤');
        throw Exception('網路連線失敗，請檢查網路後重試');
      }
      print('❓ 判定為：未知錯誤');
      throw Exception('圖片分析失敗: ${e.toString()}');
    }
  }

  /// 發送訊息給 AI 並取得回應
  /// [prompt] 要發送的提示詞
  /// 回傳 AI 的回應文字
  Future<String> generateResponse(String prompt) async {
    if (!_isInitialized) {
      initialize();
    }

    try {
      final response = await OpenAI.instance.chat.create(
        model: 'gpt-4o',
        messages: [
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.system,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text(
                '你是一位專業的健康管理助手，專門協助慢性病患者進行日常健康管理。請使用繁體中文回應。',
              ),
            ],
          ),
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.user,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt),
            ],
          ),
        ],
        temperature: 0.7,
        maxTokens: 1500,
      );

      final content = response.choices.first.message.content;
      if (content == null || content.isEmpty) {
        throw Exception('AI 回應為空');
      }

      // 取得文字內容
      final textContent = content.first.text;
      if (textContent == null || textContent.isEmpty) {
        throw Exception('AI 回應為空');
      }

      return textContent;
    } catch (e) {
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('api_key') || errorMsg.contains('api key') || errorMsg.contains('invalid')) {
        throw Exception('API Key 無效，請確認您的 OPENAI_API_KEY 設定');
      }
      if (errorMsg.contains('rate') && errorMsg.contains('limit')) {
        throw Exception('API 請求次數已達上限，請稍後再試');
      }
      if (errorMsg.contains('quota') || errorMsg.contains('insufficient')) {
        throw Exception('API 額度不足，請檢查您的 OpenAI 帳戶餘額');
      }
      throw Exception('AI 服務暫時無法使用，請稍後再試');
    }
  }

  /// 根據食物名稱估算營養成分
  /// [foodName] 食物名稱
  /// [mealType] 餐別
  /// 回傳包含營養數值的 Map
  Future<Map<String, dynamic>?> estimateNutritionByName(
    String foodName,
    String mealType,
  ) async {
    if (!_isInitialized) {
      initialize();
    }

    try {
      final requestBody = {
        'model': 'gpt-4o',
        'messages': [
          {
            'role': 'system',
            'content': '''你是一位專業的營養師。根據食物名稱估算營養成分。

首先判斷輸入是否為真實的食物或飲料名稱。
- 如果不是食物（例如：亂碼、物品、地名、人名、抽象概念等），回傳：
  {"is_food": false, "error": "這不是食物名稱"}

- 如果是食物，請用繁體中文回應，只回傳 JSON 格式：
{
  "is_food": true,
  "calories": 數字（所有食物的總熱量，單位：大卡）,
  "protein": 數字（總蛋白質，單位：克）,
  "carbs": 數字（總碳水化合物，單位：克）,
  "fat": 數字（總脂肪，單位：克）,
  "portion": "各食物份量描述",
  "category": "主要食物分類",
  "health_score": 數字（1-10的健康評分）
}

重要規則：
1. 如果有多個食物（用「、」分隔），portion 格式為「食物名+數量+量詞」，多個用「、」分隔
   例如：輸入「拿鐵咖啡、薯條、餅乾」→ portion 為「拿鐵1杯、薯條1份、餅乾3片」
2. 如果只有單一食物，portion 格式為「數量+量詞」
   例如：輸入「漢堡」→ portion 為「1個」
3. 營養數值必須是所有食物加總後的總計
4. category 類別選項：主食/蛋白質/蔬菜/水果/點心/飲料/其他（如有多種，用「、」分隔）
5. health_score 健康評分標準：
   - 9-10分：純天然蔬果、低脂蛋白質、全穀類
   - 7-8分：均衡餐點、適量調味的健康食物
   - 5-6分：一般餐點、營養尚可但有改善空間
   - 3-4分：高油高鹽、加工食品、速食
   - 1-2分：純垃圾食物、高糖飲料、油炸零食
請只回傳 JSON，不要有其他文字。'''
          },
          {
            'role': 'user',
            'content': '請估算「$foodName」的營養成分。這是$mealType。'
          }
        ],
        'max_tokens': 300,
        'temperature': 0.3
      };

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('請求超時');
        },
      );

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['error']?['message'] ?? '未知錯誤');
      }

      final responseBody = jsonDecode(response.body);
      final content = responseBody['choices']?[0]?['message']?['content'];

      if (content == null || content.isEmpty) {
        return null;
      }

      // 清理 JSON（移除可能的 markdown 標記）
      String cleanedContent = content.toString().trim();
      if (cleanedContent.startsWith('```json')) {
        cleanedContent = cleanedContent.substring(7);
      }
      if (cleanedContent.startsWith('```')) {
        cleanedContent = cleanedContent.substring(3);
      }
      if (cleanedContent.endsWith('```')) {
        cleanedContent = cleanedContent.substring(0, cleanedContent.length - 3);
      }
      cleanedContent = cleanedContent.trim();

      final result = jsonDecode(cleanedContent) as Map<String, dynamic>;
      return result;
    } catch (e) {
      print('❌ 估算營養失敗: $e');
      rethrow;
    }
  }

  /// 多輪對話生成回應
  /// [messages] 對話歷史，包含 role 和 content
  Future<String> generateConversation(List<Map<String, String>> messages) async {
    if (!_isInitialized) {
      initialize();
    }

    try {
      final requestBody = {
        'model': 'gpt-4o',
        'messages': messages,
        'max_tokens': 1000,
        'temperature': 0.7,
      };

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          throw Exception('請求超時，請檢查網路連線後重試');
        },
      );

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(response.body);
        final errorMessage = errorBody['error']?['message'] ?? '未知錯誤';
        throw Exception('API 錯誤: $errorMessage');
      }

      final responseBody = jsonDecode(response.body);
      final content = responseBody['choices']?[0]?['message']?['content'];

      if (content == null || content.isEmpty) {
        throw Exception('AI 回應為空');
      }

      return content.toString();
    } catch (e) {
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('timeout') || errorMsg.contains('超時')) {
        throw Exception('請求超時，請檢查網路連線後重試');
      }
      if (errorMsg.contains('api_key') || errorMsg.contains('api key') || errorMsg.contains('invalid')) {
        throw Exception('API Key 無效，請確認您的 OPENAI_API_KEY 設定');
      }
      if (errorMsg.contains('rate') && errorMsg.contains('limit')) {
        throw Exception('API 請求次數已達上限，請稍後再試');
      }
      if (errorMsg.contains('quota') || errorMsg.contains('insufficient')) {
        throw Exception('API 額度不足，請檢查您的 OpenAI 帳戶餘額');
      }
      throw Exception('AI 服務暫時無法使用: ${e.toString()}');
    }
  }

  /// 檢查 API Key 是否已設定
  bool get isConfigured {
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    return apiKey != null &&
           apiKey.isNotEmpty &&
           apiKey != 'your_openai_api_key_here';
  }
}
