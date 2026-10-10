import '../utils/data_error_message.dart';
import '../widgets/data_error_view.dart';
import '../services/family_relationship_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'chat_screen.dart';
import '../models/record_data.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import 'add_member_screen.dart'; 

// --- 使用者資料模型 ---
class UserModel {
  final String fullName;
  final int age;
  final String chronicDiseases;
  final String bloodType;
  final double height;
  final DateTime dateOfBirth;
  final String email;
  final String gender;
  final String allergies;

  UserModel({
    required this.fullName,
    required this.age,
    required this.chronicDiseases,
    required this.bloodType,
    required this.height,
    required this.dateOfBirth,
    required this.email,
    required this.gender,
    required this.allergies,
  });

  static UserModel fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) {
      throw Exception("Document does not exist");
    }
    
    final data = doc.data() as Map<String, dynamic>;
    final String fullName = data['fullName'] ?? 'N/A';
    final String bloodType = data['bloodtype'] ?? '未知';
    final double height = (data['height'] ?? 0).toDouble();
    final String email = data['email'] ?? '';
    final String gender = data['gender'] ?? '';
    final String allergies = data['allergies'] ?? '';
    
    // 計算年齡
    int age = 0;
    DateTime dateOfBirth = DateTime.now();

    try {
      if (data['dateOfBirth'] is Timestamp) {
        dateOfBirth = (data['dateOfBirth'] as Timestamp).toDate();
      } else if (data['date_of_birth'] is Timestamp) {
        dateOfBirth = (data['date_of_birth'] as Timestamp).toDate();
      } else if (data['dateOfBirth'] is String) {
        // 處理字串格式的日期
        dateOfBirth = DateTime.parse(data['dateOfBirth']);
      } else if (data['date_of_birth'] is String) {
        dateOfBirth = DateTime.parse(data['date_of_birth']);
      }

      final DateTime now = DateTime.now();
      age = now.year - dateOfBirth.year;
      if (now.month < dateOfBirth.month ||
          (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
        age--;
      }
      debugPrint('👤 計算年齡成功: 出生日期=$dateOfBirth, 年齡=$age');
    } catch (e) {
      debugPrint('⚠️ 計算年齡失敗: $e, dateOfBirth=${data['dateOfBirth']}');
      age = 0;
    }

    // 處理慢性病
    String diseasesText = '無已知慢性病';
    if (data['chronicDiseases'] is List && (data['chronicDiseases'] as List).isNotEmpty) {
      diseasesText = (data['chronicDiseases'] as List)
          .where((item) => item != null && item.toString().trim().isNotEmpty)
          .join('、');
      if (diseasesText.isEmpty) diseasesText = '無已知慢性病';
    } else if (data['chronicDiseases'] is String && 
               (data['chronicDiseases'] as String).isNotEmpty) {
      diseasesText = data['chronicDiseases'];
    }

    return UserModel(
      fullName: fullName,
      age: age,
      chronicDiseases: diseasesText,
      bloodType: bloodType,
      height: height,
      dateOfBirth: dateOfBirth,
      email: email,
      gender: gender,
      allergies: allergies,
    );
  }
}

// --- 健康記錄模型 ---
class HealthRecord {
  final String type;
  final double value;
  final double? secondaryValue;
  final DateTime timestamp;
  final String unit;
  final String? note;
  final String? glucoseTiming;

  HealthRecord({
    required this.type,
    required this.value,
    this.secondaryValue,
    required this.timestamp,
    required this.unit,
    this.note,
    this.glucoseTiming,
  });

  factory HealthRecord.fromFirestore(Map<String, dynamic> data) {
    return HealthRecord(
      type: data['type'] ?? '',
      value: (data['value'] ?? 0).toDouble(),
      secondaryValue: data['secondaryValue'] != null
          ? (data['secondaryValue']).toDouble()
          : null,
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      unit: data['unit'] ?? '',
      note: data['note'],
      glucoseTiming: data['glucose_timing'],
    );
  }

