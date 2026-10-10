import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/health_category.dart';
import '../models/record_data.dart';
import '../services/firestore_service.dart';
import '../services/health_alert_service.dart';
import '../theme/app_colors.dart';
import '../widgets/category_selector.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestoreService = FirestoreService();

  String selectedCategory = '全部';
  final Set<String> _collapsedDates = {};

  // 選擇分類
  void _selectCategory(String? category) {
    setState(() {
      selectedCategory = category ?? '全部';
    });
  }

  // 將類別轉成 Icon（使用 Registry）
  IconData _getCategoryIcon(String category) {
    return HealthCategoryRegistry.getIcon(category);
  }

  // 將類別轉成顏色（使用 Registry）
  Color _getCategoryColor(String category) {
    return HealthCategoryRegistry.getColor(category);
  }

  // 取得預設單位（使用 Registry）
  Map<String, String> _getDefaultValueParts(String category) {
    return HealthCategoryRegistry.getDefaultValueParts(category);
  }

  // 顯示新增／修改紀錄表單
  void _showRecordForm({DocumentSnapshot? record}) {
    // 記下這個畫面本身的 context（而不是等一下輸入視窗自己的 context）。
    // 輸入視窗存檔後會被 Navigator.pop 關掉，若健康數值警示對話框沿用
    // 輸入視窗的 context，一旦該 context 提早失效，警示就可能悄悄被跳過；
    // 改用畫面自身的 context 才能確保只要「紀錄」分頁還在，警示一定顯示得出來。
    final screenContext = context;
    final category = selectedCategory == '全部'
        ? '血壓'
        : selectedCategory; // 預設血壓類別
    final parts = _getDefaultValueParts(category);

    // 血壓需要兩個輸入欄位
    final systolicController = TextEditingController();
    final diastolicController = TextEditingController();
    final valueController = TextEditingController(
      text: record?['value']
              ?.toString()
              .replaceAll(parts['unit']!, '')
              .trim() ??
          '',
    );

    // 睡眠和運動的滑桿值
    double sleepHours = 7.0;
    double exerciseMinutes = 30.0;
    String exerciseType = '跑步';

    // 血糖測量時機 - 安全存取欄位
    String? selectedGlucoseTiming;
    if (record != null) {
      final recordData = record.data() as Map<String, dynamic>? ?? {};
      if (recordData.containsKey('glucose_timing')) {
        selectedGlucoseTiming = recordData['glucose_timing'] as String?;
      }
    }

    // 如果是編輯記錄，解析現有值
    if (record != null) {
      final recordValue = record['value']?.toString() ?? '';

      if (category == '血壓') {
        final match = RegExp(r'(\d+)/(\d+)').firstMatch(recordValue);
        if (match != null) {
          systolicController.text = match.group(1) ?? '';
          diastolicController.text = match.group(2) ?? '';
        }
      } else if (category == '睡眠') {
        final match = RegExp(r'(\d+\.?\d*)').firstMatch(recordValue);
        if (match != null) {
          sleepHours = double.tryParse(match.group(1) ?? '7') ?? 7.0;
        }
      } else if (category == '運動') {
        // 解析運動類型和時間，格式：「跑步 30 分鐘」
        final match = RegExp(r'(.+?)\s+(\d+)').firstMatch(recordValue);
        if (match != null) {
          exerciseType = match.group(1) ?? '跑步';
          exerciseMinutes = double.tryParse(match.group(2) ?? '30') ?? 30.0;
        }
      }
    }

    DateTime selectedTime =
        (record?['record_time'] as Timestamp?)?.toDate() ?? DateTime.now();

    Future<void> selectTime() async {
      final TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(selectedTime),
      );
      if (picked != null) {
        setState(() {
          selectedTime = DateTime(
            selectedTime.year,
            selectedTime.month,
            selectedTime.day,
            picked.hour,
            picked.minute,
          );
        });
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getCategoryColor(category).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Icon(
                        _getCategoryIcon(category),
                        color: _getCategoryColor(category),
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    record == null ? '新增紀錄' : '修改紀錄',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 血壓需要顯示兩個輸入欄位
                      if (category == '血壓') ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: systolicController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: '收縮壓',
                                  hintText: '120',
                                  suffixText: 'mmHg',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text('/', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                            ),
                            Expanded(
                              child: TextField(
                                controller: diastolicController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: '舒張壓',
                                  hintText: '80',
                                  suffixText: 'mmHg',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else if (category == '睡眠') ...[
                      // 睡眠滑桿
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '睡眠時長',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${sleepHours.toStringAsFixed(1)} 小時',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Slider(
                            value: sleepHours,
                            min: 4.0,
                            max: 12.0,
                            divisions: 80,
                            activeColor: AppColors.primary,
                            inactiveColor: Colors.grey.shade300,
                            label: '${sleepHours.toStringAsFixed(1)} 小時',
                            onChanged: (value) {
                              setDialogState(() {
                                sleepHours = value;
                              });
                            },
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '4 小時',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '12 小時',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ] else if (category == '運動') ...[
                      // 運動類型選擇
                      DropdownButtonFormField<String>(
                        initialValue: exerciseType,
                        decoration: InputDecoration(
                          labelText: '運動類型',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: [
                          DropdownMenuItem(value: '跑步', child: Row(children: [Icon(Icons.directions_run_rounded, size: 20, color: AppColors.primary), const SizedBox(width: 8), const Text('跑步')])),
                          DropdownMenuItem(value: '走路', child: Row(children: [Icon(Icons.directions_walk_rounded, size: 20, color: AppColors.primary), const SizedBox(width: 8), const Text('走路')])),
                          DropdownMenuItem(value: '騎車', child: Row(children: [Icon(Icons.directions_bike_rounded, size: 20, color: AppColors.primary), const SizedBox(width: 8), const Text('騎車')])),
                          DropdownMenuItem(value: '游泳', child: Row(children: [Icon(Icons.pool_rounded, size: 20, color: AppColors.primary), const SizedBox(width: 8), const Text('游泳')])),
                          DropdownMenuItem(value: '瑜珈', child: Row(children: [Icon(Icons.self_improvement_rounded, size: 20, color: AppColors.sleep), const SizedBox(width: 8), const Text('瑜珈')])),
                          DropdownMenuItem(value: '重訓', child: Row(children: [Icon(Icons.fitness_center_rounded, size: 20, color: AppColors.error), const SizedBox(width: 8), const Text('重訓')])),
                          DropdownMenuItem(value: '球類運動', child: Row(children: [Icon(Icons.sports_soccer_rounded, size: 20, color: AppColors.primary), const SizedBox(width: 8), const Text('球類運動')])),
                          DropdownMenuItem(value: '其他', child: Row(children: [Icon(Icons.sports_rounded, size: 20, color: AppColors.textSecondary), const SizedBox(width: 8), const Text('其他')])),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            exerciseType = value ?? '跑步';
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      // 運動時間滑桿
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '運動時長',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${exerciseMinutes.toInt()} 分鐘',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Slider(
                            value: exerciseMinutes,
                            min: 5.0,
                            max: 180.0,
                            divisions: 175,
                            activeColor: AppColors.primary,
                            inactiveColor: Colors.grey.shade300,
                            label: '${exerciseMinutes.toInt()} 分鐘',
                            onChanged: (value) {
                              setDialogState(() {
                                exerciseMinutes = value;
                              });
                            },
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '5 分鐘',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '180 分鐘',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ] else if (category == '心率') ...[
                      // 心率數值輸入
                      TextField(
                        controller: valueController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '心率',
                          hintText: '72',
                          suffixText: 'bpm',
                          prefixIcon: const Icon(
                            Icons.monitor_heart_rounded,
                            color: AppColors.heartRate,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 心率參考範圍提示
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.heartRateLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: AppColors.heartRate),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '正常靜息心率：60-100 bpm',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.heartRate,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (category == '血糖') ...[
                      // 血糖數值輸入
                      TextField(
                        controller: valueController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '血糖值',
                          hintText: '100',
                          suffixText: 'mg/dL',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 測量時機選擇
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '測量時機',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: RecordData.glucoseTimingOptions.map((option) {
                              final isSelected = selectedGlucoseTiming == option['value'];
                              return ChoiceChip(
                                label: Text(option['label']!),
                                selected: isSelected,
                                selectedColor: AppColors.warning.withValues(alpha: 0.3),
                                backgroundColor: Colors.grey.shade100,
                                labelStyle: TextStyle(
                                  color: isSelected ? AppColors.warning : Colors.black87,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                                onSelected: (selected) {
                                  setDialogState(() {
                                    selectedGlucoseTiming = selected ? option['value'] : null;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ] else ...[
                      TextField(
                        controller: valueController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '數值',
                          hintText: '${parts['value']} ${parts['unit']}',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      ],
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: selectTime,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Text(
                                DateFormat('yyyy/MM/dd HH:mm').format(selectedTime),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    // 根據不同類別處理數值
                    String finalValue;
                    if (category == '血壓') {
                      if (systolicController.text.trim().isEmpty ||
                          diastolicController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('請輸入收縮壓和舒張壓'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }
                      finalValue = '${systolicController.text.trim()}/${diastolicController.text.trim()} ${parts['unit']}';
                    } else if (category == '睡眠') {
                      finalValue = '${sleepHours.toStringAsFixed(1)} ${parts['unit']}';
                    } else if (category == '運動') {
                      finalValue = '$exerciseType ${exerciseMinutes.toInt()} ${parts['unit']}';
                    } else {
                      if (valueController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('請輸入數值'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }
                      finalValue = '${valueController.text.trim()} ${parts['unit']}';
                    }

                    final uid = _auth.currentUser?.uid;
                    if (uid == null) return;

                    final data = {
                      'category': category,
                      'value': finalValue,
                      'unit': parts['unit'],
                      'record_time': selectedTime,
                      if (category == '血糖' && selectedGlucoseTiming != null)
                        'glucose_timing': selectedGlucoseTiming,
                    };

                    try {
                      if (record == null) {
                        await _firestoreService.addHealthRecord(data);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('記錄已新增'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } else {
                        await _firestoreService.updateHealthRecord(record.id, data);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('記錄已更新'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('儲存失敗：${e.toString().replaceAll('Exception: ', '')}'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                      return; // 失敗時不繼續執行後續邏輯
                    }

                    // 健康數值警示檢查
                    // 注意：這裡用的是畫面自身的 screenContext，不是上面已經
                    // Navigator.pop 掉的輸入視窗 context，避免警示被悄悄跳過。
                    if (screenContext.mounted) {
                      final alertService = HealthAlertService();
                      HealthAlertResult? alertResult;

                      if (category == '血壓') {
                        final sys = int.tryParse(systolicController.text.trim());
                        final dia = int.tryParse(diastolicController.text.trim());
                        if (sys != null && dia != null) {
                          alertResult = alertService.checkBloodPressure(sys, dia);
                        }
                      } else if (category == '血糖') {
                        final glucose = int.tryParse(valueController.text.trim());
                        if (glucose != null) {
                          alertResult = alertService.checkBloodGlucose(
                            glucose,
                            timing: selectedGlucoseTiming,
                          );
                        }
                      } else if (category == '心率') {
                        final hr = int.tryParse(valueController.text.trim());
                        if (hr != null) {
                          alertResult = alertService.checkHeartRate(hr);
                        }
                      }

                      // 顯示警示對話框
                      if (alertResult != null && alertResult.isOutOfRange && screenContext.mounted) {
                        await alertService.showAlertDialog(screenContext, alertResult);
                        // 危險值發送推播通知
                        if (alertResult.isCritical) {
                          await alertService.sendCriticalNotification(alertResult);
                        }
                      }
                    }
                  },
                  child: const Text('儲存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 刪除紀錄
  Future<void> _deleteRecord(String recordId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestoreService.deleteHealthRecord(recordId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('紀錄已刪除'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刪除失敗：${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // UI 區塊
  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('請先登入帳號'));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('健康記錄'),
        centerTitle: false,
        actions: [
          if (selectedCategory != '全部')
            IconButton(
              icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary),
              onPressed: () => _showRecordForm(),
              tooltip: '新增記錄',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 使用新的分類選擇器
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: CategorySelector(
                selectedCategory: selectedCategory == '全部' ? null : selectedCategory,
                onCategoryChanged: _selectCategory,
                showAllOption: true,
              ),
            ),
            const SizedBox(height: 20),

            // 從 Firestore 即時取得資料
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestoreService.getHealthRecords(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text('尚無記錄'));
                  }

                  final records = snapshot.data!.docs;
                  final filtered = selectedCategory == '全部'
                      ? records
                      : records
                          .where((doc) =>
                              doc['category'] == selectedCategory)
                          .toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text('尚無記錄'));
                  }

                  // 「全部」時按日期分組顯示
                  if (selectedCategory == '全部') {
                    // 按日期分組
                    final Map<String, List<DocumentSnapshot>> grouped = {};
                    for (final doc in filtered) {
                      final time = (doc['record_time'] as Timestamp?)?.toDate();
                      final dateKey = time != null
                          ? DateFormat('yyyy/MM/dd').format(time)
                          : '無日期';
                      grouped.putIfAbsent(dateKey, () => []).add(doc);
                    }

                    // 建立有序的日期列表（最新在前）
                    final sortedDates = grouped.keys.toList()
                      ..sort((a, b) => b.compareTo(a));

                    // 展開成 [日期標題, 紀錄, 紀錄, ...] 的扁平列表（收折時只放標題）
                    final List<dynamic> items = [];
                    for (final date in sortedDates) {
                      final docsForDate = grouped[date]!;
                      items.add(_DateHeader(date, docsForDate.length));
                      if (!_collapsedDates.contains(date)) {
                        items.addAll(docsForDate);
                      }
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        if (item is _DateHeader) {
                          return _buildDateHeader(item.dateKey, item.count);
                        }
                        final record = item as DocumentSnapshot;
                        final time = (record['record_time'] as Timestamp?)?.toDate();
                        final timeText = time != null
                            ? DateFormat('HH:mm').format(time)
                            : '--';
                        return _buildRecordCard(record, timeText);
                      },
                    );
                  }

                  // 單一分類：原本的平鋪列表
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final record = filtered[index];
                      final time = (record['record_time'] as Timestamp?)?.toDate();
                      final timeText = time != null
                          ? DateFormat('MM/dd HH:mm').format(time)
                          : '無時間資料';
                      return _buildRecordCard(record, timeText);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateHeader(String dateKey, int count) {
    final now = DateTime.now();
    final today = DateFormat('yyyy/MM/dd').format(now);
    final yesterday = DateFormat('yyyy/MM/dd').format(now.subtract(const Duration(days: 1)));
    final isCollapsed = _collapsedDates.contains(dateKey);

    String label;
    if (dateKey == today) {
      label = '今天  $dateKey';
    } else if (dateKey == yesterday) {
      label = '昨天  $dateKey';
    } else {
      label = dateKey;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isCollapsed) {
            _collapsedDates.remove(dateKey);
          } else {
            _collapsedDates.add(dateKey);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count 筆',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black38,
              ),
            ),
            const Spacer(),
            Icon(
              isCollapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded,
              size: 20,
              color: Colors.black38,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCard(DocumentSnapshot record, String timeText) {
    // 將 DocumentSnapshot 轉換為 Map，以便安全存取欄位
    final data = record.data() as Map<String, dynamic>? ?? {};
    final hasGlucoseTiming = data.containsKey('glucose_timing') && data['glucose_timing'] != null;

    // 檢查資料來源
    final isFromHealthPlatform = data['source'] == 'health_platform';
    final sourceName = data['source_name'] as String?;

    return InkWell(
      onTap: () => _showRecordForm(record: record),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getCategoryColor(record['category'] ?? '').withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  _getCategoryIcon(record['category'] ?? ''),
                  color: _getCategoryColor(record['category'] ?? ''),
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        record['category'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // 顯示血糖測量時機標籤
                      if (data['category'] == '血糖' && hasGlucoseTiming) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            RecordData.glucoseTimingOptions.firstWhere(
                              (o) => o['value'] == data['glucose_timing'],
                              orElse: () => {'label': data['glucose_timing']?.toString() ?? ''},
                            )['label']!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    record['value'] ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textHint,
                  ),
                ),
                const SizedBox(height: 2),
                // 來源標示
                _buildSourceBadge(isFromHealthPlatform, sourceName),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
                  onPressed: () => _deleteRecord(record.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 建立來源標示小徽章
  Widget _buildSourceBadge(bool isFromHealthPlatform, String? sourceName) {
    if (isFromHealthPlatform) {
      return Tooltip(
        message: sourceName ?? 'Apple 健康',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.apple,
                size: 12,
                color: Colors.red.shade400,
              ),
              const SizedBox(width: 2),
              Text(
                '同步',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.red.shade400,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_rounded,
              size: 12,
              color: AppColors.primary,
            ),
            const SizedBox(width: 2),
            Text(
              '手動',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
  }

}

class _DateHeader {
  final String dateKey;
  final int count;
  const _DateHeader(this.dateKey, this.count);
}
