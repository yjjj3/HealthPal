import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:flutter/material.dart';
import '../models/medication_model.dart'; 

class FirestoreService {

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // --- 輔助函式：確保所有集合都在 users/{uid} 下 ---
  
  // 使用 stream 監聽用戶狀態，確保我們總是能拿到最新的 UID
  String? get _currentUid => _auth.currentUser?.uid;

  // 獲取 Medicine 集合路徑: users/{uid}/medicine
  CollectionReference _getRawMedicationsCollection() {
    final uid = _currentUid;
    if (uid == null) {
      debugPrint('AUTH ERROR: _getRawMedicationsCollection failed. User is not logged in.');
      throw Exception('AuthError: User not logged in. Cannot access medication collection.'); 
    }
    
    // 構造路徑: users/{uid}/medicine
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('medicine');
  }

  // ⭐ 關鍵修正：獲取 Medication Logs 集合路徑: users/{uid}/medication_logs
  CollectionReference _getMedicationLogsCollection() {
      final uid = _currentUid;
      if (uid == null) {
        debugPrint('AUTH ERROR: _getMedicationLogsCollection failed. User is not logged in.');
        throw Exception('AuthError: User not logged in. Cannot access medication log collection.'); 
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
    return _getRawMedicationsCollection()
        .withConverter<medicine>(
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
    if (_currentUid == null) {
      // 交易失敗，因為用戶未登入
      throw Exception('AuthError: Cannot toggle intake, user not authenticated.');
    }
    
    if (medication.medicine_id == null) {
      throw Exception('ValidationError: Medication ID is missing.');
    }
    
    // 1. 使用帶有轉換器的 DocumentReference<medicine> 來讀取
    final medicineRefWithConverter = getMedicationsCollectionWithConverter().doc(medication.medicine_id!);
    
    // 2. 使用原始的 DocumentReference 來更新 (因為 update 接受 Map)
    final medicineRef = _getRawMedicationsCollection().doc(medication.medicine_id!);
    
    // ⭐ 修正 2: 使用用戶專屬的日誌集合
    final logCollection = _getMedicationLogsCollection();
    
    // isLogging 為 true 表示要執行記錄（將狀態從 false 切換為 true）
    final isLogging = medication.shouldResetStatus || !medication.times_status[timeSlotIndex];
    
    double? newRemainingPills; 
    
    try { 
        debugPrint('Service: Starting transaction for ${medication.name}, slot $timeSlotIndex. Logging: $isLogging');
        
        // --- 執行 Firestore 交易 ---
        await _firestore.runTransaction((transaction) async {
          try {
            debugPrint('Transaction: Attempting to get document: ${medicineRefWithConverter.path}');
            
            // 修正 2: 獲取文檔快照 (類型為 DocumentSnapshot<medicine>)
            final snapshot = await transaction.get(medicineRefWithConverter);
            
            if (!snapshot.exists) {
              throw Exception("FirestoreError: Medication document does not exist at path: ${medicineRefWithConverter.path}");
            }

            // ⭐ 修正 3 (關鍵 V2): 隔離並強制將 model 轉換為 Map，解決 Web DDC 錯誤
            final medicineInstance = snapshot.data(); // 這裡返回的是 medicine?
            
            if (medicineInstance == null) {
                throw Exception("DataError: Medication snapshot data is null (medicine instance missing).");
            }

            // 這是強制 Dart Development Compiler (DDC) 正確執行 toFirestore() 的關鍵步驟
            // 顯式宣告 model 類型，並調用 toFirestore() 取得 Map
            final medicine dataModel = medicineInstance; 
            final data = dataModel.toFirestore();

            // 1. 讀取單次劑量 (total_pills)
            // 從安全的 Map 讀取
            final dosage = (data['total_pills'] as num? ?? 1).toDouble();
            
            // 2. 讀取狀態列表
            final firestoreStatus = dataModel.shouldResetStatus
                ? List<bool>.filled(dataModel.times_status.length, false)
                : List<bool>.from(data['times_status'] ?? []);
            if (timeSlotIndex < 0 || timeSlotIndex >= firestoreStatus.length) {
              throw Exception('ValidationError: Invalid medication time slot.');
            }

            // 3. 讀取現有庫存 (total_supply)，並使用容錯處理
            double currentRemainingPills = 0.0;
            final rawRemainingPills = data['total_supply'];

            if (rawRemainingPills is num) {
                currentRemainingPills = rawRemainingPills.toDouble();
            } else if (rawRemainingPills is String) {
                currentRemainingPills = double.tryParse(rawRemainingPills) ?? 0.0;
            } 
            
            debugPrint('Transaction: Dosage per time (total_pills): $dosage');
            debugPrint('Transaction: Current remaining pills (total_supply): $currentRemainingPills');

            
            // 4. 檢查狀態是否已被其他操作改變 (Race Condition Check)
            if (firestoreStatus[timeSlotIndex] == isLogging) {
              throw Exception("ConcurrencyError: 狀態不符，用藥狀態已被更新，請重新整理後再試。");
            }
            
            // 5. 執行狀態和庫存調整
            firestoreStatus[timeSlotIndex] = isLogging; 
            
            double pillsToChange = isLogging ? -dosage : dosage; 
            newRemainingPills = currentRemainingPills + pillsToChange;

            if (newRemainingPills! < 0) {
              debugPrint('Warning: Remaining pills will be negative. Capping at 0.');
            }

            // ⭐ 關鍵修正：無論是服用還是取消，都在交易中記錄日誌
            // 計算更新後的剩餘天數
            final updatedRemainingDays = _calculateRemainingDays(
              totalSupply: newRemainingPills! > 0 ? newRemainingPills!.toInt() : 0,
              totalPills: dosage.toInt(),
              frequency: medication.frequency,
            );

            final logData = {
              'medicine_id': medication.medicine_id,
              'medicine_name': medication.name,
              'intake_time': Timestamp.now(),
              'dosage_taken': dosage,
              'dose_number': timeSlotIndex + 1, // 使用一致的欄位名稱
              'user_id': _currentUid,
              'is_taken': isLogging, // true = 服用, false = 取消
              'status': isLogging ? 'taken' : 'cancelled', // 明確的狀態文字
              'route': medication.route,
              'frequency': medication.frequency,
              'remaining_days': updatedRemainingDays, // 新增：記錄當時的剩餘天數
              'created_at': FieldValue.serverTimestamp(),
            };
            
            // 新增日誌記錄（服用和取消都會記錄）
            transaction.set(logCollection.doc(), logData);
            debugPrint('Transaction: Writing log for ${isLogging ? "intake" : "cancellation"}.');

            // 6. 提交狀態和庫存的更新 (使用未轉換的 Ref 進行更新)
            transaction.update(medicineRef, {
              'times_status': firestoreStatus,
              'lastUpdated': Timestamp.now(),
              'total_supply': newRemainingPills! > 0 ? newRemainingPills : 0, 
            });
            debugPrint('Transaction: Document updated successfully.');
          } catch (e, stackTrace) {
             debugPrint('!!! TRANSACTION CRITICAL ERROR INSIDE TRANSACTION BLOCK (Potential Security Rule or Data Type Error)!!!');
             debugPrint('Error: $e');
             debugPrint('Stack Trace: $stackTrace');
             // 必須重新拋出，讓 runTransaction 知道失敗
             rethrow; 
          }
        });
        debugPrint('Service: Transaction completed successfully.');
        
        return isLogging; 
        
    } catch (e, stackTrace) {
      debugPrint('!!! SERVICE EXTERNAL CATCH BLOCK TRIGGERED (This error is being sent to UI)!!!');
      debugPrint('External Error: $e');
      debugPrint('External Stack Trace: $stackTrace');
      
      // 重新拋出更易讀的錯誤訊息給 UI 層
      // 處理 Web/JS 平台錯誤：由於錯誤來自底層 JS 引擎，我們仍然拋出一個自定義 Exception
      throw Exception('Medication intake toggle failed: ${e.toString()}'); 
    }
  }

  /// 計算剩餘天數（根據庫存、單次劑量、頻率）
  int _calculateRemainingDays({
    required int totalSupply,
    required int totalPills,
    required String frequency,
  }) {
    if (totalSupply <= 0 || totalPills <= 0) return 0;

    int frequencyCount = 1;
    if (frequency.contains('1次')) {
      frequencyCount = 1;
    } else if (frequency.contains('2次')) {
      frequencyCount = 2;
    } else if (frequency.contains('3次')) {
      frequencyCount = 3;
    }

    int dailyDosage = frequencyCount * totalPills;
    if (dailyDosage <= 0) return 0;

    return totalSupply ~/ dailyDosage;
  }

  /// 獲取用藥日誌的 Stream
  Stream<QuerySnapshot> getMedicationLogs() {
    // ⭐ 修正 3: 在讀取之前檢查用戶 ID
    if (_currentUid == null) {
      debugPrint('WARN: User is not authenticated. Medication logs stream is empty.');
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
      debugPrint('AUTH ERROR: _getHealthRecordsCollection failed. User is not logged in.');
      throw Exception('User not logged in'); 
    }
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('health_records');
  }

  /// 新增健康紀錄
  Future<void> addHealthRecord(Map<String, dynamic> data) async {
    if (_currentUid == null) {
      throw Exception('AuthError: Cannot add health record, user not authenticated.');
    }
    try {
      await _getHealthRecordsCollection().add(data);
    } catch (e) {
      throw Exception('Failed to add health record: $e');
    }
  }

  /// 更新健康紀錄
  Future<void> updateHealthRecord(String recordId, Map<String, dynamic> data) async {
    if (_currentUid == null) {
      throw Exception('AuthError: Cannot update health record, user not authenticated.');
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
      throw Exception('AuthError: Cannot delete health record, user not authenticated.');
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
        debugPrint('WARN: User is not authenticated. Health records stream is empty.');
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
      debugPrint('AUTH ERROR: _getDietRecordsCollection failed. User is not logged in.');
      throw Exception('AuthError: User not logged in. Cannot access diet records collection.'); 
    }
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('diet_records');
  }

  /// 新增飲食紀錄
  Future<void> addDietRecord(Map<String, dynamic> data) async {
    if (_currentUid == null) {
      throw Exception('AuthError: Cannot add diet record, user not authenticated.');
    }
    try {
      // 確保包含時間戳記
      final recordData = {
        ...data,
        'timestamp': FieldValue.serverTimestamp(),
      };
      
      await _getDietRecordsCollection().add(recordData);
      debugPrint('✅ Diet record added successfully: ${data['foodName'] ?? 'Unknown food'}');
    } catch (e) {
      debugPrint('❌ Failed to add diet record: $e');
      throw Exception('Failed to add diet record: $e');
    }
  }

  /// 獲取飲食紀錄的 Stream
  Stream<QuerySnapshot> getDietRecords() {
    try {
      if (_currentUid == null) {
        debugPrint('WARN: User is not authenticated. Diet records stream is empty.');
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