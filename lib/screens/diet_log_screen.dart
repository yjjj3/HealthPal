import '../theme/app_colors.dart';
// lib/screens/diet_log_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class DietLogScreen extends StatefulWidget {
  const DietLogScreen({super.key});

  @override
  State<DietLogScreen> createState() => _DietLogScreenState();
}

class _DietLogScreenState extends State<DietLogScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Set<String> _expandedDates = {};

  @override
  void initState() {
    super.initState();
    // 預設展開今天的紀錄
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _expandedDates.add(today);
  }

  Stream<QuerySnapshot> _getDietLogsStream() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Stream.empty();
    }

    // 取得最近 30 天的飲食紀錄
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

    return _firestore
        .collection('users')
        .doc(userId)
        .collection('diet_records')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
        .orderBy('timestamp', descending: true)
        .snapshots();
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

  Color _getMealColor(String type) {
    switch (type) {
      case '早餐':
        return const Color(0xFFFFB74D); // 橙色
      case '午餐':
        return const Color(0xFF4CAF50); // 綠色
      case '晚餐':
        return const Color(0xFF5C6BC0); // 紫藍色
      case '點心':
        return const Color(0xFFE91E63); // 粉紅色
      default:
        return AppColors.primary;
    }
  }

  /// 按日期分組飲食紀錄
  Map<String, List<Map<String, dynamic>>> _groupByDate(List<QueryDocumentSnapshot> docs) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = data['timestamp'] as Timestamp?;
      if (timestamp == null) continue;

      final date = timestamp.toDate();
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add({
        'id': doc.id,
        ...data,
        'dateTime': date,
      });
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

  /// 計算單日總熱量
  int _calculateDailyCalories(List<Map<String, dynamic>> meals) {
    int total = 0;
    for (var meal in meals) {
      if (meal['calories'] != null) {
        total += (meal['calories'] as num).toInt();
      }
    }
    return total;
  }

  /// 統計各餐數量
  Map<String, int> _countMealTypes(List<Map<String, dynamic>> meals) {
    final Map<String, int> counts = {};
    for (var meal in meals) {
      final type = meal['mealType'] ?? '其他';
      counts[type] = (counts[type] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          '飲食日誌',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.primary),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getDietLogsStream(),
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
                  Text('載入失敗：${snapshot.error}'),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.restaurant_menu, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 20),
                  const Text(
                    '尚無飲食紀錄',
                    style: TextStyle(fontSize: 18, color: AppColors.textHint),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '請在飲食頁面新增紀錄',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final groupedMeals = _groupByDate(snapshot.data!.docs);
          final sortedDates = groupedMeals.keys.toList()
            ..sort((a, b) => b.compareTo(a)); // 日期降序

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: sortedDates.length,
            itemBuilder: (context, index) {
              final dateKey = sortedDates[index];
              final meals = groupedMeals[dateKey]!;
              final isExpanded = _expandedDates.contains(dateKey);
              final dailyCalories = _calculateDailyCalories(meals);
              final mealCounts = _countMealTypes(meals);

              return _buildDateSection(
                dateKey: dateKey,
                meals: meals,
                isExpanded: isExpanded,
                dailyCalories: dailyCalories,
                mealCounts: mealCounts,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDateSection({
    required String dateKey,
    required List<Map<String, dynamic>> meals,
    required bool isExpanded,
    required int dailyCalories,
    required Map<String, int> mealCounts,
  }) {
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
                            Text(
                              '${meals.length} 筆紀錄',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (dailyCalories > 0) ...[
                              const SizedBox(width: 12),
                              Icon(
                                Icons.local_fire_department,
                                size: 14,
                                color: Colors.orange[600],
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '$dailyCalories kcal',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.orange[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
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
          // 展開的飲食內容
          if (isExpanded) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: meals.map((meal) => _buildMealItem(meal)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMealItem(Map<String, dynamic> meal) {
    final mealType = meal['mealType'] ?? '其他';
    final foodName = meal['foodName'] ?? '未命名食物';
    final calories = meal['calories'];
    final notes = meal['notes'];
    final dateTime = meal['dateTime'] as DateTime?;
    final timeString = dateTime != null ? DateFormat('HH:mm').format(dateTime) : '';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _getMealColor(mealType).withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getMealColor(mealType).withAlpha(80),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 餐別圖示
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getMealColor(mealType).withAlpha(50),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getMealIcon(mealType),
              color: _getMealColor(mealType),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          // 食物資訊
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getMealColor(mealType),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        mealType,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timeString,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  foodName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (calories != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 14,
                        color: Colors.orange[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$calories kcal',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
                if (notes != null && notes.toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    notes,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
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