  // 從 RecordData 轉換的工廠方法
  factory HealthRecord.fromRecordData(RecordData recordData) {
    String type = '';
    double value = 0;
    double? secondaryValue;
    String unit = recordData.unit;
    
    switch (recordData.category) {
      case '血壓':
        type = 'blood_pressure';
        value = recordData.systolicBloodPressure?.toDouble() ?? 0;
        secondaryValue = recordData.diastolicBloodPressure?.toDouble();
        unit = 'mmHg';
        break;
      case '血糖':
        type = 'blood_sugar';
        value = recordData.bloodGlucose?.toDouble() ?? 0;
        unit = 'mg/dL';
        break;

      case '體重':
        type = 'weight';
        value = recordData.weight ?? 0;
        unit = 'kg';
        break;
      case '睡眠':
        type = 'sleep';
        value = recordData.sleepHours ?? 0;
        unit = '小時';
        break;
      case '運動':
        type = 'exercise';
        value = recordData.exerciseMinutes?.toDouble() ?? 0;
        unit = '分鐘';
        break;
      default:
        type = recordData.category;
        value = 0;
    }
    
    return HealthRecord(
      type: type,
      value: value,
      secondaryValue: secondaryValue,
      timestamp: recordData.recordTime,
      unit: unit,
      note: recordData.notes,
      glucoseTiming: recordData.glucoseTiming,
    );
  }
}

// --- 藥物記錄模型 ---
class MedicationRecord {
  final String medicineName;
  final DateTime scheduledTime;
  final bool completed;
  final String dosage;
  final String frequency;
  final String? id;
  final String? medicineId; // 藥物ID
  final int? timeIndex; // 服藥時間索引

  MedicationRecord({
    required this.medicineName,
    required this.scheduledTime,
    required this.completed,
    required this.dosage,
    required this.frequency,
    this.id,
    this.medicineId,
    this.timeIndex,
  });

  factory MedicationRecord.fromFirestore(Map<String, dynamic> data) {
    // 處理 scheduledTime 可能為 null 的情況
    DateTime scheduledTime;
    if (data['scheduledTime'] is Timestamp) {
      scheduledTime = (data['scheduledTime'] as Timestamp).toDate();
    } else {
      // 如果沒有時間，使用當前時間
      scheduledTime = DateTime.now();
    }

    return MedicationRecord(
      medicineName: data['medicineName'] ?? data['name'] ?? '',
      scheduledTime: scheduledTime,
      completed: data['completed'] ?? false,
      dosage: data['dosage'] ?? '',
      frequency: data['frequency'] ?? '每日一次',
    );
  }

  String get formattedTime {
    return DateFormat('HH:mm').format(scheduledTime);
  }

  String get periodOfDay {
    final hour = scheduledTime.hour;
    if (hour < 12) return '上午';
    if (hour < 18) return '下午';
    return '晚上';
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  UserModel? _userData;
  bool _isLoading = true;
  List<HealthRecord> _healthRecords = [];
  List<MedicationRecord> _todayMedications = [];
  final Map<String, dynamic> _healthStats = {};
  List<Map<String, dynamic>> _pendingInvitations = [];
  bool _hasPendingInvitations = false;
  final FirestoreService _firestoreService = FirestoreService(); // 新增 FirestoreService
  final NotificationService _notificationService = NotificationService(); // 新增 NotificationService 實例

  // 即時監聽的訂閱，需在 dispose() 時取消，避免每次切換分頁都多洩漏一組監聽器
  StreamSubscription<QuerySnapshot>? _invitationsSubscription;
  StreamSubscription<DocumentSnapshot>? _userDataSubscription;
  StreamSubscription<QuerySnapshot>? _healthRecordsSubscription;
  StreamSubscription<QuerySnapshot>? _medicineSubscription;
  int _listenerGeneration = 0;
  final Set<String> _readySources = {};
  final Map<String, String> _dataErrors = {};
  String? _invitationTarget;

    // 邀請通知卡片
Widget _buildInvitationNotification() {
  return Container(
    margin: EdgeInsets.all(16),
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.warningLight, AppColors.warningLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.warning, width: 1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.group_add, color: AppColors.warning),
            SizedBox(width: 8),
            Text(
              '家庭邀請',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        ..._pendingInvitations.map((invitation) => _buildInvitationItem(invitation)),
      ],
    ),
  );
}

