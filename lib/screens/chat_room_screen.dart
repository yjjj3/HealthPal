import '../services/live_query_window.dart';
import '../utils/data_error_message.dart';
import '../widgets/data_error_view.dart';
import '../services/chat_message_service.dart';
import 'dart:async';
import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'family_health_screen.dart';
class ChatRoomScreen extends StatefulWidget {
  final String chatId; 
  final String name;
  final String? nickname;
  final Widget avatar;
  final bool isOnline;
  final String otherUserId;

  const ChatRoomScreen({
    super.key,
    required this.chatId,
    required this.name,
    this.nickname,
    required this.avatar,
    required this.isOnline,
    required this.otherUserId,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  late String _safeChatId;

  bool _isSending = false;
  String? _pendingMessageId;
  String? _pendingMessageText;
  bool _showEmojiPicker = false;
  bool _chatRoomCreated = false;
  String? _chatError;
  late LiveQueryWindow _messageWindow;
  Timestamp? _lastMessageTimestamp;
  String _myName = '用戶';

  // 即時監聽的訂閱，需在 dispose() 時取消，避免每次進出聊天室都多洩漏一組監聽器
  StreamSubscription<QuerySnapshot>? _autoScrollSubscription;
  StreamSubscription<DocumentSnapshot>? _unreadSubscription;

  String _getStandardChatId(String userId1, String userId2) {
    final userIds = [userId1, userId2];
    userIds.sort();
    return userIds.join('_');
  }

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) {
      _safeChatId = _getStandardChatId(user.uid, widget.otherUserId);
    } else {
      _safeChatId = widget.chatId; 
    }

    _messageWindow = LiveQueryWindow(_firestore.collection('chats').doc(_safeChatId)
      .collection('messages').orderBy('timestamp', descending: true),
      onChanged: () { if (mounted) setState(() {}); });
    _initializeChatRoom();
    _messageController.addListener(() => setState(() {}));
  }

  Future<void> _initializeChatRoom() async {
    if (mounted) setState(() => _chatError = null);
    await _loadMyName();
    if (!mounted) return;
    await _ensureChatRoomExists();
    if (!mounted || !_chatRoomCreated) return;
    _markMessagesAsRead();
    _setupUnreadListener();
    _setupAutoScroll();
  }

  String? _latestMessageId;

