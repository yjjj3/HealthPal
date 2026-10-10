import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_colors.dart';

/// 家庭成員邀請資料模型
class FamilyInvite {
  final String inviteCode;
  final String invitedBy;
  final String inviterName;
  final String relation;
  final Map<String, bool> sharedData;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String status;

  FamilyInvite({
    required this.inviteCode,
    required this.invitedBy,
    required this.inviterName,
    required this.relation,
    required this.sharedData,
    required this.createdAt,
    required this.expiresAt,
    this.status = 'pending',
  });

  Map<String, dynamic> toJson() => {
    'inviteCode': inviteCode,
    'invitedBy': invitedBy,
    'inviterName': inviterName,
    'relation': relation,
    'sharedData': sharedData,
    'createdAt': createdAt,
    'expiresAt': expiresAt,
    'status': status,
  };
}

class AddMemberScreen extends StatefulWidget {
  const AddMemberScreen({super.key});

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _currentUserName = '';
  String _memberRelation = '父親';
  String _customRelation = '';
  bool _isCustomRelation = false;
  String _inviteCode = '';
  bool _isLoading = true;
  bool _isGeneratingCode = false;

  // 電子郵件邀請
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // 共享資料選項
  final Map<String, bool> _sharedData = {
    '血糖數據': true,
    '血壓數據': true,
    '用藥記錄': true,
    '健康分析': true,
  };

