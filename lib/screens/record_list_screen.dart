import '../theme/app_colors.dart';
// lib/screens/record_list_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../models/record_data.dart';

class RecordListScreen extends StatefulWidget {
  const RecordListScreen({super.key});

  @override
  State<RecordListScreen> createState() => _RecordListScreenState();
}

class _RecordListScreenState extends State<RecordListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  String _selectedFilter = 'all';

  Stream<List<RecordData>> _getHealthRecordsStream() {
    final uid = _auth.currentUser?.uid;
    
    if (uid == null) {
      return Stream.value([]);
    }
    
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('health_records')
        .orderBy('record_time', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return RecordData.fromFirestore(doc);
      }).toList();
    });
  }

  List<RecordData> _filterRecords(List<RecordData> records, String filter) {
    if (filter == 'all') return records;
    
    return records.where((record) {
      switch (filter) {
        case 'blood_pressure':
          return record.systolicBloodPressure != null || record.diastolicBloodPressure != null;
        case 'glucose':
          return record.bloodGlucose != null;
        case 'weight':
          return record.weight != null;
        default:
          return true;
      }
    }).toList();
  }

  void _deleteRecord(String recordId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('health_records')
          .doc(recordId)
          .delete();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('記錄已刪除')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刪除失敗: $e')),
      );
    }
  }

  void _showDeleteDialog(RecordData record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Text('確定要刪除這筆健康記錄嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteRecord(record.id);
            },
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _getRecordType(RecordData record) {
    if (record.systolicBloodPressure != null || record.diastolicBloodPressure != null) {
      return '血壓';
    } else if (record.bloodGlucose != null) {
      return '血糖';
    } else if (record.weight != null) {
      return '體重';
    }
    return '記錄';
  }

  String _getRecordValue(RecordData record) {
    if (record.systolicBloodPressure != null && record.diastolicBloodPressure != null) {
      return '${record.systolicBloodPressure}/${record.diastolicBloodPressure} mmHg';
    } else if (record.bloodGlucose != null) {
      return '${record.bloodGlucose} mg/dL';
    } else if (record.weight != null) {
      return '${record.weight} kg';
    }
    return '--';
  }

  IconData _getRecordIcon(RecordData record) {
    if (record.systolicBloodPressure != null || record.diastolicBloodPressure != null) {
      return Icons.monitor_heart_rounded;
    } else if (record.bloodGlucose != null) {
      return Icons.bloodtype_rounded;
    } else if (record.weight != null) {
      return Icons.monitor_weight_rounded;
    }
    return Icons.assignment_rounded;
  }

  Color _getRecordColor(RecordData record) {
    if (record.systolicBloodPressure != null || record.diastolicBloodPressure != null) {
      return AppColors.primary;
    } else if (record.bloodGlucose != null) {
      return const Color(0xFFF59E0B);
    } else if (record.weight != null) {
      return AppColors.success;
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('所有測量紀錄'),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        elevation: 1,
      ),
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // 筛选器
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                const Text('篩選:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('全部', 'all'),
                        _buildFilterChip('血壓', 'blood_pressure'),
                        _buildFilterChip('血糖', 'glucose'),
                        _buildFilterChip('體重', 'weight'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 记录列表
          Expanded(
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
                        const Icon(Icons.error_outline, size: 60, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text('載入失敗', style: TextStyle(fontSize: 18)),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setState(() {}),
                          child: const Text('重試'),
                        ),
                      ],
                    ),
                  );
                }

                final allRecords = snapshot.data ?? [];
                final filteredRecords = _filterRecords(allRecords, _selectedFilter);

                if (filteredRecords.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_stories_rounded, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          _selectedFilter == 'all' ? '尚無記錄數據' : '此類別尚無記錄',
                          style: const TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '請在「記錄」頁面新增健康數據',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredRecords.length,
                  itemBuilder: (context, index) {
                    final record = filteredRecords[index];
                    return _buildRecordItem(record);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: _selectedFilter == value,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = value;
          });
        },
      ),
    );
  }

  Widget _buildRecordItem(RecordData record) {
    final recordColor = _getRecordColor(record);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: recordColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Icon(_getRecordIcon(record), color: recordColor),
        ),
        title: Text(
          _getRecordType(record),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getRecordValue(record),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: recordColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('yyyy/MM/dd HH:mm').format(record.recordTime),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') {
              _showDeleteDialog(record);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'delete', child: Text('刪除記錄')),
          ],
        ),
      ),
    );
  }
}