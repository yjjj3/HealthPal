import '../theme/app_colors.dart';
// lib/screens/medication_log_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MedicationLogScreen extends StatefulWidget {
  final Stream<QuerySnapshot> logs;

  const MedicationLogScreen({
    required this.logs,
    Key? key,
  }) : super(key: key);

  @override
  State<MedicationLogScreen> createState() => _MedicationLogScreenState();
}

class _MedicationLogScreenState extends State<MedicationLogScreen> {
  final Set<String> _expandedDates = {};

  @override
  void initState() {
    super.initState();
    // 預設展開今天的紀錄
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _expandedDates.add(today);
  }

  DateTime? _getDateTimeFromTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }
    return null;
  }

  Map<String, dynamic> _mapDocumentToLog(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      debugPrint('MedicationLog: Document ${doc.id} data is null.');
      return {};
    }

    // 處理多種可能的時間字段
    dynamic timestamp = data['intake_time'] ?? data['createdAt'] ?? data['timestamp'] ?? data['time'];
    final intakeTime = _getDateTimeFromTimestamp(timestamp);

    // 處理多種可能的藥物名稱字段
    final medicineName = data['medicine_name'] ?? data['name'] ?? data['drug_name'] ?? '未知藥物';

    // 處理劑量字段
    final dosage = data['dosage'] ?? data['dose'] ?? 1;
    final dosageTaken = data['dosage_taken'] ?? data['dose_taken'] ?? dosage;

    // 處理狀態字段
    final isTaken = data['is_taken'] as bool? ?? (data['status'] == 'taken' || data['status'] == 'completed');
    final doseNumber = data['dose_number'] as int? ?? 1;

    // 處理頻率和剩餘天數
    final frequency = data['frequency'] ?? '每日一次';
    final remainingDays = data['remaining_days'] as int? ?? 0;

    return {
      'id': doc.id,
      'name': medicineName,
      'dosage': dosageTaken,
      'time': intakeTime != null ? DateFormat('HH:mm').format(intakeTime) : 'N/A',
      'isTaken': isTaken,
      'doseNumber': doseNumber,
      'date': intakeTime != null ? DateFormat('MM/dd').format(intakeTime) : 'N/A',
      'dateTime': intakeTime,
      'frequency': frequency,
      'remainingDays': remainingDays,
    };
  }

  /// 按日期分組用藥紀錄
  Map<String, List<Map<String, dynamic>>> _groupByDate(List<Map<String, dynamic>> logs) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var log in logs) {
      final dateTime = log['dateTime'] as DateTime?;
      if (dateTime == null) continue;

      final dateKey = DateFormat('yyyy-MM-dd').format(dateTime);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(log);
    }

    return grouped;
  }

  String _formatDateHeader(String dateKey) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final recordDate = DateTime(date.year, date.month, date.day);

    if (recordDate == today) {
      return '今天 ${DateFormat('MM/dd (E)', 'zh_TW').format(date)}';
    } else if (recordDate == yesterday) {
      return '昨天 ${DateFormat('MM/dd (E)', 'zh_TW').format(date)}';
    } else {
      return DateFormat('MM/dd (EEEE)', 'zh_TW').format(date);
    }
  }

  /// 統計服藥情況
  Map<String, int> _calculateStats(List<Map<String, dynamic>> logs) {
    int taken = 0;
    int pending = 0;

    for (var log in logs) {
      if (log['isTaken'] == true) {
        taken++;
      } else {
        pending++;
      }
    }

    return {'taken': taken, 'pending': pending, 'total': logs.length};
  }

  // 將數字轉換為中文數字
  String _getChineseNumber(int number) {
    switch (number) {
      case 1:
        return '一';
      case 2:
        return '二';
      case 3:
        return '三';
      case 4:
        return '四';
      case 5:
        return '五';
      case 6:
        return '六';
      case 7:
        return '七';
      case 8:
        return '八';
      case 9:
        return '九';
      case 10:
        return '十';
      case 11:
        return '十一';
      case 12:
        return '十二';
      default:
        return number.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          '用藥日誌',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.primary),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: widget.logs,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('Firestore Stream Error: ${snapshot.error}');
            return Center(child: Text('載入日誌發生錯誤：${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.data == null || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final medicationLogs = snapshot.data!.docs
              .map(_mapDocumentToLog)
              .where((log) => log.isNotEmpty && log['dateTime'] != null)
              .toList();

          medicationLogs.sort((a, b) {
            final aDateTime = a['dateTime'] as DateTime?;
            final bDateTime = b['dateTime'] as DateTime?;
            if (aDateTime == null || bDateTime == null) return 0;
            return bDateTime.compareTo(aDateTime);
          });

          if (medicationLogs.isEmpty) {
            return _buildEmptyState();
          }

          final groupedLogs = _groupByDate(medicationLogs);
          final sortedDates = groupedLogs.keys.toList()
            ..sort((a, b) => b.compareTo(a)); // 日期降序

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: sortedDates.length,
            itemBuilder: (context, index) {
              final dateKey = sortedDates[index];
              final logs = groupedLogs[dateKey]!;
              final isExpanded = _expandedDates.contains(dateKey);
              final stats = _calculateStats(logs);

              return _buildDateSection(
                dateKey: dateKey,
                logs: logs,
                isExpanded: isExpanded,
                stats: stats,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medication_liquid, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 20),
          const Text(
            '尚無用藥紀錄',
            style: TextStyle(fontSize: 18, color: AppColors.textHint),
          ),
          const SizedBox(height: 10),
          const Text(
            '請先使用用藥提醒功能記錄您的用藥',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection({
    required String dateKey,
    required List<Map<String, dynamic>> logs,
    required bool isExpanded,
    required Map<String, int> stats,
  }) {
    final takenCount = stats['taken'] ?? 0;
    final pendingCount = stats['pending'] ?? 0;
    final totalCount = stats['total'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 日期標題（可點擊展開/收合）
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedDates.remove(dateKey);
                } else {
                  _expandedDates.add(dateKey);
                }
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // 日期圖示
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.calendar_today,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 日期和摘要
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDateHeader(dateKey),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // 已服用
                            Icon(
                              Icons.check_circle,
                              size: 14,
                              color: Colors.green[600],
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '$takenCount',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 10),
                            // 待服用
                            if (pendingCount > 0) ...[
                              Icon(
                                Icons.schedule,
                                size: 14,
                                color: Colors.orange[600],
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '$pendingCount',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.orange[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            // 總計
                            Text(
                              '共 $totalCount 筆',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 展開/收合圖示
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
          // 展開的用藥內容
          if (isExpanded) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: logs.map((log) => _buildMedicationItem(log)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMedicationItem(Map<String, dynamic> log) {
    final isTaken = log['isTaken'] as bool;
    final doseNumber = log['doseNumber'] as int;
    final dosage = log['dosage'];
    final frequency = log['frequency'] as String;
    final remainingDays = log['remainingDays'] as int;
    final medicineName = log['name'] as String;
    final time = log['time'] as String;

    // 處理劑量顯示
    final dosageText = (dosage is int || dosage is double)
        ? '$dosage 顆'
        : dosage.toString();

    // 狀態顏色
    final statusColor = isTaken ? AppColors.success : AppColors.warning;
    final statusIcon = isTaken ? Icons.check_circle : Icons.schedule;
    final statusText = isTaken ? '已服用' : '待服用';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withAlpha(80),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 狀態圖示
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(50),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              statusIcon,
              color: statusColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          // 藥物資訊
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 狀態標籤
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$medicineName ($dosageText)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                // 頻率
                Text(
                  '頻率：$frequency',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
                // 第幾次用藥
                if (doseNumber >= 1) ...[
                  const SizedBox(height: 2),
                  Text(
                    '第 ${_getChineseNumber(doseNumber)} 次用藥',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
                // 剩餘天數
                if (remainingDays > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '剩餘 $remainingDays 天',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