  void _setupAutoScroll() {
    _autoScrollSubscription = _messageWindow.stream.listen((snapshot) {
      if (!mounted) return;
      final latestId = snapshot.docs.isEmpty ? null : snapshot.docs.first.id;
      final hasNewLatest = latestId != _latestMessageId && snapshot.docChanges.any(
        (change) => change.type == DocumentChangeType.added && change.doc.id == latestId);
      _latestMessageId = latestId;
      if (hasNewLatest) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToBottom();
        });
      }
    }, onError: (Object error) {
      if (mounted) setState(() => _chatError = dataErrorMessage(error));
    });
  }

  @override
  void dispose() {
    _autoScrollSubscription?.cancel();
    _messageWindow.dispose();
    _unreadSubscription?.cancel();
    _scrollController.dispose();
    _focusNode.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // Chat identity does not imply consent to disclose the private profile name.
  Future<void> _loadMyName() async {
    _myName = '家人';
  }

  // 確保聊天室存在
  Future<void> _ensureChatRoomExists() async {
    try {
      final chatDoc = await _firestore.collection('chats').doc(_safeChatId).get();
      
      if (!chatDoc.exists) {
        print('🆕 聊天室不存在，創建新聊天室...');
        await _createChatRoom();
      } else {
        print('✅ 聊天室已存在');
        if (!mounted) return;
        setState(() {
          _chatRoomCreated = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _chatError = dataErrorMessage(e));
    }
  }

  // 創建聊天室
  Future<void> _createChatRoom() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final chatData = {
        'members': [user.uid, widget.otherUserId],
        'memberNames': {
          user.uid: _myName,
          widget.otherUserId: widget.name,
        },
        'lastMessage': '開始聊天吧！',
        'lastTime': FieldValue.serverTimestamp(),
        'unread': {
          user.uid: 0, // 創建時未讀為0
          widget.otherUserId: 0,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'family',
      };
      
      final chatRef = _firestore.collection('chats').doc(_safeChatId);
      await _firestore.runTransaction((transaction) async {
        if (!(await transaction.get(chatRef)).exists) {
          transaction.set(chatRef, chatData);
        }
      });

      if (!mounted) return;
      setState(() {
        _chatError = null;
        _chatRoomCreated = true;
      });
      
      print('✅ 聊天室創建成功');
    } catch (e) {
      if (mounted) setState(() => _chatError = dataErrorMessage(e));
    }
  }

  // 🎯 重要：標記訊息為已讀
  void _markMessagesAsRead() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // 直接將當前用戶的未讀計數設為0
      await _firestore.collection('chats').doc(_safeChatId).update({
        'unread.${user.uid}': 0,
      });
      
      print('✅ 標記訊息為已讀（用戶: ${user.uid}）');
    } on FirebaseException catch (e) {
      if (e.code != 'not-found') {
        print('❌ 標記已讀失敗: $e');
      }
    } catch (e) {
      print('❌ 標記已讀發生錯誤: $e');
    }
  }

  // 監聽未讀訊息
  void _setupUnreadListener() {
    final user = _auth.currentUser;
    if (user == null) return;

    _unreadSubscription = _firestore.collection('chats').doc(_safeChatId).snapshots().listen((snapshot) {
      if (!mounted || user.uid != _auth.currentUser?.uid) return;
      if (snapshot.exists) {
        final data = snapshot.data()!;
        final unread = (data['unread'] ?? {})[user.uid] ?? 0;
        
        // 如果有未讀訊息，立即標記為已讀
        if (unread > 0) {
          print('📬 偵測到 $unread 條未讀訊息，自動標記為已讀...');
          _markMessagesAsRead();
        }
      }
    }, onError: (Object error) { if (mounted) setState(() => _chatError = dataErrorMessage(error)); });
  }

  void _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSending) return;

    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isSending = true);
    if (_pendingMessageText != message) {
      _pendingMessageText = message;
      _pendingMessageId = _firestore.collection('chats').doc(_safeChatId)
          .collection('messages').doc().id;
    }
    if (!_chatRoomCreated) {
      await _ensureChatRoomExists();
      if (!_chatRoomCreated) {
        print('❌ 聊天室創建失敗，無法發送訊息。');
        if (mounted) setState(() => _isSending = false);
        return;
      }
    }

    if (!mounted) return;
    try {
      await ChatMessageService(_firestore).sendOnce(
        chatId: _safeChatId, messageId: _pendingMessageId!,
        senderId: user.uid, recipientId: widget.otherUserId,
        senderName: _myName, text: message,
      );
      _pendingMessageId = null;
      _pendingMessageText = null;
      if (!mounted) return;

      print('✅ 訊息發送成功');

      _messageController.clear();
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } on FirebaseException catch (e) {
      print('❌ 發送訊息失敗: ${e.code} - ${e.message}');
      
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('發送失敗 (${e.code})，請重試'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    if (mounted && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
    if (_showEmojiPicker) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _addEmoji(String emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      emoji,
    );
    _messageController.value = _messageController.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + emoji.length),
    );
  }

  bool _shouldShowDate(Timestamp currentTimestamp, [Timestamp? previousTimestamp]) {
    if (previousTimestamp == null) return true;

    final currentDate = currentTimestamp.toDate();
    final previousDate = previousTimestamp.toDate();
    
    return currentDate.year != previousDate.year ||
           currentDate.month != previousDate.month ||
           currentDate.day != previousDate.day;
  }

  Widget _buildMessageBubble({
    required String text,
    required bool isMe,
    required Timestamp timestamp,
    required String senderName,
    required String senderId,
    Timestamp? previousTimestamp, 
  }) {
    String displayName = isMe ? senderName : (widget.nickname != null && widget.nickname!.isNotEmpty ? widget.nickname! : widget.name);

    final date = timestamp.toDate();
    final time = DateFormat('HH:mm').format(date);
    final showDate = _shouldShowDate(timestamp, previousTimestamp); 

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDate)
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _formatMessageDate(date),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey.shade300,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0] : '?',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isMe ? AppColors.primary : Colors.grey.shade100,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                          bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            text,
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87,
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 10,
                              color: isMe ? Colors.white70 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isMe) const SizedBox(width: 8),
            ],
          ),
        ),
      ],
    );
  }

  String _formatMessageDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return '今天';
    } else if (messageDate == yesterday) {
      return '昨天';
    } else {
      return DateFormat('MM月dd日').format(date);
    }
  }

  Widget _buildEmojiPicker() {
    if (!_showEmojiPicker) return const SizedBox.shrink();

    final emojis = ['😀', '😂', '🥰', '😎', '🤔', '👍', '❤️', '🎉', '🙏', '🔥'];
    
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: emojis.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => _addEmoji(emojis[index]),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade100,
              ),
              child: Center(
                child: Text(
                  emojis[index],
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            '正在準備聊天室...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        FamilyHealthScreen(userId: widget.otherUserId),

                  ),
                );
              },
              child: widget.avatar,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.nickname != null && widget.nickname!.isNotEmpty ? widget.nickname! : widget.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    widget.isOnline ? '在線' : '離線',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.isOnline ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.info_outline_rounded),
                          title: const Text('聊天資訊'),
                          onTap: () {
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.notifications_off_rounded),
                          title: const Text('靜音通知'),
                          onTap: () {
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: _chatError != null
          ? DataErrorView(message: _chatError!, onRetry: () {
              _chatError = null;
              _autoScrollSubscription?.cancel();
              _unreadSubscription?.cancel();
              _messageWindow.refresh();
              _initializeChatRoom();
            })
          : !_chatRoomCreated
          ? _buildLoadingState()
          : Column(
              children: [
                if (_messageWindow.hasMore) TextButton(
                  onPressed: _messageWindow.loadMore, child: const Text('載入更早的訊息')),
                // 訊息列表
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _messageWindow.stream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                '開始對話吧！',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final messages = snapshot.data!.docs.toList();

                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final data = message.data() as Map<String, dynamic>;
                          
                          final previousMessageDoc = index + 1 < messages.length ? messages[index + 1] : null;
                          final previousTimestamp = (previousMessageDoc?.data() as Map<String, dynamic>?)?['timestamp'] as Timestamp?;

                          final text = data['text']?.toString() ?? '';
                          final senderId = data['senderId']?.toString() ?? '';
                          final senderName = data['senderName']?.toString() ?? '用戶';
                          
                          Timestamp timestamp;
                          if (data['timestamp'] != null) {
                            timestamp = data['timestamp'] as Timestamp;
                          } else {
                            timestamp = Timestamp.fromMicrosecondsSinceEpoch(0); 
                          }
                          
                          final isMe = senderId == _auth.currentUser?.uid;

                          return _buildMessageBubble(
                            text: text,
                            isMe: isMe,
                            timestamp: timestamp,
                            senderName: senderName,
                            senderId: senderId,
                            previousTimestamp: previousTimestamp, 
                          );
                        },
                      );
                    },
                  ),
                ),

                // 表情符號選擇器
                _buildEmojiPicker(),

                // 輸入框
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _showEmojiPicker ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                          color: _showEmojiPicker ? AppColors.primary : Colors.grey,
                        ),
                        onPressed: _toggleEmojiPicker,
                      ),
                      
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                          decoration: InputDecoration(
                            hintText: '輸入訊息...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          maxLines: 5,
                          minLines: 1,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      
                      const SizedBox(width: 8),
                      
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _messageController.text.trim().isEmpty || _isSending
                              ? Colors.grey.shade300
                              : AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: _isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          onPressed: _messageController.text.trim().isEmpty || _isSending
                              ? null
                              : _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}