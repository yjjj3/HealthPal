import '../models/ai/nutrition_analysis.dart';
import '../utils/data_error_message.dart';
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/ai_service.dart';
import '../theme/app_colors.dart';
import 'diet_log_screen.dart';

class DietScreen extends StatefulWidget {
  const DietScreen({super.key});

  @override
  State<DietScreen> createState() => _DietScreenState();
}

class _DietScreenState extends State<DietScreen> {
  String _selectedMealType = '早餐';
  final List<String> _mealTypes = ['早餐', '午餐', '晚餐', '點心'];
  bool _isAnalyzing = false;
  bool _isLoading = true;
  String? _dataError;
  Timer? _dayTimer;
  DateTime? _queryDay;
  List<Map<String, dynamic>> _dietRecords = [];
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 用於拍照功能
  final ImagePicker _imagePicker = ImagePicker();

  // 用於監聽資料流的訂閱
  StreamSubscription<QuerySnapshot>? _dietRecordsSubscription;
  Timer? _dietRetryTimer;
  int _dietListenerGeneration = 0;

  // 新增：用於控制分析流程
  Completer<void>? _analysisCompleter;
  Map<String, dynamic>? _currentAnalysisResult;

  // 非食物關鍵詞列表
  final List<String> _nonFoodKeywords = [
    // 常見物品
    '手機', '電腦', '電視', '書本', '筆記本', '紙', '筆', '鉛筆',
    '椅子', '桌子', '床', '門', '窗', '房子', '車', '汽車',
    '飛機', '火車', '船', '自行車', '摩托車',
    // 概念和抽象事物
    '愛情', '友情', '夢想', '希望', '快樂', '悲傷', '憤怒',
    '數學', '物理', '化學', '歷史', '地理', '科學', '哲學',
    // 自然現象
    '太陽', '月亮', '星星', '雲', '雨', '風', '雪', '雷',
    '彩虹', '天空', '海洋', '山', '河', '石頭', '土壤',
    // 動物（不是食物形式）
    '貓', '狗', '鳥', '魚(寵物)', '兔子', '倉鼠', '烏龜',
    // 其他
    '時間', '空間', '宇宙', '世界', '國家', '城市',
    '學校', '公司', '工作', '遊戲', '音樂', '電影', '電視劇',
    '衣服', '鞋子', '帽子', '包包', '眼鏡', '手錶',
    // 問候語和常見無意義輸入
    '你好', '哈囉', '嗨', '早安', '午安', '晚安', '謝謝', '再見',
    '好的', '是的', '不是', '什麼', '為什麼', '怎麼', '可以',
    'hello', 'hi', 'hey', 'thanks', 'bye', 'yes', 'no', 'ok', 'okay',
    // 英文對應詞
    'phone', 'computer', 'book', 'chair', 'table', 'bed',
    'car', 'plane', 'train', 'ship', 'bicycle', 'motorcycle',
    'love', 'dream', 'math', 'science', 'history', 'physics',
    'sun', 'moon', 'star', 'cloud', 'rain', 'wind', 'snow',
    'cat', 'dog', 'bird', 'fish(pet)', 'rabbit', 'turtle',
    'time', 'space', 'universe', 'world', 'school', 'work',
    'game', 'music', 'movie', 'clothes', 'shoes', 'hat'
  ];

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _startListeningToDietRecords();
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (mounted && _queryDay != today) _startListeningToDietRecords();
    });
  }

  @override
  void dispose() {
    // 取消訂閱以避免記憶體洩漏
    _dietListenerGeneration++;
    _dietRetryTimer?.cancel();
    _dayTimer?.cancel();
    _dietRecordsSubscription?.cancel();

    // 取消任何正在進行的分析
    if (_analysisCompleter?.isCompleted == false) {
      _analysisCompleter!.complete();
    }

    super.dispose();
  }

  void _initializeServices() async {
    try {
      // 初始化 AI 服務
      AIService.instance.initialize();
    } catch (_) {
      // AI 服務初始化失敗，靜默處理
    }

  }

  // 使用 Stream 監聽實時資料
  Future<void> _startListeningToDietRecords() async {
    final generation = ++_dietListenerGeneration;
    _dietRetryTimer?.cancel();
    final previous = _dietRecordsSubscription;
    _dietRecordsSubscription = null;
    await previous?.cancel();
    if (!mounted || generation != _dietListenerGeneration) return;
    final now = DateTime.now();
    _queryDay = DateTime(now.year, now.month, now.day);
    setState(() { _isLoading = true; _dataError = null; });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() { _dietRecords = []; _isLoading = false; _dataError = '請先登入'; });
        return;
      }

      // 監聽飲食紀錄的變化
      _dietRecordsSubscription = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('diet_records')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_queryDay!))
          .where('timestamp', isLessThan: Timestamp.fromDate(_queryDay!.add(const Duration(days: 1))))
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen(
            (QuerySnapshot snapshot) {

              // 處理資料前先檢查是否還有連接
              if (!mounted || generation != _dietListenerGeneration) return;

              try {
              final records = snapshot.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final timestamp = data['timestamp'] as Timestamp?;
                final foodName = data['foodName'] ?? '未命名食物';

                return {
                  'id': doc.id,
                  'mealType': data['mealType'] ?? _selectedMealType,
                  'foodName': foodName,
                  'calories': _safeParseInt(data['calories'] ?? 0),
                  'protein': _safeParseDouble(data['protein_g'] ?? 0.0),
                  'carbs': _safeParseDouble(data['carbs_g'] ?? 0.0),
                  'fat': _safeParseDouble(data['fat_g'] ?? 0.0),
                  'notes': data['suggestions'] ?? data['notes'] ?? '',
                  'timestamp': timestamp?.toDate() ?? DateTime.now(),
                  'portion':
                      data['estimatedPortion'] ??
                      data['estimated_portion'] ??
                      '一份',
                  'category': data['category'] ?? '其他',
                  'healthScore': _safeParseInt(data['healthScore'] ?? 5),
                };
              }).toList();

              if (mounted) {
                setState(() {
                  _dietRecords = records;
                  _isLoading = false;
                  _dataError = null;
                });


              }
              } catch (error) {
                setState(() { _isLoading = false; _dataError = dataErrorMessage(error); });
              }
            },
            onError: (Object error) {
              if (!mounted || generation != _dietListenerGeneration) return;
              setState(() { _isLoading = false; _dataError = dataErrorMessage(error); });
              // Permission errors need configuration changes, not endless retries.
              if (error is FirebaseException &&
                  error.code == 'permission-denied') {
                return;
              }
              _dietRetryTimer?.cancel();
              _dietRetryTimer = Timer(const Duration(seconds: 2), () {
                if (mounted && generation == _dietListenerGeneration) {
                  _startListeningToDietRecords();
                }
              });
            },
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _dataError = dataErrorMessage(e);
        });
      }
    }
  }

  // 安全的整數解析函式
  int _safeParseInt(dynamic value, {int defaultValue = 0}) {
    try {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is double) return value.round();
      if (value is String) {
        // 移除可能的單位
        String cleanValue = value.replaceAll(RegExp(r'[^0-9\.]'), '');
        return int.tryParse(cleanValue) ?? defaultValue;
      }
      return defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  // 安全的浮點數解析函式
  double _safeParseDouble(dynamic value, {double defaultValue = 0.0}) {
    try {
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) {
        // 移除可能的單位
        String cleanValue = value.replaceAll(RegExp(r'[^0-9\.]'), '');
        return double.tryParse(cleanValue) ?? defaultValue;
      }
      return defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  // ==================== AI 分析功能 ====================

  // 檢查是否為食物輸入
  bool _isFoodInput(String input) {
    if (input.trim().isEmpty) return false;

    final lowerInput = input.toLowerCase().trim();

    // 檢查是否為純數字或過短
    if (RegExp(r'^[0-9\s]+$').hasMatch(lowerInput) || lowerInput.length < 2) {
      return false;
    }

    // 檢查是否包含明顯的非食物關鍵詞
    for (var keyword in _nonFoodKeywords) {
      if (lowerInput.contains(keyword.toLowerCase())) {
        return false;
      }
    }

    // 放寬驗證：只要不是明顯的非食物，就讓 AI 來判斷
    // AI 會在 estimateNutritionByName 中判斷是否為真實食物
    return true;
  }

  Future<void> _performAIAnalysis(
    BuildContext context,
    String foodName,
    String mealType,
  ) async {
    // 檢查是否為食物
    if (!_isFoodInput(foodName)) {
      _showNonFoodDialog(
        '「$foodName」不是食物名稱。\n請輸入真實的食物或飲料名稱。',
        allowRetry: true,
      );
      return;
    }

    if (_isAnalyzing) return;

    if (!mounted) return;
    setState(() => _isAnalyzing = true);
    final session = Completer<void>();
    _analysisCompleter = session;

    // 顯示分析中的對話框
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (context) {
        return PopScope(
          canPop: false,
          onPopInvoked: (didPop) {
            if (didPop) return;
            // 如果用戶嘗試手動關閉，顯示提示
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('分析中，請稍候...'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          child: StatefulBuilder(
            builder: (context, setState) {
              return _buildAnalyzingDialog(context, foodName, mealType, () {
                // 手動關閉按鈕
                _closeAnalysisDialog();
              });
            },
          ),
        );
      },
    );

    try {
      // 檢查 AI 服務是否可用
      if (!AIService.instance.isConfigured) {
        throw Exception('請先設定 OpenAI API 金鑰');
      }

      // 準備提示詞 - 嚴格檢查是否為食物
      final response = await AIService.instance.analyzeFoodByName(foodName, mealType);

      if (!mounted || !identical(_analysisCompleter, session) || !_isAnalyzing) return;
      // 解析 AI 回應
      _currentAnalysisResult = _parseAIResponse(response, foodName, mealType);

      // 檢查是否為非食物
      final isFood = _currentAnalysisResult!['is_food'];
      if (isFood == false || isFood == 'false') {
        // 先取出錯誤訊息，再關閉對話框（因為 _closeAnalysisDialog 會把 _currentAnalysisResult 設為 null）
        final errorMsg = _currentAnalysisResult!['error_message'] ??
            '「$foodName」不是食物名稱，請輸入真實的食物或飲料。';
        if (mounted) {
          _closeAnalysisDialog();
          _showNonFoodDialog(errorMsg, allowRetry: true);
        }
        return;
      }

      // 如果是食物，先保存結果，再關閉分析中對話框，然後顯示結果讓用戶確認
      final analysisResult = Map<String, dynamic>.from(_currentAnalysisResult!);
      _closeAnalysisDialog();
      _showTextAnalysisResult(analysisResult, foodName, mealType);
    } on TimeoutException catch (_) {
      if (mounted && identical(_analysisCompleter, session) && _isAnalyzing) {
        _closeAnalysisDialog();
        _showErrorDialog(this.context, '分析超時，請檢查網路連線後重試');
      }
    } catch (e) {
      if (mounted && identical(_analysisCompleter, session) && _isAnalyzing) {
        _closeAnalysisDialog();
        _showErrorDialog(this.context, e.toString());
      }
    } finally {
      if (!session.isCompleted) session.complete();
      if (identical(_analysisCompleter, session)) _analysisCompleter = null;

      // Result confirmation manages its own dialog lifecycle.
    }
  }

  // 關閉分析對話框
  void _closeAnalysisDialog() {
    if (context.mounted) {
      // 無論 _isAnalyzing 狀態如何，都嘗試關閉對話框
      if (_isAnalyzing) {
        try {
          Navigator.of(context).pop();
        } catch (_) {
          // 對話框可能已關閉，靜默處理
        }
      }
      setState(() => _isAnalyzing = false);
      _currentAnalysisResult = null;
    }
  }

  Widget _buildAnalyzingDialog(
    BuildContext context,
    String foodName,
    String mealType,
    VoidCallback onCancel,
  ) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '正在分析食物熱量...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              foodName,
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '餐別：$mealType',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '分析中...',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              '飲食記錄新增後將自動關閉',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            // 手動關閉按鈕
            OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: const Text('取消分析', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Map<String,dynamic> _parseAIResponse(String response, String foodName, String mealType) =>
      {...NutritionAnalysis.parse(response).toJson(), 'meal_type': mealType};

  Future<void> _addMealFromAnalysis(
    Map<String, dynamic> result,
    String foodName,
    String mealType,
  ) async {
    try {

      // 使用安全的解析函式確保數值正確
      final calories = _safeParseInt(result['estimated_calories']);
      final protein = _safeParseDouble(result['protein_g']);
      final carbs = _safeParseDouble(result['carbs_g']);
      final fat = _safeParseDouble(result['fat_g']);
      final healthScore = _safeParseInt(
        result['health_score'],
        defaultValue: 5,
      );


      // 準備要儲存到 Firestore 的資料
      final recordData = {
        'foodName': foodName,
        'mealType': mealType,
        'calories': calories,
        'protein_g': protein,
        'carbs_g': carbs,
        'fat_g': fat,
        'healthScore': healthScore,
        'suggestions': result['suggestions']?.toString() ?? '',
        'estimatedPortion': result['estimated_portion']?.toString() ?? '一份',
        'category': result['category']?.toString() ?? '其他',
        'notes': result['suggestions']?.toString() ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      };


      final user = _auth.currentUser;
      if (user != null) {
        // 儲存到 Firestore
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('diet_records')
            .add(recordData);
        // The snapshot listener updates data; dialogs are owned by their action.
      } else {
        // 用戶未登入，使用本地儲存
        _addToLocalMemory(result, foodName, mealType);
      }
    } catch (error) {
      rethrow; // 重新拋出錯誤，讓上層處理
    }
  }

  void _addToLocalMemory(
    Map<String, dynamic> result,
    String foodName,
    String mealType,
  ) {
    final calories = _safeParseInt(result['estimated_calories']);
    final protein = _safeParseDouble(result['protein_g']);
    final carbs = _safeParseDouble(result['carbs_g']);
    final fat = _safeParseDouble(result['fat_g']);
    final healthScore = _safeParseInt(result['health_score'], defaultValue: 5);

    final newRecord = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'mealType': mealType,
      'foodName': foodName,
      'timestamp': DateTime.now(),
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'notes': result['suggestions'] ?? '',
      'portion': result['estimated_portion'] ?? '一份',
      'category': result['category'] ?? '其他',
      'healthScore': healthScore,
    };

    setState(() {
      _dietRecords.insert(0, newRecord);
      _selectedMealType = mealType;
    });

    // 新增：本地儲存成功後也關閉對話框
    if (_isAnalyzing && context.mounted) {
      _closeAnalysisDialog();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已新增 $foodName 為 $mealType（本地儲存）'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // 顯示錯誤對話框
  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('分析失敗'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('關閉'),
            ),

          ],
        );
      },
    );
  }

  // 顯示非食物照片提示對話框
  void _showNotFoodDialog(String message) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 圖示
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.no_photography_outlined,
                  color: Colors.orange.shade600,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              // 標題
              const Text(
                '似乎不是食物照片',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // 訊息
              Text(
                '無法從照片中辨識出食物',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              // 提示
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '拍攝小技巧：',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• 確保食物在畫面中清晰可見\n• 光線充足，避免過暗或過曝\n• 避免拍攝風景、人物等非食物',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // 按鈕
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '我知道了',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 顯示非食物輸入對話框
  void _showNonFoodDialog(String message, {bool allowRetry = true}) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 圖示
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.no_food_outlined,
                  color: Colors.orange.shade600,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              // 標題
              const Text(
                '無法辨識為食物',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // 訊息
              Text(
                '請輸入真實的食物或飲料名稱',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              // 範例提示
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '例如：拉麵、雞排、珍珠奶茶、蛋糕',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 按鈕
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    if (allowRetry) {
                      _showAIAnalysisDialog(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '重新輸入',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== 拍照分析功能 ====================

  /// 顯示選擇圖片來源的對話框
  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '拍照分析食物營養',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '選擇圖片來源',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildImageSourceOption(
                      icon: Icons.camera_alt,
                      label: '拍照',
                      color: AppColors.primary,
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.camera);
                      },
                    ),
                    _buildImageSourceOption(
                      icon: Icons.photo_library,
                      label: '從相簿選擇',
                      color: AppColors.success,
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 選擇圖片（相機或相簿）
  Future<void> _pickImage(ImageSource source) async {

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800, // 縮小尺寸避免記憶體問題
        maxHeight: 800,
        imageQuality: 70, // 降低品質加快處理
      );

      if (pickedFile != null && mounted) {
        final imageFile = File(pickedFile.path);

        // 確認檔案存在
        final exists = await imageFile.exists();

        if (exists) {
          // 延遲一點再顯示對話框，確保 UI 更新完成
          await Future.delayed(const Duration(milliseconds: 100));

          if (mounted) {
            _showImageAnalysisDialog(imageFile);
          } else {
          }
        } else {
          throw Exception('圖片檔案不存在');
        }
      } else {
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('選擇圖片失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 顯示圖片分析對話框
  void _showImageAnalysisDialog(File imageFile) {

    String selectedMealType = _selectedMealType;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.restaurant, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('分析食物照片'),
                ],
              ),
              content: SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 圖片預覽 - 使用 4:3 比例，適合大多數食物照片
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Image.file(
                            imageFile,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey.shade100,
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                      SizedBox(height: 8),
                                      Text('圖片載入失敗', style: TextStyle(color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 餐別選擇
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: '餐別',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.schedule),
                          isDense: true,
                        ),
                        value: selectedMealType,
                        isExpanded: true,
                        items: _mealTypes.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Row(
                              children: [
                                Icon(_getMealIcon(type), size: 20),
                                const SizedBox(width: 8),
                                Text(type),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedMealType = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'AI 將分析圖片中的食物，如果不是食物將不會進行分析',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('開始分析'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _analyzeImage(imageFile, selectedMealType);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 執行圖片分析
  Future<void> _analyzeImage(File imageFile, String mealType) async {

    if (!mounted || _isAnalyzing) return;
    setState(() => _isAnalyzing = true);

    // 顯示分析中對話框（帶動畫效果）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _AnalyzingDialog(mealType: mealType);
      },
    );

    try {

      // 呼叫 AI 服務分析圖片
      final response = await AIService.instance.analyzeFood(
        imageFile,
        mealType,
      );

      if (!mounted) return;
      // 解析回應
      final result = _parseAIResponse(response, '圖片食物', mealType);

      // 關閉分析中對話框
      if (mounted) {
        Navigator.pop(context);
      }

      // 檢查是否為非食物照片
      final isFood = result['is_food'];
      
      if (isFood == false || isFood == 'false') {
        setState(() => _isAnalyzing = false);
        
        final errorMessage = result['error_message']?.toString() ??
            result['suggestions']?.toString() ??
            '無法辨識此圖片中的食物，請確認照片中有清晰可見的食物或飲料。';
        
        if (mounted) {
          _showNotFoodDialog(errorMessage);
        }
        return;
      }

      setState(() => _isAnalyzing = false);
      // 顯示分析結果
      if (mounted) {
        _showImageAnalysisResult(imageFile, result, mealType);
      }
    } catch (e) {
      if (!mounted) return;

      // 關閉分析中對話框
      if (mounted) {
        Navigator.pop(context);
      }

      setState(() => _isAnalyzing = false);

      if (mounted) {
        _showErrorDialog(context, '圖片分析失敗: $e');
      }
    }
  }

  /// 顯示圖片分析結果
  void _showImageAnalysisResult(
    File imageFile,
    Map<String, dynamic> result,
    String mealType,
  ) {
    final foodName = result['food_name']?.toString() ?? '未識別食物';
    final calories = _safeParseInt(result['estimated_calories']);
    final protein = _safeParseDouble(result['protein_g']);
    final carbs = _safeParseDouble(result['carbs_g']);
    final fat = _safeParseDouble(result['fat_g']);
    final healthScore = _safeParseInt(result['health_score'], defaultValue: 5);
    final suggestions = result['suggestions']?.toString() ?? '';
    final portion = result['estimated_portion']?.toString() ?? '一份';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  foodName,
                  style: const TextStyle(fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 圖片 - 使用 4:3 比例
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.file(
                        imageFile,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey.shade100,
                            child: const Icon(Icons.image, size: 40, color: Colors.grey),
                          );
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // 營養資訊卡片
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      // 熱量（大字顯示）
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.local_fire_department,
                            color: Colors.orange,
                            size: 28,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$calories',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          const Text(
                            ' kcal',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // 三大營養素
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildNutrientColumn(
                            '蛋白質',
                            '${protein.round()}g',
                            Colors.red.shade400,
                          ),
                          _buildNutrientColumn(
                            '碳水',
                            '${carbs.round()}g',
                            Colors.amber.shade600,
                          ),
                          _buildNutrientColumn(
                            '脂肪',
                            '${fat.round()}g',
                            Colors.blue.shade400,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 健康評分和分量
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        const SizedBox(width: 4),
                        Text('$healthScore/10', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                    Flexible(
                      child: Text(
                        portion,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lightbulb_outline,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            suggestions,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                setState(() => _isAnalyzing = false);
              },
              child: const Text('取消'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增到紀錄'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await _addMealFromAnalysis(result, foodName, mealType);
                  if (!mounted) return;
                  setState(() => _isAnalyzing = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已新增「$foodName」到$mealType'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (!mounted) return;
                  setState(() => _isAnalyzing = false);
                  if (mounted) {
                    _showErrorDialog(context, '儲存失敗: $e');
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  // 顯示文字分析結果（用於文字輸入的 AI 分析）
  void _showTextAnalysisResult(
    Map<String, dynamic> result,
    String foodName,
    String mealType,
  ) {
    final displayName = result['food_name']?.toString() ?? foodName;
    final calories = _safeParseInt(result['estimated_calories']);
    final protein = _safeParseDouble(result['protein_g']);
    final carbs = _safeParseDouble(result['carbs_g']);
    final fat = _safeParseDouble(result['fat_g']);
    final healthScore = _safeParseInt(result['health_score'], defaultValue: 5);
    final suggestions = result['suggestions']?.toString() ?? '';
    final portion = result['estimated_portion']?.toString() ?? '一份';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 食物圖標區域（取代圖片）
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.success.withOpacity(0.1),
                          AppColors.primary.withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.restaurant,
                          size: 40,
                          color: AppColors.success,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          mealType,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 營養資訊卡片
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // 熱量（大字顯示）
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.local_fire_department,
                              color: Colors.orange,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$calories',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            const Text(
                              ' kcal',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        // 三大營養素
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildNutrientColumn(
                              '蛋白質',
                              '${protein.round()}g',
                              Colors.red.shade400,
                            ),
                            _buildNutrientColumn(
                              '碳水',
                              '${carbs.round()}g',
                              Colors.amber.shade600,
                            ),
                            _buildNutrientColumn(
                              '脂肪',
                              '${fat.round()}g',
                              Colors.blue.shade400,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 健康評分和分量
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 18),
                          const SizedBox(width: 4),
                          Text('$healthScore/10', style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                      Flexible(
                        child: Text(
                          portion,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.lightbulb_outline,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              suggestions,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                setState(() => _isAnalyzing = false);
              },
              child: const Text('取消'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增到紀錄'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await _addMealFromAnalysis(result, displayName, mealType);
                  setState(() => _isAnalyzing = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已新增「$displayName」到$mealType'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (!mounted) return;
                  setState(() => _isAnalyzing = false);
                  if (mounted) {
                    _showErrorDialog(context, '儲存失敗: $e');
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildNutrientColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // ==================== UI 部分 ====================

  @override
  Widget build(BuildContext context) {
    // 篩選今日的紀錄
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayRecords = _dietRecords.where((record) {
      final timestamp = record['timestamp'] as DateTime?;
      if (timestamp == null) return false;
      return timestamp.isAfter(todayStart) ||
             (timestamp.year == now.year &&
              timestamp.month == now.month &&
              timestamp.day == now.day);
    }).toList();

    // 計算今日總營養（只計算今天的紀錄）
    final totalCalories = todayRecords.fold<int>(
      0,
      (sum, record) => sum + (record['calories'] as int? ?? 0),
    );
    final totalProtein = todayRecords.fold<double>(
      0,
      (sum, record) => sum + (record['protein'] as double? ?? 0.0),
    );
    final totalCarbs = todayRecords.fold<double>(
      0,
      (sum, record) => sum + (record['carbs'] as double? ?? 0.0),
    );
    final totalFat = todayRecords.fold<double>(
      0,
      (sum, record) => sum + (record['fat'] as double? ?? 0.0),
    );

    // 篩選當前餐別的紀錄（只顯示今天的）
    final currentMealRecords = _dietRecords.where((record) {
      // 先檢查餐別
      if (record['mealType'] != _selectedMealType) return false;

      // 再檢查日期是否為今天
      final timestamp = record['timestamp'] as DateTime?;
      if (timestamp == null) return false;

      return timestamp.year == now.year &&
             timestamp.month == now.month &&
             timestamp.day == now.day;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('飲食紀錄'),
        centerTitle: false,
        actions: [
          // 拍照分析按鈕
          IconButton(
            icon: Icon(
              Icons.camera_alt,
              color: _isAnalyzing ? Colors.grey : AppColors.success,
            ),
            onPressed: _isAnalyzing ? null : _showImageSourceDialog,
            tooltip: '拍照分析',
          ),
          // AI 文字分析按鈕
          IconButton(
            icon: Icon(
              Icons.auto_awesome,
              color: _isAnalyzing ? Colors.grey : AppColors.primary,
            ),
            onPressed: _isAnalyzing ? null : () => _showAIAnalysisDialog(context),
            tooltip: 'AI 文字分析',
          ),
          // 飲食日誌按鈕
          IconButton(
            icon: const Icon(Icons.menu_book, color: AppColors.primary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DietLogScreen()),
              );
            },
            tooltip: '飲食日誌',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [

            // 今日營養摘要
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildNutritionSummaryItem(
                                Icons.local_fire_department_rounded,
                                AppColors.warning,
                                '$totalCalories',
                                '卡路里',
                              ),
                              _buildNutritionSummaryItem(
                                Icons.fitness_center_rounded,
                                AppColors.error,
                                '${totalProtein.round()}',
                                '蛋白質(g)',
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildNutritionSummaryItem(
                                Icons.grain_rounded,
                                AppColors.primary,
                                '${totalCarbs.round()}',
                                '碳水化合物(g)',
                              ),
                              _buildNutritionSummaryItem(
                                Icons.opacity_rounded,
                                AppColors.success,
                                '${totalFat.round()}',
                                '脂肪(g)',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '共 ${todayRecords.length} 筆紀錄',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),

            // 餐別選擇器
            _buildMealTypeSelector(),

            if (_dataError != null) Padding(padding: const EdgeInsets.all(12),
              child: Column(children: [Text(_dataError!),
                TextButton(onPressed: _startListeningToDietRecords, child: const Text('重試'))])),
            // 飲食紀錄列表
            if (_isLoading && _dietRecords.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '載入飲食紀錄中...',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else if (currentMealRecords.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.restaurant_menu,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '尚無$_selectedMealType紀錄',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    // 顯示載入中（如果有資料但還在載入中）
                    if (_isLoading && _dietRecords.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        color: Colors.grey.shade50,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '更新資料中...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 飲食紀錄列表
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        itemCount: currentMealRecords.length,
                        itemBuilder: (context, index) {
                          final meal = currentMealRecords[index];
                          return _buildMealCard(meal);
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionSummaryItem(IconData icon, Color color, String value, String label) {
    return SizedBox(
      width: 120,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildMealTypeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _mealTypes.map((type) {
            final isSelected = _selectedMealType == type;
            final IconData icon = _getMealIcon(type);

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedMealType = type;
                });
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : Colors.grey.shade300,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isSelected ? Colors.white : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      type,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  IconData _getMealIcon(String type) {
    switch (type) {
      case '早餐':
        return Icons.free_breakfast;
      case '午餐':
        return Icons.lunch_dining;
      case '晚餐':
        return Icons.dinner_dining;
      case '點心':
        return Icons.cookie;
      default:
        return Icons.restaurant;
    }
  }

  Widget _buildMealCard(Map<String, dynamic> data) {
    final DateTime? mealTime = data['timestamp'] as DateTime?;
    final String timeString = mealTime != null
        ? DateFormat('HH:mm').format(mealTime)
        : '未知時間';

    final int? calories = data['calories'] as int?;
    final double? protein = data['protein'] as double?;
    final double? carbs = data['carbs'] as double?;
    final double? fat = data['fat'] as double?;
    final String? notes = data['notes'] as String?;
    final String? portion = data['portion'] as String?;
    final String? category = data['category'] as String?;
    final int? healthScore = data['healthScore'] as int?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeString,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data['foodName'] ?? '未命名食物',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (calories != null)
                      Text(
                        '$calories 卡',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: Icon(Icons.more_vert, color: Colors.grey.shade400),
                      onPressed: () => _showMealOptions(data['id'] as String),
                    ),
                  ],
                ),
              ],
            ),

            if (category != null && category.isNotEmpty) ...[
              const SizedBox(height: 8),
              Chip(
                label: Text(category),
                backgroundColor: Colors.blue.withOpacity(0.1),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: Colors.blue.shade700,
                ),
              ),
            ],

            if (portion != null && portion.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '分量: $portion',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],

            if (healthScore != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '健康評分: $healthScore/10',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],

            if (protein != null || carbs != null || fat != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (protein != null)
                    _buildNutritionTag('蛋白質', '${protein}g', Colors.blue),
                  const SizedBox(width: 8),
                  if (carbs != null)
                    _buildNutritionTag('碳水', '${carbs}g', Colors.green),
                  const SizedBox(width: 8),
                  if (fat != null)
                    _buildNutritionTag('脂肪', '${fat}g', Colors.amber),
                ],
              ),
            ],

            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  notes,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionTag(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showMealOptions(String recordId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('編輯紀錄'),
                onTap: () {
                  Navigator.pop(context);
                  _editMeal(recordId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('刪除紀錄'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(recordId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.grey),
                title: const Text('取消'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  void _editMeal(String recordId) async {
    final mealIndex = _dietRecords.indexWhere(
      (record) => record['id'] == recordId,
    );
    if (mealIndex == -1) return;

    final meal = _dietRecords[mealIndex];

    _showAddMealDialog(
      initialMealType: meal['mealType'],
      initialFoodName: meal['foodName'],
      initialCalories: meal['calories'],
      initialProtein: meal['protein'],
      initialCarbs: meal['carbs'],
      initialFat: meal['fat'],
      initialNotes: meal['notes'],
      initialPortion: meal['portion'],
      onSave: (updatedMeal) async {
        try {
          final user = _auth.currentUser;
          if (user != null) {
            // 準備要更新到 Firestore 的資料
            final newPortion = updatedMeal['portion'] ?? meal['portion'] ?? '1份';
            // 優先使用 AI 更新的類別和健康評分，否則保留原值
            final newCategory = updatedMeal['category'] ?? meal['category'] ?? '其他';
            final newHealthScore = updatedMeal['healthScore'] ?? meal['healthScore'] ?? 5;
            final updateData = {
              'foodName': updatedMeal['foodName'],
              'mealType': updatedMeal['mealType'],
              'calories': updatedMeal['calories'] ?? 0,
              'protein_g': updatedMeal['protein'] ?? 0.0,
              'carbs_g': updatedMeal['carbs'] ?? 0.0,
              'fat_g': updatedMeal['fat'] ?? 0.0,
              'notes': updatedMeal['notes'] ?? '',
              // 同時更新兩個份量欄位，確保讀取時能取得新值
              'estimatedPortion': newPortion,
              'estimated_portion': newPortion,
              'category': newCategory,
              'healthScore': newHealthScore,
              'timestamp': FieldValue.serverTimestamp(),
            };

            // 更新 Firestore
            await _firestore
                .collection('users')
                .doc(user.uid)
                .collection('diet_records')
                .doc(recordId)
                .update(updateData);

          }

          // Firestore 監聽器會自動更新本地列表，不需要手動更新
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('更新失敗: $error'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  void _showAddMealDialog({
    String? initialMealType,
    String? initialFoodName,
    int? initialCalories,
    double? initialProtein,
    double? initialCarbs,
    double? initialFat,
    String? initialNotes,
    String? initialPortion,
    Future<void> Function(Map<String, dynamic>)? onSave,
  }) {
    final foodNameController = TextEditingController(text: initialFoodName);
    final caloriesController = TextEditingController(
      text: initialCalories?.toString() ?? '',
    );
    final proteinController = TextEditingController(
      text: initialProtein?.toString() ?? '',
    );
    final carbsController = TextEditingController(
      text: initialCarbs?.toString() ?? '',
    );
    final fatController = TextEditingController(
      text: initialFat?.toString() ?? '',
    );
    final notesController = TextEditingController(text: initialNotes);
    final portionController = TextEditingController(text: initialPortion ?? '');
    String selectedMealType = initialMealType ?? _selectedMealType;
    // 用於儲存 AI 建議的類別和健康評分
    String? aiCategory;
    int? aiHealthScore;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(initialFoodName != null ? '編輯飲食紀錄' : '新增飲食紀錄'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: '餐別',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: selectedMealType,
                      items: _mealTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Row(
                            children: [
                              Icon(_getMealIcon(type), size: 20),
                              const SizedBox(width: 8),
                              Text(type),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedMealType = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: foodNameController,
                      decoration: const InputDecoration(
                        labelText: '食物名稱',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // AI 建議按鈕
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('AI 建議營養數值'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                        ),
                        onPressed: () async {
                          if (foodNameController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('請先輸入食物名稱'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          // 檢查是否為食物
                          if (!_isFoodInput(foodNameController.text)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('請輸入真實的食物名稱'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          // 顯示載入中
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => const AlertDialog(
                              content: Row(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(width: 16),
                                  Text('AI 正在分析...'),
                                ],
                              ),
                            ),
                          );

                          try {
                            // 用文字方式請 AI 估算營養
                            final response = await AIService.instance.estimateNutritionByName(
                              foodNameController.text,
                              selectedMealType,
                            );

                            Navigator.pop(context); // 關閉載入對話框

                            // 解析並填入數值
                            if (response != null) {

                              // 檢查 AI 是否判定為食物
                              final isFood = response['is_food'];
                              final isFoodBool = isFood == true || isFood == 'true';

                              if (!isFoodBool) {
                                final errorMsg = response['error_message'] ?? response['error'] ?? '這不是食物名稱';
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('「${foodNameController.text}」$errorMsg'),
                                      backgroundColor: Colors.orange,
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                }
                                // 清空輸入框讓用戶重新輸入
                                foodNameController.clear();
                                return;
                              }

                              // 直接更新 controller 的值
                              caloriesController.text = response['calories']?.toString() ?? '';
                              proteinController.text = response['protein']?.toString() ?? '';
                              carbsController.text = response['carbs']?.toString() ?? '';
                              fatController.text = response['fat']?.toString() ?? '';

                              // 更新份量
                              final portion = response['portion']?.toString() ?? '';
                              if (portion.isNotEmpty) {
                                portionController.text = portion;
                              }

                              // 更新類別和健康評分
                              aiCategory = response['category']?.toString();
                              aiHealthScore = int.tryParse(response['health_score']?.toString() ?? '');

                              // 強制重繪 UI
                              setState(() {});

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('已填入 AI 建議的營養數值（份量：$portion）'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            Navigator.pop(context); // 關閉載入對話框
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('AI 分析失敗: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('營養成分（選填）'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: caloriesController,
                            decoration: const InputDecoration(
                              labelText: '熱量',
                              suffixText: 'kcal',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: proteinController,
                            decoration: const InputDecoration(
                              labelText: '蛋白質',
                              suffixText: 'g',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: carbsController,
                            decoration: const InputDecoration(
                              labelText: '碳水化合物',
                              suffixText: 'g',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: fatController,
                            decoration: const InputDecoration(
                              labelText: '脂肪',
                              suffixText: 'g',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: portionController,
                      decoration: const InputDecoration(
                        labelText: '份量（例如：1份、2個、1碗）',
                        border: OutlineInputBorder(),
                        hintText: '1份',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: '備註（選填）',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (foodNameController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('請輸入食物名稱'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    // 檢查是否為食物
                    if (!_isFoodInput(foodNameController.text)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('請輸入真實的食物名稱'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    // 建立或更新紀錄
                    final newRecord = {
                      'id': initialFoodName != null
                          ? 'existing'
                          : DateTime.now().millisecondsSinceEpoch.toString(),
                      'mealType': selectedMealType,
                      'foodName': foodNameController.text,
                      'timestamp': DateTime.now(),
                    };

                    // 僅添加非空值
                    if (caloriesController.text.isNotEmpty) {
                      newRecord['calories'] =
                          int.tryParse(caloriesController.text) ?? 0;
                    }
                    if (proteinController.text.isNotEmpty) {
                      newRecord['protein'] =
                          double.tryParse(proteinController.text) ?? 0.0;
                    }
                    if (carbsController.text.isNotEmpty) {
                      newRecord['carbs'] =
                          double.tryParse(carbsController.text) ?? 0.0;
                    }
                    if (fatController.text.isNotEmpty) {
                      newRecord['fat'] =
                          double.tryParse(fatController.text) ?? 0.0;
                    }
                    if (notesController.text.isNotEmpty) {
                      newRecord['notes'] = notesController.text;
                    }
                    if (portionController.text.isNotEmpty) {
                      newRecord['portion'] = portionController.text;
                    }
                    // 如果有 AI 建議的類別和健康評分，也加入
                    if (aiCategory != null) {
                      newRecord['category'] = aiCategory!;
                    }
                    if (aiHealthScore != null) {
                      newRecord['healthScore'] = aiHealthScore!;
                    }

                    if (onSave != null) {
                      // 編輯模式 - 等待 onSave 完成
                      await onSave(newRecord);
                    } else {
                      // 新增模式 - 嘗試儲存到 Firebase
                      try {
                        final user = _auth.currentUser;
                        if (user != null) {
                          final recordData = {
                            'foodName': newRecord['foodName'],
                            'mealType': newRecord['mealType'],
                            'calories': newRecord['calories'] ?? 0,
                            'protein_g': newRecord['protein'] ?? 0.0,
                            'carbs_g': newRecord['carbs'] ?? 0.0,
                            'fat_g': newRecord['fat'] ?? 0.0,
                            'notes': newRecord['notes'] ?? '',
                            'estimated_portion': newRecord['portion'] ?? '1份',
                            'timestamp': FieldValue.serverTimestamp(),
                          };

                          await _firestore
                              .collection('users')
                              .doc(user.uid)
                              .collection('diet_records')
                              .add(recordData);

                        }
                      } catch (e) {
                      }

                      setState(() {
                        _dietRecords.add(newRecord);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('飲食紀錄已新增'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }

                    Navigator.of(context).pop();
                  },
                  child: Text(initialFoodName != null ? '更新' : '新增'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 顯示 AI 分析對話框
  void _showAIAnalysisDialog(BuildContext context) {
    final foodNameController = TextEditingController();
    String selectedMealType = _selectedMealType;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'AI 食物分析',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),

                      // 選擇餐別標題
                      const Text(
                        '選擇餐別：',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 餐別選擇器
                      Container(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: _mealTypes.map((type) {
                            final isSelected = selectedMealType == type;
                            final IconData icon = _getMealIcon(type);

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedMealType = type;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : Colors.grey.shade300,
                                    width: 1.5,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xFF4A90E2,
                                            ).withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icon,
                                      size: 16,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      type,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.grey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 目前選擇的餐別
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _getMealIcon(selectedMealType),
                              color: AppColors.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '當前選擇：$selectedMealType',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 食物名稱輸入框
                      TextField(
                        controller: foodNameController,
                        decoration: InputDecoration(
                          labelText: '輸入食物名稱',
                          hintText: '例如：巧克力吐司一片、雞胸肉沙拉、牛肉麵',
                          border: const OutlineInputBorder(),
                          prefixIcon: Icon(
                            Icons.fastfood,
                            color: Theme.of(context).primaryColor,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (value) {
                          if (value.isNotEmpty) {
                            Navigator.of(context).pop();
                            _performAIAnalysis(
                              context,
                              value,
                              selectedMealType,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info, color: Colors.orange.shade700, size: 16),
                                const SizedBox(width: 4),
                                const Text(
                                  '請輸入真實的食物名稱',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '例如：蘋果、雞胸肉、牛肉麵、巧克力蛋糕、鮮奶茶等',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 按鈕區域
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('取消'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              onPressed: () {
                                if (foodNameController.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('請輸入食物名稱'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }
                                Navigator.of(context).pop();
                                _performAIAnalysis(
                                  context,
                                  foodNameController.text,
                                  selectedMealType,
                                );
                              },
                              child: const Text('開始分析'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDelete(String recordId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('確認刪除'),
          content: const Text('確定要刪除這筆飲食紀錄嗎？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  final user = _auth.currentUser;
                  if (user != null) {
                    // 從 Firestore 刪除
                    await _firestore
                        .collection('users')
                        .doc(user.uid)
                        .collection('diet_records')
                        .doc(recordId)
                        .delete();

                  }

                  // 本地也刪除
                  if (mounted) {
                    setState(() {
                      _dietRecords.removeWhere(
                        (record) => record['id'] == recordId,
                      );
                    });
                  }

                  Navigator.of(context).pop();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('飲食紀錄已刪除'),
                        backgroundColor: AppColors.warning,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('刪除失敗: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('刪除', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}

/// 分析中對話框（帶動畫效果）
class _AnalyzingDialog extends StatefulWidget {
  final String mealType;

  const _AnalyzingDialog({required this.mealType});

  @override
  State<_AnalyzingDialog> createState() => _AnalyzingDialogState();
}

class _AnalyzingDialogState extends State<_AnalyzingDialog>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _dotsController;
  late Animation<double> _pulseAnimation;
  int _dotCount = 0;
  int _stepIndex = 0;

  final List<String> _steps = [
    '正在讀取圖片...',
    '上傳中...',
    'AI 正在辨識食物...',
    '計算營養成分...',
    '生成分析報告...',
  ];

  @override
  void initState() {
    super.initState();

    // 脈動動畫
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 點點動畫
    _dotsController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _dotCount = (_dotCount + 1) % 4;
          });
          _dotsController.reset();
          _dotsController.forward();
        }
      });
    _dotsController.forward();

    // 步驟切換
    _startStepAnimation();
  }

  void _startStepAnimation() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          _stepIndex = (_stepIndex + 1) % _steps.length;
        });
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * _dotCount;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          // 動畫圖示
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.success,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.restaurant_menu,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          // 主標題
          const Text(
            '🔍 AI 分析中',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // 餐別
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              widget.mealType,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 進度指示器
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 16),
          // 動態步驟文字
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              '${_steps[_stepIndex]}$dots',
              key: ValueKey<int>(_stepIndex * 10 + _dotCount),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '請稍候，這可能需要 10-30 秒',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}