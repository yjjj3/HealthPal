// lib/services/pdf_report_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/record_data.dart';

class PdfReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 報告時間範圍
  static const List<Map<String, dynamic>> timeRangeOptions = [
    {'value': 7, 'label': '最近 7 天'},
    {'value': 30, 'label': '最近 30 天'},
    {'value': 90, 'label': '最近 3 個月'},
    {'value': 0, 'label': '自訂範圍'},
  ];

  // 報告內容選項
  static const List<Map<String, dynamic>> contentOptions = [
    {'value': 'basic_info', 'label': '基本資料', 'icon': 'person'},
    {'value': 'blood_pressure', 'label': '血壓記錄', 'icon': 'favorite'},
    {'value': 'blood_glucose', 'label': '血糖記錄', 'icon': 'water_drop'},
    {'value': 'weight', 'label': '體重記錄', 'icon': 'monitor_weight'},
    {'value': 'sleep', 'label': '睡眠記錄', 'icon': 'bedtime'},
    {'value': 'exercise', 'label': '運動記錄', 'icon': 'directions_run'},
    {'value': 'medication', 'label': '用藥記錄', 'icon': 'medication'},
    {'value': 'trends', 'label': '趨勢分析', 'icon': 'trending_up'},
  ];

  /// 生成健康報告 PDF
  Future<void> generateReport({
    required int days,
    DateTime? startDate,
    DateTime? endDate,
    required Set<String> selectedContent,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('用戶未登入');

    // 計算時間範圍
    final now = DateTime.now();
    final DateTime reportStartDate;
    final DateTime reportEndDate;

    if (days > 0) {
      reportEndDate = now;
      reportStartDate = now.subtract(Duration(days: days));
    } else {
      reportStartDate = startDate ?? now.subtract(const Duration(days: 30));
      reportEndDate = endDate ?? now;
    }

    // 載入所需數據
    final userData = await _loadUserData(uid);
    final healthRecords = await _loadHealthRecords(uid, reportStartDate, reportEndDate);
    final medicationRecords = await _loadMedicationRecords(uid);

    // 計算趨勢數據
    final trends = _calculateTrends(healthRecords);

    // 生成 PDF
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansTCRegular();
    final boldFont = await PdfGoogleFonts.notoSansTCBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        header: (context) => _buildHeader(font, boldFont, userData, reportStartDate, reportEndDate),
        footer: (context) => _buildFooter(font, context),
        build: (context) => _buildReportContent(
          font: font,
          boldFont: boldFont,
          userData: userData,
          healthRecords: healthRecords,
          medicationRecords: medicationRecords,
          trends: trends,
          selectedContent: selectedContent,
          startDate: reportStartDate,
          endDate: reportEndDate,
        ),
      ),
    );

    // 顯示列印/分享對話框
    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: '健康報告_${DateFormat('yyyyMMdd').format(now)}.pdf',
    );
  }

  // 載入用戶資料
  Future<Map<String, dynamic>> _loadUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data() ?? {};
  }

  // 載入健康記錄
  Future<List<RecordData>> _loadHealthRecords(
    String uid,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final query = await _firestore
        .collection('users')
        .doc(uid)
        .collection('health_records')
        .where('record_time', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('record_time', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .orderBy('record_time', descending: true)
        .get();

    return query.docs.map((doc) => RecordData.fromFirestore(doc)).toList();
  }

  // 載入用藥記錄
  Future<List<Map<String, dynamic>>> _loadMedicationRecords(String uid) async {
    final query = await _firestore
        .collection('users')
        .doc(uid)
        .collection('medicine')
        .get();

    return query.docs.map((doc) {
      final data = doc.data();
      return {
        'name': data['name'] ?? '未命名藥物',
        'dosage': '${data['dosage'] ?? '1'}${data['unit'] ?? '顆'}',
        'frequency': data['frequency'] ?? '每日一次',
        'instruction': data['instruction'] ?? '',
      };
    }).toList();
  }

  // 計算趨勢數據
  Map<String, dynamic> _calculateTrends(List<RecordData> records) {
    final trends = <String, dynamic>{};

    // 血壓趨勢
    final bpRecords = records.where((r) => r.category == '血壓' && r.systolicBloodPressure != null).toList();
    if (bpRecords.isNotEmpty) {
      final avgSystolic = bpRecords.map((r) => r.systolicBloodPressure!).reduce((a, b) => a + b) / bpRecords.length;
      final avgDiastolic = bpRecords.map((r) => r.diastolicBloodPressure!).reduce((a, b) => a + b) / bpRecords.length;
      final maxSystolic = bpRecords.map((r) => r.systolicBloodPressure!).reduce((a, b) => a > b ? a : b);
      final minSystolic = bpRecords.map((r) => r.systolicBloodPressure!).reduce((a, b) => a < b ? a : b);

      trends['blood_pressure'] = {
        'count': bpRecords.length,
        'avg_systolic': avgSystolic.round(),
        'avg_diastolic': avgDiastolic.round(),
        'max_systolic': maxSystolic,
        'min_systolic': minSystolic,
      };
    }

    // 血糖趨勢（分餐前餐後）
    final glucoseRecords = records.where((r) => r.category == '血糖' && r.bloodGlucose != null).toList();
    if (glucoseRecords.isNotEmpty) {
      final avgGlucose = glucoseRecords.map((r) => r.bloodGlucose!).reduce((a, b) => a + b) / glucoseRecords.length;
      final maxGlucose = glucoseRecords.map((r) => r.bloodGlucose!).reduce((a, b) => a > b ? a : b);
      final minGlucose = glucoseRecords.map((r) => r.bloodGlucose!).reduce((a, b) => a < b ? a : b);

      // 分類統計
      final fastingRecords = glucoseRecords.where((r) => r.glucoseTiming == 'fasting').toList();
      final afterMealRecords = glucoseRecords.where((r) => r.glucoseTiming == 'after_meal').toList();

      trends['blood_glucose'] = {
        'count': glucoseRecords.length,
        'avg': avgGlucose.round(),
        'max': maxGlucose,
        'min': minGlucose,
        'fasting_avg': fastingRecords.isNotEmpty
            ? (fastingRecords.map((r) => r.bloodGlucose!).reduce((a, b) => a + b) / fastingRecords.length).round()
            : null,
        'fasting_count': fastingRecords.length,
        'after_meal_avg': afterMealRecords.isNotEmpty
            ? (afterMealRecords.map((r) => r.bloodGlucose!).reduce((a, b) => a + b) / afterMealRecords.length).round()
            : null,
        'after_meal_count': afterMealRecords.length,
      };
    }

    // 體重趨勢
    final weightRecords = records.where((r) => r.category == '體重' && r.weight != null).toList();
    if (weightRecords.isNotEmpty) {
      final latestWeight = weightRecords.first.weight!;
      final earliestWeight = weightRecords.last.weight!;
      final weightChange = latestWeight - earliestWeight;

      trends['weight'] = {
        'count': weightRecords.length,
        'latest': latestWeight,
        'earliest': earliestWeight,
        'change': weightChange,
      };
    }

    // 睡眠趨勢
    final sleepRecords = records.where((r) => r.category == '睡眠' && r.sleepHours != null).toList();
    if (sleepRecords.isNotEmpty) {
      final avgSleep = sleepRecords.map((r) => r.sleepHours!).reduce((a, b) => a + b) / sleepRecords.length;

      trends['sleep'] = {
        'count': sleepRecords.length,
        'avg': avgSleep,
      };
    }

    // 運動趨勢
    final exerciseRecords = records.where((r) => r.category == '運動' && r.exerciseMinutes != null).toList();
    if (exerciseRecords.isNotEmpty) {
      final totalMinutes = exerciseRecords.map((r) => r.exerciseMinutes!).reduce((a, b) => a + b);

      trends['exercise'] = {
        'count': exerciseRecords.length,
        'total_minutes': totalMinutes,
        'avg_minutes': (totalMinutes / exerciseRecords.length).round(),
      };
    }

    return trends;
  }

  // 建立報告標題
  pw.Widget _buildHeader(
    pw.Font font,
    pw.Font boldFont,
    Map<String, dynamic> userData,
    DateTime startDate,
    DateTime endDate,
  ) {
    final userName = userData['fullName'] ?? userData['name'] ?? '用戶';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '健康管理報告',
              style: pw.TextStyle(font: boldFont, fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'HealthPal',
              style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.grey600),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '患者姓名：$userName',
          style: pw.TextStyle(font: boldFont, fontSize: 14),
        ),
        pw.Text(
          '報告期間：${DateFormat('yyyy/MM/dd').format(startDate)} - ${DateFormat('yyyy/MM/dd').format(endDate)}',
          style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 2, color: PdfColors.blue),
        pw.SizedBox(height: 10),
      ],
    );
  }

  // 建立頁尾
  pw.Widget _buildFooter(pw.Font font, pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '由「HealthPal」App 生成 | ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
              style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey),
            ),
            pw.Text(
              '第 ${context.pageNumber} 頁，共 ${context.pagesCount} 頁',
              style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey),
            ),
          ],
        ),
      ],
    );
  }

  // 建立報告內容
  List<pw.Widget> _buildReportContent({
    required pw.Font font,
    required pw.Font boldFont,
    required Map<String, dynamic> userData,
    required List<RecordData> healthRecords,
    required List<Map<String, dynamic>> medicationRecords,
    required Map<String, dynamic> trends,
    required Set<String> selectedContent,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final widgets = <pw.Widget>[];

    // 基本資料
    if (selectedContent.contains('basic_info')) {
      widgets.add(_buildBasicInfoSection(font, boldFont, userData));
      widgets.add(pw.SizedBox(height: 20));
    }

    // 趨勢分析摘要
    if (selectedContent.contains('trends') && trends.isNotEmpty) {
      widgets.add(_buildTrendsSummary(font, boldFont, trends));
      widgets.add(pw.SizedBox(height: 20));
    }

    // 血壓記錄
    if (selectedContent.contains('blood_pressure')) {
      final bpRecords = healthRecords.where((r) => r.category == '血壓').toList();
      if (bpRecords.isNotEmpty) {
        widgets.add(_buildBloodPressureSection(font, boldFont, bpRecords, trends['blood_pressure']));
        widgets.add(pw.SizedBox(height: 20));
      }
    }

    // 血糖記錄
    if (selectedContent.contains('blood_glucose')) {
      final glucoseRecords = healthRecords.where((r) => r.category == '血糖').toList();
      if (glucoseRecords.isNotEmpty) {
        widgets.add(_buildBloodGlucoseSection(font, boldFont, glucoseRecords, trends['blood_glucose']));
        widgets.add(pw.SizedBox(height: 20));
      }
    }

    // 體重記錄
    if (selectedContent.contains('weight')) {
      final weightRecords = healthRecords.where((r) => r.category == '體重').toList();
      if (weightRecords.isNotEmpty) {
        widgets.add(_buildWeightSection(font, boldFont, weightRecords, trends['weight']));
        widgets.add(pw.SizedBox(height: 20));
      }
    }

    // 睡眠記錄
    if (selectedContent.contains('sleep')) {
      final sleepRecords = healthRecords.where((r) => r.category == '睡眠').toList();
      if (sleepRecords.isNotEmpty) {
        widgets.add(_buildSleepSection(font, boldFont, sleepRecords, trends['sleep']));
        widgets.add(pw.SizedBox(height: 20));
      }
    }

    // 運動記錄
    if (selectedContent.contains('exercise')) {
      final exerciseRecords = healthRecords.where((r) => r.category == '運動').toList();
      if (exerciseRecords.isNotEmpty) {
        widgets.add(_buildExerciseSection(font, boldFont, exerciseRecords, trends['exercise']));
        widgets.add(pw.SizedBox(height: 20));
      }
    }

    // 用藥記錄
    if (selectedContent.contains('medication') && medicationRecords.isNotEmpty) {
      widgets.add(_buildMedicationSection(font, boldFont, medicationRecords));
      widgets.add(pw.SizedBox(height: 20));
    }

    // 醫療備註
    widgets.add(_buildMedicalNotes(font, boldFont));

    return widgets;
  }

  // 基本資料區塊
  pw.Widget _buildBasicInfoSection(pw.Font font, pw.Font boldFont, Map<String, dynamic> userData) {
    final name = userData['fullName'] ?? userData['name'] ?? '--';
    final gender = userData['gender'] ?? '--';
    final height = userData['height']?.toString() ?? '--';
    final weight = userData['weight']?.toString() ?? '--';
    final bloodType = userData['bloodType'] ?? '--';

    // 計算年齡
    String age = '--';
    final dateOfBirth = userData['dateOfBirth'];
    if (dateOfBirth is Timestamp) {
      final birthDate = dateOfBirth.toDate();
      final now = DateTime.now();
      int years = now.year - birthDate.year;
      if (now.month < birthDate.month || (now.month == birthDate.month && now.day < birthDate.day)) {
        years--;
      }
      age = '$years 歲';
    }

    // 慢性病
    String chronicDiseases = '無';
    final diseases = userData['chronicDiseases'];
    if (diseases is List && diseases.isNotEmpty) {
      chronicDiseases = diseases.cast<String>().join('、');
    }

    // 過敏史
    String allergies = '無';
    final allergyData = userData['allergies'];
    if (allergyData is List && allergyData.isNotEmpty) {
      allergies = allergyData.cast<String>().join('、');
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(boldFont, '基本資料'),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(1.5),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(children: [
              _buildTableCell(font, '姓名', isLabel: true),
              _buildTableCell(font, name),
              _buildTableCell(font, '性別', isLabel: true),
              _buildTableCell(font, gender),
            ]),
            pw.TableRow(children: [
              _buildTableCell(font, '年齡', isLabel: true),
              _buildTableCell(font, age),
              _buildTableCell(font, '血型', isLabel: true),
              _buildTableCell(font, bloodType),
            ]),
            pw.TableRow(children: [
              _buildTableCell(font, '身高', isLabel: true),
              _buildTableCell(font, height != '--' ? '$height cm' : '--'),
              _buildTableCell(font, '體重', isLabel: true),
              _buildTableCell(font, weight != '--' ? '$weight kg' : '--'),
            ]),
            pw.TableRow(children: [
              _buildTableCell(font, '慢性病史', isLabel: true),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(chronicDiseases, style: pw.TextStyle(font: font, fontSize: 10)),
              ),
              _buildTableCell(font, '過敏史', isLabel: true),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(allergies, style: pw.TextStyle(font: font, fontSize: 10)),
              ),
            ]),
          ],
        ),
      ],
    );
  }

  // 趨勢摘要區塊
  pw.Widget _buildTrendsSummary(pw.Font font, pw.Font boldFont, Map<String, dynamic> trends) {
    final summaryItems = <pw.Widget>[];

    if (trends['blood_pressure'] != null) {
      final bp = trends['blood_pressure'];
      summaryItems.add(_buildTrendItem(
        font,
        boldFont,
        '血壓',
        '平均 ${bp['avg_systolic']}/${bp['avg_diastolic']} mmHg',
        '${bp['count']} 筆記錄',
      ));
    }

    if (trends['blood_glucose'] != null) {
      final glucose = trends['blood_glucose'];
      String detail = '平均 ${glucose['avg']} mg/dL';
      if (glucose['fasting_avg'] != null) {
        detail += '\n空腹平均 ${glucose['fasting_avg']} mg/dL';
      }
      if (glucose['after_meal_avg'] != null) {
        detail += '\n餐後平均 ${glucose['after_meal_avg']} mg/dL';
      }
      summaryItems.add(_buildTrendItem(font, boldFont, '血糖', detail, '${glucose['count']} 筆記錄'));
    }

    if (trends['weight'] != null) {
      final weight = trends['weight'];
      final change = weight['change'] as double;
      final changeText = change >= 0 ? '+${change.toStringAsFixed(1)}' : change.toStringAsFixed(1);
      summaryItems.add(_buildTrendItem(
        font,
        boldFont,
        '體重',
        '最新 ${weight['latest']} kg ($changeText kg)',
        '${weight['count']} 筆記錄',
      ));
    }

    if (trends['sleep'] != null) {
      final sleep = trends['sleep'];
      summaryItems.add(_buildTrendItem(
        font,
        boldFont,
        '睡眠',
        '平均 ${(sleep['avg'] as double).toStringAsFixed(1)} 小時',
        '${sleep['count']} 筆記錄',
      ));
    }

    if (trends['exercise'] != null) {
      final exercise = trends['exercise'];
      summaryItems.add(_buildTrendItem(
        font,
        boldFont,
        '運動',
        '總計 ${exercise['total_minutes']} 分鐘',
        '${exercise['count']} 次運動',
      ));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(boldFont, '趨勢摘要'),
        pw.SizedBox(height: 10),
        pw.Wrap(
          spacing: 10,
          runSpacing: 10,
          children: summaryItems,
        ),
      ],
    );
  }

  pw.Widget _buildTrendItem(pw.Font font, pw.Font boldFont, String title, String value, String count) {
    return pw.Container(
      width: 160,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(font: boldFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(font: font, fontSize: 10)),
          pw.SizedBox(height: 2),
          pw.Text(count, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  // 血壓記錄區塊
  pw.Widget _buildBloodPressureSection(
    pw.Font font,
    pw.Font boldFont,
    List<RecordData> records,
    Map<String, dynamic>? trends,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(boldFont, '血壓記錄'),
        if (trends != null) ...[
          pw.SizedBox(height: 5),
          pw.Text(
            '平均：${trends['avg_systolic']}/${trends['avg_diastolic']} mmHg | 最高收縮壓：${trends['max_systolic']} | 最低收縮壓：${trends['min_systolic']}',
            style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700),
          ),
        ],
        pw.SizedBox(height: 10),
        _buildRecordsTable(
          font,
          boldFont,
          headers: ['日期', '時間', '收縮壓', '舒張壓', '狀態'],
          rows: records.take(20).map((r) {
            final systolic = r.systolicBloodPressure ?? 0;
            final diastolic = r.diastolicBloodPressure ?? 0;
            String status = '正常';
            if (systolic >= 140 || diastolic >= 90) {
              status = '偏高';
            } else if (systolic < 90 || diastolic < 60) {
              status = '偏低';
            }
            return [
              DateFormat('MM/dd').format(r.recordTime),
              DateFormat('HH:mm').format(r.recordTime),
              '$systolic mmHg',
              '$diastolic mmHg',
              status,
            ];
          }).toList(),
        ),
      ],
    );
  }

  // 血糖記錄區塊（含餐前餐後標記）
  pw.Widget _buildBloodGlucoseSection(
    pw.Font font,
    pw.Font boldFont,
    List<RecordData> records,
    Map<String, dynamic>? trends,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(boldFont, '血糖記錄'),
        if (trends != null) ...[
          pw.SizedBox(height: 5),
          pw.RichText(
            text: pw.TextSpan(
              style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700),
              children: [
                pw.TextSpan(text: '整體平均：${trends['avg']} mg/dL'),
                if (trends['fasting_avg'] != null)
                  pw.TextSpan(text: ' | 空腹平均：${trends['fasting_avg']} mg/dL (${trends['fasting_count']}筆)'),
                if (trends['after_meal_avg'] != null)
                  pw.TextSpan(text: ' | 餐後平均：${trends['after_meal_avg']} mg/dL (${trends['after_meal_count']}筆)'),
              ],
            ),
          ),
        ],
        pw.SizedBox(height: 10),
        _buildRecordsTable(
          font,
          boldFont,
          headers: ['日期', '時間', '血糖值', '測量時機', '狀態'],
          rows: records.take(20).map((r) {
            final glucose = r.bloodGlucose ?? 0;
            final timing = r.glucoseTimingLabel ?? '--';
            String status = '正常';

            // 根據測量時機判斷正常範圍
            if (r.glucoseTiming == 'fasting') {
              if (glucose >= 126) {
                status = '偏高';
              } else if (glucose >= 100) {
                status = '臨界';
              }
            } else if (r.glucoseTiming == 'after_meal') {
              if (glucose >= 200) {
                status = '偏高';
              } else if (glucose >= 140) {
                status = '臨界';
              }
            } else {
              if (glucose >= 140) status = '偏高';
            }

            return [
              DateFormat('MM/dd').format(r.recordTime),
              DateFormat('HH:mm').format(r.recordTime),
              '$glucose mg/dL',
              timing,
              status,
            ];
          }).toList(),
        ),
      ],
    );
  }

  // 體重記錄區塊
  pw.Widget _buildWeightSection(
    pw.Font font,
    pw.Font boldFont,
    List<RecordData> records,
    Map<String, dynamic>? trends,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(boldFont, '體重記錄'),
        if (trends != null) ...[
          pw.SizedBox(height: 5),
          pw.Text(
            '期間變化：${trends['earliest']} kg → ${trends['latest']} kg (${(trends['change'] as double) >= 0 ? '+' : ''}${(trends['change'] as double).toStringAsFixed(1)} kg)',
            style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700),
          ),
        ],
        pw.SizedBox(height: 10),
        _buildRecordsTable(
          font,
          boldFont,
          headers: ['日期', '時間', '體重', '備註'],
          rows: records.take(15).map((r) {
            return [
              DateFormat('MM/dd').format(r.recordTime),
              DateFormat('HH:mm').format(r.recordTime),
              '${r.weight} kg',
              r.notes ?? '--',
            ];
          }).toList(),
        ),
      ],
    );
  }

  // 睡眠記錄區塊
  pw.Widget _buildSleepSection(
    pw.Font font,
    pw.Font boldFont,
    List<RecordData> records,
    Map<String, dynamic>? trends,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(boldFont, '睡眠記錄'),
        if (trends != null) ...[
          pw.SizedBox(height: 5),
          pw.Text(
            '平均睡眠時長：${(trends['avg'] as double).toStringAsFixed(1)} 小時',
            style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700),
          ),
        ],
        pw.SizedBox(height: 10),
        _buildRecordsTable(
          font,
          boldFont,
          headers: ['日期', '睡眠時長', '品質評估'],
          rows: records.take(15).map((r) {
            final hours = r.sleepHours ?? 0;
            String quality = '良好';
            if (hours < 6) {
              quality = '不足';
            } else if (hours > 9) {
              quality = '過長';
            }
            return [
              DateFormat('MM/dd').format(r.recordTime),
              '${hours.toStringAsFixed(1)} 小時',
              quality,
            ];
          }).toList(),
        ),
      ],
    );
  }

  // 運動記錄區塊
  pw.Widget _buildExerciseSection(
    pw.Font font,
    pw.Font boldFont,
    List<RecordData> records,
    Map<String, dynamic>? trends,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(boldFont, '運動記錄'),
        if (trends != null) ...[
          pw.SizedBox(height: 5),
          pw.Text(
            '總運動時間：${trends['total_minutes']} 分鐘 | 平均每次：${trends['avg_minutes']} 分鐘',
            style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700),
          ),
        ],
        pw.SizedBox(height: 10),
        _buildRecordsTable(
          font,
          boldFont,
          headers: ['日期', '運動類型', '時長'],
          rows: records.take(15).map((r) {
            return [
              DateFormat('MM/dd').format(r.recordTime),
              r.exerciseType ?? '--',
              '${r.exerciseMinutes ?? 0} 分鐘',
            ];
          }).toList(),
        ),
      ],
    );
  }

  // 用藥記錄區塊
  pw.Widget _buildMedicationSection(pw.Font font, pw.Font boldFont, List<Map<String, dynamic>> records) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(boldFont, '目前用藥'),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _buildTableCell(font, '藥品名稱', isLabel: true),
                _buildTableCell(font, '劑量', isLabel: true),
                _buildTableCell(font, '服用方式', isLabel: true),
              ],
            ),
            ...records.map((med) => pw.TableRow(children: [
              _buildTableCell(font, med['name']),
              _buildTableCell(font, med['dosage']),
              _buildTableCell(font, '${med['frequency']} ${med['instruction']}'),
            ])),
          ],
        ),
      ],
    );
  }

  // 醫療備註
  pw.Widget _buildMedicalNotes(pw.Font font, pw.Font boldFont) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('備註', style: pw.TextStyle(font: boldFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text(
            '• 本報告由「HealthPal」HealthPal 自動生成，僅供醫療參考。\n'
            '• 數據來源為用戶自行記錄，建議配合專業醫療檢測結果進行判讀。\n'
            '• 如有任何健康疑慮，請諮詢您的醫療團隊。',
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  // 輔助方法：區塊標題
  pw.Widget _buildSectionTitle(pw.Font boldFont, String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const pw.BoxDecoration(
        color: PdfColors.blue100,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(font: boldFont, fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
      ),
    );
  }

  // 輔助方法：表格儲存格
  pw.Widget _buildTableCell(pw.Font font, String text, {bool isLabel = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: 10,
          fontWeight: isLabel ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // 輔助方法：記錄表格
  pw.Widget _buildRecordsTable(
    pw.Font font,
    pw.Font boldFont, {
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    if (rows.isEmpty) {
      return pw.Text('暫無記錄', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600));
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        // 表頭
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: headers.map((h) => _buildTableCell(font, h, isLabel: true)).toList(),
        ),
        // 數據行
        ...rows.map((row) => pw.TableRow(
          children: row.map((cell) => _buildTableCell(font, cell)).toList(),
        )),
      ],
    );
  }
}
