import '../theme/app_colors.dart';
// lib/screens/share_report_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/pdf_report_service.dart';

class ShareReportScreen extends StatefulWidget {
  const ShareReportScreen({super.key});

  @override
  State<ShareReportScreen> createState() => _ShareReportScreenState();
}

class _ShareReportScreenState extends State<ShareReportScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _recentRecords = [];
  List<Map<String, dynamic>> _medicationRecords = [];
  bool _isLoading = true;

  // 進階報告設定
  final PdfReportService _pdfReportService = PdfReportService();
  int _selectedDays = 30;
  Set<String> _selectedContent = {
    'basic_info',
    'blood_pressure',
    'blood_glucose',
    'weight',
    'medication',
    'trends',
  };

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      debugPrint('正在載入用戶資料: $uid');

      // 獲取用戶基本資料 - 修正欄位名稱
      final userDoc = await _firestore.collection('users').doc(uid).get();
      
      if (userDoc.exists) {
        final data = userDoc.data();
        debugPrint('用戶資料: $data');
        setState(() {
          _userData = data;
        });
      } else {
        debugPrint('用戶文件不存在');
      }

      // 獲取健康記錄 - 根據您的資料庫結構調整
      await _loadHealthRecords(uid);

      // 獲取用藥記錄 - 根據您的資料庫結構調整
      await _loadMedicationRecords(uid);

      setState(() {
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('加載用戶數據失敗: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('載入資料失敗，請稍後再試'),
            backgroundColor: AppColors.error,
            action: SnackBarAction(
              label: '重試',
              textColor: AppColors.surface,
              onPressed: _loadUserData,
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadHealthRecords(String uid) async {
    try {
      debugPrint('開始載入健康記錄...');
      
      // 根據您的截圖，嘗試可能的集合名稱
      final collections = ['health_records', 'records', 'measurements', 'healthRecords'];
      
      for (final collection in collections) {
        try {
          debugPrint('嘗試載入集合: $collection');
          
          final query = await _firestore
              .collection('users')
              .doc(uid)
              .collection(collection)
              .orderBy('createdAt', descending: true)
              .limit(20)
              .get();
          
          debugPrint('集合 $collection 查詢結果: ${query.docs.length} 筆記錄');

          if (query.docs.isNotEmpty) {
            List<Map<String, dynamic>> records = [];
            
            for (final doc in query.docs) {
              final data = doc.data();
              debugPrint('找到記錄資料: ${doc.id} - $data');
              
              // 轉換時間戳記
              Timestamp? timestamp;
              if (data['createdAt'] != null) {
                timestamp = data['createdAt'] as Timestamp;
              } else if (data['timestamp'] != null) {
                timestamp = data['timestamp'] as Timestamp;
              } else if (data['date'] != null) {
                timestamp = data['date'] as Timestamp;
              }
              
              records.add({
                'id': doc.id,
                'record_time': timestamp?.toDate() ?? DateTime.now(),
                'systolic_blood_pressure': data['systolic_blood_pressure'] ?? 
                                          data['systolic'] ?? 
                                          data['systolicBP'] ?? 
                                          data['bloodPressureSystolic'] ??
                                          data['systolicPressure'],
                'diastolic_blood_pressure': data['diastolic_blood_pressure'] ?? 
                                           data['diastolic'] ?? 
                                           data['diastolicBP'] ?? 
                                           data['bloodPressureDiastolic'] ??
                                           data['diastolicPressure'],
                'blood_glucose': data['blood_glucose'] ?? 
                                data['glucose'] ?? 
                                data['bloodSugar'] ?? 
                                data['sugarLevel'] ??
                                data['glucoseLevel'],
                'weight': data['weight'] ??
                         data['body_weight'] ??
                         data['weight_kg'] ??
                         data['bodyWeight'],
                'heart_rate': data['heart_rate'] ?? 
                             data['heartRate'] ?? 
                             data['pulse'],
                'temperature': data['temperature'] ?? 
                              data['body_temperature'] ?? 
                              data['bodyTemperature'],
              });
            }
            
            setState(() {
              _recentRecords = records;
            });
            debugPrint('成功載入 ${records.length} 筆健康記錄');
            return;
          }
        } catch (e) {
          debugPrint('嘗試集合 $collection 失敗: $e');
        }
      }
      
      // 如果都沒找到，顯示除錯訊息
      debugPrint('所有健康記錄集合都找不到資料，顯示範例資料');
      _showSampleHealthRecords();
      
    } catch (e) {
      debugPrint('獲取健康記錄失敗: $e');
      _showSampleHealthRecords();
    }
  }

  void _showSampleHealthRecords() {
    // 顯示範例資料供測試
    final now = DateTime.now();
    setState(() {
      _recentRecords = [
        {
          'id': 'sample1',
          'record_time': now.subtract(const Duration(days: 1)),
          'systolic_blood_pressure': 120,
          'diastolic_blood_pressure': 80,
          'blood_glucose': 95,
          'weight': 65.5,
        },
        {
          'id': 'sample2',
          'record_time': now.subtract(const Duration(days: 2)),
          'systolic_blood_pressure': 118,
          'diastolic_blood_pressure': 78,
          'blood_glucose': 92,
          'weight': 65.2,
        },
      ];
    });
  }

  Future<void> _loadMedicationRecords(String uid) async {
    try {
      debugPrint('開始載入用藥記錄...');

      // 先嘗試從 medicine 集合載入（不使用 orderBy 避免索引問題）
      try {
        debugPrint('嘗試載入用藥集合: medicine');

        final query = await _firestore
            .collection('users')
            .doc(uid)
            .collection('medicine')
            .get();

        debugPrint('用藥集合 medicine 查詢結果: ${query.docs.length} 筆記錄');

        if (query.docs.isNotEmpty) {
          List<Map<String, dynamic>> medications = [];

          for (final doc in query.docs) {
            final data = doc.data();
            debugPrint('找到用藥記錄: ${doc.id} - $data');

            // medicine 集合的數據格式
            final name = data['name'] ?? '未命名藥物';
            final dosage = data['dosage'] ?? '1';
            final unit = data['unit'] ?? '顆';
            final frequency = data['frequency'] ?? '每日一次';
            final instruction = data['instruction'] ?? '';

            // 檢查今日用藥狀態
            final timesStatus = data['times_status'] as List<dynamic>?;
            int totalDoses = timesStatus?.length ?? 0;
            int completedDoses = timesStatus?.where((status) => status == true).length ?? 0;
            bool isTaken = totalDoses > 0 && completedDoses == totalDoses;

            medications.add({
              'id': doc.id,
              'name': name,
              'dosage': '$dosage$unit',
              'frequency': instruction.isNotEmpty ? '$frequency · $instruction' : frequency,
              'isTaken': isTaken,
              'completedDoses': completedDoses,
              'totalDoses': totalDoses,
            });
          }

          setState(() {
            _medicationRecords = medications;
          });
          debugPrint('成功載入 ${medications.length} 筆用藥記錄');
          return;
        }
      } catch (e) {
        debugPrint('載入 medicine 集合失敗: $e');
      }

      debugPrint('沒有找到用藥記錄');
      setState(() {
        _medicationRecords = [];
      });
    } catch (e) {
      debugPrint('獲取用藥記錄失敗: $e');
      setState(() {
        _medicationRecords = [];
      });
    }
  }

  void _showSampleMedicationRecords() {
    // 顯示範例用藥資料
    setState(() {
      _medicationRecords = [
        {
          'id': 'med1',
          'name': '降血壓藥',
          'dosage': '10mg',
          'frequency': '每日一次',
          'isTaken': true,
          'time': '早上',
        },
        {
          'id': 'med2',
          'name': '維生素D',
          'dosage': '1000IU', 
          'frequency': '每日一次',
          'isTaken': false,
          'time': '晚上',
        },
      ];
    });
  }

  // 基本資訊獲取方法 - 修正欄位名稱
  String _getUserName() {
    return _userData?['fullName'] ?? _userData?['name'] ?? '用戶';
  }

  String _getUserAge() {
    final dateOfBirth = _userData?['dateOfBirth'] ?? _userData?['datedfBirth'];

    DateTime? birthDate;
    if (dateOfBirth is Timestamp) {
      birthDate = dateOfBirth.toDate();
    } else if (dateOfBirth is String && dateOfBirth.isNotEmpty) {
      try {
        birthDate = DateTime.parse(dateOfBirth);
      } catch (e) {
        debugPrint('無法解析生日字串: $dateOfBirth, 錯誤: $e');
        return '--';
      }
    }

    if (birthDate != null) {
      final now = DateTime.now();
      int age = now.year - birthDate.year;
      if (now.month < birthDate.month ||
          (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }
      return '$age歲';
    }
    return '--';
  }

  String _getUserGender() {
    return _userData?['gender'] ?? '--';
  }

  String _getUserHeight() {
    final height = _userData?['height'];
    if (height != null) {
      return '$height cm';
    }
    return '--';
  }

  String _getUserWeight() {
    // 先從用戶基本資料中獲取
    final weight = _userData?['weight'];
    if (weight != null && weight != 0) {
      return '$weight kg';
    }
    
    // 從健康記錄中獲取最新的體重記錄
    if (_recentRecords.isNotEmpty) {
      for (final record in _recentRecords) {
        final recordWeight = record['weight'];
        if (recordWeight != null && recordWeight != 0) {
          return '$recordWeight kg';
        }
      }
    }
    return '--';
  }

  double? _getWeightValue() {
    // 先從用戶基本資料中獲取
    final weight = _userData?['weight'];
    if (weight != null && weight != 0) {
      if (weight is int) return weight.toDouble();
      if (weight is double) return weight;
      if (weight is String) return double.tryParse(weight);
    }
    
    // 從健康記錄中獲取
    if (_recentRecords.isNotEmpty) {
      for (final record in _recentRecords) {
        final recordWeight = record['weight'];
        if (recordWeight != null && recordWeight != 0) {
          if (recordWeight is int) return recordWeight.toDouble();
          if (recordWeight is double) return recordWeight;
          if (recordWeight is String) return double.tryParse(recordWeight);
        }
      }
    }
    return null;
  }

  String _getUserBMI() {
    final height = _userData?['height'];
    final weight = _getWeightValue();
    
    if (height != null && weight != null && height > 0) {
      final heightInMeter = height / 100;
      final bmi = weight / (heightInMeter * heightInMeter);
      String status = '正常';
      if (bmi < 18.5) {
        status = '過輕';
      } else if (bmi >= 24 && bmi < 27) status = '過重';
      else if (bmi >= 27) status = '肥胖';
      return '${bmi.toStringAsFixed(1)} ($status)';
    }
    return '--';
  }

  String _getMedicalHistory() {
    final chronicDiseases = _userData?['chronicDiseases'];
    if (chronicDiseases is List && chronicDiseases.isNotEmpty) {
      return chronicDiseases.cast<String>().join('、');
    } else if (chronicDiseases is String && chronicDiseases.isNotEmpty) {
      return chronicDiseases;
    }
    return _userData?['medicalHistory'] ?? '無';
  }

  String _getBloodType() {
    return _userData?['bloodType'] ?? '--';
  }

  String _getAllergies() {
    final allergies = _userData?['allergies'];
    if (allergies is List && allergies.isNotEmpty) {
      return allergies.cast<String>().join('、');
    } else if (allergies is String && allergies.isNotEmpty) {
      return allergies;
    }
    return '無';
  }

  List<Map<String, dynamic>> _getRecentMeasurements() {
    final List<Map<String, dynamic>> measurements = [];
    
    for (final record in _recentRecords) {
      final time = record['record_time'] as DateTime;
      final dateStr = DateFormat('MM/dd').format(time);
      
      // 血壓
      if (record['systolic_blood_pressure'] != null && 
          record['diastolic_blood_pressure'] != null) {
        final systolic = record['systolic_blood_pressure'];
        final diastolic = record['diastolic_blood_pressure'];
        measurements.add({
          'type': '血壓',
          'date': dateStr,
          'value': '$systolic/$diastolic mmHg',
          'isWarning': (systolic is int && systolic > 140) || 
                      (diastolic is int && diastolic > 90),
        });
      }
      
      // 血糖
      if (record['blood_glucose'] != null) {
        final glucose = record['blood_glucose'];
        measurements.add({
          'type': '血糖',
          'date': dateStr,
          'value': '$glucose mg/dL',
          'isWarning': (glucose is int && glucose > 140),
        });
      }
      
      // 體重
      if (record['weight'] != null && record['weight'] != 0) {
        final weight = record['weight'];
        measurements.add({
          'type': '體重',
          'date': dateStr,
          'value': '$weight kg',
          'isWarning': false,
        });
      }

      // 心率
      if (record['heart_rate'] != null) {
        final heartRate = record['heart_rate'];
        measurements.add({
          'type': '心率',
          'date': dateStr,
          'value': '$heartRate bpm',
          'isWarning': (heartRate is int && (heartRate < 60 || heartRate > 100)),
        });
      }

    }
    
    return measurements.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '分享健康報告',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _loadUserData();
            },
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '選擇分享內容',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 15),
            _buildOptionCard(
              icon: Icons.description_rounded,
              title: '簡易版報告',
              description: '包含基本資料與近期記錄',
              color: AppColors.primary,
              onTap: () {
                _shareSimpleReport(context);
              },
            ),
            _buildOptionCard(
              icon: Icons.print_rounded,
              title: '完整版報告',
              description: '詳細數據與可列印格式',
              color: AppColors.success,
              onTap: () {
                _shareFullReport(context);
              },
            ),
            _buildOptionCard(
              icon: Icons.tune_rounded,
              title: '進階報告',
              description: '自訂時間範圍與內容',
              color: AppColors.sleep,
              onTap: () {
                _showAdvancedReportDialog(context);
              },
            ),
            const SizedBox(height: 30),
            _buildDataStatusInfo(),
            const SizedBox(height: 15),
            const Text(
              '報告預覽',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 15),
            _buildReportPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildDataStatusInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '已載入 ${_recentRecords.length} 筆健康記錄與 ${_medicationRecords.length} 筆用藥記錄',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildReportPreview() {
    final recentMeasurements = _getRecentMeasurements();
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              '${_getUserName()} 健康記錄',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Center(
            child: Text(
              '${DateFormat('yyyy年MM月').format(DateTime.now())} 健康摘要',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 15),
          _buildSectionTitle('基本資料'),
          const SizedBox(height: 10),
          _buildInfoItem('姓名', _getUserName()),
          _buildInfoItem('年齡', _getUserAge()),
          _buildInfoItem('性別', _getUserGender()),
          _buildInfoItem('身高', _getUserHeight()),
          _buildInfoItem('體重', _getUserWeight()),
          _buildInfoItem('BMI', _getUserBMI()),
          _buildInfoItem('血型', _getBloodType()),
          _buildInfoItem('過敏史', _getAllergies()),
          _buildInfoItem('慢性病史', _getMedicalHistory()),
          const SizedBox(height: 20),
          _buildSectionTitle('近期記錄'),
          const SizedBox(height: 10),
          if (recentMeasurements.isNotEmpty)
            ...recentMeasurements.map((measurement) => _buildRecordItem(
              '${measurement['type']} (${measurement['date']})',
              measurement['value'] as String,
              measurement['isWarning'] as bool,
            ))
          else
            _buildNoDataMessage('暫無近期記錄'),
          const SizedBox(height: 20),
          _buildSectionTitle('用藥記錄'),
          const SizedBox(height: 10),
          if (_medicationRecords.isNotEmpty)
            ..._medicationRecords.map((med) => _buildMedicationItem(
              med['name'] as String,
              med['isTaken'] as bool ? '已按時服用' : '待服用',
              med['dosage'] as String,
              med['frequency'] as String,
            ))
          else
            _buildNoDataMessage('暫無用藥記錄'),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              '由「HealthPal」生成',
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
          ),
          Center(
            child: Text(
              DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now()),
              style: const TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordItem(String title, String value, bool isWarning) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isWarning ? AppColors.warning : AppColors.success,
                ),
              ),
              if (isWarning) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.warning_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationItem(String name, String status, String dosage, String frequency) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            status == '已按時服用' ? Icons.check_circle : Icons.schedule,
            size: 20,
            color: status == '已按時服用' ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (dosage.isNotEmpty || frequency.isNotEmpty)
                  Text(
                    '$dosage $frequency',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            status,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: status == '已按時服用' ? AppColors.success : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.disabled),
          const SizedBox(width: 12),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _shareSimpleReport(BuildContext context) {
    final recentMeasurements = _getRecentMeasurements();
    
    String reportText = '''
【健康記錄分享 - 簡易版】
${_getUserName()} - ${DateFormat('yyyy/MM/dd').format(DateTime.now())}

━━━━━━━━━━━━
基本資料
姓名: ${_getUserName()}
年齡: ${_getUserAge()}
性別: ${_getUserGender()}
身高: ${_getUserHeight()}
體重: ${_getUserWeight()}
BMI: ${_getUserBMI()}
血型: ${_getBloodType()}
過敏史: ${_getAllergies()}
慢性病史: ${_getMedicalHistory()}

━━━━━━━━━━━━
近期記錄
''';

    for (final measurement in recentMeasurements) {
      final status = measurement['isWarning'] as bool ? '[警告]' : '[正常]';
      reportText += '\n${measurement['type']} (${measurement['date']}): ${measurement['value']} $status';
    }

    if (recentMeasurements.isEmpty) {
      reportText += '\n暫無近期記錄';
    }

    reportText += '''

━━━━━━━━━━━━
用藥記錄
''';

    for (final med in _medicationRecords) {
      final status = med['isTaken'] as bool ? '[已服用]' : '[待服用]';
      final dosage = med['dosage'] as String;
      final frequency = med['frequency'] as String;
      reportText += '\n$status ${med['name']}';
      if (dosage.isNotEmpty || frequency.isNotEmpty) {
        reportText += ' ($dosage $frequency)';
      }
    }

    if (_medicationRecords.isEmpty) {
      reportText += '\n暫無用藥記錄';
    }

    reportText += '''

━━━━━━━━━━━━
由「HealthPal」生成
${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}
''';

    Clipboard.setData(ClipboardData(text: reportText));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('簡易版報告已複製到剪貼簿'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareFullReport(BuildContext context) async {
    try {
      final pdf = pw.Document();

      // 添加中文字體支持
      final font = await PdfGoogleFonts.notoSansTCRegular();
      final boldFont = await PdfGoogleFonts.notoSansTCBold();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(
            base: font,
            bold: boldFont,
          ),
          build: (pw.Context context) {
            return [
              // 標題
              pw.Text(
                '健康記錄完整報告',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                '患者：${_getUserName()}',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                '報告日期：${DateFormat('yyyy年MM月dd日').format(DateTime.now())}',
                style: pw.TextStyle(font: font, fontSize: 12),
              ),
              pw.SizedBox(height: 20),

              // 基本資料表格
              pw.Text(
                '基本資料',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              _buildPdfBasicInfoTable(font, boldFont),
              pw.SizedBox(height: 20),

              // 生理數據記錄
              pw.Text(
                '近期生理數據記錄',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              _buildPdfMeasurementsTable(font, boldFont),
              pw.SizedBox(height: 20),

              // 用藥記錄
              pw.Text(
                '用藥記錄',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              _buildPdfMedicationsTable(font, boldFont),
              pw.SizedBox(height: 20),

              // 頁尾
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text(
                '由「HealthPal」生成',
                style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                '報告生成時間：${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                '僅供醫療參考',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey),
                textAlign: pw.TextAlign.center,
              ),
            ];
          },
        ),
      );

      // 顯示列印對話框
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );

    } catch (e) {
      debugPrint('PDF 生成失敗: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF 生成失敗: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  pw.Widget _buildPdfBasicInfoTable(pw.Font font, pw.Font boldFont) {
    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(2),
      },
      children: [
        _buildPdfTableRow('姓名', _getUserName(), font, boldFont, isHeader: true),
        _buildPdfTableRow('年齡', _getUserAge(), font, boldFont),
        _buildPdfTableRow('性別', _getUserGender(), font, boldFont),
        _buildPdfTableRow('身高', _getUserHeight(), font, boldFont),
        _buildPdfTableRow('體重', _getUserWeight(), font, boldFont),
        _buildPdfTableRow('BMI', _getUserBMI(), font, boldFont),
        _buildPdfTableRow('血型', _getBloodType(), font, boldFont),
        _buildPdfTableRow('過敏史', _getAllergies(), font, boldFont),
        _buildPdfTableRow('慢性病史', _getMedicalHistory(), font, boldFont),
      ],
    );
  }

  pw.Widget _buildPdfMeasurementsTable(pw.Font font, pw.Font boldFont) {
    final measurements = _getRecentMeasurements();

    if (measurements.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text('暫無近期記錄', style: pw.TextStyle(font: font, fontSize: 12)),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1),
      },
      children: [
        // 表頭
        pw.TableRow(
          children: [
            pw.Padding(
              child: pw.Text('類型', style: pw.TextStyle(font: boldFont, fontWeight: pw.FontWeight.bold)),
              padding: const pw.EdgeInsets.all(8),
            ),
            pw.Padding(
              child: pw.Text('日期', style: pw.TextStyle(font: boldFont, fontWeight: pw.FontWeight.bold)),
              padding: const pw.EdgeInsets.all(8),
            ),
            pw.Padding(
              child: pw.Text('數值', style: pw.TextStyle(font: boldFont, fontWeight: pw.FontWeight.bold)),
              padding: const pw.EdgeInsets.all(8),
            ),
            pw.Padding(
              child: pw.Text('狀態', style: pw.TextStyle(font: boldFont, fontWeight: pw.FontWeight.bold)),
              padding: const pw.EdgeInsets.all(8),
            ),
          ],
        ),
        // 數據行
        for (final measurement in measurements)
          pw.TableRow(
            children: [
              pw.Padding(
                child: pw.Text(measurement['type'] as String, style: pw.TextStyle(font: font)),
                padding: const pw.EdgeInsets.all(8),
              ),
              pw.Padding(
                child: pw.Text(measurement['date'] as String, style: pw.TextStyle(font: font)),
                padding: const pw.EdgeInsets.all(8),
              ),
              pw.Padding(
                child: pw.Text(measurement['value'] as String, style: pw.TextStyle(font: font)),
                padding: const pw.EdgeInsets.all(8),
              ),
              pw.Padding(
                child: pw.Text(
                  measurement['isWarning'] as bool ? '需注意' : '正常',
                  style: pw.TextStyle(
                    font: font,
                    color: measurement['isWarning'] as bool ? PdfColors.red : PdfColors.green,
                  ),
                ),
                padding: const pw.EdgeInsets.all(8),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _buildPdfMedicationsTable(pw.Font font, pw.Font boldFont) {
    if (_medicationRecords.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text('暫無用藥記錄', style: pw.TextStyle(font: font, fontSize: 12)),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
      },
      children: [
        // 表頭
        pw.TableRow(
          children: [
            pw.Padding(
              child: pw.Text('藥品名稱', style: pw.TextStyle(font: boldFont, fontWeight: pw.FontWeight.bold)),
              padding: const pw.EdgeInsets.all(8),
            ),
            pw.Padding(
              child: pw.Text('劑量', style: pw.TextStyle(font: boldFont, fontWeight: pw.FontWeight.bold)),
              padding: const pw.EdgeInsets.all(8),
            ),
            pw.Padding(
              child: pw.Text('頻率', style: pw.TextStyle(font: boldFont, fontWeight: pw.FontWeight.bold)),
              padding: const pw.EdgeInsets.all(8),
            ),
            pw.Padding(
              child: pw.Text('狀態', style: pw.TextStyle(font: boldFont, fontWeight: pw.FontWeight.bold)),
              padding: const pw.EdgeInsets.all(8),
            ),
          ],
        ),
        // 數據行
        for (final med in _medicationRecords)
          pw.TableRow(
            children: [
              pw.Padding(
                child: pw.Text(med['name'] as String, style: pw.TextStyle(font: font)),
                padding: const pw.EdgeInsets.all(8),
              ),
              pw.Padding(
                child: pw.Text(med['dosage'] as String, style: pw.TextStyle(font: font)),
                padding: const pw.EdgeInsets.all(8),
              ),
              pw.Padding(
                child: pw.Text(med['frequency'] as String, style: pw.TextStyle(font: font)),
                padding: const pw.EdgeInsets.all(8),
              ),
              pw.Padding(
                child: pw.Text(
                  med['isTaken'] as bool ? '已服用' : '待服用',
                  style: pw.TextStyle(
                    font: font,
                    color: med['isTaken'] as bool ? PdfColors.green : PdfColors.orange,
                  ),
                ),
                padding: const pw.EdgeInsets.all(8),
              ),
            ],
          ),
      ],
    );
  }

  pw.TableRow _buildPdfTableRow(String label, String value, pw.Font font, pw.Font boldFont, {bool isHeader = false}) {
    return pw.TableRow(
      children: [
        pw.Padding(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: isHeader ? boldFont : font,
              fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          padding: const pw.EdgeInsets.all(8),
        ),
        pw.Padding(
          child: pw.Text(
            value,
            style: pw.TextStyle(font: font),
          ),
          padding: const pw.EdgeInsets.all(8),
        ),
      ],
    );
  }

  // 顯示進階報告對話框
  void _showAdvancedReportDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // 標題列
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '進階報告設定',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // 內容區域
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 時間範圍選擇
                          const Text(
                            '報告時間範圍',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: PdfReportService.timeRangeOptions.map((option) {
                              final isSelected = _selectedDays == option['value'];
                              return ChoiceChip(
                                label: Text(option['label']),
                                selected: isSelected,
                                selectedColor: AppColors.primary.withValues(alpha: 0.2),
                                labelStyle: TextStyle(
                                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    setModalState(() {
                                      _selectedDays = option['value'];
                                    });
                                    setState(() {
                                      _selectedDays = option['value'];
                                    });
                                  }
                                },
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 25),

                          // 報告內容選擇
                          const Text(
                            '報告內容',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...PdfReportService.contentOptions.map((option) {
                            final isSelected = _selectedContent.contains(option['value']);
                            return CheckboxListTile(
                              title: Text(option['label']),
                              value: isSelected,
                              activeColor: AppColors.primary,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (value) {
                                setModalState(() {
                                  if (value == true) {
                                    _selectedContent.add(option['value']);
                                  } else {
                                    _selectedContent.remove(option['value']);
                                  }
                                });
                                setState(() {});
                              },
                            );
                          }),

                          const SizedBox(height: 20),

                          // 預覽資訊
                          Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
                                    const SizedBox(width: 8),
                                    const Text(
                                      '報告預覽',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '時間範圍：${_selectedDays > 0 ? "最近 $_selectedDays 天" : "自訂範圍"}',
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '包含內容：${_selectedContent.length} 個區塊',
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 底部按鈕
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.sleep,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _selectedContent.isEmpty
                              ? null
                              : () async {
                                  Navigator.pop(context);
                                  _generateAdvancedReport();
                                },
                          child: const Text(
                            '生成報告',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 生成進階報告
  Future<void> _generateAdvancedReport() async {
    try {
      // 顯示載入指示器
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      await _pdfReportService.generateReport(
        days: _selectedDays,
        selectedContent: _selectedContent,
      );

      if (mounted) {
        Navigator.pop(context); // 關閉載入對話框
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 關閉載入對話框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('報告生成失敗：$e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}