// 單個邀請項目
Widget _buildInvitationItem(Map<String, dynamic> invitation) {
  final inviterName = invitation['inviterName'];
  final relation = invitation['relation'];
  final invitedAt = invitation['invitedAt'] as DateTime;
  final invitationId = invitation['id'];
  
  return Container(
    margin: EdgeInsets.only(bottom: 12),
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$inviterName 邀請您成為$relation',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 4),
        Text(
          '邀請時間: ${DateFormat('yyyy/MM/dd HH:mm').format(invitedAt)}',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _respondToInvitation(invitationId, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey,
                  side: BorderSide(color: Colors.grey),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('拒絕'),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _respondToInvitation(invitationId, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('接受'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _listenerGeneration++;
    _invitationsSubscription?.cancel();
    _userDataSubscription?.cancel();
    _healthRecordsSubscription?.cancel();
    _medicineSubscription?.cancel();
    super.dispose();
  }

  void _sourceReady(String source, [Object? error]) {
    if (!mounted) return;
    setState(() {
      _readySources.add(source);
      if (error == null) {
        _dataErrors.remove(source);
      } else {
        _dataErrors[source] = dataErrorMessage(error);
      }
      _isLoading = !_readySources.containsAll(['個人資料', '健康紀錄', '用藥']);
    });
  }

  Future<void> _loadAllData() async {
    final generation = ++_listenerGeneration;
    final old = [_userDataSubscription, _healthRecordsSubscription,
      _medicineSubscription, _invitationsSubscription];
    _userDataSubscription = null;
    _healthRecordsSubscription = null;
    _medicineSubscription = null;
    _invitationsSubscription = null;
    _invitationTarget = null;
    await Future.wait(old.whereType<StreamSubscription>().map((s) => s.cancel()));
    if (!mounted || generation != _listenerGeneration) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() { _isLoading = false; _userData = null;
        _healthRecords = []; _todayMedications = []; _pendingInvitations = []; });
      return;
    }
    setState(() { _isLoading = true; _readySources.clear(); _dataErrors.clear(); });
    final owner = FirebaseFirestore.instance.collection('users').doc(user.uid);
    bool active() => mounted && generation == _listenerGeneration &&
      FirebaseAuth.instance.currentUser?.uid == user.uid;
    _userDataSubscription = owner.snapshots().listen((snapshot) {
      if (!active()) return;
      try {
        setState(() { _userData = snapshot.exists ? UserModel.fromFirestore(snapshot) : null; });
        _setupInvitationsListener(user.email, snapshot.data()?['phoneNumber'] as String?, generation);
        _sourceReady('個人資料');
      } catch (error) { _sourceReady('個人資料', error); }
    }, onError: (Object error) { if (active()) _sourceReady('個人資料', error); });
    _healthRecordsSubscription = owner.collection('health_records')
      .where('record_time', isGreaterThanOrEqualTo:
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7))))
      .orderBy('record_time', descending: true).snapshots().listen((snapshot) {
        if (!active()) return;
        try {
          final records = snapshot.docs.map((doc) =>
            HealthRecord.fromRecordData(RecordData.fromFirestore(doc)))
              .where((record) => record.value > 0).toList();
          setState(() { _healthRecords = records; _calculateHealthStats(); });
          _sourceReady('健康紀錄');
        } catch (error) { _sourceReady('健康紀錄', error); }
      }, onError: (Object error) { if (active()) _sourceReady('健康紀錄', error); });
    _medicineSubscription = owner.collection('medicine').snapshots().listen((snapshot) {
      if (!active()) return;
      try { _applyMedicationSnapshot(snapshot); _sourceReady('用藥'); }
      catch (error) { _sourceReady('用藥', error); }
    }, onError: (Object error) { if (active()) _sourceReady('用藥', error); });
  }

  Future<void> _setupInvitationsListener(String? email, String? phone, int generation) async {
    final targets = [if (email != null && email.isNotEmpty) email.toLowerCase().trim(),
      if (phone != null && phone.isNotEmpty) phone.trim()];
    final target = targets.join('|');
    if (_invitationTarget == target) return;
    _invitationTarget = target;
    final previous = _invitationsSubscription;
    _invitationsSubscription = null;
    await previous?.cancel();
    if (!mounted || generation != _listenerGeneration || target != _invitationTarget) return;
    if (targets.isEmpty) {
      setState(() { _pendingInvitations = []; _hasPendingInvitations = false; });
      return;
    }
    final filters = [if (email != null && email.isNotEmpty)
      Filter('invitedToEmail', isEqualTo: email.toLowerCase().trim()),
      Filter('emailOrPhone', whereIn: targets)];
    final filter = filters.length == 1 ? filters.first : Filter.or(filters[0], filters[1]);
    _invitationsSubscription = FirebaseFirestore.instance.collection('family_invites')
      .where('status', isEqualTo: 'pending').where(filter).snapshots().listen((snapshot) {
        if (!mounted || generation != _listenerGeneration || target != _invitationTarget) return;
        final invitations = snapshot.docs.map((doc) {
          final data = doc.data();
          final date = data['invitedAt'] ?? data['createdAt'];
          return <String, dynamic>{'id': doc.id,
            'inviterName': data['inviterName'] ?? data['name'] ?? '家人',
            'relation': data['relation'] ?? '家人',
            'invitedAt': date is Timestamp ? date.toDate() :
              date is int ? DateTime.fromMillisecondsSinceEpoch(date) : DateTime.now(),
            'sharedData': data['sharedData'] ?? {}, 'invitedBy': data['invitedBy']};
        }).toList();
        setState(() { _pendingInvitations = invitations;
          _hasPendingInvitations = invitations.isNotEmpty; _dataErrors.remove('邀請'); });
      }, onError: (Object error) {
        if (mounted && generation == _listenerGeneration && target == _invitationTarget) _sourceReady('邀請', error);
      });
  }

