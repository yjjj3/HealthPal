import '../utils/data_error_message.dart';
import '../widgets/data_error_view.dart';
import 'dart:async';
import 'dart:io' show File; // 只保留 File
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 新增: 導入 kIsWeb 來判斷是否為 Web 環境
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_profile_screen.dart';
import 'health_record_screen.dart';
import 'family_link_screen.dart';
import 'notification_setting_screen.dart';
import 'privacy_security_screen.dart';
import 'about_app_screen.dart';
import 'meal_time_settings_screen.dart';
import 'login_screen.dart';
import 'health_sync_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';
import 'dart:typed_data'; // 導入 Uint8List 所需
import '../theme/app_colors.dart';

// =================================================================
// 1. UserProfile Data Model (已修改：新增 fromFirestore 靜態方法)
// =================================================================
class UserProfile {
  String name;
  String gender;
  DateTime? dateOfBirth;
  String phoneNumber;
  String chronicDisease; // 保留作為顯示用的逗號分隔字串
  List<String> chronicDiseaseList; // 新增：慢性病列表
  String allergies; // 新增：過敏史
  String height;
  String weight;
  String bloodType;
  String? profileImagePath;

  UserProfile({
    required this.name,
    this.gender = '未設定',
    this.dateOfBirth,
    this.phoneNumber = '',
    this.chronicDisease = '未設定',
    List<String>? chronicDiseaseList,
    this.allergies = '無',
    this.height = '未設定',
    this.weight = '75 公斤',
    this.bloodType = '未設定',
    this.profileImagePath,
  }) : chronicDiseaseList = chronicDiseaseList ?? [];
  
  // 複製構造函數，用於在 EditProfileScreen 中建立副本
  UserProfile copyWith({
    String? name,
    String? gender,
    DateTime? dateOfBirth,
    String? phoneNumber,
    String? chronicDisease,
    List<String>? chronicDiseaseList,
    String? allergies,
    String? height,
    String? weight,
    String? bloodType,
    String? profileImagePath,
  }) {
    return UserProfile(
      name: name ?? this.name,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      chronicDisease: chronicDisease ?? this.chronicDisease,
      chronicDiseaseList: chronicDiseaseList ?? this.chronicDiseaseList,
      allergies: allergies ?? this.allergies,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      bloodType: bloodType ?? this.bloodType,
      profileImagePath: profileImagePath ?? this.profileImagePath,
    );
  }
  
  // =================================================================
  // 新增：從 Firestore DocumentSnapshot 建立 UserProfile 物件
  // =================================================================
  static UserProfile fromFirestore(DocumentSnapshot doc) {
    // 強制轉換為 Map<String, dynamic>
    final data = doc.data() as Map<String, dynamic>? ?? {}; 
    
    // 處理日期：從 Timestamp 或 String 轉換為 DateTime
    DateTime? dob;
    final dobData = data['dateOfBirth'];
    if (dobData is Timestamp) {
      dob = dobData.toDate();
    } else if (dobData is String && dobData.isNotEmpty) {
      try {
        dob = DateTime.parse(dobData);
      } catch (e) {
        dob = null;
      }
    } 
    
    // 處理慢性病：將 List 轉換為單一字串和列表
    String chronicDisease = '未設定';
    List<String> chronicDiseaseList = [];
    final diseases = data['chronicDiseases'];
    if (diseases is List && diseases.isNotEmpty) {
      chronicDiseaseList = diseases.cast<String>().toList();
      // 將列表中的所有慢性病以「、」連接
      chronicDisease = chronicDiseaseList.join('、');
    } else if (diseases is String && diseases.isNotEmpty) {
      chronicDisease = diseases;
      chronicDiseaseList = [diseases];
    }

    // 處理過敏史
    String allergies = '無';
    final allergiesData = data['allergies'];
    if (allergiesData is String && allergiesData.isNotEmpty) {
      allergies = allergiesData;
    } else if (allergiesData is List && allergiesData.isNotEmpty) {
      allergies = allergiesData.cast<String>().join('、');
    }

    // 處理身高、體重、血型：確保有單位
    String height = data['height'] != null ? '${(data['height'] as num).toInt()} 公分' : '未設定';
    String weight = data['weight'] != null ? '${data['weight']} 公斤' : '未設定';
    // 血型可能已經包含「型」字，避免重複添加
    String bloodType = '未設定';
    if (data['bloodType'] != null) {
      final bloodTypeStr = data['bloodType'].toString();
      bloodType = bloodTypeStr.contains('型') ? bloodTypeStr : '$bloodTypeStr 型';
    }

    // 轉換並回傳 UserProfile
    return UserProfile(
      // 截圖中的欄位是 'fullName'
      name: data['fullName'] ?? '未命名使用者',
      gender: data['gender'] ?? '未設定',
      dateOfBirth: dob,
      // 假設手機號碼在 Firestore 欄位為 'phoneNumber' (如果沒有，留空)
      phoneNumber: data['phoneNumber'] ?? '',
      chronicDisease: chronicDisease,
      chronicDiseaseList: chronicDiseaseList,
      allergies: allergies,
      height: height,
      weight: weight,
      bloodType: bloodType,
      profileImagePath: null,
    );
  }
}

