import 'medication_history.dart';
import '../utils/medication_regimen.dart';
import '../models/medication_dose.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/medication_model.dart';

class FirestoreService {
  FirestoreService({
    FirebaseFirestore? firestore,
    String? Function()? currentUid,
    DateTime Function()? now,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _now = now ?? DateTime.now,
       _uidProvider =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);
  final FirebaseFirestore _firestore;
  final DateTime Function() _now;
  final String? Function() _uidProvider;

  // --- 輔助函式：確保所有集合都在 users/{uid} 下 ---

  // 使用 stream 監聽用戶狀態，確保我們總是能拿到最新的 UID
  String? get _currentUid => _uidProvider();

  // 獲取 Medicine 集合路徑: users/{uid}/medicine
  CollectionReference _getRawMedicationsCollection() {
    final uid = _currentUid;
    if (uid == null) {
      debugPrint(
        'AUTH ERROR: _getRawMedicationsCollection failed. User is not logged in.',
      );
      throw Exception(
        'AuthError: User not logged in. Cannot access medication collection.',
      );
    }

    // 構造路徑: users/{uid}/medicine
    return _firestore.collection('users').doc(uid).collection('medicine');
  }

  // ⭐ 關鍵修正：獲取 Medication Logs 集合路徑: users/{uid}/medication_logs
  CollectionReference _getMedicationLogsCollection() {
    final uid = _currentUid;
    if (uid == null) {
      debugPrint(
        'AUTH ERROR: _getMedicationLogsCollection failed. User is not logged in.',
      );
      throw Exception(
        'AuthError: User not logged in. Cannot access medication log collection.',
      );
    }
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('medication_logs');
  }

  // 2. 輔助函式：用於 Model 讀取 (例如：StreamBuilder) 和本次交易讀取
  // 返回帶有 medicine 轉換器的 CollectionReference
  CollectionReference<medicine> getMedicationsCollectionWithConverter() {
    // 使用原始 CollectionReference, 然後添加轉換器
    return _getRawMedicationsCollection().withConverter<medicine>(
      fromFirestore: (snapshot, _) => medicine.fromFirestore(snapshot),
      toFirestore: (med, _) => med.toFirestore(),
    );
  }

  // ----------------------------------------------------
  // I. 用藥管理 (Medication)
  // ----------------------------------------------------

  /// 執行用藥狀態切換的原子交易 (新增/取消)
  Future<bool> toggleMedicationIntake({
    required medicine medication,
    required int timeSlotIndex,
  }) async {
    final uid = _currentUid;
    final id = medication.medicine_id;
    if (uid == null || id == null) throw StateError('請登入並重新載入藥品。');
    if (timeSlotIndex < 0 ||
        timeSlotIndex >= medication.times_status.length ||
        timeSlotIndex >= medication.times_of_day_list.length)
      throw StateError('服藥時段不存在。');
    final operationDay = calendarDay(_now());
    if (medication.times_status[timeSlotIndex] &&
        calendarDay(medication.lastUpdated) != operationDay) {
      throw StateError('已跨日，請重新載入今天的服藥狀態。');
    }
    final taking = !medication.times_status[timeSlotIndex];
    final owner = _firestore.collection('users').doc(uid);
    final ref = owner.collection('medicine').doc(id);
    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (_currentUid != uid || !snapshot.exists) throw StateError('帳號或藥品已變更。');
      final current = medicine.fromFirestore(snapshot);
      final now = _now();
      if (calendarDay(now) != operationDay) {
        throw StateError('操作期間已跨日，請重新載入。');
      }
      // A boolean alone cannot detect take/cancel/take (ABA). Preserve the
      // generation from the initiating screen across transaction retries.
      if (current.intakeSequence != medication.intakeSequence) {
        throw StateError('用藥操作已在其他畫面更新，請重新載入。');
      }
      final times = current.times_of_day_list;
      if (times.map((t) => '${t.hour}:${t.minute}').toSet().length !=
          times.length)
        throw StateError('提醒時段不可重複，請先編輯藥品。');
      if (timeSlotIndex >= times.length ||
          timeSlotIndex >= current.times_status.length ||
          times[timeSlotIndex].hour !=
              medication.times_of_day_list[timeSlotIndex].hour ||
          times[timeSlotIndex].minute !=
              medication.times_of_day_list[timeSlotIndex].minute) {
        throw StateError('服藥時段已變更，請重新載入。');
      }
      final status = calendarDay(now).isAfter(calendarDay(current.lastUpdated))
          ? List<bool>.filled(times.length, false)
          : List<bool>.from(current.times_status);
      if (status[timeSlotIndex] == taking) throw StateError('用藥狀態已更新，請重新載入。');
      final stock = current.total_supply.toDouble();
      final dose = current.total_pills.toDouble();
      if (!stock.isFinite || stock < 0 || !dose.isFinite || dose <= 0)
        throw StateError('劑量或庫存無效。');
      if (taking && !MedicationRegimen(current).includesDay(now)) {
        throw StateError('今天不在此藥品的應服日期內。');
      }
      final day = '${now.year}-${now.month}-${now.day}';
      final slot =
          '${times[timeSlotIndex].hour}:${times[timeSlotIndex].minute}';
      final receipts = Map<String, dynamic>.from(
        snapshot.data()?['intake_receipts'] ?? {},
      );
      double deducted;
      double loggedDose = dose;
      if (taking) {
        deducted = stock < dose ? stock : dose;
        receipts[slot] = {'day': day, 'deducted': deducted, 'dosage': dose};
      } else {
        final receipt = receipts[slot];
        if (receipt is! Map ||
            receipt['day'] != day ||
            receipt['deducted'] is! num ||
            receipt['dosage'] is! num) {
          throw StateError('舊服藥紀錄缺少庫存扣除明細，無法安全取消；請先核對紀錄與庫存。');
        }
        deducted = (receipt['deducted'] as num).toDouble();
        loggedDose = (receipt['dosage'] as num).toDouble();
        if (!deducted.isFinite ||
            deducted < 0 ||
            !loggedDose.isFinite ||
            loggedDose <= 0)
          throw StateError('扣除明細無效。');
        receipts.remove(slot);
      }
      final remaining = taking ? stock - deducted : stock + deducted;
      final sequence = (snapshot.data()?['intake_sequence'] as int? ?? 0) + 1;
      status[timeSlotIndex] = taking;
      tx.update(ref, {
        'times_status': status,
        'total_supply': remaining,
        'lastUpdated': Timestamp.fromDate(now),
        'intake_receipts': receipts,
        'intake_sequence': sequence,
        if (snapshot.data()?['regimen_history'] == null)
          'regimen_history': [regimenVersion(current.toFirestore(), now)],
      });
      tx.set(owner.collection('medication_logs').doc(), {
        'medicine_id': id,
        'medicine_name': current.name,
        'intake_time': Timestamp.fromDate(now),
        'operation_sequence': sequence,
        'scheduled_at': Timestamp.fromDate(
          DateTime(
            now.year,
            now.month,
            now.day,
            times[timeSlotIndex].hour,
            times[timeSlotIndex].minute,
          ),
        ),
        'dosage_taken': loggedDose,
        'stock_change': taking ? -deducted : deducted,
        'dose_number': timeSlotIndex + 1,
        'user_id': uid,
        'is_taken': taking,
        'status': taking ? 'taken' : 'cancelled',
        'route': current.route,
        'frequency': current.frequency,
        'remaining_days': _calculateRemainingDays(
          totalSupply: remaining,
          totalPills: dose,
          frequency: current.frequency,
        ),
        'created_at': FieldValue.serverTimestamp(),
      });
    });
    return taking;
  }

  Future<String> addMedication(medicine med) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('請先登入。');
    final ref = await _firestore
        .collection('users')
        .doc(uid)
        .collection('medicine')
        .add(medicationCreationData(med, _now()));
    return ref.id;
  }

  /// Merge only fields edited by this form; preserve live stock and intake receipts.
  Future<medicine> editMedication(medicine original, medicine edited) async {
    final uid = _currentUid;
    if (uid == null || original.medicine_id == null) throw StateError('請重新登入。');
    final before = original.toFirestore(), after = edited.toFirestore();
    const fields = [
      'name',
      'dosage',
      'unit',
      'total_pills',
      'frequency',
      'times_of_day_list',
      'instruction',
      'route',
      'duration_days',
      'start_date',
      'reminderEnabled',
      'source',
      'clinicalUse',
      'sideEffects',
      'precautions',
      'storageMethod',
      'appearance',
    ];
    bool equal(Object? a, Object? b) {
      if (a is List && b is List)
        return a.length == b.length &&
            List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
      return a == b;
    }

    final changes = <String, dynamic>{
      for (final key in fields)
        if (!equal(before[key], after[key]))
          key: after[key] ?? FieldValue.delete(),
    };
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('medicine')
        .doc(original.medicine_id);
    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (_currentUid != uid || !snapshot.exists) throw StateError('帳號或藥品已變更。');
      final current = medicine.fromFirestore(snapshot);
      final raw = current.toFirestore();
      final patch = Map<String, dynamic>.from(changes);
      for (final key in changes.keys) {
        if (!equal(raw[key], before[key]) && !equal(raw[key], after[key]))
          throw StateError('此欄位已在其他裝置修改，請重新載入。');
      }
      if (changes.containsKey('times_of_day_list')) {
        final statuses =
            calendarDay(_now()).isAfter(calendarDay(current.lastUpdated))
            ? List<bool>.filled(current.times_status.length, false)
            : current.times_status;
        final next = edited.times_of_day_list;
        final clocks = next.map((t) => '${t.hour}:${t.minute}').toList();
        if (clocks.toSet().length != clocks.length)
          throw StateError('提醒時段不可重複。');
        for (var i = 0; i < statuses.length; i++) {
          if (statuses[i] &&
              !clocks.contains(
                '${current.times_of_day_list[i].hour}:${current.times_of_day_list[i].minute}',
              ))
            throw StateError('已服用時段須先取消紀錄，才能移除或修改時間。');
        }
        patch['times_status'] = next.map((t) {
          final i = current.times_of_day_list.indexWhere(
            (old) => old.hour == t.hour && old.minute == t.minute,
          );
          return i >= 0 && i < statuses.length ? statuses[i] : false;
        }).toList();
      }
      if (regimenFields.any(changes.containsKey)) {
        MedicationRegimen(edited);
        patch['regimen_history'] = appendRegimenHistory(snapshot.data()!, {
          ...raw,
          ...changes,
        }, _now());
      }
      if (patch.isNotEmpty) tx.update(ref, patch);
    });
    return medicine.fromFirestore(await ref.get());
  }

  /// 計算剩餘天數（根據庫存、單次劑量、頻率）
  int _calculateRemainingDays({
    required num totalSupply,
    required num totalPills,
    required String frequency,
  }) => MedicationDose.remainingDays(totalSupply, totalPills, frequency);

  /// 獲取用藥日誌的 Stream
  Stream<QuerySnapshot> getMedicationLogs() {
    // ⭐ 修正 3: 在讀取之前檢查用戶 ID
    if (_currentUid == null) {
      debugPrint(
        'WARN: User is not authenticated. Medication logs stream is empty.',
      );
      return Stream.empty(); // 如果未登入，返回一個空的 Stream
    }

    // 獲取用戶專屬的日誌集合
    return _getMedicationLogsCollection()
        .orderBy('intake_time', descending: true)
        .snapshots();
  }

  // ----------------------------------------------------
  // II. 健康紀錄 (Health Records)
  // ----------------------------------------------------

  CollectionReference _getHealthRecordsCollection() {
    final uid = _currentUid;
    if (uid == null) {
      debugPrint(
        'AUTH ERROR: _getHealthRecordsCollection failed. User is not logged in.',
      );
      throw Exception('User not logged in');
    }
    return _firestore.collection('users').doc(uid).collection('health_records');
  }

  /// 新增健康紀錄
  Future<void> addHealthRecord(Map<String, dynamic> data) async {
    if (_currentUid == null) {
      throw Exception(
        'AuthError: Cannot add health record, user not authenticated.',
      );
    }
    try {
      await _getHealthRecordsCollection().add(data);
    } catch (e) {
      throw Exception('Failed to add health record: $e');
    }
  }

  /// 更新健康紀錄
  Future<void> updateHealthRecord(
    String recordId,
    Map<String, dynamic> data,
  ) async {
    if (_currentUid == null) {
      throw Exception(
        'AuthError: Cannot update health record, user not authenticated.',
      );
    }
    try {
      await _getHealthRecordsCollection().doc(recordId).update(data);
    } catch (e) {
      throw Exception('Failed to update health record: $e');
    }
  }

  /// 刪除健康紀錄
  Future<void> deleteHealthRecord(String recordId) async {
    if (_currentUid == null) {
      throw Exception(
        'AuthError: Cannot delete health record, user not authenticated.',
      );
    }
    try {
      await _getHealthRecordsCollection().doc(recordId).delete();
    } catch (e) {
      throw Exception('Failed to delete health record: $e');
    }
  }

  /// 獲取健康紀錄的 Stream
  Stream<QuerySnapshot> getHealthRecords() {
    try {
      if (_currentUid == null) {
        debugPrint(
          'WARN: User is not authenticated. Health records stream is empty.',
        );
        return Stream.empty();
      }
      return _getHealthRecordsCollection()
          .orderBy('record_time', descending: true)
          .snapshots();
    } catch (e) {
      // 如果獲取失敗，返回空的 Stream
      return Stream.empty();
    }
  }

  // ----------------------------------------------------
  // III. 飲食紀錄 (Diet Records)
  // ----------------------------------------------------

  // 獲取 Diet Records 集合路徑: users/{uid}/diet_records
  CollectionReference _getDietRecordsCollection() {
    final uid = _currentUid;
    if (uid == null) {
      debugPrint(
        'AUTH ERROR: _getDietRecordsCollection failed. User is not logged in.',
      );
      throw Exception(
        'AuthError: User not logged in. Cannot access diet records collection.',
      );
    }
    return _firestore.collection('users').doc(uid).collection('diet_records');
  }

  /// 新增飲食紀錄
  Future<void> addDietRecord(Map<String, dynamic> data) async {
    if (_currentUid == null) {
      throw Exception(
        'AuthError: Cannot add diet record, user not authenticated.',
      );
    }
    try {
      // 確保包含時間戳記
      final recordData = {...data, 'timestamp': FieldValue.serverTimestamp()};

      await _getDietRecordsCollection().add(recordData);
      debugPrint(
        '✅ Diet record added successfully: ${data['foodName'] ?? 'Unknown food'}',
      );
    } catch (e) {
      debugPrint('❌ Failed to add diet record: $e');
      throw Exception('Failed to add diet record: $e');
    }
  }

  /// 獲取飲食紀錄的 Stream
  Stream<QuerySnapshot> getDietRecords() {
    try {
      if (_currentUid == null) {
        debugPrint(
          'WARN: User is not authenticated. Diet records stream is empty.',
        );
        return Stream.empty();
      }
      return _getDietRecordsCollection()
          .orderBy('timestamp', descending: true)
          .snapshots();
    } catch (e) {
      debugPrint('❌ Error getting diet records: $e');
      return Stream.empty();
    }
  }
} // 注意：這裡是類別的結束大括號
