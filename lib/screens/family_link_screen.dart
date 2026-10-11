import '../utils/account_page_session.dart';
import '../services/family_profile_service.dart';
import '../widgets/family_share_settings.dart';
import '../services/family_relationship_service.dart';
import 'dart:async';
import '../theme/app_colors.dart';
// lib/screens/family_link_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// 引入新增成員頁面和聊天室
import 'add_member_screen.dart'; 
import 'chat_room_screen.dart'; 

// FamilyMember class 定義
class FamilyMember {
  final String? inviteId;
  String name;
  String relation;
  String emailOrPhone;
  bool isOnline;
  String? avatarUrl; 
  String userId; // 新增：用戶ID
  String email; // 新增：email
  
  // 記錄該成員可以查看的資料清單
  Map<String, bool> sharedData; 

  FamilyMember({
    this.inviteId,
    required this.name,
    required this.relation,
    required this.emailOrPhone,
    this.isOnline = false,
    this.avatarUrl, 
    required this.userId, // 新增
    required this.email, // 新增
    Map<String, bool>? sharedData,
  }) : sharedData = sharedData ?? {
    '用藥': false,
    '血糖': false,
    '血壓': false,
  };

  // 從 Firestore 資料建立 FamilyMember
  factory FamilyMember.fromFirestore(Map<String, dynamic> data) {
    return FamilyMember(
      inviteId: data['inviteId'] is String ? data['inviteId'] : null,
      name: data['name'] ?? '家庭成員',
      relation: data['relation'] ?? '家人',
      emailOrPhone: '',
      isOnline: data['isOnline'] ?? false,
      userId: data['userId'] ?? '',
      email: '',
      sharedData: FamilyProfileService.choices(data['sharedData'], FamilyProfileService.recordFields.keys),
    );
  }
}

class FamilyLinkScreen extends StatefulWidget {
  const FamilyLinkScreen({super.key});

  @override
  State<FamilyLinkScreen> createState() => _FamilyLinkScreenState();
}

class _PendingInvite {
  final String docId;
  final String invitedBy;
  final String inviterName;
  final String relation;
  final Map<String, bool> sharedData;
  final String? inviteCode;

  _PendingInvite({
    required this.docId,
    required this.invitedBy,
    required this.inviterName,
    required this.relation,
    required this.sharedData,
    this.inviteCode,
  });

  factory _PendingInvite.fromFirestore(String docId, Map<String, dynamic> data) {
    return _PendingInvite(
      docId: docId,
      invitedBy: data['invitedBy'] ?? '',
      inviterName: data['inviterName'] ?? '家人',
      relation: data['relation'] ?? '家人',
      sharedData: FamilyProfileService.choices(data['sharedData'], FamilyProfileService.recordFields.keys),
      inviteCode: data['inviteCode'],
    );
  }
}

class _FamilyLinkScreenState extends State<FamilyLinkScreen> {
  // 改為從 Firebase 載入的真實資料
  List<FamilyMember> _members = [];
  List<_PendingInvite> _pendingInvites = [];
  bool _isLoading = true;
  late final AccountPageSession _account;

  // 即時監聽的訂閱，需在 dispose() 時取消，避免每次進出此頁都多洩漏一組監聽器
  StreamSubscription<QuerySnapshot>? _familyListenerSubscription;

  @override
  void initState() {
    super.initState();
    _account = AccountPageSession(() => FirebaseAuth.instance.currentUser?.uid,
      FirebaseAuth.instance.authStateChanges().map((user) => user?.uid));
    _loadFamilyMembers();
    _loadPendingInvites();
    _setupFamilyListener();
  }

  @override
  void dispose() {
    _account.dispose();
    _familyListenerSubscription?.cancel();
    super.dispose();
  }