// =================================================================
// 家庭成員模型
// =================================================================
class FamilyMember {
  String name;
  String relation;
  String userId;
  String email;
  bool isOnline;
  Map<String, bool> sharedData;
  DateTime? joinedAt;

  FamilyMember({
    required this.name,
    required this.relation,
    required this.userId,
    required this.email,
    this.isOnline = false,
    Map<String, bool>? sharedData,
    this.joinedAt,
  }) : sharedData = sharedData ?? {
    '血糖': true,
    '血壓': true,
    '用藥': true,
  };

  factory FamilyMember.fromFirestore(Map<String, dynamic> data) {
    return FamilyMember(
      name: data['name'] ?? '家庭成員',
      relation: data['relation'] ?? '家人',
      userId: data['userId'] ?? '',
      email: data['email'] ?? '',
      isOnline: data['isOnline'] ?? false,
      sharedData: Map<String, bool>.from(data['sharedData'] ?? {}),
      joinedAt: data['joinedAt'] != null 
          ? (data['joinedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

// =================================================================
// 2. ProfileScreen Widget
// =================================================================
class ProfileScreen extends StatefulWidget {
  final UserProfile userProfile; 

  const ProfileScreen({Key? key, required this.userProfile}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late UserProfile _user;
  Uint8List? _profileImageBytes;
  final ImagePicker _picker = ImagePicker();

  // 新增：家庭成員列表
  List<FamilyMember> _familyMembers = [];
  bool _isLoadingFamily = true;

  // 新增：從健康記錄獲取的最新體重
  String? _latestWeightFromRecords;
  String? _weightError;

  // 即時監聽的訂閱，需在 dispose() 時取消，避免每次切換分頁都多洩漏一組監聽器
  StreamSubscription<QuerySnapshot>? _healthRecordsSubscription;

  @override
  void initState() {
    super.initState();
    _user = widget.userProfile;
    _loadFamilyMembers(); // 載入家庭成員
    _setupHealthRecordsListener(); // 監聽健康記錄以獲取最新體重
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _user = widget.userProfile;
  }

  @override
  void dispose() {
    _healthRecordsSubscription?.cancel();
    super.dispose();
  }

  // 新增：監聽健康記錄中的最新體重
  void _setupHealthRecordsListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _healthRecordsSubscription?.cancel();
    _healthRecordsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('health_records')
        .where('category', isEqualTo: '體重')
        .orderBy('record_time', descending: true).limit(1)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        // 找出最新的體重記錄
        String? latestWeight;
        DateTime? latestTime;

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final category = data['category'] as String?;

          if (category == '體重') {
            DateTime? recordTime;
            if (data['record_time'] is Timestamp) {
              recordTime = (data['record_time'] as Timestamp).toDate();
            }

            if (latestTime == null || (recordTime != null && recordTime.isAfter(latestTime))) {
              latestTime = recordTime;
              final valueStr = data['value']?.toString() ?? '';
              // 解析 "65 kg" 格式
              final match = RegExp(r'([\d.]+)').firstMatch(valueStr);
              if (match != null) {
                latestWeight = '${match.group(1)} 公斤';
              }
            }
          }
        }

        if (_weightError != null || latestWeight != _latestWeightFromRecords) {
          setState(() {
            _latestWeightFromRecords = latestWeight;
            _weightError = null;
          });
        }
      }
    }, onError: (Object error) { if (mounted) setState(() { _weightError = dataErrorMessage(error); _latestWeightFromRecords = null; }); });
  }

  // 新增：獲取顯示用的體重（優先使用健康記錄的體重）
  String get _displayWeight {
    return _latestWeightFromRecords ?? _user.weight;
  }

  // 載入家庭成員
  Future<void> _loadFamilyMembers() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final familyQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('family_members')
          .get();

      final members = familyQuery.docs.map((doc) {
        return FamilyMember.fromFirestore(doc.data());
      }).toList();

      if (mounted) {
        setState(() {
          _familyMembers = members;
          _isLoadingFamily = false;
        });
      }
    } catch (e) {
      debugPrint('載入家庭成員失敗: $e');
      if (mounted) {
        setState(() {
          _isLoadingFamily = false;
        });
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (!mounted) return;
    
    if (mounted) Navigator.of(context).pop(); 
    
    if (image != null) {
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;
        setState(() {
          _profileImageBytes = bytes;
          _user.profileImagePath = null; 
        });
      } else {
        setState(() {
          _user.profileImagePath = image.path;
          _profileImageBytes = null;
        });
      }
    }
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('圖庫中選擇照片'),
                onTap: () => _pickImage(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('拍攝照片'),
                onTap: () => _pickImage(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );
  }

  // 導航到編輯頁面
  void _navigateToEditProfile() async {
    // 建立一個包含最新體重的 UserProfile 副本
    final userWithLatestWeight = _latestWeightFromRecords != null
        ? _user.copyWith(weight: _latestWeightFromRecords)
        : _user;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final updatedUser = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(initialUser: userWithLatestWeight),
      ),
    );

