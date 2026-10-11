import 'dart:async';
import '../services/family_profile_service.dart';
import '../utils/account_page_session.dart';
import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// 家庭成員健康資料查看頁面
/// 用於查看家人分享的健康資訊（慢性病、過敏史、健康記錄等）
class FamilyHealthScreen extends StatefulWidget {
  final String userId; // 要查看的家庭成員的 userId
  final FirebaseFirestore? firestore;
  final String? Function()? currentUid;
  final Stream<String?>? accountChanges;

  const FamilyHealthScreen({
    super.key,
    required this.userId,
    this.firestore, this.currentUid, this.accountChanges,
  });

  @override
  State<FamilyHealthScreen> createState() => _FamilyHealthScreenState();
}

class _FamilyHealthScreenState extends State<FamilyHealthScreen> {
  late final FirebaseFirestore _firestore = widget.firestore ?? FirebaseFirestore.instance;
  late final String? Function() _uid = widget.currentUid ??
      (() => FirebaseAuth.instance.currentUser?.uid);
  late final AccountPageSession _account;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _relationSubscription;
  Map<String, dynamic>? _userData;
  Map<String, bool>? _sharedData;
  Map<String, dynamic> _projection = {};
  bool _related = false;
  String? _inviteId;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _account = AccountPageSession(_uid, widget.accountChanges ??
      FirebaseAuth.instance.authStateChanges().map((user) => user?.uid));
    _account.addListener(_accountChanged);
    final viewer = _account.ownerUid;
    if (viewer == null) { _isLoading = false; _errorMessage = '您尚未登入'; return; }
    // Observe our own relationship, not the owner's private relationship metadata.
    _relationSubscription = _firestore.collection('users').doc(viewer)
      .collection('family_members').doc(widget.userId)
      .snapshots(includeMetadataChanges: true).listen((doc) {
        if (!mounted || !_account.active) return;
        _related = doc.exists && !doc.metadata.isFromCache;
        _inviteId = doc.data()?['inviteId'] as String?;
        _applyProjection();
      }, onError: (Object _) => _clear('無法確認家庭關係，請連線重試。'));
    _profileSubscription = _firestore.collection('users').doc(widget.userId)
      .collection('shared_profile').doc(viewer)
      .snapshots(includeMetadataChanges: true).listen((doc) {
        if (!mounted || !_account.active) return;
        _projection = !doc.metadata.isFromCache && doc.data()?['version'] == 1
            ? doc.data()! : {};
        _applyProjection();
      }, onError: (Object _) => _clear('資料未分享、已撤回或無法確認權限。'));
  }

  void _applyProjection() {
    if (!mounted || !_account.active) return;
    final currentGrant = _related && _inviteId != null && _projection['inviteId'] == _inviteId;
    final consent = FamilyProfileService.choices(currentGrant ? _projection['consent'] : null,
      FamilyProfileService.fields.keys);
    final values = _projection['values'];
    setState(() {
      _userData = currentGrant && values is Map ? {
        for (final key in FamilyProfileService.fields.keys)
          if (consent[key] == true && values.containsKey(key)) key: values[key],
      } : {};
      _sharedData = FamilyProfileService.choices(currentGrant ? _projection['records'] : null,
        FamilyProfileService.recordFields.keys);
      _isLoading = false;
      _errorMessage = '';
    });
  }
  void _clear(String message) {
    if (!mounted) return;
    setState(() { _userData = {}; _sharedData = {}; _projection = {};
      _isLoading = false; _errorMessage = message; });
  }
  void _accountChanged() {
    _profileSubscription?.cancel(); _relationSubscription?.cancel();
    _clear('帳號已變更，請返回後重新開啟。');
  }
  @override
  void dispose() {
    _profileSubscription?.cancel(); _relationSubscription?.cancel();
    _account.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _userData?['fullName'] ?? '家庭成員健康資料',
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        elevation: 1,
      ),
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : _buildHealthData(),
    );
  }

  Widget _buildHealthData() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 基本資訊卡片
          const Text('只顯示對方選擇分享的資料；個人資料為儲存分享時的副本。'),
          _buildBasicInfoCard(),
          const SizedBox(height: 16),

          // 健康資訊卡片（慢性病、過敏史）
          _buildHealthInfoCard(),
          const SizedBox(height: 16),

          // 健康記錄區塊（如果有分享權限）
          if (_sharedData != null && _hasAnyHealthDataShared())
            _buildHealthRecordsSection(),
        ],
      ),
    );
  }

  /// 基本資訊卡片
  Widget _buildBasicInfoCard() {
    final dateOfBirth = _userData?['dateOfBirth'];
    int age = 0;
    if (dateOfBirth != null) {
      try {
        final dob = dateOfBirth is Timestamp
            ? dateOfBirth.toDate()
            : DateTime.parse(dateOfBirth.toString());
        final now = DateTime.now();
        age = now.year - dob.year;
        if (now.month < dob.month ||
            (now.month == dob.month && now.day < dob.day)) {
          age--;
        }
      } catch (e) {
        age = 0;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                '基本資訊',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('姓名', _userData?['fullName']?.toString() ?? '未分享'),
          _buildInfoRow('電子郵件', _userData?['email']?.toString() ?? '未分享'),
          _buildInfoRow('電話', _userData?['phoneNumber']?.toString() ?? '未分享'),
          _buildInfoRow('身高', _userData?['height']?.toString() ?? '未分享'),
          _buildInfoRow('體重', _userData?['weight']?.toString() ?? '未分享'),
          _buildInfoRow('年齡', age > 0 ? '$age 歲' : '未分享'),
          _buildInfoRow('性別', _userData?['gender']?.toString() ?? '未分享'),
          _buildInfoRow('血型', _userData?['bloodType']?.toString() ?? '未分享'),
        ],
      ),
    );
  }

  /// 健康資訊卡片（慢性病、過敏史）
  Widget _buildHealthInfoCard() {
    final chronicDiseases = _userData?['chronicDiseases'];
    final allergies = _userData?['allergies'];

    List<String> chronicDiseaseList = [];
    if (chronicDiseases is List && chronicDiseases.isNotEmpty) {
      chronicDiseaseList = chronicDiseases.whereType<String>().toList();
    } else if (chronicDiseases is String && chronicDiseases.isNotEmpty) {
      chronicDiseaseList = [chronicDiseases];
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 慢性病史
          Row(
            children: [
              const Icon(
                Icons.medical_information,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                '慢性病史',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          chronicDiseaseList.isEmpty
              ? Text(
                  _userData?.containsKey('chronicDiseases') == true ? '無' : '未分享',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textHint,
                  ),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: chronicDiseaseList.map((disease) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        disease,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),
          // 過敏史
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                '過敏史',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            allergies?.toString() ?? '未分享',
            style: TextStyle(
              fontSize: 15,
              color: (allergies?.toString() ?? '未分享') == '無'
                  ? AppColors.textHint
                  : AppColors.warning,
              fontWeight: (allergies?.toString() ?? '未分享') == '無'
                  ? FontWeight.normal
                  : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 健康記錄區塊
  Widget _buildHealthRecordsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '共享健康記錄',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        if (_canView('血糖', '血糖數據')) _buildHealthRecordStream('血糖', Icons.water_drop, 'bloodSugar'),
        if (_canView('血壓', '血壓數據')) _buildHealthRecordStream('血壓', Icons.favorite, 'bloodPressure'),
        if (_canView('用藥', '用藥記錄') || _sharedData?['用藥數據'] == true) _buildMedicationList(),
      ],
    );
  }

  bool _canView(String key, String legacyKey) =>
      _sharedData?[key] == true || _sharedData?[legacyKey] == true;

  /// 健康記錄卡片 - 使用 StreamBuilder 顯示實際數據
  Widget _buildHealthRecordStream(String title, IconData icon, String dataType) {
    print('📊 建立 $title StreamBuilder, 查詢路徑: users/${widget.userId}/health_records');

    // 將 dataType 轉換為 category 值
    String categoryFilter = '';
    if (dataType == 'bloodSugar') {
      categoryFilter = '血糖';
    } else if (dataType == 'bloodPressure') {
      categoryFilter = '血壓';
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('health_records')
          .where('category', isEqualTo: categoryFilter)
          .orderBy('record_time', descending: true).limit(1)
          .snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        if (!_account.active || !_related || snapshot.data?.metadata.isFromCache == true) {
          return _buildHealthRecordCard('共享資料', Icons.lock, '未分享或尚未確認權限', null);
        }
        if (snapshot.hasError) {
          return _buildHealthRecordCard(title, icon, '無法讀取，請確認分享權限', null);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          print('⏳ $title - 等待數據中...');
          return _buildHealthRecordCard(title, icon, '載入中...', null);
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          print('❌ $title - 無數據: hasData=${snapshot.hasData}, docs=${snapshot.data?.docs.length ?? 0}');
          return _buildHealthRecordCard(title, icon, '暫無記錄', null);
        }

        print('📋 $title - 查詢到總記錄數: ${snapshot.data!.docs.length}');

        // 根據 category 欄位篩選記錄
        final records = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final category = data['category'] as String?;
          print('   記錄 ${doc.id}: category=$category');
          return category == categoryFilter;
        }).toList();

        print('📋 $title - 篩選後 category=$categoryFilter 記錄數: ${records.length}');

        if (records.isEmpty) {
          print('⚠️ $title - 沒有找到符合的記錄');
          return _buildHealthRecordCard(title, icon, '暫無記錄', null);
        }

        // 根據時間戳排序，取最新一筆
        records.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['timestamp'] as Timestamp? ?? aData['record_time'] as Timestamp?;
          final bTime = bData['timestamp'] as Timestamp? ?? bData['record_time'] as Timestamp?;

          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;

          return bTime.compareTo(aTime); // 降序排列，最新的在前
        });

        final latestRecord = records.first.data() as Map<String, dynamic>;
        final value = latestRecord['value'] as String? ?? '';
        print('✅ $title - 找到最新記錄: value=$value');

        final timestamp = latestRecord['timestamp'] as Timestamp? ??
                         latestRecord['record_time'] as Timestamp?;
        final dateStr = timestamp != null
            ? DateFormat('MM/dd HH:mm').format(timestamp.toDate())
            : '未知時間';

        String valueStr = value.isNotEmpty ? value : '暫無記錄';

        return _buildHealthRecordCard(title, icon, valueStr, dateStr);
      },
    );
  }

  /// 健康記錄卡片
  Widget _buildHealthRecordCard(String title, IconData icon, String value, String? dateStr) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: value == '暫無記錄' || value == '載入中...'
                  ? Colors.grey
                  : AppColors.primary,
            ),
          ),
          if (dateStr != null) ...[
            const SizedBox(height: 4),
            Text(
              '最後記錄：$dateStr',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 用藥記錄列表
  Widget _buildMedicationList() {
    print('💊 建立用藥 StreamBuilder, 查詢路徑: users/${widget.userId}/medicine');

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('medicine')
          .snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        if (!_account.active || !_related || snapshot.data?.metadata.isFromCache == true) {
          return _buildHealthRecordCard('共享資料', Icons.lock, '未分享或尚未確認權限', null);
        }
        if (snapshot.hasError) {
          return _buildHealthRecordCard('用藥', Icons.medication, '無法讀取，請確認分享權限', null);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          print('⏳ 用藥 - 等待數據中...');
          return _buildHealthRecordCard('用藥', Icons.medication, '載入中...', null);
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          print('❌ 用藥 - 無數據: hasData=${snapshot.hasData}, docs=${snapshot.data?.docs.length ?? 0}');
          return _buildHealthRecordCard('用藥', Icons.medication, '暫無用藥記錄', null);
        }

        final medications = snapshot.data!.docs;
        print('✅ 用藥 - 找到 ${medications.length} 筆用藥記錄');
        final activeMedsCount = medications.length;

        // 計算今日用藥總進度
        int totalDoses = 0;
        int completedDoses = 0;

        for (var doc in medications) {
          final data = doc.data() as Map<String, dynamic>;
          final timesStatus = data['times_status'] as List<dynamic>?;

          if (timesStatus != null) {
            totalDoses += timesStatus.length;
            completedDoses += timesStatus.where((status) => status == true).length;
          }
        }

        final completionRate = totalDoses > 0
            ? (completedDoses / totalDoses * 100).toInt()
            : 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.medication, color: AppColors.primary, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '用藥記錄',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 今日用藥進度
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '今日進度',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$completedDoses / $totalDoses 次',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 圓形進度條
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: totalDoses > 0 ? completedDoses / totalDoses : 0,
                          strokeWidth: 6,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            completionRate == 100
                                ? Colors.green
                                : AppColors.primary,
                          ),
                        ),
                        Text(
                          '$completionRate%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: completionRate == 100
                                ? Colors.green
                                : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              Text(
                '藥物清單 ($activeMedsCount 種)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // 藥物列表
              ...medications.take(3).map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = data['name'] ?? '未命名藥品';
                final frequency = data['frequency'] ?? '每天1次';
                final dosage = data['dosage'] ?? '1';
                final unit = data['unit'] ?? '顆';
                final timesStatus = data['times_status'] as List<dynamic>?;

                // 計算這個藥的完成狀態
                int medTotal = timesStatus?.length ?? 0;
                int medCompleted = timesStatus?.where((s) => s == true).length ?? 0;
                bool isFullyTaken = medTotal > 0 && medCompleted == medTotal;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      // 完成狀態圖示
                      Icon(
                        isFullyTaken
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: isFullyTaken
                            ? Colors.green
                            : Colors.grey[400],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$frequency · $dosage$unit',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 用藥進度
                      if (medTotal > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isFullyTaken
                                ? Colors.green.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isFullyTaken
                                  ? Colors.green
                                  : Colors.orange,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '$medCompleted/$medTotal',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isFullyTaken
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),

              if (medications.length > 3) ...[
                const SizedBox(height: 4),
                Text(
                  '還有 ${medications.length - 3} 種藥物...',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 資訊列
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textHint,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 檢查是否有任何健康資料被分享
  bool _hasAnyHealthDataShared() {
    if (_sharedData == null) return false;
    return _sharedData!.values.any((shared) => shared == true);
  }
}