  // 載入待處理邀請（寄給我的）
  Future<void> _loadPendingInvites() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !_account.active) return;

      final email = user.email?.toLowerCase().trim();
      if (email == null) return;

      final query = await FirebaseFirestore.instance
          .collection('family_invites')
          .where('invitedToEmail', isEqualTo: email)
          .where('status', isEqualTo: 'pending')
          .get();

      if (mounted && _account.active && user.uid == FirebaseAuth.instance.currentUser?.uid) {
        setState(() {
          _pendingInvites = query.docs.map((doc) {
            return _PendingInvite.fromFirestore(doc.id, doc.data());
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('載入待處理邀請失敗: $e');
    }
  }

  // 接受邀請
  Future<void> _acceptInvite(_PendingInvite invite) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !_account.active) return;

      await FamilyRelationshipService().acceptInvite(invite.docId);

      if (mounted && _account.active && user.uid == FirebaseAuth.instance.currentUser?.uid) {
        setState(() {
          _pendingInvites.removeWhere((i) => i.docId == invite.docId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已接受 ${invite.inviterName} 的邀請！'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadFamilyMembers();
      }
    } catch (e) {
      debugPrint('接受邀請失敗: $e');
      if (mounted && _account.active) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('接受邀請失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 拒絕邀請
  Future<void> _declineInvite(_PendingInvite invite) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !_account.active) return;
    try {
      await FamilyRelationshipService().declineInvite(invite.docId);

      if (mounted && _account.active && user.uid == FirebaseAuth.instance.currentUser?.uid) {
        setState(() {
          _pendingInvites.removeWhere((i) => i.docId == invite.docId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已拒絕邀請')),
        );
      }
    } catch (e) {
      debugPrint('拒絕邀請失敗: $e');
    }
  }

  // 顯示輸入邀請碼對話框
  void _showEnterCodeDialog() {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        bool isProcessing = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('輸入邀請碼'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '請輸入對方分享給您的 6 位數邀請碼',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '000000',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        letterSpacing: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: isProcessing
                      ? null
                      : () async {
                          final code = codeController.text.trim();
                          if (code.length != 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('請輸入 6 位數邀請碼')),
                            );
                            return;
                          }
                          setDialogState(() => isProcessing = true);
                          final success = await _acceptByCode(code);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (!success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('邀請碼無效或已過期'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('確認綁定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 透過邀請碼接受邀請
  Future<bool> _acceptByCode(String code) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !_account.active) return false;

      await FamilyRelationshipService().acceptInvite(code);

      if (mounted && _account.active) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功完成家庭綁定！'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadFamilyMembers();
      }
      return true;
    } catch (e) {
      debugPrint('透過邀請碼接受邀請失敗: $e');
      return false;
    }
  }

  // 載入家庭成員
  Future<void> _loadFamilyMembers() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !_account.active) return;

      final familyQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('family_members')
          .get();

      final members = familyQuery.docs.map((doc) {
        return FamilyMember.fromFirestore(doc.data());
      }).toList();

      if (mounted && _account.active && user.uid == FirebaseAuth.instance.currentUser?.uid) {
        setState(() {
          _members = members;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('載入家庭成員失敗: $e');
      if (mounted && _account.active) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 設定即時監聽家庭成員變化
  void _setupFamilyListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !_account.active) return;

    _familyListenerSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('family_members')
        .snapshots()
        .listen((snapshot) {
      if (mounted && _account.active && user.uid == FirebaseAuth.instance.currentUser?.uid) {
        setState(() {
          _members = snapshot.docs.map((doc) {
            return FamilyMember.fromFirestore(doc.data());
          }).toList();
        });
      }
    });
  }

  // 導航到新增成員頁面
  void _navigateToAddMember() async {
    final newMember = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const AddMemberScreen()),
    );

    if (mounted && _account.active && newMember != null && newMember is FamilyMember) {
      setState(() {
        _members.add(newMember);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已向 ${newMember.name} 發出綁定邀請！')),
      );
    }
  }
  
  void _showShareSettings(FamilyMember member) {
    showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      builder: (_) => FamilyShareSettings(viewer: member.userId,
        service: FamilyProfileService()),
    );
  }

  // 移除家庭成員
  Future<void> _removeFamilyMember(FamilyMember member) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !_account.active) return;

      // 顯示確認對話框
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('移除家庭成員'),
            content: Text('確定要移除 ${member.name} 嗎？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('移除', style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        },
      );

      if (confirmed == true && mounted && _account.active && user.uid == FirebaseAuth.instance.currentUser?.uid) {
        await FamilyProfileService().removeMember(member.userId, expectedInviteId: member.inviteId);
        if (!mounted || !_account.active) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移除 ${member.name}')),
        );
      }
    } catch (e) {
      print('移除家庭成員失敗: $e');
      if (!mounted || !_account.active) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移除失敗: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('家人關係綁定',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        elevation: 1,
        actions: [
          // 輸入邀請碼按鈕
          TextButton.icon(
            onPressed: _showEnterCodeDialog,
            icon: const Icon(Icons.vpn_key_rounded, size: 18),
            label: const Text('輸入邀請碼'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, size: 28),
            onPressed: _navigateToAddMember,
            tooltip: '新增家庭成員',
          ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadFamilyMembers();
                await _loadPendingInvites();
              },
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // 待處理邀請區塊
                  if (_pendingInvites.isNotEmpty) ...[
                    _buildPendingInvitesSection(),
                    const SizedBox(height: 16),
                  ],
                  // 家庭成員列表
                  if (_members.isEmpty && _pendingInvites.isEmpty)
                    _buildEmptyState()
                  else
                    ..._members.map((member) => _buildMemberCard(member)),
                  if (_members.isEmpty && _pendingInvites.isNotEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: Column(
                          children: [
                            Icon(Icons.family_restroom_rounded, size: 60, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            const Text('尚未綁定任何家庭成員',
                                style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  // 待處理邀請區塊
  Widget _buildPendingInvitesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.notifications_active_rounded, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Text(
              '待處理的邀請（${_pendingInvites.length}）',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._pendingInvites.map((invite) => _buildInviteCard(invite)),
      ],
    );
  }

  Widget _buildInviteCard(_PendingInvite invite) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(
                child: Text(
                  invite.inviterName.isNotEmpty ? invite.inviterName[0] : '?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${invite.inviterName} 邀請您綁定',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    '關係：${invite.relation}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success),
                  tooltip: '接受',
                  onPressed: () => _acceptInvite(invite),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  tooltip: '拒絕',
                  onPressed: () => _declineInvite(invite),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helper: 空狀態介面
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.family_restroom_rounded, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 20),
          const Text('尚未綁定任何家庭成員', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          const Text('點擊右上角 "+" 邀請家人加入。', style: TextStyle(fontSize: 14, color: AppColors.textHint)),
        ],
      ),
    );
  }

  // Helper: 構建頭像 Widget
  Widget _buildAvatarWidget(FamilyMember member) {
    // 檢查是否為 AI 助理，提供特殊圖標
    if (member.name == 'AI 健康助理') {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(25),
        ),
        child: const Icon(Icons.psychology_alt_rounded, color: Colors.white, size: 25),
      );
    }

    // 構建 CircleAvatar
    return CircleAvatar(
      radius: 20, 
      backgroundColor: AppColors.primary.withOpacity(0.8),
      
      // 如果有圖片 URL，使用 NetworkImage
      backgroundImage: (member.avatarUrl != null && member.avatarUrl!.isNotEmpty)
          ? NetworkImage(member.avatarUrl!) as ImageProvider<Object>?
          : null,
      
      // 如果沒有圖片 URL，顯示名字的第一個字
      child: (member.avatarUrl == null || member.avatarUrl!.isEmpty) 
          ? Text(
              member.name[0],
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            )
          : null,
    );
  }

  // Helper: 成員卡片
  Widget _buildMemberCard(FamilyMember member) {
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 頭像/狀態 (成員是否上線中)
            Stack(
              children: [
                _buildAvatarWidget(member),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: member.isOnline ? Colors.greenAccent[400] : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 15),
            
            // 資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    member.relation,
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 5),
                  // 資料分享狀態提示
                  Text(
                    '共享數據: ${member.sharedData.values.where((v) => v).length} 項',
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey[400]),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    member.email,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),

            // 操作按鈕區塊
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 資料分享按鈕
                IconButton(
                  icon: const Icon(Icons.settings_suggest_rounded, color: AppColors.primary),
                  tooltip: '設定資料分享',
                  onPressed: () => _showShareSettings(member),
                ),
                // 2. 聊天按鈕
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF7ED321)),
                  tooltip: '開啟聊天室',
                  onPressed: () {
                    final chatId = '${FirebaseAuth.instance.currentUser?.uid}_${member.userId}';
                    
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ChatRoomScreen(
                          chatId: chatId,
                          name: member.name, 
                          isOnline: member.isOnline, 
                          avatar: _buildAvatarWidget(member), 
                          otherUserId: member.userId,
                        ),
                      ),
                    );
                  },
                ),
                // 3. 移除按鈕
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  tooltip: '移除成員',
                  onPressed: () => _removeFamilyMember(member),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}