    if (!mounted || uid != FirebaseAuth.instance.currentUser?.uid) return;
    if (updatedUser != null && updatedUser is UserProfile) {
      // 儲存更新後的資料到 Firestore
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
            'fullName': updatedUser.name,
            'gender': updatedUser.gender,
            'dateOfBirth': updatedUser.dateOfBirth?.toIso8601String(),
            'phoneNumber': updatedUser.phoneNumber,
            'height': double.tryParse(updatedUser.height.replaceAll(' 公分', '').trim()),
            'weight': double.tryParse(updatedUser.weight.replaceAll(' 公斤', '').trim()),
            'bloodType': updatedUser.bloodType.replaceAll(' 型', '').trim(),
            'chronicDiseases': updatedUser.chronicDiseaseList,
            'allergies': updatedUser.allergies,
          });
        }
      } catch (e) {
        debugPrint('儲存個人資料失敗: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('儲存失敗，請稍後再試')),
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _user = updatedUser;
          debugPrint('慢性病列表已更新: ${updatedUser.chronicDiseaseList}');
          debugPrint('慢性病字串已更新: ${updatedUser.chronicDisease}');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('個人資料已同步更新！')),
        );
      }
    }
  }
  
  void _navigateToHealthRecord() {
     Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const HealthRecordScreen()),
    );
  }

  // 導航到家人關係綁定頁面
  void _navigateToFamilyLink() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const FamilyLinkScreen()),
    );
    // 返回時重新載入家庭成員
    if (mounted) _loadFamilyMembers();
  }
  
  void _handleLogout() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('確認登出'),
          content: const Text('您確定要登出帳號嗎？'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('登出', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(dialogContext).pop(); 
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                  (Route<dynamic> route) => false, 
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _getProfileImageWidget() {
    if (_profileImageBytes != null) {
      return ClipOval(
        child: Image.memory(
          _profileImageBytes!,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
        ),
      );
    }
    
    if (_user.profileImagePath != null && !kIsWeb) {
      try {
        return ClipOval(
          child: Image.file(
            File(_user.profileImagePath!),
            width: 100,
            height: 100,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Error loading image file: $error');
              return const Icon(Icons.person, size: 60, color: Colors.white);
            },
          ),
        );
      } catch (e) {
        debugPrint('Error creating File object: $e');
      }
    }

    return const Icon(Icons.person, size: 60, color: Colors.white);
  }
  
  Widget _buildProfileImage() {
    return GestureDetector(
      onTap: () => _showImageSourceActionSheet(context),
      child: Stack(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _getProfileImageWidget(), 
          ),
          const Positioned(
            bottom: 0,
            right: 0,
            child: SizedBox(
              width: 30,
              height: 30,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _calculateAge(DateTime? dob) {
    if (dob == null) return 0;
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  // 構建家庭成員卡片
  Widget _buildFamilyMemberCard(FamilyMember member) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary,
            child: Text(
              member.name[0],
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  member.relation,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: member.isOnline ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  // 構建家庭成員區塊
  Widget _buildFamilySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '家庭成員 (${_familyMembers.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              GestureDetector(
                onTap: _navigateToFamilyLink,
                child: Text(
                  '管理',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
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
          child: _isLoadingFamily
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _familyMembers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            Icons.family_restroom_rounded,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '尚未添加家庭成員',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _navigateToFamilyLink,
                            child: const Text('立即添加'),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: _familyMembers
                            .map((member) => _buildFamilyMemberCard(member))
                            .toList(),
                      ),
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _weightError != null ? DataErrorView(message: _weightError!, onRetry: _setupHealthRecordsListener) : SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildProfileImage(), 
              const SizedBox(height: 15),
              Text(
                _user.name, 
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${_calculateAge(_user.dateOfBirth)} 歲',
                style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
              ),
              
              const SizedBox(height: 20),
              _buildUserInfoCard(),

              const SizedBox(height: 15),

              // --- 新增：慢性病與過敏史卡片 ---
              _buildHealthInfoCard(),

              const SizedBox(height: 30),

              // --- 新增：家庭成員區塊 ---
              _buildFamilySection(),

              const SizedBox(height: 30),

              // --- 區塊 1: 個人資料 ---
              _buildSettingSection('個人資料', [
                _buildSettingItem(Icons.edit_rounded, '編輯個人資料', _navigateToEditProfile),
                _buildSettingItem(
                  Icons.health_and_safety_rounded,
                  '健康檔案',
                  _navigateToHealthRecord,
                ),
                _buildSettingItem(
                  Icons.sync_rounded,
                  '健康平台同步',
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const HealthSyncScreen()),
                    );
                  },
                  isLast: true,
                ),
              ]),

              // --- 區塊 2: 帳號與設定 ---
              _buildSettingSection('帳號與設定', [
                _buildSettingItem(
                  Icons.family_restroom_rounded,
                  '家人關係綁定',
                  _navigateToFamilyLink,
                ),
                _buildSettingItem(
                  Icons.notifications_active_rounded,
                  '通知設定',
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const NotificationSettingScreen()),
                    );
                  }
                ),
                _buildSettingItem(
                  Icons.restaurant_rounded,
                  '用餐時間設定',
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const MealTimeSettingsScreen()),
                    );
                  }
                ),
                _buildSettingItem(
                  Icons.manage_accounts_rounded,
                  '帳號設定',
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const PrivacySecurityScreen()),
                    );
                  }
                ),
                _buildSettingItem(
                  Icons.info_rounded,
                  '關於本應用程式',
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const AboutAppScreen()),
                    );
                  }
                ),
                _buildSettingItem(
                  Icons.logout_rounded,
                  '登出',
                  _handleLogout,
                  isDestructive: true,
                ),
              ]),

              // --- 區塊 3: 法律資訊 ---
              _buildSettingSection('法律資訊', [
                _buildSettingItem(
                  Icons.privacy_tip_rounded,
                  '隱私權政策',
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
                    );
                  },
                ),
                _buildSettingItem(
                  Icons.description_rounded,
                  '服務條款',
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const TermsOfServiceScreen()),
                    );
                  },
                  isLast: true,
                ),
              ]),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildUserInfoCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 20),
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
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(child: _buildInfoItem('身高', _user.height)),
            _buildDivider(),
            Expanded(child: _buildInfoItem('體重', _displayWeight)),
            _buildDivider(),
            Expanded(child: _buildInfoItem('血型', _user.bloodType)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    final parts = value.split(' ');
    final displayValue = parts[0];
    final displayUnit = parts.length > 1 ? parts[1] : '';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
           mainAxisAlignment: MainAxisAlignment.center,
           crossAxisAlignment: CrossAxisAlignment.end,
           children: [
             Text(
               displayValue,
               style: const TextStyle(
                 fontSize: 18,
                 fontWeight: FontWeight.bold,
                 color: AppColors.primary,
               ),
             ),
             if (displayUnit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 2.0, bottom: 1.0),
                  child: Text(
                    displayUnit,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
           ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // 新增：慢性病與過敏史卡片
  Widget _buildHealthInfoCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
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
          _user.chronicDiseaseList.isEmpty
              ? const Text(
                  '無',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textHint,
                  ),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _user.chronicDiseaseList.map((disease) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            _user.allergies,
            style: TextStyle(
              fontSize: 15,
              color: _user.allergies == '無'
                  ? AppColors.textHint
                  : AppColors.warning,
              fontWeight: _user.allergies == '無'
                  ? FontWeight.normal
                  : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 35,
      color: AppColors.border,
    );
  }

  Widget _buildSettingSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
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
          child: Column(children: items),
        ),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _buildSettingItem(
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isDestructive = false,
    bool isLast = false,
  }) {
    BorderRadius? borderRadius;
    if (isLast) {
      borderRadius = const BorderRadius.only(
        bottomLeft: Radius.circular(16),
        bottomRight: Radius.circular(16),
      );
    } 
    
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius,
          border: Border(
            bottom: BorderSide(
              color: isLast ? Colors.transparent : AppColors.border,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive
                  ? AppColors.error
                  : AppColors.primary,
              size: 24,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  color: isDestructive ? AppColors.error : Colors.black87,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}