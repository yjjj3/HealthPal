import 'dart:async';
import '../theme/app_colors.dart';
// lib/screens/health_record_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class HealthRecordScreen extends StatefulWidget {
  const HealthRecordScreen({Key? key}) : super(key: key);

  @override
  State<HealthRecordScreen> createState() => _HealthRecordScreenState();
}

class _HealthRecordScreenState extends State<HealthRecordScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _recentRecords = [];
  List<Map<String, dynamic>> _medicationRecords = [];
  bool _isLoading = true;

  // 即時監聽的訂閱，需在 dispose() 時取消，避免每次進出此頁都多洩漏一組監聽器
  StreamSubscription<QuerySnapshot>? _healthRecordsSubscription;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _setupHealthRecordsListener(); // 監聽健康記錄變更
  }

  @override
  void dispose() {
    _healthRecordsSubscription?.cancel();
    super.dispose();
  }

  // 即時監聽健康記錄變更
  void _setupHealthRecordsListener() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _healthRecordsSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('health_records')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        debugPrint('🔄 健康檔案頁面：健康記錄有更新，重新載入...');
        _loadHealthRecords(uid);
      }
    });
  }

  Future<void> _loadUserData() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // 獲取用戶基本資料
      final userDoc = await _firestore.collection('users').doc(uid).get();

      if (userDoc.exists) {
        setState(() {
          _userData = userDoc.data();
        });
      }

      // 獲取健康記錄
      await _loadHealthRecords(uid);

      // 獲取用藥記錄
      await _loadMedicationRecords(uid);

      setState(() {
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('加載用戶數據失敗: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadHealthRecords(String uid) async {
    try {
      final query = await _firestore
          .collection('users')
          .doc(uid)
          .collection('health_records')
          .orderBy('record_time', descending: true)
          .limit(20)
          .get();

      if (query.docs.isNotEmpty) {
        List<Map<String, dynamic>> records = [];

        for (final doc in query.docs) {
          final data = doc.data();

          Timestamp? timestamp;
          if (data['record_time'] != null) {
            timestamp = data['record_time'] as Timestamp;
          } else if (data['createdAt'] != null) {
            timestamp = data['createdAt'] as Timestamp;
          }

          // 解析儲存格式 (category + value 字串格式)
          final category = data['category'] as String?;
          final valueStr = data['value'] as String? ?? '';

          int? systolic;
          int? diastolic;
          double? glucose;
          double? weight;
          int? heartRate;

          if (category == '血壓' && valueStr.contains('/')) {
            // 解析 "120/80 mmHg" 格式
            final parts = valueStr.split(' ')[0].split('/');
            if (parts.length == 2) {
              systolic = int.tryParse(parts[0]);
              diastolic = int.tryParse(parts[1]);
            }
          } else if (category == '血糖') {
            // 解析 "100 mg/dL" 格式
            final numStr = valueStr.split(' ')[0];
            glucose = double.tryParse(numStr);
          } else if (category == '體重') {
            // 解析 "65 kg" 格式
            final numStr = valueStr.split(' ')[0];
            weight = double.tryParse(numStr);
          } else if (category == '心率') {
            // 解析 "72 bpm" 格式
            final numStr = valueStr.split(' ')[0];
            heartRate = int.tryParse(numStr);
          }

          // 也支援舊格式（直接儲存數值欄位）
          systolic ??= data['systolic_blood_pressure'] as int? ?? data['systolic'] as int?;
          diastolic ??= data['diastolic_blood_pressure'] as int? ?? data['diastolic'] as int?;
          glucose ??= (data['blood_glucose'] ?? data['glucose'])?.toDouble();
          weight ??= data['weight']?.toDouble();
          heartRate ??= data['heart_rate'] as int? ?? data['heartRate'] as int?;

          records.add({
            'id': doc.id,
            'record_time': timestamp?.toDate() ?? DateTime.now(),
            'category': category,
            'systolic_blood_pressure': systolic,
            'diastolic_blood_pressure': diastolic,
            'blood_glucose': glucose,
            'weight': weight,
            'heart_rate': heartRate,
          });
        }

        setState(() {
          _recentRecords = records;
        });
      }
    } catch (e) {
      debugPrint('獲取健康記錄失敗: $e');
    }
  }

  Future<void> _loadMedicationRecords(String uid) async {
    try {
      final query = await _firestore
          .collection('users')
          .doc(uid)
          .collection('medicine')
          .get();

      if (query.docs.isNotEmpty) {
        List<Map<String, dynamic>> medications = [];

        for (final doc in query.docs) {
          final data = doc.data();

          final name = data['name'] ?? '未命名藥物';
          final dosage = data['dosage'] ?? '';
          final unit = data['unit'] ?? '顆';
          final frequency = data['frequency'] ?? '每日一次';
          final instruction = data['instruction'] ?? '';

          final timesStatus = data['times_status'] as List<dynamic>?;
          int totalDoses = timesStatus?.length ?? 0;
          int completedDoses = timesStatus?.where((status) => status == true).length ?? 0;
          bool isTaken = totalDoses > 0 && completedDoses == totalDoses;

          // dosage 可能是 "1 顆" 或只是 "1"，需要判斷
          String displayDosage = dosage;
          if (dosage.isNotEmpty && !dosage.contains(unit) && !dosage.contains(' ')) {
            // 如果 dosage 只是數字，加上單位
            displayDosage = '$dosage $unit';
          }

          medications.add({
            'id': doc.id,
            'name': name,
            'dosage': displayDosage,
            'frequency': instruction.isNotEmpty ? '$frequency · $instruction' : frequency,
            'isTaken': isTaken,
            'completedDoses': completedDoses,
            'totalDoses': totalDoses,
          });
        }

        setState(() {
          _medicationRecords = medications;
        });
      }
    } catch (e) {
      debugPrint('獲取用藥記錄失敗: $e');
    }
  }

  // 基本資訊獲取方法
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
    // 優先使用健康記錄中的最新體重
    if (_recentRecords.isNotEmpty) {
      for (final record in _recentRecords) {
        final recordWeight = record['weight'];
        if (recordWeight != null && recordWeight != 0) {
          return '$recordWeight kg';
        }
      }
    }

    // 如果健康記錄沒有體重，才使用用戶資料中的體重
    final weight = _userData?['weight'];
    if (weight != null && weight != 0) {
      return '$weight kg';
    }
    return '--';
  }

  double? _getWeightValue() {
    // 優先使用健康記錄中的最新體重
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

    // 如果健康記錄沒有體重，才使用用戶資料中的體重
    final weight = _userData?['weight'];
    if (weight != null && weight != 0) {
      if (weight is int) return weight.toDouble();
      if (weight is double) return weight;
      if (weight is String) return double.tryParse(weight);
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
        final glucoseValue = glucose is int ? glucose.toDouble() : (glucose as double);
        measurements.add({
          'type': '血糖',
          'date': dateStr,
          'value': '${glucoseValue.toStringAsFixed(0)} mg/dL',
          'isWarning': glucoseValue > 140,
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
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '健康檔案',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.black87),
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
            // 分享選項
            const Text(
              '分享健康報告',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 15),
            _buildOptionCard(
              icon: Icons.description_rounded,
              title: '簡易版報告',
              description: '包含基本資料與近期記錄（複製到剪貼簿）',
              color: AppColors.primary,
              onTap: () => _shareSimpleReport(context),
            ),
            _buildOptionCard(
              icon: Icons.print_rounded,
              title: '完整版報告',
              description: '詳細數據與可列印 PDF 格式',
              color: AppColors.success,
              onTap: () => _shareFullReport(context),
            ),
            const SizedBox(height: 20),
            _buildDataStatusInfo(),
            const SizedBox(height: 20),

            // 報告預覽
            const Text(
              '報告預覽',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
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
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '已載入 ${_recentRecords.length} 筆健康記錄與 ${_medicationRecords.length} 筆用藥記錄',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue[700],
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
          color: Colors.white,
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
                      color: Colors.black87,
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
        color: Colors.white,
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
                color: Colors.black87,
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
        color: Colors.black87,
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
              style: const TextStyle(fontSize: 14, color: Colors.black87),
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
                  color: isWarning ? AppColors.warning : const Color(0xFF059669),
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            status == '已按時服用' ? Icons.check_circle : Icons.schedule,
            size: 20,
            color: status == '已按時服用' ? AppColors.success : const Color(0xFFF59E0B),
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
                    color: Colors.black87,
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
              color: status == '已按時服用' ? AppColors.success : const Color(0xFFF59E0B),
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.grey[400]),
          const SizedBox(width: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF 生成失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
}
