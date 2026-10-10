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
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
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
    Future<void> _loadPendingInvitations() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 獲取使用者的 email 和手機號碼
      final userEmail = user.email?.toLowerCase().trim();
      String? userPhone;

      // 從 Firestore 讀取使用者的手機號碼
      if (_userData != null && _userData!.email.isNotEmpty) {
        // 如果已經載入了使用者資料，就使用它
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          userPhone = userDoc.data()?['phoneNumber'] as String?;
        }
      }

      // 查詢所有符合條件的邀請（email 或手機號碼）
      final invitationsQuery = await FirebaseFirestore.instance
          .collection('family_invites')
          .where('status', isEqualTo: 'pending')
          .get();

      // 過濾出匹配當前使用者 email 或手機號碼的邀請
      final invitations = invitationsQuery.docs.where((doc) {
        final data = doc.data();
        final emailOrPhone = (data['emailOrPhone'] as String?)?.toLowerCase().trim();

        // 匹配 email 或手機號碼
        return emailOrPhone == userEmail ||
               (userPhone != null && emailOrPhone == userPhone.toLowerCase().trim());
      }).map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'inviterName': data['name'] ?? '未知用戶',
          'relation': data['relation'] ?? '家人',
          'invitedAt': data['invitedAt'] != null
              ? DateTime.fromMillisecondsSinceEpoch(data['invitedAt'])
              : DateTime.now(),
          'sharedData': data['sharedData'] ?? {},
          'invitedBy': data['invitedBy'],
        };
      }).toList();

      if (mounted) {
        setState(() {
          _pendingInvitations = invitations;
          _hasPendingInvitations = invitations.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('載入邀請失敗: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _loadPendingInvitations();
    _setupInvitationsListener();
    _setupUserDataListener(); // 監聽使用者資料變更
    _setupHealthRecordsListener(); // 監聽健康記錄變更
  }

  @override
  void dispose() {
    // 取消所有即時監聽，避免每次切換分頁重建這個畫面時都多洩漏一組 Firestore 監聽器
    _invitationsSubscription?.cancel();
    _userDataSubscription?.cancel();
    _healthRecordsSubscription?.cancel();
    super.dispose();
  }

  // 即時監聽邀請狀態
  void _setupInvitationsListener() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 獲取使用者的 email 和手機號碼
    final userEmail = user.email?.toLowerCase().trim();
    String? userPhone;

    // 從 Firestore 讀取使用者的手機號碼
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (userDoc.exists) {
      userPhone = userDoc.data()?['phoneNumber'] as String?;
    }

    // 監聽所有 pending 邀請，然後在客戶端過濾
    _invitationsSubscription = FirebaseFirestore.instance
        .collection('family_invites')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        // 過濾出匹配當前使用者的邀請
        final filteredInvitations = snapshot.docs.where((doc) {
          final data = doc.data();
          final emailOrPhone = (data['emailOrPhone'] as String?)?.toLowerCase().trim();

          // 匹配 email 或手機號碼
          return emailOrPhone == userEmail ||
                 (userPhone != null && emailOrPhone == userPhone.toLowerCase().trim());
        }).map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'inviterName': data['name'] ?? '未知用戶',
            'relation': data['relation'] ?? '家人',
            'invitedAt': data['invitedAt'] != null
                ? DateTime.fromMillisecondsSinceEpoch(data['invitedAt'])
                : DateTime.now(),
            'sharedData': data['sharedData'] ?? {},
          };
        }).toList();

        setState(() {
          _pendingInvitations = filteredInvitations;
          _hasPendingInvitations = filteredInvitations.isNotEmpty;
        });
      }
    });
  }

  // 新增：即時監聯使用者資料變更
  void _setupUserDataListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userDataSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      if (mounted && snapshot.exists) {
        setState(() {
          _userData = UserModel.fromFirestore(snapshot);
          debugPrint('使用者資料已更新: 慢性病=${_userData?.chronicDiseases}');
        });
      }
    });
  }

  // 新增：即時監聽健康記錄變更
  void _setupHealthRecordsListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _healthRecordsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('health_records')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        debugPrint('🔄 健康記錄有更新，重新載入數據...');
        _loadHealthRecords().then((_) {
          // _calculateHealthStats() 只是同步計算、寫入 _healthStats map，
          // 本身不會觸發畫面重建；沒有包在 setState 裡的話，
          // 主頁卡片（血壓/血糖/體重…）就不會反映剛剛的即時更新。
          if (mounted) {
            setState(() {
              _calculateHealthStats();
            });
          }
        });
      }
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

      if (!invitationDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('邀請不存在或已被取消')),
        );
        return;
      }

      final invitationData = invitationDoc.data();

      // 更新邀請狀態
      await FirebaseFirestore.instance
          .collection('family_invites')
          .doc(invitationId)
          .update({
        'status': accepted ? 'accepted' : 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      if (accepted) {
        // 建立家庭成員關係
        await _createFamilyRelationship(invitationData!, user.uid);
        
        // 建立聊天室
        await _createChatRoom(invitationData, user.uid);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功加入家庭群組'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已拒絕邀請'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      // 重新載入邀請列表
      _loadPendingInvitations();
      
    } catch (e) {
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

// 新增：建立聊天室
Future<void> _createChatRoom(Map<String, dynamic>? invitationData, String currentUserId) async {
  if (invitationData == null) return;

  final inviterId = invitationData['invitedBy'];
  final currentUserName = _userData?.fullName ?? '家庭成員';

  // 從 Firestore 獲取邀請者的真實姓名
  String inviterName = invitationData['name']; // 預設值
  try {
    final inviterDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(inviterId)
        .get();
    if (inviterDoc.exists) {
      inviterName = inviterDoc.data()?['fullName'] ?? invitationData['name'];
    }
  } catch (e) {
    debugPrint('獲取邀請者姓名失敗: $e');
  }

  // 檢查是否已經有聊天室
  final existingChat = await FirebaseFirestore.instance
      .collection('chats')
      .where('members', arrayContainsAny: [currentUserId, inviterId])
      .get();

  // 如果已經有聊天室，就不重複建立
  for (final doc in existingChat.docs) {
    final members = List<String>.from(doc['members']);
    if (members.contains(currentUserId) && members.contains(inviterId)) {
      return; // 聊天室已存在
    }
  }

  // 建立新的聊天室
  final chatId = '${currentUserId}_$inviterId'; // 或用 Firebase 自動生成 ID

  await FirebaseFirestore.instance
      .collection('chats')
      .doc(chatId)
      .set({
    'members': [currentUserId, inviterId],
    'memberNames': {
      currentUserId: currentUserName,
      inviterId: inviterName,
    },
    'lastMessage': '你們現在是家庭成員了！開始聊天吧～',
    'lastTime': FieldValue.serverTimestamp(),
    'unread': {
      currentUserId: 0,
      inviterId: 0,
    },
    'createdAt': FieldValue.serverTimestamp(),
    'type': 'family', // 標記為家庭聊天
  });
}

  // 建立家庭成員關係
  Future<void> _createFamilyRelationship(Map<String, dynamic>? invitationData, String currentUserId) async {
    if (invitationData == null) return;

    final inviterId = invitationData['invitedBy'];
    final relation = invitationData['relation'];
    final sharedData = invitationData['sharedData'] ?? {};

    // 從 Firestore 獲取邀請者的真實姓名
    String inviterName = invitationData['name']; // 預設值
    try {
      final inviterDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(inviterId)
          .get();
      if (inviterDoc.exists) {
        inviterName = inviterDoc.data()?['fullName'] ?? invitationData['name'];
      }
    } catch (e) {
      debugPrint('獲取邀請者姓名失敗: $e');
    }

    // 在邀請者的家庭成員列表中加入當前用戶
    await FirebaseFirestore.instance
        .collection('users')
        .doc(inviterId)
        .collection('family_members')
        .doc(currentUserId)
        .set({
      'name': _userData?.fullName ?? '家庭成員',
      'relation': _getReverseRelation(relation),
      'userId': currentUserId,
      'email': _userData?.email ?? '',
      'sharedData': sharedData,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    // 在當前用戶的家庭成員列表中加入邀請者
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('family_members')
        .doc(inviterId)
        .set({
      'name': inviterName,
      'relation': relation,
      'userId': inviterId,
      'email': invitationData['emailOrPhone'],
      'sharedData': sharedData,
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  // 獲取相反的關係稱謂
  String _getReverseRelation(String relation) {
    switch (relation) {
      case '父親': return '兒子/女兒';
      case '母親': return '兒子/女兒';
      case '兒子': return '父親/母親';
      case '女兒': return '父親/母親';
      case '配偶': return '配偶';
      case '祖父': return '孫子/孫女';
      case '祖母': return '孫子/孫女';
      default: return '家人';
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
      if (medication.times_status[med.timeIndex!]) {
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
      await _loadTodayMedications();

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

  Future<void> _loadAllData() async {
    bool hasError = false;
    try {
      await _loadUserData();
      await _loadHealthRecords();
      await _loadMedications();
      await _loadTodayMedications();
      if (mounted) {
        setState(() {
          _calculateHealthStats();
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      hasError = true;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // 只在完全載入失敗時顯示錯誤提示
        if (hasError && _userData == null && _healthRecords.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('載入資料時發生錯誤，請檢查網路連線'),
              backgroundColor: AppColors.error,
              action: SnackBarAction(
                label: '重試',
                textColor: AppColors.surface,
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadAllData();
                },
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      final db = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;
      final userId = auth.currentUser?.uid;

      if (userId == null) {
        debugPrint('User not logged in');
        return;
      }

      debugPrint('Loading user data for: $userId');

      // 根據您的 Firebase 結構，直接讀取 users 集合
      final docRef = db.collection('users').doc(userId);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        debugPrint('User data found: ${docSnapshot.data()}');
        if (mounted) {
          setState(() {
            _userData = UserModel.fromFirestore(docSnapshot);
          });
        }
      } else {
        debugPrint('No user data found at users/$userId');
        // 嘗試其他可能的路徑
        await _tryAlternativePaths(userId);
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _tryAlternativePaths(String userId) async {
    final db = FirebaseFirestore.instance;
    
    // 嘗試從 user_settings 讀取
    try {
      final settingsRef = db
          .collection('users')
          .doc(userId)
          .collection('user_settings')
          .doc(userId);
      final settingsSnapshot = await settingsRef.get();
      
      if (settingsSnapshot.exists) {
        debugPrint('User data found in user_settings');
        if (mounted) {
          setState(() {
            _userData = UserModel.fromFirestore(settingsSnapshot);
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('Error reading user_settings: $e');
    }
  }

  Future<void> _loadHealthRecords() async {
    try {
      final db = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;
      final userId = auth.currentUser?.uid;

      if (userId == null) {
        debugPrint('❌ 用戶未登入');
        return;
      }

      debugPrint('🔍 開始讀取健康記錄...');
      debugPrint('🔍 用戶ID: $userId');
      debugPrint('🔍 正在從 users/$userId/health_records 讀取數據...');

      // 先嘗試不排序讀取（避免索引問題）
      QuerySnapshot healthQuery;
      try {
        healthQuery = await db
            .collection('users')
            .doc(userId)
            .collection('health_records')
            .get();
      } catch (e) {
        debugPrint('❌ 讀取健康記錄失敗: $e');
        return;
      }

      debugPrint('📊 從資料庫收到 ${healthQuery.docs.length} 筆記錄');

      if (healthQuery.docs.isEmpty) {
        debugPrint('⚠️ Firebase 中沒有任何健康記錄！');
        debugPrint('   請確認是否已經新增過健康記錄數據');
      }

      final records = <HealthRecord>[];
      int successCount = 0;
      int errorCount = 0;

      for (final doc in healthQuery.docs) {
        try {
          final data = doc.data();
          debugPrint('🔍 處理記錄 ${doc.id}');
          debugPrint('   原始數據: $data');

          // 使用 RecordData 解析
          final recordData = RecordData.fromFirestore(doc);
          debugPrint('   解析後: category=${recordData.category}, value=${recordData.value}');

          // 轉換為 Dashboard 使用的 HealthRecord 格式
          final healthRecord = HealthRecord.fromRecordData(recordData);
          debugPrint('   健康記錄: type=${healthRecord.type}, value=${healthRecord.value}');

          // 只添加有有效數據的記錄
          if (healthRecord.value > 0) {
            records.add(healthRecord);
            successCount++;
            debugPrint('✅ 成功轉換記錄: ${recordData.category} - ${healthRecord.value}');
          } else {
            debugPrint('⚠️ 記錄無有效數值，跳過: ${recordData.category}');
            errorCount++;
          }

        } catch (e, stackTrace) {
          debugPrint('❌ 解析記錄 ${doc.id} 失敗: $e');
          debugPrint('   堆疊追蹤: $stackTrace');
          errorCount++;
        }
      }

      // 按時間排序（客戶端排序）
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      debugPrint('📈 轉換結果: 成功 $successCount 筆, 失敗 $errorCount 筆, 總共 ${records.length} 筆有效記錄');

      if (mounted) {
        setState(() {
          _healthRecords = records;
        });
      }

      // 如果主要路徑沒有數據，嘗試其他路徑
      if (records.isEmpty) {
        debugPrint('⚠️ 主要路徑無數據，嘗試其他路徑...');
        await _loadFamilyHealthRecords();
      }
    } catch (e) {
      debugPrint('Error loading health records: $e');
      // 如果主要路徑失敗，嘗試 family_members 路徑
      await _loadFamilyHealthRecords();
    }
  }

  Future<void> _loadFamilyHealthRecords() async {
    try {
      final db = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;
      final userId = auth.currentUser?.uid;

      if (userId == null) return;

      debugPrint('🔍 嘗試從 family_members 讀取健康記錄...');

      // 嘗試從 family_members 讀取健康記錄
      final familyQuery = await db
          .collection('family_members')
          .doc(userId)
          .collection('health_records')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      final records = familyQuery.docs
          .map((doc) => HealthRecord.fromFirestore(doc.data()))
          .toList();

      debugPrint('Loaded ${records.length} family health records');

      if (mounted) {
        setState(() {
          _healthRecords.addAll(records);
        });
      }
    } catch (e) {
      debugPrint('Error loading family health records: $e');
    }
  }

  Future<void> _loadMedications() async {
    try {
      final db = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;
      final userId = auth.currentUser?.uid;

      if (userId == null) return;

      // 讀取 medicine 集合（基本藥物資訊）
      final medsQuery = await db
          .collection('users')
          .doc(userId)
          .collection('medicine')
          .get();

      final medications = <MedicationRecord>[];
      
      for (final doc in medsQuery.docs) {
        try {
          final data = doc.data();
          debugPrint('💊 處理藥物資料: $data');
          
          // 安全地創建 MedicationRecord
          final medication = MedicationRecord.fromFirestore(data);
          medications.add(medication);
        } catch (e) {
          debugPrint('❌ 處理藥物資料失敗: $e');
        }
      }

      debugPrint('Loaded ${medications.length} medications');
    } catch (e) {
      debugPrint('Error loading medications: $e');
    }
  }

  // 載入今日用藥（為每個服藥時間創建獨立記錄）
  Future<void> _loadTodayMedications() async {
    try {
      final db = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;
      final userId = auth.currentUser?.uid;

      if (userId == null) return;

      // 讀取 medicine 集合（直接從藥物資訊獲取今日用藥狀態）
      final medsQuery = await db
          .collection('users')
          .doc(userId)
          .collection('medicine')
          .get();

      List<MedicationRecord> todayMeds = [];

      for (final doc in medsQuery.docs) {
        try {
          final data = doc.data();
          final medicineId = doc.id;

          // 解析藥物資料
          final medicineName = data['name'] as String? ?? '未命名藥物';
          final dosage = data['dosage'] as String? ?? '';
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

          debugPrint('💊 載入藥物: $medicineName，共 ${timesOfDayList.length} 次服藥');
        } catch (e) {
          debugPrint('❌ 處理今日用藥記錄失敗: $e');
        }
      }

      // 按照時間排序
      todayMeds.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

      debugPrint('✅ 載入了 ${todayMeds.length} 筆今日用藥記錄');

      if (mounted) {
        setState(() {
          _todayMedications = todayMeds;
        });
      }
    } catch (e) {
      debugPrint('❌ 載入今日用藥失敗: $e');
      if (mounted) {
        setState(() {
          _todayMedications = [];
        });
        // 用藥資料對用戶很重要，顯示錯誤提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('載入用藥記錄失敗'),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 已移除 _generateTodayMedicationsFromBase 函數，現在直接從 medicine 集合讀取

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