// 修改：處理邀請回應
  void _respondToInvitation(String invitationId, bool accepted) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 先讀取邀請資料
      final invitationDoc = await FirebaseFirestore.instance
          .collection('family_invites')
          .doc(invitationId)
          .get();

      if (!mounted) return;
      if (!invitationDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('邀請不存在或已被取消')),
        );
        return;
      }

      if (accepted) {
        await FamilyRelationshipService().acceptInvite(invitationId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功加入家庭群組'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        await FamilyRelationshipService().declineInvite(invitationId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已拒絕邀請'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      // 重新載入邀請列表
      // The invitation listener updates the list after the transaction.
      
    } catch (e) {
      if (!mounted) return;
      debugPrint('處理邀請失敗: $e');
      
      String errorMessage = '操作失敗，請重試';
      if (e is FirebaseException) {
        if (e.code == 'permission-denied') {
          errorMessage = '權限不足，請檢查 Firebase 規則設定';
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 標記藥物為已完成（使用 FirestoreService 以同步更新用藥日誌）
  Future<void> _completeMedication(MedicationRecord med) async {
    if (med.medicineId == null || med.timeIndex == null) {
      debugPrint('❌ 無法完成用藥：缺少藥物ID或時間索引');
      return;
    }

    try {
      // 從 Firestore 獲取完整的 medicine 資料
      final medicationDoc = await _firestoreService
          .getMedicationsCollectionWithConverter()
          .doc(med.medicineId)
          .get();

      if (!medicationDoc.exists || medicationDoc.data() == null) {
        debugPrint('❌ 藥物不存在');
        return;
      }

      final medication = medicationDoc.data()!;

      // 檢查該時段是否已經完成（避免重複執行）
      if (!medication.shouldResetStatus && medication.times_status[med.timeIndex!]) {
        debugPrint('⚠️ 該時段已完成用藥');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${med.medicineName} ${med.formattedTime} 已經完成過了'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 使用 FirestoreService 執行用藥狀態切換（會同時更新用藥日誌）
      final wasLogged = await _firestoreService.toggleMedicationIntake(
        medication: medication,
        timeSlotIndex: med.timeIndex!,
      );

      // 取消該時段的用藥提醒和漏吃提醒
      final notificationId = med.medicineId.hashCode + med.timeIndex!;
      if (wasLogged) {
        // 使用已初始化的 notificationService 實例
        await _notificationService.cancelNotification(notificationId);
        await _notificationService.cancelMissedDoseReminders(notificationId); // 第774行 - 已修正
      }

      debugPrint('✅ 已標記用藥完成：${med.medicineName} - 第 ${med.timeIndex! + 1} 次');

      // 重新載入今日用藥
      // The medication listener updates today's list after the transaction.

      // 顯示完成提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasLogged
                ? '${med.medicineName} ${med.formattedTime} 已完成並記錄'
                : '${med.medicineName} ${med.formattedTime} 已取消'),
            duration: Duration(seconds: 2),
            backgroundColor: wasLogged ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ 完成用藥時發生錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失敗，請稍後再試'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _applyMedicationSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
      List<MedicationRecord> todayMeds = [];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final medicineId = doc.id;

          // 解析藥物資料
          final medicineName = data['name'] as String? ?? '未命名藥物';
          final dosage = data['dosage']?.toString() ?? '';
          final frequency = data['frequency'] as String? ?? '每日一次';

          // 獲取服藥時間列表和狀態列表
          List<DateTime> timesOfDayList = (data['times_of_day_list'] as List<dynamic>?)
              ?.map((ts) => (ts as Timestamp).toDate())
              .toList() ?? [];

          List<bool> timesStatus = (data['times_status'] as List<dynamic>?)
              ?.map((s) => s as bool)
              .toList() ?? [];

          // 為每個服藥時間創建獨立的 MedicationRecord
          for (int i = 0; i < timesOfDayList.length; i++) {
            final scheduledTime = timesOfDayList[i];
            final completed = i < timesStatus.length ? timesStatus[i] : false;

            todayMeds.add(MedicationRecord(
              medicineName: medicineName,
              scheduledTime: scheduledTime,
              completed: completed,
              dosage: dosage,
              frequency: frequency,
              medicineId: medicineId,
              timeIndex: i,
            ));
          }


        } catch (e) {
          rethrow;
        }
      }

    todayMeds.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    setState(() => _todayMedications = todayMeds);
  }

  void _calculateHealthStats() {
    final now = DateTime.now();
    final oneWeekAgo = now.subtract(const Duration(days: 7));

    // 過濾最近一週的記錄
    final recentRecords = _healthRecords
        .where((record) => record.timestamp.isAfter(oneWeekAgo))
        .toList();

    debugPrint('Calculating stats from ${recentRecords.length} recent records');

    // 血壓數據
    final bpRecords = recentRecords.where((r) => r.type == 'blood_pressure').toList();
    if (bpRecords.isNotEmpty) {
      final latest = bpRecords.first;
      final systolic = latest.value.toInt();
      final diastolic = (latest.secondaryValue ?? 80).toInt();

      // 血壓健康狀態判斷（依 AHA/台灣衛福部標準）
      String status;
      bool isWarning;
      if (systolic < 90 || diastolic < 60) {
        status = '偏低';
        isWarning = true;
      } else if (systolic < 120 && diastolic < 80) {
        status = '正常';
        isWarning = false;
      } else if (systolic < 130 && diastolic < 80) {
        status = '高血壓前期';
        isWarning = true;
      } else {
        status = '高血壓';
        isWarning = true;
      }

      _healthStats['bloodPressure'] = {
        'systolic': latest.value,
        'diastolic': latest.secondaryValue ?? 80,
        'status': status,
        'isNormal': !isWarning,
        'isWarning': isWarning,
        'hasData': true,
      };
      debugPrint('💓 血壓數據: ${latest.value}/${latest.secondaryValue} - $status');
    } else {
      _healthStats['bloodPressure'] = {
        'systolic': 0,
        'diastolic': 0,
        'status': '尚無數據',
        'isNormal': true,
        'isWarning': false,
        'hasData': false,
      };
      debugPrint('⚠️ 無血壓數據');
    }

    // 血糖數據
    final sugarRecords = recentRecords.where((r) => r.type == 'blood_sugar').toList();
    if (sugarRecords.isNotEmpty) {
      final latest = sugarRecords.first;
      final glucose = latest.value.toInt();

      // 血糖健康狀態判斷（依測量時機區分標準）
      final timing = latest.glucoseTiming ?? '';
      final isAfterMeal = timing.contains('飯後') || timing.contains('after');
      String status;
      bool isWarning;
      if (glucose < 70) {
        status = '偏低';
        isWarning = true;
      } else if (isAfterMeal) {
        // 飯後2小時標準：< 140 正常
        if (glucose < 140) {
          status = '正常';
          isWarning = false;
        } else if (glucose < 200) {
          status = '偏高';
          isWarning = true;
        } else {
          status = '過高';
          isWarning = true;
        }
      } else {
        // 空腹標準
        if (glucose <= 99) {
          status = '正常';
          isWarning = false;
        } else if (glucose <= 125) {
          status = '糖尿病前期';
          isWarning = true;
        } else {
          status = '過高';
          isWarning = true;
        }
      }

      _healthStats['bloodSugar'] = {
        'value': latest.value,
        'status': status,
        'isWarning': isWarning,
        'isNormal': !isWarning,
        'hasData': true,
      };
      debugPrint('🩸 血糖數據: ${latest.value} - $status');
    } else {
      _healthStats['bloodSugar'] = {
        'value': 0,
        'status': '尚無數據',
        'isWarning': false,
        'isNormal': true,
        'hasData': false,
      };
      debugPrint('⚠️ 無血糖數據');
    }

    // 體重數據
    final weightRecords = recentRecords.where((r) => r.type == 'weight').toList();
    if (weightRecords.isNotEmpty) {
      final latest = weightRecords.first;

      // 體重變化趨勢判斷
      String status;
      bool isWarning = false;
      if (weightRecords.length >= 2) {
        final previous = weightRecords[1].value;
        final change = latest.value - previous;
        if (change.abs() < 0.5) {
          status = '穩定';
          isWarning = false;
        } else if (change > 0) {
          status = '上升';
          isWarning = change > 2.0; // 增加超過2kg視為警告
        } else {
          status = '下降';
          isWarning = change.abs() > 2.0; // 減少超過2kg視為警告
        }
      } else {
        status = '資料不足';
        isWarning = false;
      }

      _healthStats['weight'] = {
        'value': latest.value,
        'status': status,
        'unit': latest.unit,
        'isWarning': isWarning,
        'hasData': true,
      };
      debugPrint('⚖️ 體重數據: ${latest.value} - $status');
    } else {
      _healthStats['weight'] = {
        'value': 0,
        'status': '尚無數據',
        'unit': 'kg',
        'isWarning': false,
        'hasData': false,
      };
      debugPrint('⚠️ 無體重數據');
    }

    // BMI 數據 (需要身高和體重)
    if (_userData != null && weightRecords.isNotEmpty) {
      final height = _userData!.height;
      final latestWeight = weightRecords.first.value;

      if (height > 0 && latestWeight > 0) {
        // BMI = 體重(kg) / 身高(m)²
        final heightInMeters = height / 100; // 轉換 cm 為 m
        final bmi = latestWeight / (heightInMeters * heightInMeters);

        // 判斷 BMI 健康狀態
        String status;
        bool isWarning = false;
        if (bmi < 18.5) {
          status = '過輕';
          isWarning = true;
        } else if (bmi < 24) {
          status = '正常';
          isWarning = false;
        } else if (bmi < 27) {
          status = '過重';
          isWarning = true;
        } else {
          status = '肥胖';
          isWarning = true;
        }

        _healthStats['bmi'] = {
          'value': bmi,
          'status': status,
          'isWarning': isWarning,
          'hasData': true,
        };
        debugPrint('📏 BMI 數據: ${bmi.toStringAsFixed(1)} ($status)');
      } else {
        _healthStats['bmi'] = {
          'value': 0,
          'status': '尚無數據',
          'isWarning': false,
          'hasData': false,
        };
        debugPrint('⚠️ 無法計算 BMI：身高或體重不足');
      }
    } else {
      _healthStats['bmi'] = {
        'value': 0,
        'status': '尚無數據',
        'isWarning': false,
        'hasData': false,
      };
      debugPrint('⚠️ 無法計算 BMI：缺少個人資料或體重數據');
    }

    // 睡眠數據 - 顯示最新記錄
    final sleepRecords = recentRecords.where((r) => r.type == 'sleep').toList();
    if (sleepRecords.isNotEmpty) {
      final latest = sleepRecords.first;
      final hours = latest.value;

      // 睡眠健康狀態判斷
      String status;
      bool isWarning;
      if (hours < 6) {
        status = '不足';
        isWarning = true;
      } else if (hours <= 9) {
        status = '正常';
        isWarning = false;
      } else {
        status = '過多';
        isWarning = true;
      }

      _healthStats['sleep'] = {
        'value': latest.value,
        'status': status,
        'isWarning': isWarning,
        'hasData': true,
      };
      debugPrint('😴 睡眠數據: ${latest.value} 小時 - $status');
    } else {
      _healthStats['sleep'] = {
        'value': 0,
        'status': '尚無數據',
        'isWarning': false,
        'hasData': false,
      };
      debugPrint('⚠️ 無睡眠數據');
    }

    // 運動數據 - 顯示今日總計
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final exerciseRecords = _healthRecords
        .where((r) => r.type == 'exercise' && r.timestamp.isAfter(todayStart))
        .toList();

    if (exerciseRecords.isNotEmpty) {
      // 計算今日總運動時間
      final totalMinutes = exerciseRecords.fold<double>(
        0, (sum, record) => sum + record.value
      );

      // 運動健康狀態判斷
      String status;
      bool isWarning;
      if (totalMinutes < 30) {
        status = '不足';
        isWarning = true;
      } else if (totalMinutes <= 120) {
        status = '良好';
        isWarning = false;
      } else {
        status = '充足';
        isWarning = false;
      }

      _healthStats['exercise'] = {
        'value': totalMinutes,
        'count': exerciseRecords.length,
        'status': status,
        'isWarning': isWarning,
        'hasData': true,
      };
      debugPrint('🏃 運動數據: ${totalMinutes.toInt()} 分鐘 (${exerciseRecords.length} 次) - $status');
    } else {
      _healthStats['exercise'] = {
        'value': 0,
        'count': 0,
        'status': '尚無數據',
        'isWarning': false,
        'hasData': false,
      };
      debugPrint('⚠️ 無運動數據');
    }

    debugPrint('📊 最終健康統計: $_healthStats');
  }

  // 檢查藥物是否已完成
  bool _isMedicationCompleted(MedicationRecord med) {
    return med.completed;
  }

  // 取得未完成的藥物
  List<MedicationRecord> get _incompleteMedications {
    return _todayMedications.where((med) => !_isMedicationCompleted(med)).toList();
  }

  // 計算用藥進度
  String get _medicationProgress {
    if (_todayMedications.isEmpty) return '0/0';
    final completedCount = _todayMedications.where((med) => _isMedicationCompleted(med)).length;
    return '$completedCount/${_todayMedications.length}';
  }

  void _navigateToFriendsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddMemberScreen(), // 連接到 add_member_screen.dart
      ),
    );
  }

  Widget _buildTodoCard(
    IconData icon,
    String title,
    String time,
    bool completed,
    VoidCallback onTap,
    String medId, // 新增藥物ID參數
  ) {
    return GestureDetector(
      onTap: completed ? null : onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(
              color: completed ? AppColors.success : AppColors.primary,
              width: 4
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: completed ? AppColors.successLight : AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: completed ? AppColors.success : AppColors.primary,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: completed ? AppColors.textSecondary : Colors.black87,
                      decoration: completed ? TextDecoration.lineThrough : TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 14,
                      color: completed ? AppColors.textHint : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: completed ? null : onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: completed
                    ? AppColors.success
                    : AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                completed ? '已完成' : '執行',
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 新增：用藥進度顯示部件
  Widget _buildMedicationProgress() {
    final completedCount = _todayMedications.where((med) => _isMedicationCompleted(med)).length;
    final totalCount = _todayMedications.length;
    final progress = totalCount > 0 ? completedCount / totalCount : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '今日用藥進度',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              Text(
                '$completedCount/$totalCount 已完成',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendCard(
    IconData icon,
    String label,
    String value,
    String trend,
    bool isWarning, {
    Color? accentColor,
  }) {
    final bool hasData = value != '--' && value != '--/--' && value != '--kg';

    // 狀態標籤文字：直接使用傳入的 trend（已是正確狀態文字）
    String statusLabel = '尚無數據';
    if (hasData) {
      statusLabel = trend;
    }

    final bool isUp = trend.contains('↑') || trend.contains('上升') || trend.contains('偏高') || trend.contains('過高');
    final bool isDown = trend.contains('↓') || trend.contains('下降') || trend.contains('偏低');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWarning ? AppColors.error : AppColors.primary,
          width: isWarning ? 1.5 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頂部：圖標與標籤
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              // 狀態標籤
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isWarning
                      ? AppColors.warning.withValues(alpha: 0.15)
                      : hasData
                          ? AppColors.primaryLight
                          : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isWarning
                        ? AppColors.warning
                        : hasData
                            ? AppColors.primaryDark
                            : Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 數值顯示
          Text(
            value,
            style: TextStyle(
              fontSize: hasData ? 28 : 22,
              fontWeight: FontWeight.w700,
              color: hasData ? Colors.grey.shade800 : Colors.grey.shade400,
              letterSpacing: -0.5,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          // 趨勢說明
          Row(
            children: [
              if (hasData && (isUp || isDown)) ...[
                Icon(
                  isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  size: 14,
                  color: isWarning ? AppColors.warning : AppColors.primary,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  trend,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getHealthStatus() {
    // 先檢查是否有任何健康數據
    final hasAnyData = (_healthStats['bloodPressure']?['hasData'] ?? false) ||
        (_healthStats['bloodSugar']?['hasData'] ?? false) ||
        (_healthStats['bmi']?['hasData'] ?? false) ||
        (_healthStats['weight']?['hasData'] ?? false);

    // 如果沒有任何數據，返回「尚無數據」
    if (!hasAnyData) {
      return '尚無數據';
    }

    final warnings = [];

    if ((_healthStats['bloodSugar']?['isWarning'] ?? false)) {
      warnings.add('血糖');
    }

    if (!(_healthStats['bloodPressure']?['isNormal'] ?? true)) {
      warnings.add('血壓');
    }

    if ((_healthStats['bmi']?['isWarning'] ?? false)) {
      warnings.add('BMI');
    }

    if (warnings.isEmpty) return '良好';
    return '${warnings.join('、')}需要關注';
  }

  @override
  Widget build(BuildContext context) {
    if (_dataErrors.isNotEmpty) {
      return DataErrorView(message: _dataErrors.entries
        .map((entry) => '${entry.key}：${entry.value}').join('\n'), onRetry: _loadAllData);
    }
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 100),
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final user = _userData;
    final fullName = user?.fullName ?? '美肉包';


    final healthStatus = _getHealthStatus();
    final hasNoData = healthStatus == '尚無數據';
    final hasWarnings = !hasNoData && healthStatus != '良好';

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 頂部個人資訊區域
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.person,
                          size: 36,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 修改：將原本的LINE按鈕和新增的好友按鈕放在一個Row中
                      Row(
                        children: [
                          // 好友按鈕
                          GestureDetector(
                            onTap: _navigateToFriendsPage,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.group_add,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // 訊息按鈕 (修改：將LINE改為訊息圖標)
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ChatScreen(),
                                ),
                              );
                            },
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.message,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (hasWarnings) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              healthStatus,
                              style: TextStyle(fontSize: 13, color: AppColors.warning),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (hasNoData) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            '尚無健康數據，請前往紀錄頁新增',
                            style: TextStyle(fontSize: 13, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
                          const SizedBox(width: 8),
                          Text(
                            '健康狀態不錯，繼續保持！',
                            style: TextStyle(fontSize: 13, color: AppColors.success),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            if (_hasPendingInvitations)
              _buildInvitationNotification(),
            // 用藥提醒區域
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.medication_rounded, color: AppColors.primary, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    '用藥提醒',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            // 顯示用藥進度（只在有用藥時顯示）
            if (_todayMedications.isNotEmpty)
              _buildMedicationProgress(),
            
            // 顯示未完成的藥物
            ..._incompleteMedications.map((med) {
              final medId = '${med.medicineId}_${med.timeIndex}';
              return _buildTodoCard(
                Icons.medication_rounded,
                '服用 ${med.medicineName} (${med.dosage})',
                '${med.periodOfDay} ${med.formattedTime} · ${med.frequency}',
                _isMedicationCompleted(med),
                () {
                  _completeMedication(med);
                },
                medId,
              );
            }),
            
            // 如果所有藥物都已完成，顯示提示訊息
            if (_incompleteMedications.isEmpty && _todayMedications.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: AppColors.success),
                    SizedBox(width: 8),
                    Text(
                      '今日所有用藥已完成！',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            
            // 如果沒有任何藥物，顯示提示訊息
            if (_todayMedications.isEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, color: AppColors.warning),
                    SizedBox(width: 8),
                    Text(
                      '今日無用藥安排',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),

            // 健康趨勢區域
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.trending_up_rounded, color: AppColors.primary, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    '健康趨勢',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTrendCard(
                      Icons.favorite_rounded,
                      '血壓',
                      (_healthStats['bloodPressure']?['hasData'] ?? false)
                          ? '${_healthStats['bloodPressure']['systolic'].toInt()}/${_healthStats['bloodPressure']['diastolic'].toInt()}'
                          : '--/--',
                      _healthStats['bloodPressure']?['status'] ?? '尚無數據',
                      _healthStats['bloodPressure']?['isWarning'] ?? false,
                      accentColor: const Color(0xFFE53935), // 紅色系 - 血壓
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTrendCard(
                      Icons.water_drop_rounded,
                      '血糖',
                      (_healthStats['bloodSugar']?['hasData'] ?? false)
                          ? '${_healthStats['bloodSugar']['value'].toInt()}'
                          : '--',
                      _healthStats['bloodSugar']?['status'] ?? '尚無數據',
                      _healthStats['bloodSugar']?['isWarning'] ?? false,
                      accentColor: const Color(0xFFFFA726), // 橙色系 - 血糖
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTrendCard(
                      Icons.monitor_weight_rounded,
                      '體重',
                      (_healthStats['weight']?['hasData'] ?? false)
                          ? '${_healthStats['weight']['value'].toStringAsFixed(1)}${_healthStats['weight']['unit'] ?? 'kg'}'
                          : '--kg',
                      _healthStats['weight']?['status'] ?? '尚無數據',
                      _healthStats['weight']?['isWarning'] ?? false,
                      accentColor: const Color(0xFF42A5F5), // 藍色系 - 體重
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTrendCard(
                      Icons.straighten_rounded,
                      'BMI',
                      (_healthStats['bmi']?['hasData'] ?? false)
                          ? '${_healthStats['bmi']['value'].toStringAsFixed(1)}'
                          : '--',
                      _healthStats['bmi']?['status'] ?? '尚無數據',
                      _healthStats['bmi']?['isWarning'] ?? false,
                      accentColor: const Color(0xFF7E57C2), // 紫色系 - BMI
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTrendCard(
                      Icons.bedtime_rounded,
                      '睡眠',
                      (_healthStats['sleep']?['hasData'] ?? false)
                          ? '${_healthStats['sleep']['value'].toStringAsFixed(1)}小時'
                          : '--',
                      _healthStats['sleep']?['status'] ?? '尚無數據',
                      _healthStats['sleep']?['isWarning'] ?? false,
                      accentColor: const Color(0xFF5C6BC0), // 靛藍色 - 睡眠
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTrendCard(
                      Icons.directions_run_rounded,
                      '運動',
                      (_healthStats['exercise']?['hasData'] ?? false)
                          ? '${_healthStats['exercise']['value'].toInt()}分鐘'
                          : '--',
                      _healthStats['exercise']?['status'] ?? '尚無數據',
                      _healthStats['exercise']?['isWarning'] ?? false,
                      accentColor: const Color(0xFF66BB6A), // 綠色系 - 運動
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}