  final List<String> _relations = [
    '父親', '母親', '兒子', '女兒', '配偶',
    '祖父', '祖母', '兄弟', '姐妹', '其他'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists && mounted) {
          setState(() {
            _currentUserName = userDoc.data()?['fullName'] ?? '用戶';
            _isLoading = false;
          });
          await _generateInviteCode();
        }
      }
    } catch (e) {
      debugPrint('載入用戶資料失敗: $e');
      if (mounted) {
        setState(() {
          _currentUserName = '用戶';
          _isLoading = false;
        });
      }
    }
  }

  /// 生成邀請碼
  Future<void> _generateInviteCode() async {
    setState(() => _isGeneratingCode = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 生成 6 位數邀請碼
      final random = Random();
      final code = List.generate(6, (_) => random.nextInt(10)).join();

      // 檢查邀請碼是否已存在
      final existing = await FirebaseFirestore.instance
          .collection('family_invites')
          .where('inviteCode', isEqualTo: code)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existing.docs.isNotEmpty) {
        // 重新生成
        await _generateInviteCode();
        return;
      }

      final finalRelation = _isCustomRelation ? _customRelation : _memberRelation;

      // 創建邀請記錄
      final invite = FamilyInvite(
        inviteCode: code,
        invitedBy: user.uid,
        inviterName: _currentUserName,
        relation: finalRelation,
        sharedData: _sharedData,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );

      await FirebaseFirestore.instance
          .collection('family_invites')
          .doc(code)
          .set(invite.toJson());

      if (mounted) {
        setState(() {
          _inviteCode = code;
          _isGeneratingCode = false;
        });
      }
    } catch (e) {
      debugPrint('生成邀請碼失敗: $e');
      if (mounted) {
        setState(() => _isGeneratingCode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成邀請碼失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 複製邀請碼
  void _copyInviteCode() {
    Clipboard.setData(ClipboardData(text: _inviteCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('邀請碼已複製到剪貼簿'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 分享邀請連結
  void _shareInviteLink() {
    final message = '''
🏠 $_currentUserName 邀請您加入家庭健康管理

邀請碼：$_inviteCode
有效期限：7 天

請在「HealthPal」App 中輸入此邀請碼完成綁定。
''';
    Share.share(message, subject: '家庭健康管理邀請');
  }

  /// 發送電子郵件邀請
  Future<void> _sendEmailInvite() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('用戶未登入');

      final email = _emailController.text.toLowerCase().trim();
      final finalRelation = _isCustomRelation ? _customRelation : _memberRelation;

      // 檢查是否已邀請過
      final existing = await FirebaseFirestore.instance
          .collection('family_invites')
          .where('invitedBy', isEqualTo: user.uid)
          .where('invitedToEmail', isEqualTo: email)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existing.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已經向 $email 發送過邀請'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // 創建邀請
      await FirebaseFirestore.instance.collection('family_invites').add({
        'invitedBy': user.uid,
        'inviterName': _currentUserName,
        'invitedToEmail': email,
        'relation': finalRelation,
        'sharedData': _sharedData,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': DateTime.now().add(const Duration(days: 7)),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已向 $email 發送邀請'),
          backgroundColor: AppColors.success,
        ),
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('發送失敗: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '邀請家庭成員',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_rounded), text: 'QR Code'),
            Tab(icon: Icon(Icons.link_rounded), text: '邀請碼'),
            Tab(icon: Icon(Icons.email_rounded), text: '電子郵件'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 關係選擇和資料權限設定（通用）
                _buildCommonSettings(),
                // Tab 內容
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildQRCodeTab(),
                      _buildInviteCodeTab(),
                      _buildEmailTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// 通用設定區塊（關係 + 權限）
  Widget _buildCommonSettings() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 邀請者資訊
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '邀請者',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      _currentUserName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // 關係選擇
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _memberRelation,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                    items: _relations.map((r) {
                      return DropdownMenuItem(value: r, child: Text(r));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _memberRelation = value!;
                        _isCustomRelation = value == '其他';
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          // 自訂關係輸入
          if (_isCustomRelation) ...[
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: '請輸入關係稱謂（如：外婆、姑姑）',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (value) => _customRelation = value,
            ),
          ],
          const SizedBox(height: 16),
          // 資料權限快速設定
          Row(
            children: [
              const Text(
                '共享資料：',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  children: _sharedData.entries.map((e) {
                    return FilterChip(
                      label: Text(
                        e.key.replaceAll('數據', '').replaceAll('記錄', ''),
                        style: TextStyle(
                          fontSize: 12,
                          color: e.value ? AppColors.primary : Colors.grey,
                        ),
                      ),
                      selected: e.value,
                      onSelected: (selected) {
                        setState(() => _sharedData[e.key] = selected);
                      },
                      selectedColor: AppColors.primaryLight,
                      checkmarkColor: AppColors.primary,
                      backgroundColor: Colors.grey.shade100,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// QR Code Tab
  Widget _buildQRCodeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // QR Code 卡片
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // QR Code
                if (_isGeneratingCode)
                  const SizedBox(
                    width: 200,
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  QrImageView(
                    data: 'healthapp://invite/$_inviteCode',
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppColors.primary,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black87,
                    ),
                  ),
                const SizedBox(height: 20),
                // 邀請碼顯示
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _inviteCode,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _copyInviteCode,
                        icon: const Icon(Icons.copy_rounded),
                        color: AppColors.primary,
                        tooltip: '複製',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '邀請碼有效期限：7 天',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 說明
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '讓家人使用「HealthPal」App 掃描此 QR Code，或輸入邀請碼即可完成綁定',
                    style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 分享按鈕
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _shareInviteLink,
              icon: const Icon(Icons.share_rounded),
              label: const Text('分享邀請'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 重新生成
          TextButton.icon(
            onPressed: _isGeneratingCode ? null : _generateInviteCode,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('重新生成邀請碼'),
          ),
        ],
      ),
    );
  }

  /// 邀請碼 Tab
  Widget _buildInviteCodeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          // 大型邀請碼顯示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.vpn_key_rounded,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  '您的邀請碼',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 12),
                if (_isGeneratingCode)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  Text(
                    _inviteCode,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 12,
                      color: Colors.white,
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _copyInviteCode,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('複製'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _shareInviteLink,
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('分享'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // 使用說明
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '如何使用邀請碼？',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildStep('1', '將邀請碼分享給家人'),
                _buildStep('2', '家人開啟「HealthPal」App'),
                _buildStep('3', '在「家人綁定」頁面輸入邀請碼'),
                _buildStep('4', '完成綁定，開始共享健康資料'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 重新生成
          TextButton.icon(
            onPressed: _isGeneratingCode ? null : _generateInviteCode,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('重新生成邀請碼'),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  /// 電子郵件 Tab
  Widget _buildEmailTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // 說明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.email_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '透過電子郵件邀請',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '輸入家人的電子郵件，對方會收到邀請通知',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 電子郵件輸入
            const Text(
              '家人的電子郵件',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'example@email.com',
                prefixIcon: const Icon(Icons.email_outlined),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '請輸入電子郵件';
                }
                if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(value)) {
                  return '請輸入有效的電子郵件格式';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            // 發送按鈕
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _sendEmailInvite,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_isLoading ? '發送中...' : '發送邀請'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 注意事項
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: Colors.orange.shade700,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '對方需要使用相同的電子郵件註冊「HealthPal」App，才能收到邀請通知',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
