import '../services/medication_day_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'medication_add_screen.dart';
import 'medication_detail_screen.dart';
import 'medication_log_screen.dart';
import 'prescription_scan_screen.dart';

// 導入服務層
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

// 導入設計系統
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart'; 

class MedicationScreen extends StatefulWidget {
  const MedicationScreen({super.key});

  @override
  State<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends State<MedicationScreen>
    with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance; 
  final FirestoreService _firestoreService = FirestoreService(); 

  late final CollectionReference<medicine> _medicationsCollection;

  StreamSubscription<QuerySnapshot<medicine>>? _resetSubscription;
  Stream<QuerySnapshot<medicine>>? _medicationsStream;
  final Set<String> _resettingMedicationIds = {};
  final Map<String, medicine> _observedMedications = {};
  Timer? _dayTimer;

  final Map<String, bool> hoverMap = {};

  final List<String> encouragementMessages = [
    '太棒了！您剛剛完成了今日的用藥，健康又向前邁進了一步！🎉',
    '用藥完成！您的堅持是健康的基石，繼續保持！💪',
    '恭喜！您已成功完成用藥，為自己的健康負責，真了不起！🌟',
    '用藥完成！每一次的堅持都在為健康加分，做得很好！⭐',
    '太優秀了！按時用藥是維持健康的重要習慣，您做得很好！🏆',
    '用藥完成！您的自律讓健康更有保障，繼續保持這個好習慣！🌈',
  ];

  // 新增：追蹤是否已顯示重置通知
  bool _hasShownResetNotification = false;
  DateTime? _lastResetDate;

