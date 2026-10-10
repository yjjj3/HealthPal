import '../services/live_query_window.dart';
import '../utils/data_error_message.dart';
import '../widgets/data_error_view.dart';
import '../theme/app_colors.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'chat_room_screen.dart';
import 'ai_chat_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _chats = [];
  bool _isLoading = true;
  bool _isSearching = false;
  StreamSubscription? _chatsSubscription;
  LiveQueryWindow? _chatWindow;
  String? _chatError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _setupChatsStream();
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    _chatWindow?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _isSearching = _searchController.text.isNotEmpty;
    });
  }

  // 🎯 設定聊天串流監聽
  void _setupChatsStream() {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    // 取消舊訂閱
    _chatsSubscription?.cancel();

    _chatWindow?.dispose();
    _chatWindow = LiveQueryWindow(_firestore.collection('chats')
      .where('members', arrayContains: user.uid).orderBy('lastTime', descending: true));
    _chatsSubscription = _chatWindow!.stream.listen((snapshot) {
      if (!mounted || _auth.currentUser?.uid != user.uid) return;
      _chatError = null;
      try { _processChatsSnapshot(snapshot, user.uid); }
      catch (error) { setState(() { _isLoading = false; _chatError = dataErrorMessage(error); }); }
    }, onError: (Object error) {
      if (mounted) setState(() { _isLoading = false; _chatError = dataErrorMessage(error); });
    });
  }

  // 處理聊天快照
  void _processChatsSnapshot(QuerySnapshot snapshot, String userId) {
    List<Map<String, dynamic>> chatList = [];

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final members = List<String>.from(data['members']);
      final memberNames = Map<String, String>.from(data['memberNames'] ?? {});

      // 找到對方用戶ID
      final otherId = members.firstWhere(
        (id) => id != userId,
        orElse: () => '',
      );

      if (otherId.isEmpty) continue;

      // 取得對方名稱
      final otherName = memberNames[otherId] ?? '家庭成員';

      // 處理時間
      DateTime? lastTime;
      if (data['lastTime'] is Timestamp) {
        lastTime = (data['lastTime'] as Timestamp).toDate();
      }

      // 🎯 取得未讀數量 - 這是關鍵
      final unread = (data['unread'] ?? {})[userId] ?? 0;

      chatList.add({
        'id': doc.id,
        'name': otherName,
        'message': data['lastMessage'] ?? '',
        'time': lastTime,
        'unread': unread, // 即時更新的未讀數字
        'otherId': otherId,
        'lastTime': lastTime,
      });

      // 除錯資訊
      if (unread > 0) {
        print('📱 聊天 "$otherName" 有 $unread 條未讀訊息');
      }
    }

    // 在記憶體中按時間排序
    chatList.sort((a, b) {
      final aTime = a['time'] as DateTime?;
      final bTime = b['time'] as DateTime?;
      final aDate = aTime ?? DateTime(1970);
      final bDate = bTime ?? DateTime(1970);
      return bDate.compareTo(aDate); // 降序排序
    });

    if (mounted) {
      setState(() {
        _chats = chatList;
        _isLoading = false;
      });
    }
  }

  // 重新載入聊天
  void _reloadChats() {
    setState(() => _isLoading = true);
    _setupChatsStream();
  }

  // 刪除聊天記錄
  Future<void> _deleteChat(String chatId, BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除聊天記錄'),
        content: const Text('確定要刪除這個聊天記錄嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _firestore.collection('chats').doc(chatId).update({
                  'members': FieldValue.arrayRemove([user.uid]),
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已刪除聊天記錄'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                  _reloadChats();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('刪除失敗: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 根據用戶ID生成一致的頭像顏色
  Color _getAvatarColor(String userId) {
    final colors = [
      AppColors.primary, // 藍色
      const Color(0xFF50C878), // 綠色
      AppColors.error, // 紅色
      const Color(0xFFFFA500), // 橙色
      const Color(0xFF9B59B6), // 紫色
      const Color(0xFF1ABC9C), // 青色
    ];
    final index = userId.hashCode % colors.length;
    return colors[index];
  }

  // 格式化時間
  String _formatTime(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);

    if (messageDay == today) {
      return DateFormat('HH:mm').format(date);
    } else if (messageDay == today.subtract(const Duration(days: 1))) {
      return '昨天';
    } else if (messageDay.year == now.year) {
      return DateFormat('MM/dd').format(date);
    } else {
      return DateFormat('yy/MM/dd').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_chatError != null) return Scaffold(appBar: AppBar(title: const Text('聊天')),
      body: DataErrorView(message: _chatError!, onRetry: _setupChatsStream));
    final user = _auth.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('聊天'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                '請先登入帳號',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '訊息',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(onPressed: _chatWindow?.hasMore == true ? () => _chatWindow?.loadMore() : null,
            child: const Text('載入更多')),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            color: Colors.black54,
            onPressed: _reloadChats,
            tooltip: '重新整理',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔍 現代風格搜尋框
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Icon(
                      Icons.search,
                      size: 20,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '搜尋已載入的聊天',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 16,
                          ),
                        ),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    if (_isSearching)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 💬 聊天列表
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : _chats.isEmpty
                  ? _buildEmptyState()
                  : _buildChatList(),
            ),
          ],
        ),
      ),
    );
  }

  // 建立 AI 小助手入口
  Widget _buildAIAssistantEntry() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AIChatScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.1),
              AppColors.primary.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // AI 頭像
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  '安',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // AI 資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '小安',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'AI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '你的專屬健康管理助手',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            // 箭頭
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.primary.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  // 建立聊天列表
  Widget _buildChatList() {
    List<Map<String, dynamic>> displayChats = _chats;

    // 搜尋過濾
    if (_isSearching && _searchController.text.isNotEmpty) {
      final searchText = _searchController.text.toLowerCase();
      displayChats = _chats.where((chat) {
        final name = chat['name']?.toString().toLowerCase() ?? '';
        return name.contains(searchText);
      }).toList();
    }

    if (displayChats.isEmpty && !_isSearching) {
      return RefreshIndicator(
        onRefresh: () async {
          _reloadChats();
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            _buildAIAssistantEntry(),
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '還沒有家庭聊天',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '接受家庭邀請後會自動建立聊天室',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (displayChats.isEmpty && _isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '找不到相關聊天',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _reloadChats();
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: displayChats.length + 1, // +1 for AI assistant
        itemBuilder: (context, index) {
          // 第一項是 AI 小助手
          if (index == 0) {
            return _buildAIAssistantEntry();
          }

          // 其餘是正常聊天
          final chat = displayChats[index - 1];
          final name = chat['name']?.toString() ?? '未知用戶';
          final message = chat['message']?.toString() ?? '';
          final time = _formatTime(chat['time'] as DateTime?);
          final unread = chat['unread'] as int? ?? 0;
          final chatId = chat['id']?.toString() ?? '';
          final otherId = chat['otherId']?.toString() ?? '';

          final avatarColor = _getAvatarColor(otherId);

          return InkWell(
            onTap: () {
              print('👆 點擊進入聊天室: $name (未讀: $unread)');

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatRoomScreen(
                    chatId: chatId,
                    name: name,
                    avatar: CircleAvatar(
                      backgroundColor: avatarColor,
                      child: Text(
                        name.isNotEmpty ? name[0] : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    isOnline: false,
                    otherUserId: otherId,
                  ),
                ),
              ).then((_) {
                // 🎯 從聊天室返回時，重新整理列表
                print('↩️ 從聊天室返回，重新整理未讀數字');
                _reloadChats();
              });
            },
            onLongPress: () => _deleteChat(chatId, context),
            child: Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 頭像
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: avatarColor,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0] : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 聊天內容
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: unread > 0
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              time,
                              style: TextStyle(
                                fontSize: 12,
                                color: unread > 0
                                    ? AppColors.primary
                                    : AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                message,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: unread > 0
                                      ? Colors.black87
                                      : AppColors.textSecondary,
                                  fontWeight: unread > 0
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            // 🎯 未讀數字徽章
                            if (unread > 0)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  unread.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 載入狀態
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text(
            '載入聊天記錄中...',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // 空狀態
  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: () async {
        _reloadChats();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          _buildAIAssistantEntry(),
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                const Text(
                  '還沒有家庭聊天',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  '接受家庭邀請後會自動建立聊天室',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
