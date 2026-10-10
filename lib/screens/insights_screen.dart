// lib/screens/insights_screen.dart
import 'dart:math' show max;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/record_data.dart';
import '../services/health_ai_analyzer.dart';
import '../services/ai_service.dart';
import '../theme/app_colors.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({Key? key}) : super(key: key);

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final HealthAIAnalyzer _aiAnalyzer = HealthAIAnalyzer();

  int _chartRange = 0; // 0 = 7 days, 1 = 30 days, 2 = 90 days
  String _dataRange = '7 days';

  // AI 相關狀態
  bool _isLoadingAI = false;
  String? _aiAnalysis;
  String? _aiError;
  bool _isAIExpanded = false;

  @override
  void initState() {
    super.initState();
    _updateDataRangeFromChartRange(_chartRange);
  }

  /// 取得 AI 健康分析
  Future<void> _fetchAIAnalysis() async {
    // 檢查 API Key 是否已設定
    if (!AIService.instance.isConfigured) {
      setState(() {
        _aiError = '請先設定 API Key';
      });
      return;
    }

    setState(() {
      _isLoadingAI = true;
      _aiError = null;
    });

    try {
      final analysis = await _aiAnalyzer.getHealthAnalysis();
      if (mounted) {
        setState(() {
          _aiAnalysis = analysis;
          _isLoadingAI = false;
          _isAIExpanded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiError = e.toString().replaceAll('Exception: ', '');
          _isLoadingAI = false;
        });
      }
    }
  }
  
  void _updateDataRangeFromChartRange(int index) {
     setState(() {
         if (index == 0) _dataRange = '7 days';
         else if (index == 1) _dataRange = '30 days';
         else _dataRange = '90 days';
         _chartRange = index;
     });
  }

  Stream<List<RecordData>> _getHealthRecordsStream() {
    final uid = _auth.currentUser?.uid;
    
    if (uid == null) {
      return Stream.value([]);
    }
    
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('health_records')
        .orderBy('record_time', descending: false)
        .snapshots()
        .map((snapshot) {
            final records = snapshot.docs.map<RecordData>((doc) {
              try {
                return RecordData.fromFirestore(doc);
              } catch (e) {
                debugPrint('DEBUG: 解析文件錯誤 ${doc.id}: $e');
                // 創建一個基本的 RecordData 對象作為備用
                return RecordData(
                  id: doc.id,
                  category: '錯誤',
                  value: '解析錯誤',
                  unit: '',
                  emoji: '',
                  recordTime: DateTime.now(),
                );
              }
            }).toList();
            
            return records;
        });
  }

  List<RecordData> _getFilteredRecords(List<RecordData> allRecords) {
    final now = DateTime.now();
    DateTime startDate;

    if (_dataRange == '7 days') {
      startDate = now.subtract(const Duration(days: 7));
    } else if (_dataRange == '30 days') {
      startDate = now.subtract(const Duration(days: 30));
    } else {
      startDate = now.subtract(const Duration(days: 90));
    }

    final filtered = allRecords
        .where((r) => r.recordTime.isAfter(startDate))
        .toList();

    return filtered;
  }
  
  Map<String, Map<String, dynamic>> _getDailyAverages(List<RecordData> allRecords) {
    final filtered = allRecords
        .where((r) => r.recordTime.isAfter(DateTime.now().subtract(const Duration(days: 30))))
        .toList();
        
    final Map<String, List<RecordData>> groupedByDay = {};

    for (var record in filtered) {
      final dayKey = DateFormat('yyyy-MM-dd').format(record.recordTime); 
      groupedByDay.putIfAbsent(dayKey, () => []).add(record);
    }

    final Map<String, Map<String, dynamic>> dailyAverages = {};

    groupedByDay.forEach((dayKey, recordsOfDay) {
      if (recordsOfDay.isNotEmpty) {
        final sysList = recordsOfDay.map((r) => r.systolicBloodPressure).whereType<int>().toList();
        final diaList = recordsOfDay.map((r) => r.diastolicBloodPressure).whereType<int>().toList();
        final gluList = recordsOfDay.map((r) => r.bloodGlucose).whereType<int>().toList();
        final weightList = recordsOfDay.map((r) => r.weight).whereType<double>().toList();

        final avgSys = sysList.isNotEmpty ? (sysList.reduce((a, b) => a + b) / sysList.length).round() : null;
        final avgDia = diaList.isNotEmpty ? (diaList.reduce((a, b) => a + b) / diaList.length).round() : null;
        final avgGlu = gluList.isNotEmpty ? (gluList.reduce((a, b) => a + b) / gluList.length).round() : null;
        final avgWeight = weightList.isNotEmpty ? (weightList.reduce((a, b) => a + b) / weightList.length) : null;

        dailyAverages[dayKey] = {
          'avgSys': avgSys,
          'avgDia': avgDia,
          'avgGlu': avgGlu,
          'avgWeight': avgWeight,
          'count': recordsOfDay.length,
        };
      }
    });

    return dailyAverages;
  }
  
  // 根據血糖值和測量時機返回顏色
  Color _getGlucosePointColor(int value, String? timing) {
    final isFasting = timing == 'fasting' || timing == 'before_meal';
    final maxNormal = isFasting ? 100 : 140;

    if (value < 70) return AppColors.error; // 過低 - 紅色
    if (value > maxNormal) return AppColors.warning; // 偏高 - 橘色
    return AppColors.success; // 正常 - 綠色
  }

  // 取得血糖測量時機標籤
  String _getGlucoseTimingLabel(String? timing) {
    switch (timing) {
      case 'fasting':
        return '空腹';
      case 'before_meal':
        return '餐前';
      case 'after_meal':
        return '餐後';
      case 'bedtime':
        return '睡前';
      case 'random':
        return '隨機';
      default:
        return '';
    }
  }

  // 回傳 LineChartBarData 和對應的日期列表
  ({LineChartBarData barData, List<DateTime> dates}) _getChartBarDataWithDates(
    String type,
    Color color,
    List<RecordData> records,
  ) {
    final List<FlSpot> spots = [];
    final List<DateTime> dates = [];

    final List<RecordData> dataPoints = records.where((r) {
      switch (type) {
        case 'systolic':
          return r.systolicBloodPressure != null;
        case 'diastolic':
          return r.diastolicBloodPressure != null;
        case 'glucose':
          return r.bloodGlucose != null;
        case 'weight':
          return r.weight != null;
        default:
          return false;
      }
    }).toList();

    for (var i = 0; i < dataPoints.length; i++) {
        final record = dataPoints[i];
        double? yValue;

        switch (type) {
          case 'systolic':
            yValue = record.systolicBloodPressure?.toDouble();
            break;
          case 'diastolic':
            yValue = record.diastolicBloodPressure?.toDouble();
            break;
          case 'glucose':
            yValue = record.bloodGlucose?.toDouble();
            break;
          case 'weight':
            yValue = record.weight;
            break;
        }

        if (yValue != null) {
            spots.add(FlSpot(i.toDouble(), yValue));
            dates.add(record.recordTime);
        }
    }

    return (
      barData: LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 3,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(
          show: true,
          color: color.withAlpha(25),
        ),
      ),
      dates: dates,
    );
  }

  // 專門為血糖圖表建立帶顏色標記的資料
  ({LineChartBarData barData, List<DateTime> dates, List<RecordData> glucoseRecords}) _getGlucoseChartData(
    List<RecordData> records,
  ) {
    final List<FlSpot> spots = [];
    final List<DateTime> dates = [];
    final List<RecordData> glucoseRecords = [];

    final dataPoints = records.where((r) => r.bloodGlucose != null).toList();

    for (var i = 0; i < dataPoints.length; i++) {
      final record = dataPoints[i];
      final yValue = record.bloodGlucose?.toDouble();

      if (yValue != null) {
        spots.add(FlSpot(i.toDouble(), yValue));
        dates.add(record.recordTime);
        glucoseRecords.add(record);
      }
    }

    return (
      barData: LineChartBarData(
        spots: spots,
        isCurved: true,
        color: AppColors.warning,
        barWidth: 3,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) {
            if (index >= glucoseRecords.length) {
              return FlDotCirclePainter(
                radius: 4,
                color: AppColors.warning,
                strokeWidth: 2,
                strokeColor: Colors.white,
              );
            }
            final record = glucoseRecords[index];
            final color = _getGlucosePointColor(
              record.bloodGlucose ?? 0,
              record.glucoseTiming,
            );
            return FlDotCirclePainter(
              radius: 5,
              color: color,
              strokeWidth: 2,
              strokeColor: Colors.white,
            );
          },
        ),
        belowBarData: BarAreaData(
          show: true,
          color: AppColors.warning.withAlpha(25),
        ),
      ),
      dates: dates,
      glucoseRecords: glucoseRecords,
    );
  }

  List<Widget> _buildDailyAverageList(List<RecordData> allRecords) {
    final dailyAverages = _getDailyAverages(allRecords);

    if (dailyAverages.isEmpty) {
      return [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: ExpansionTile(
            title: const Text(
              '最近 30 天每日平均數據 (0 天)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Center(child: Text('此範圍內沒有可用的每日平均數據。', style: TextStyle(color: Colors.grey))),
              ),
            ],
          ),
        ),
      ];
    }

    final sortedDayKeys = dailyAverages.keys.toList();
    sortedDayKeys.sort((a, b) => b.compareTo(a));

    return [
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: ExpansionTile(
          title: Text(
            '最近 30 天每日平均數據 (${sortedDayKeys.length} 天)',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          initiallyExpanded: false, // 改为 false，默认收起
          children: sortedDayKeys.map((dayKey) {
            final data = dailyAverages[dayKey]!;
            final displayDate = DateFormat('MM月dd日 (EEE)').format(DateTime.parse(dayKey));
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 日期標題
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.blue[700],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        displayDate,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 12, color: Colors.grey),
                  
                  // 數據內容 - 直接顯示全部數據
                  _buildDetailRow('收縮壓 (平均)', data['avgSys'] != null ? '${data['avgSys']} mmHg' : 'N/A', AppColors.error),
                  _buildDetailRow('舒張壓 (平均)', data['avgDia'] != null ? '${data['avgDia']} mmHg' : 'N/A', AppColors.primary),
                  _buildDetailRow('血糖 (平均)', data['avgGlu'] != null ? '${data['avgGlu']} mg/dL' : 'N/A', AppColors.warning),
                  _buildDetailRow('體重 (平均)', data['avgWeight'] != null ? '${data['avgWeight']!.toStringAsFixed(1)} kg' : 'N/A', AppColors.success),
                  _buildDetailRow('記錄次數', '${data['count']} 次', Colors.black54),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('健康分析'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: StreamBuilder<List<RecordData>>(
          stream: _getHealthRecordsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 60, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    const Text('載入數據失敗', style: TextStyle(fontSize: 18, color: Colors.red)),
                  ],
                ),
              );
            }

            final allRecords = snapshot.data ?? [];
            if (allRecords.isEmpty) {
                 return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          Icon(Icons.monitor_heart_outlined, size: 80, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('尚無健康記錄數據', style: TextStyle(fontSize: 18, color: Colors.grey)),
                          SizedBox(height: 8),
                          Text('請在「記錄」頁面新增健康數據', style: TextStyle(fontSize: 14, color: Colors.grey)),
                      ],
                    ),
                  );
            }
            
            final filteredRecords = _getFilteredRecords(allRecords);

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _buildAIAdviceSection(filteredRecords),
                  const SizedBox(height: 25),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.insights_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              '趨勢分析',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        // 高級時間選擇器
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              _buildTimeRangeChip(0, '7天'),
                              _buildTimeRangeChip(1, '30天'),
                              _buildTimeRangeChip(2, '90天'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),

                  // 血壓趨勢
                  _buildChartCard(
                      title: '血壓趨勢 (收縮壓/舒張壓)',
                      filteredRecords: filteredRecords,
                      type: 'bloodPressure'),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegend(AppColors.error, '收縮壓'),
                        const SizedBox(width: 20),
                        _buildLegend(AppColors.primary, '舒張壓'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),
                  
                  // 血糖趨勢
                  _buildChartCard(
                      title: '血糖趨勢 (mg/dL)',
                      filteredRecords: filteredRecords,
                      type: 'bloodGlucose'),

                  const SizedBox(height: 25),

                  // 體重趨勢
                  _buildChartCard(
                      title: '體重趨勢 (kg)',
                      filteredRecords: filteredRecords,
                      type: 'weight'),

                  const SizedBox(height: 25),
                  
                  // 最近30天每日平均數據（下拉式）
                  Column(
                    children: _buildDailyAverageList(allRecords),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildChartCard({
    required String title,
    required List<RecordData> filteredRecords,
    required String type,
  }) {
    final hasData = filteredRecords.any((r) {
      switch (type) {
        case 'bloodPressure':
          return r.systolicBloodPressure != null || r.diastolicBloodPressure != null;
        case 'bloodGlucose':
          return r.bloodGlucose != null;
        case 'weight':
          return r.weight != null;
        default:
          return false;
      }
    });

    if (!hasData) {
      Color emptyStateColor;
      switch (type) {
        case 'bloodPressure':
          emptyStateColor = AppColors.error;
          break;
        case 'bloodGlucose':
          emptyStateColor = AppColors.warning;
          break;
        case 'weight':
          emptyStateColor = AppColors.success;
          break;
        default:
          emptyStateColor = AppColors.primary;
      }

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: emptyStateColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _getChartIcon(type),
                    color: emptyStateColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  title.split(' ')[0],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Icon(
              Icons.insert_chart_outlined_rounded,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              '$_dataRange 內尚無${title.split(' ')[0]}數據',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '請新增記錄以查看趨勢分析',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      );
    }
    
    LineChartData chartData;
    double minY, maxY;

    // 動態計算 Y 軸範圍，根據實際數據調整
    switch (type) {
      case 'bloodPressure':
        final sysValues = filteredRecords
            .map((r) => r.systolicBloodPressure)
            .whereType<int>()
            .toList();
        final diaValues = filteredRecords
            .map((r) => r.diastolicBloodPressure)
            .whereType<int>()
            .toList();
        final allBPValues = [...sysValues, ...diaValues];
        if (allBPValues.isNotEmpty) {
          final dataMin = allBPValues.reduce((a, b) => a < b ? a : b).toDouble();
          final dataMax = allBPValues.reduce((a, b) => a > b ? a : b).toDouble();
          // 對齊到 20 的倍數
          minY = ((dataMin - 10) / 20).floor() * 20.0;
          minY = minY.clamp(40, double.infinity);
          maxY = ((dataMax + 10) / 20).ceil() * 20.0;
          if (maxY - minY < 40) maxY = minY + 40;
        } else {
          minY = 60;
          maxY = 160;
        }
        break;
      case 'bloodGlucose':
        final glucoseValues = filteredRecords
            .map((r) => r.bloodGlucose)
            .whereType<int>()
            .toList();
        if (glucoseValues.isNotEmpty) {
          final dataMin = glucoseValues.reduce((a, b) => a < b ? a : b).toDouble();
          final dataMax = glucoseValues.reduce((a, b) => a > b ? a : b).toDouble();
          // 對齊到 20 的倍數
          minY = ((dataMin - 10) / 20).floor() * 20.0;
          minY = minY.clamp(0, double.infinity);
          maxY = ((dataMax + 10) / 20).ceil() * 20.0;
          if (maxY - minY < 40) maxY = minY + 40;
        } else {
          minY = 70;
          maxY = 200;
        }
        break;
      case 'weight':
        final weightValues = filteredRecords
            .map((r) => r.weight)
            .whereType<double>()
            .toList();
        if (weightValues.isNotEmpty) {
          final dataMin = weightValues.reduce((a, b) => a < b ? a : b);
          final dataMax = weightValues.reduce((a, b) => a > b ? a : b);
          // 對齊到 5 的倍數，讓刻度更整齊
          minY = ((dataMin - 5) / 5).floor() * 5.0;
          minY = minY.clamp(30, double.infinity); // 最低不低於 30kg
          maxY = ((dataMax + 5) / 5).ceil() * 5.0;
          // 確保範圍至少有 10kg，避免刻度太擠
          if (maxY - minY < 10) {
            maxY = minY + 10;
          }
        } else {
          minY = 50;
          maxY = 100;
        }
        break;
      default:
        minY = 0;
        maxY = 100;
    }
    
    List<LineChartBarData> lineBarsData = [];
    List<DateTime> chartDates = [];
    List<RecordData> glucoseRecordsForTooltip = [];
    Color chartColor;

    switch (type) {
      case 'bloodPressure':
        final sysResult = _getChartBarDataWithDates('systolic', AppColors.error, filteredRecords);
        final diaResult = _getChartBarDataWithDates('diastolic', AppColors.primary, filteredRecords);
        lineBarsData.add(sysResult.barData);
        lineBarsData.add(diaResult.barData);
        chartDates = sysResult.dates.isNotEmpty ? sysResult.dates : diaResult.dates;
        chartColor = AppColors.primary;
        break;
      case 'bloodGlucose':
        final glucoseResult = _getGlucoseChartData(filteredRecords);
        lineBarsData.add(glucoseResult.barData);
        chartDates = glucoseResult.dates;
        glucoseRecordsForTooltip = glucoseResult.glucoseRecords;
        chartColor = AppColors.warning;
        break;
      case 'weight':
        final result = _getChartBarDataWithDates('weight', AppColors.success, filteredRecords);
        lineBarsData.add(result.barData);
        chartDates = result.dates;
        chartColor = AppColors.success;
        break;
      default:
        final result = _getChartBarDataWithDates('glucose', AppColors.warning, filteredRecords);
        lineBarsData.add(result.barData);
        chartDates = result.dates;
        chartColor = AppColors.warning;
    }

    final maxSpots = lineBarsData.fold<int>(0, (prev, bar) => max(prev, bar.spots.length));
    final maxX = (maxSpots > 0 ? maxSpots - 1 : 0).toDouble();

    // 計算合適的 Y 軸間隔，確保刻度不會太密集
    final yRange = maxY - minY;
    final yInterval = yRange <= 20 ? 5.0
                    : yRange <= 50 ? 10.0
                    : yRange <= 100 ? 20.0
                    : (yRange / 5).roundToDouble();

    // 計算 X 軸顯示間隔，避免日期太擠
    final xInterval = maxSpots <= 5 ? 1.0
                    : maxSpots <= 10 ? 2.0
                    : maxSpots <= 20 ? 4.0
                    : (maxSpots / 5).roundToDouble();

    // 血糖圖表的目標範圍線
    ExtraLinesData? extraLinesData;
    if (type == 'bloodGlucose') {
      extraLinesData = ExtraLinesData(
        horizontalLines: [
          // 低血糖警戒線 70
          HorizontalLine(
            y: 70,
            color: AppColors.error.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: [5, 5],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: TextStyle(fontSize: 10, color: AppColors.error),
              labelResolver: (_) => '70 低',
            ),
          ),
          // 空腹正常上限 100
          HorizontalLine(
            y: 100,
            color: AppColors.success.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: [5, 5],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: TextStyle(fontSize: 10, color: AppColors.success),
              labelResolver: (_) => '100 空腹',
            ),
          ),
          // 餐後正常上限 140
          HorizontalLine(
            y: 140,
            color: AppColors.warning.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: [5, 5],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: TextStyle(fontSize: 10, color: AppColors.warning),
              labelResolver: (_) => '140 餐後',
            ),
          ),
        ],
      );
    }

    // 血糖圖表的觸控提示
    LineTouchData? touchData;
    if (type == 'bloodGlucose' && glucoseRecordsForTooltip.isNotEmpty) {
      touchData = LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: Colors.black87,
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final index = spot.spotIndex;
              if (index < 0 || index >= glucoseRecordsForTooltip.length) {
                return LineTooltipItem(
                  '${spot.y.toInt()} mg/dL',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              }
              final record = glucoseRecordsForTooltip[index];
              final timingLabel = _getGlucoseTimingLabel(record.glucoseTiming);
              final dateLabel = DateFormat('M/d HH:mm').format(record.recordTime);
              return LineTooltipItem(
                '${spot.y.toInt()} mg/dL\n${timingLabel.isNotEmpty ? '$timingLabel · ' : ''}$dateLabel',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              );
            }).toList();
          },
        ),
      );
    }

    chartData = LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: yInterval,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: AppColors.border, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: yInterval,
            getTitlesWidget: (value, meta) {
              if (value < minY || value > maxY) {
                return const SizedBox.shrink();
              }
              return Text(
                value.toInt().toString(),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: xInterval,
            reservedSize: 30,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (i < 0 || i >= chartDates.length || value != i.toDouble()) {
                return const SizedBox.shrink();
              }
              // 顯示日期格式 MM/dd
              final date = chartDates[i];
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  DateFormat('M/d').format(date),
                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                ),
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      lineBarsData: lineBarsData,
      extraLinesData: extraLinesData ?? const ExtraLinesData(),
      lineTouchData: touchData ?? const LineTouchData(),
    );

    // 計算最新數值和趨勢
    String latestValue = '--';
    String trendText = '';
    IconData trendIcon = Icons.remove;
    Color trendColor = Colors.grey;

    switch (type) {
      case 'bloodPressure':
        final sysRecords = filteredRecords.where((r) => r.systolicBloodPressure != null).toList();
        if (sysRecords.isNotEmpty) {
          final latest = sysRecords.last;
          latestValue = '${latest.systolicBloodPressure}/${latest.diastolicBloodPressure}';
          if (sysRecords.length >= 2) {
            final prev = sysRecords[sysRecords.length - 2];
            final diff = (latest.systolicBloodPressure ?? 0) - (prev.systolicBloodPressure ?? 0);
            if (diff > 0) {
              trendIcon = Icons.trending_up_rounded;
              trendColor = const Color(0xFFFF6B6B);
              trendText = '+$diff';
            } else if (diff < 0) {
              trendIcon = Icons.trending_down_rounded;
              trendColor = const Color(0xFF4ADE80);
              trendText = '$diff';
            } else {
              trendIcon = Icons.trending_flat_rounded;
              trendColor = Colors.grey;
              trendText = '持平';
            }
          }
        }
        break;
      case 'bloodGlucose':
        final gluRecords = filteredRecords.where((r) => r.bloodGlucose != null).toList();
        if (gluRecords.isNotEmpty) {
          latestValue = '${gluRecords.last.bloodGlucose}';
          if (gluRecords.length >= 2) {
            final diff = (gluRecords.last.bloodGlucose ?? 0) - (gluRecords[gluRecords.length - 2].bloodGlucose ?? 0);
            if (diff > 0) {
              trendIcon = Icons.trending_up_rounded;
              trendColor = const Color(0xFFFFB347);
              trendText = '+$diff';
            } else if (diff < 0) {
              trendIcon = Icons.trending_down_rounded;
              trendColor = const Color(0xFF4ADE80);
              trendText = '$diff';
            } else {
              trendIcon = Icons.trending_flat_rounded;
              trendColor = Colors.grey;
              trendText = '持平';
            }
          }
        }
        break;
      case 'weight':
        final weightRecords = filteredRecords.where((r) => r.weight != null).toList();
        if (weightRecords.isNotEmpty) {
          latestValue = weightRecords.last.weight!.toStringAsFixed(1);
          if (weightRecords.length >= 2) {
            final diff = (weightRecords.last.weight ?? 0) - (weightRecords[weightRecords.length - 2].weight ?? 0);
            if (diff > 0.1) {
              trendIcon = Icons.trending_up_rounded;
              trendColor = const Color(0xFFFFB347);
              trendText = '+${diff.toStringAsFixed(1)}';
            } else if (diff < -0.1) {
              trendIcon = Icons.trending_down_rounded;
              trendColor = const Color(0xFF4ADE80);
              trendText = diff.toStringAsFixed(1);
            } else {
              trendIcon = Icons.trending_flat_rounded;
              trendColor = Colors.grey;
              trendText = '持平';
            }
          }
        }
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: chartColor.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 標題區域
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                // 圖標容器
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        chartColor.withValues(alpha: 0.15),
                        chartColor.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _getChartIcon(type),
                    color: chartColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // 標題和數值
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.split(' ')[0],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title.contains('(') ? title.split('(')[1].replaceAll(')', '') : '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                // 最新數值
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      latestValue,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: chartColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (trendText.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(trendIcon, size: 14, color: trendColor),
                          const SizedBox(width: 2),
                          Text(
                            trendText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: trendColor,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          // 分隔線
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  chartColor.withValues(alpha: 0.15),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // 圖表區域
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 20, 20),
            child: SizedBox(
              height: 160,
              child: LineChart(chartData),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getChartIcon(String type) {
    switch (type) {
      case 'bloodPressure':
        return Icons.monitor_heart_rounded;
      case 'bloodGlucose':
        return Icons.bloodtype_rounded;
      case 'weight':
        return Icons.monitor_weight_rounded;
      default:
        return Icons.show_chart_rounded;
    }
  }

  /// 時間範圍選擇 Chip
  Widget _buildTimeRangeChip(int index, String label) {
    final isSelected = _chartRange == index;
    return GestureDetector(
      onTap: () => _updateDataRangeFromChartRange(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
  
  Widget _buildAIAdviceSection(List<RecordData> filteredRecords) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
            const Color(0xFF1A237E),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題區域
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(51),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.psychology_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'AI 健康建議',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                // 展開/收起按鈕
                if (_aiAnalysis != null)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isAIExpanded = !_isAIExpanded;
                      });
                    },
                    child: Icon(
                      _isAIExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
              ],
            ),
          ),

          // AI 分析內容
          if (_isLoadingAI)
            _buildLoadingState()
          else if (_aiError != null)
            _buildErrorState()
          else if (_aiAnalysis != null && _isAIExpanded)
            _buildAnalysisContent()
          else
            _buildInitialState(filteredRecords),
        ],
      ),
    );
  }

  /// 載入中狀態
  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 16),
            const Text(
              '正在分析您的健康數據...',
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              '這可能需要幾秒鐘',
              style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(128)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// 錯誤狀態
  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(51),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _aiError ?? '發生未知錯誤',
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _fetchAIAnalysis,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重試'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withAlpha(51),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// AI 分析內容
  Widget _buildAnalysisContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 資料來源提示
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  '已讀取您的健康紀錄、用藥與飲食資料',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              _aiAnalysis ?? '',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _fetchAIAnalysis,
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                label: const Text(
                  '重新分析',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 初始狀態（尚未取得 AI 分析）- 高級設計版
  Widget _buildInitialState(List<RecordData> filteredRecords) {
    final bloodPressureRecords = filteredRecords
        .where((r) =>
            r.systolicBloodPressure != null || r.diastolicBloodPressure != null)
        .toList();
    final glucoseRecords =
        filteredRecords.where((r) => r.bloodGlucose != null).toList();
    final weightRecords =
        filteredRecords.where((r) => r.weight != null).toList();

    final allSys = bloodPressureRecords
        .map((r) => r.systolicBloodPressure)
        .whereType<int>()
        .toList();
    final allDia = bloodPressureRecords
        .map((r) => r.diastolicBloodPressure)
        .whereType<int>()
        .toList();
    final allGlu =
        glucoseRecords.map((r) => r.bloodGlucose).whereType<int>().toList();
    final allWeight =
        weightRecords.map((r) => r.weight).whereType<double>().toList();

    final avgSys = allSys.isNotEmpty
        ? (allSys.reduce((a, b) => a + b) / allSys.length).round()
        : null;
    final avgDia = allDia.isNotEmpty
        ? (allDia.reduce((a, b) => a + b) / allDia.length).round()
        : null;
    final avgGlu = allGlu.isNotEmpty
        ? (allGlu.reduce((a, b) => a + b) / allGlu.length).round()
        : null;
    final avgWeight = allWeight.isNotEmpty
        ? (allWeight.reduce((a, b) => a + b) / allWeight.length)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 健康數據卡片網格
          Row(
            children: [
              Expanded(
                child: _buildPremiumHealthCard(
                  icon: Icons.favorite_rounded,
                  label: '血壓',
                  value: avgSys != null ? '$avgSys/$avgDia' : '--/--',
                  unit: 'mmHg',
                  status: avgSys != null
                      ? (avgSys > 140 ? 'warning' : 'normal')
                      : 'noData',
                  gradientColors: [
                    const Color(0xFFFF6B6B),
                    const Color(0xFFEE5A5A),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPremiumHealthCard(
                  icon: Icons.water_drop_rounded,
                  label: '血糖',
                  value: avgGlu?.toString() ?? '--',
                  unit: 'mg/dL',
                  status: avgGlu != null
                      ? (avgGlu > 140 ? 'warning' : (avgGlu < 70 ? 'low' : 'normal'))
                      : 'noData',
                  gradientColors: [
                    const Color(0xFFFFB347),
                    const Color(0xFFFF9500),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildPremiumHealthCard(
                  icon: Icons.monitor_weight_rounded,
                  label: '體重',
                  value: avgWeight?.toStringAsFixed(1) ?? '--',
                  unit: 'kg',
                  status: 'normal',
                  gradientColors: [
                    const Color(0xFF4ECDC4),
                    const Color(0xFF44A08D),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPremiumHealthCard(
                  icon: Icons.monitor_heart_rounded,
                  label: '記錄',
                  value: '${filteredRecords.length}',
                  unit: '筆',
                  status: 'info',
                  gradientColors: [
                    const Color(0xFF667EEA),
                    const Color(0xFF764BA2),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 取得 AI 詳細分析按鈕
          Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: AIService.instance.isConfigured ? _fetchAIAnalysis : null,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  AIService.instance.isConfigured ? '取得 AI 詳細分析' : 'AI 功能未設定',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primaryDark,
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
                  disabledForegroundColor: Colors.white70,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 高級健康數據卡片
  Widget _buildPremiumHealthCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required String status,
    required List<Color> gradientColors,
  }) {
    IconData statusIcon;
    Color statusColor;

    switch (status) {
      case 'warning':
        statusIcon = Icons.warning_rounded;
        statusColor = Colors.amber;
        break;
      case 'low':
        statusIcon = Icons.arrow_downward_rounded;
        statusColor = Colors.redAccent;
        break;
      case 'info':
        statusIcon = Icons.info_outline_rounded;
        statusColor = Colors.white70;
        break;
      case 'noData':
        statusIcon = Icons.remove_circle_outline_rounded;
        statusColor = Colors.white54;
        break;
      default:
        statusIcon = Icons.check_circle_rounded;
        statusColor = const Color(0xFF4ADE80);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.25),
            Colors.white.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors[0].withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              Icon(statusIcon, color: statusColor, size: 18),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.8),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
  
  Widget _buildDetailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}