  @override
  void initState() {
    super.initState();
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      _medicationsCollection = _firestore
          .collection('users')
          .doc(uid)
          .collection('medicine')
          .withConverter<medicine>(
        fromFirestore: (snapshot, _) => medicine.fromFirestore(snapshot),
        toFirestore: (med, _) => med.toFirestore(),
      );
    }
    _lastResetDate = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) => _refreshMedicationDay());
    if (uid != null) {
      _medicationsStream = _medicationsCollection.orderBy('name').snapshots();
      _resetSubscription = _medicationsStream!.listen((snapshot) {
        _observedMedications
          ..clear()
          ..addEntries(snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())));
        _refreshMedicationDay();
      }, onError: (Object error) {
        debugPrint('用藥重置監聽失敗: $error');
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayTimer?.cancel();
    _resetSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshMedicationDay();
  }

  void _refreshMedicationDay() {
    if (!mounted) return;
    for (final entry in _observedMedications.entries) {
      if (entry.value.shouldResetStatus) _resetMedication(entry.key);
    }
  }

  Future<void> _resetMedication(String id) async {
    if (!_resettingMedicationIds.add(id)) return;
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      final reset = await MedicationDayService(_firestore).resetIfNeeded(uid, id);
      if (reset == null || !mounted) return;
      await _scheduleMedicationReminders(id, reset);
      if (!mounted || _hasShownResetNotification) return;
      _hasShownResetNotification = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('新的一天開始！用藥狀態已重置')),
      );
    } catch (error) {
      debugPrint('重置用藥狀態失敗: $error');
    } finally {
      _resettingMedicationIds.remove(id);
    }
  }

  // 新增：重置通知狀態（當頁面重新打開時）
  void _resetNotificationState() {
    final now = DateTime.now();
    final currentDate = DateTime(now.year, now.month, now.day);
    
    if (_lastResetDate == null || 
        currentDate.isAfter(DateTime(_lastResetDate!.year, _lastResetDate!.month, _lastResetDate!.day))) {
      _hasShownResetNotification = false;
      _lastResetDate = now;
    }
  }

  Future<void> _addMedication(medicine medication) async {
    try {
      final initialTimesStatus = List<bool>.filled(medication.times_of_day_list.length, false);
      final medicationWithStatus = medication.copyWith(times_status: initialTimesStatus);

      final docRef = await _medicationsCollection.add(medicationWithStatus);

      // 排程用藥提醒通知
      await _scheduleMedicationReminders(docRef.id, medicationWithStatus);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('藥品已新增'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增失敗: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 排程用藥提醒通知
  Future<void> _scheduleMedicationReminders(String medicineId, medicine med) async {
    final notificationService = NotificationService();

    // 如果該藥物已關閉提醒，取消所有通知並返回
    if (!med.reminderEnabled) {
      for (int i = 0; i < med.times_of_day_list.length; i++) {
        final notificationId = medicineId.hashCode + i;
        await notificationService.cancelNotification(notificationId);
        // 取消漏吃提醒
        for (int j = 1; j <= 3; j++) {
          await notificationService.cancelNotification(notificationId + 1000 + j);
        }
      }
      debugPrint('已取消 ${med.name} 的所有提醒');
      return;
    }

    final missedDoseSettings = notificationService.getMissedDoseSettings();
    final missedDoseInterval = missedDoseSettings['missedDoseInterval'] as int? ?? 30;
    final maxReminders = missedDoseSettings['missedDoseMaxReminders'] as int? ?? 2;

    for (int i = 0; i < med.times_of_day_list.length; i++) {
      final time = med.times_of_day_list[i];
      final now = DateTime.now();

      // 建立今天的排程時間
      var scheduledTime = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );

      // 如果今天的時間已過，排程到明天
      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      // 使用 medicineId 的 hashCode 和 index 產生唯一的通知 ID
      final notificationId = medicineId.hashCode + i;

      // 排程正常用藥提醒
      await notificationService.scheduleMedicationReminder(
        id: notificationId,
        medicineName: med.name,
        dosage: med.dosage,
        scheduledTime: scheduledTime,
        medicationId: medicineId,
      );

      // 排程漏吃提醒（在用藥時間後的指定間隔）
      // 當 maxReminders = 0 時，表示「持續提醒」，最多排程 50 次（避免過多通知影響效能）
      final actualMaxReminders = maxReminders == 0
          ? 50  // 持續提醒模式最多 50 次
          : maxReminders;

      for (int j = 1; j <= actualMaxReminders; j++) {
        final missedDoseTime = scheduledTime.add(Duration(minutes: missedDoseInterval * j));

        await notificationService.scheduleMissedDoseReminder(
          id: notificationId,
          medicationName: med.name,
          dosage: med.dosage,
          scheduledTime: missedDoseTime,
          medicationId: medicineId,
          reminderCount: j,
        );
      }
    }

    debugPrint('已為 ${med.name} 排程 ${med.times_of_day_list.length} 個用藥提醒及漏吃提醒');
  }

  Future<void> _updateMedication(String medicineId, medicine medication) async {
    try {
      await _medicationsCollection.doc(medicineId).set(medication);

      // 取消舊的通知並重新排程
      await _cancelMedicationReminders(medicineId, medication.times_of_day_list.length);
      await _scheduleMedicationReminders(medicineId, medication);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('藥品已更新'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新失敗: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteMedication(String medicineId) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        throw Exception("User not logged in.");
      }

      // 取消該藥物的所有通知（假設最多 10 個時段）
      await _cancelMedicationReminders(medicineId, 10);

      await _firestore.collection('users').doc(uid).collection('medicine').doc(medicineId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('藥品已刪除'), backgroundColor: AppColors.warning),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刪除失敗: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 取消用藥提醒通知
  Future<void> _cancelMedicationReminders(String medicineId, int count) async {
    final notificationService = NotificationService();
    for (int i = 0; i < count; i++) {
      final notificationId = medicineId.hashCode + i;
      await notificationService.cancelNotification(notificationId);
    }
  }

  // 核心：用藥狀態切換邏輯
  Future<void> _toggleMedicationStatus(
    medicine med, 
    int timeIndex, 
  ) async {
    try {
      if (med.medicine_id == null) {
          throw Exception("ValidationError: 藥品ID缺失，無法進行用藥切換操作。");
      }
      
      // 調用服務層的原子交易
      final bool wasLogged = await _firestoreService.toggleMedicationIntake(
        medication: med,
        timeSlotIndex: timeIndex,
      );
      
      // --- UI 回饋邏輯 ---
      final String message;
      final Color color;

      if (wasLogged) {
        message = '${med.name} 第 ${timeIndex + 1} 次用藥已記錄';
        color = AppColors.success;

        // 取消該時段的用藥提醒和漏吃提醒
        final notificationId = med.medicine_id.hashCode + timeIndex;
        final notificationService = NotificationService();
        await notificationService.cancelNotification(notificationId);  // 取消用藥提醒
        await notificationService.cancelMissedDoseReminders(notificationId);  // 取消漏吃提醒
        debugPrint('已取消 ${med.name} 第 ${timeIndex + 1} 次的用藥提醒和漏吃提醒');

        // 觸發頁面重新整理以同步狀態
        if (mounted) {
          setState(() {});
        }

        // 檢查是否所有用藥都已完成
        final updatedMedications = await _getCurrentMedications();
        final currentMed = updatedMedications.firstWhere(
          (m) => m.medicine_id == med.medicine_id,
          orElse: () => med
        );

        if (currentMed.times_status.every((status) => status)) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _showEncouragementMessage();
            }
          });
        }

      } else {
        message = '${med.name} 第 ${timeIndex + 1} 次用藥記錄已取消';
        color = AppColors.warning;

        // 重新排程該時段的漏吃提醒
        final notificationService = NotificationService();
        final missedDoseSettings = notificationService.getMissedDoseSettings();
        final missedDoseInterval = missedDoseSettings['missedDoseInterval'] as int? ?? 30;
        final maxReminders = missedDoseSettings['missedDoseMaxReminders'] as int? ?? 2;

        final time = med.times_of_day_list[timeIndex];
        final now = DateTime.now();
        var scheduledTime = DateTime(now.year, now.month, now.day, time.hour, time.minute);

        // 當 maxReminders = 0 時，表示「持續提醒」，最多 50 次
        final actualMaxReminders = maxReminders == 0
            ? 50
            : maxReminders;

        // 如果用藥時間還沒過，重新排程漏吃提醒
        if (scheduledTime.isAfter(now) || scheduledTime.add(Duration(minutes: missedDoseInterval * actualMaxReminders)).isAfter(now)) {
          final notificationId = med.medicine_id.hashCode + timeIndex;

          for (int j = 1; j <= actualMaxReminders; j++) {
            final missedDoseTime = scheduledTime.add(Duration(minutes: missedDoseInterval * j));
            if (missedDoseTime.isAfter(now)) {
              await notificationService.scheduleMissedDoseReminder(
                id: notificationId,
                medicationName: med.name,
                dosage: med.dosage,
                scheduledTime: missedDoseTime,
                medicationId: med.medicine_id!,
                reminderCount: j,
              );
            }
          }
          debugPrint('已重新排程 ${med.name} 第 ${timeIndex + 1} 次的漏吃提醒');
        }

        // 觸發頁面重新整理以同步狀態
        if (mounted) {
          setState(() {});
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: color),
      );

    } catch (e, stackTrace) { 
      String displayMessage = "操作失敗：發生未知錯誤。";
      String errorMessage = e.toString();
      
      if (errorMessage.contains("ConcurrencyError")) {
        displayMessage = "操作失敗：用藥狀態已被其他操作更新，請重新整理清單後再試。";
      } else if (errorMessage.contains("FirestoreError")) {
         displayMessage = "操作失敗：找不到藥品資料或權限不足。";
      } else if (errorMessage.contains("ValidationError")) {
         displayMessage = "操作失敗：資料驗證錯誤。";
      } else {
          final match = RegExp(r"Exception: Medication intake toggle failed: (.+)$").firstMatch(errorMessage);
          if (match != null) {
              displayMessage = "操作失敗: ${match.group(1)!.trim()}";
          } else {
              displayMessage = "操作失敗: ${errorMessage.split('Exception:').last.trim()}";
          }
      }

      debugPrint('UI Layer Caught Error: $e');
      debugPrint('UI Layer Stack Trace: $stackTrace');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(displayMessage), backgroundColor: Colors.red),
      );
    }
  }

  // 新增：獲取當前藥物列表
  Future<List<medicine>> _getCurrentMedications() async {
    try {
      final snapshot = await _medicationsCollection.get();
      return snapshot.docs.map((doc) => doc.data().copyWith(medicine_id: doc.id)).toList();
    } catch (e) {
      debugPrint('獲取當前藥物列表失敗: $e');
      return [];
    }
  }

  void _showEncouragementMessage() {
    final randomMessage = (encouragementMessages..shuffle()).first;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '用藥完成！',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      randomMessage,
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.all(20),
        padding: EdgeInsets.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 每次建立頁面時重置通知狀態
    _resetNotificationState();
    
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('請先登入帳號以查看用藥資訊', style: TextStyle(color: Colors.red)));
    }
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('我的用藥'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.document_scanner, color: AppColors.primary),
            tooltip: '掃描處方箋',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrescriptionScanScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.menu_book, color: AppColors.primary),
            tooltip: '用藥記錄',
            onPressed: _navigateToMedicationLog,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary),
            tooltip: '新增用藥',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MedicationAddScreen()),
              );
              if (result is medicine) {
                _addMedication(result);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot<medicine>>(
                stream: _medicationsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text('載入失敗: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: Text('請先登入以查看用藥資料'));
                  }
                  final medications = snapshot.data!.docs
                      .map((doc) => doc.data().copyWith(medicine_id: doc.id)) 
                      .toList();


                  if (medications.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.medication_outlined,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '尚無用藥資料',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // 分類：未完成的藥物和已完成的藥物
                  final pendingMeds = medications.where((med) => !med.times_status.every((s) => s)).toList();
                  final completedMeds = medications.where((med) => med.times_status.every((s) => s)).toList();

                  return Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      children: [
                        // 待服用區塊
                        if (pendingMeds.isNotEmpty) ...[
                          _buildSectionHeader(
                            icon: Icons.schedule,
                            title: '待服用',
                            count: pendingMeds.length,
                            color: AppColors.warning,
                          ),
                          const SizedBox(height: 12),
                          ...pendingMeds.map((med) => _buildMedicationCardWithTap(med)),
                        ],

                        // 已完成區塊
                        if (completedMeds.isNotEmpty) ...[
                          if (pendingMeds.isNotEmpty) const SizedBox(height: 20),
                          _buildSectionHeader(
                            icon: Icons.check_circle,
                            title: '已完成',
                            count: completedMeds.length,
                            color: AppColors.success,
                          ),
                          const SizedBox(height: 12),
                          ...completedMeds.map((med) => _buildMedicationCardWithTap(med)),
                        ],

                        // 全部完成的鼓勵訊息
                        if (pendingMeds.isEmpty && completedMeds.isNotEmpty)
                          _buildAllCompletedBanner(),

                        const SizedBox(height: 20),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 區塊標題
  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required int count,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count 項',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  // 包含點擊事件的藥物卡片
  Widget _buildMedicationCardWithTap(medicine med) {
    final docId = med.medicine_id;
    if (docId == null) return _buildMedicationCard(med);
    return Dismissible(
      key: ValueKey(docId),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('確認刪除'),
            content: Text('確定要刪除「${med.name}」嗎？此操作無法復原。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('刪除'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => _deleteMedication(docId),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text('刪除', style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MedicationDetailScreen(
                medication: med,
                onUpdate: (medicine editedMed) => _updateMedication(docId, editedMed),
                onDelete: () => _deleteMedication(docId),
              ),
            ),
          );
        },
        child: _buildMedicationCard(med),
      ),
    );
  }

  // 全部完成的鼓勵橫幅
  Widget _buildAllCompletedBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.success, AppColors.success],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.celebration,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '太棒了！',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '今日所有用藥已完成，繼續保持！',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationCard(medicine med) {
    final List<String> formattedTimes = med.times_of_day_list.map((time) => _formatTime(time)).toList();
    
    final String timeString = formattedTimes.isNotEmpty 
        ? formattedTimes.join(', ') 
        : '未設定時間'; 
        
    final isAllTaken = med.times_status.every((status) => status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAllTaken ? AppColors.success : AppColors.border,
          width: isAllTaken ? 2 : 1.5,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  med.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isAllTaken ? AppColors.success : Colors.black87,
                    decoration: isAllTaken ? TextDecoration.lineThrough : TextDecoration.none,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: med.times_status.asMap().entries.map((entry) {
                  final index = entry.key;
                  final status = entry.value;

                  return Padding(
                    padding: EdgeInsets.only(left: index > 0 ? 8.0 : 0.0),
                    child: GestureDetector(
                      onTap: () => _toggleMedicationStatus(med, index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 35, 
                        height: 35,
                        decoration: BoxDecoration(
                          color: status ? AppColors.successLight : AppColors.background,
                          borderRadius: BorderRadius.circular(8), 
                          border: Border.all(
                            color: status ? AppColors.success : AppColors.border,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: status
                                ? Icon(
                                    Icons.check,
                                    color: AppColors.success,
                                    size: 20,
                                    key: ValueKey('checked_$index'),
                                  )
                                : SizedBox(
                                    key: ValueKey('unchecked_$index'),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoChip(
                icon: Icons.medication,
                text: med.dosage,
                color: AppColors.primary,
                isCompleted: isAllTaken,
              ),
              const SizedBox(width: 8),
              _buildInfoChip(
                icon: Icons.medical_services,
                text: med.route,
                color: AppColors.success,
                isCompleted: isAllTaken,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildInfoChip(
                icon: Icons.schedule,
                text: med.frequency,
                color: AppColors.warning,
                isCompleted: isAllTaken,
              ),
              const SizedBox(width: 8),
              _buildInfoChip(
                icon: Icons.assignment,
                text: med.instruction,
                color: const Color(0xFF9C27B0),
                isCompleted: isAllTaken,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: isAllTaken ? AppColors.success : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '用藥時間: $timeString',
                        style: TextStyle(
                          fontSize: 14,
                          color: isAllTaken ? AppColors.success : AppColors.textSecondary,
                          decoration: isAllTaken ? TextDecoration.lineThrough : TextDecoration.none,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '剩餘 ${med.remaining_days_calculated} 天',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isAllTaken
                      ? AppColors.success
                      : (med.remaining_days_calculated < 7
                          ? AppColors.warning
                          : AppColors.textSecondary),
                ),
              ),
            ],
          ),
          if (med.source != null && med.source!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.local_pharmacy_outlined, size: 13, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  med.source!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String text,
    required Color color,
    bool isCompleted = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isCompleted ? color.withOpacity(0.2) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted ? color : color.withOpacity(0.3),
          width: isCompleted ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isCompleted ? color : color.withOpacity(0.8),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: isCompleted ? color : color.withOpacity(0.8),
              fontWeight: FontWeight.w500,
              decoration: isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  
  Future<void> _navigateToMedicationLog() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationLogScreen(
          logs: _firestoreService.getMedicationLogs(), 
        ),
      ),
    );
  }
}