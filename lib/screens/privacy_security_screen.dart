import '../services/ai/benchmark/runtime.dart';
import 'ai_benchmark_screen.dart';
import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'change_password_screen.dart';
import '../services/app_unlock_runtime.dart';
import '../widgets/app_unlock_settings.dart';
import '../services/session_timeout_service.dart';


// =================================================================
// PrivacySecurityScreen Widget
// 這是「帳號設定」頁面
// =================================================================
class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  final _sessionTimeoutService = SessionTimeoutService();

  // 閒置自動登出設定
  bool _sessionTimeoutEnabled = true;
  int _sessionTimeoutMinutes = 5;

  @override
  void initState() {
    super.initState();
    _loadSessionTimeoutSettings();
  }

  Future<void> _loadSessionTimeoutSettings() async {
    final isEnabled = await _sessionTimeoutService.isTimeoutEnabled();
    final duration = await _sessionTimeoutService.getTimeoutDuration();

    if (mounted) {
      setState(() {
        _sessionTimeoutEnabled = isEnabled;
        _sessionTimeoutMinutes = duration;
      });
    }
  }

  Future<void> _toggleSessionTimeout(bool value) async {
    await _sessionTimeoutService.setTimeoutEnabled(value);
    setState(() => _sessionTimeoutEnabled = value);
    _showSnackbar(value ? '閒置自動登出已啟用' : '閒置自動登出已停用');
  }

  Future<void> _showTimeoutDurationPicker() async {
    final durations = [3, 5, 10, 15, 30];
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.timer, color: AppColors.primary),
            SizedBox(width: 12),
            Text('閒置登出時間'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: durations.map((minutes) {
            return RadioListTile<int>(
              title: Text('$minutes 分鐘'),
              value: minutes,
              groupValue: _sessionTimeoutMinutes,
              activeColor: AppColors.primary,
              onChanged: (value) => Navigator.pop(context, value),
            );
          }).toList(),
        ),
      ),
    );

    if (result != null && result != _sessionTimeoutMinutes) {
      await _sessionTimeoutService.setTimeoutDuration(result);
      setState(() => _sessionTimeoutMinutes = result);
      _showSnackbar('閒置登出時間已設為 $result 分鐘');
    }
  }

  // 顯示操作結果的 SnackBar
  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  // 建立設定區塊標題
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  // 建立導航/操作設定項目 (使用 ListTile)
  Widget _buildActionItem({
    required String title,
    required IconData icon,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isDestructive ? AppColors.error : AppColors.primary
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isDestructive ? AppColors.error : Colors.black87,
          ),
        ),
        trailing: isDestructive ? null : const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }

  // 彈出刪除帳號確認對話框
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除帳號？'),
        content: const Text('刪除後所有資料將無法復原。您確定要繼續嗎？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showSnackbar('帳號刪除流程已啟動...');
              // 實際應用中，這裡應執行刪除 API
            },
            child: const Text('確認刪除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  // =================================================================
  // build 函式 (主 UI 結構)
  // =================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('帳號設定',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (benchmarkEnabled)
              ListTile(title: const Text('合成處方 benchmark（debug）'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AIBenchmarkScreen()))),
            // --- 區塊 1: 登入安全 ---
            _buildSectionTitle('登入安全'),

            AppUnlockSettings(controller: AppUnlockRuntime.instance.controller),

            // 閒置自動登出開關
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.timer_off, color: AppColors.primary),
                    title: const Text(
                      '閒置自動登出',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      _sessionTimeoutEnabled
                          ? '閒置 $_sessionTimeoutMinutes 分鐘後自動登出'
                          : '已停用自動登出',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    value: _sessionTimeoutEnabled,
                    onChanged: _toggleSessionTimeout,
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  ),
                  if (_sessionTimeoutEnabled)
                    InkWell(
                      onTap: _showTimeoutDurationPicker,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
                        child: Row(
                          children: [
                            Text(
                              '設定時間：$_sessionTimeoutMinutes 分鐘',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit, size: 14, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // --- 區塊 2: 帳號安全 ---
            _buildSectionTitle('帳號安全'),
            _buildActionItem(
              icon: Icons.lock_reset_rounded,
              title: '更改密碼',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const ChangePasswordScreen()),
                );
              },
            ),

            // --- 區塊 3: 帳號管理 ---
            _buildSectionTitle('帳號管理'),
            _buildActionItem(
              icon: Icons.delete_forever_rounded,
              title: '刪除我的帳號',
              isDestructive: true,
              onTap: _showDeleteAccountDialog,
            ),

            const SizedBox(height: 30),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '我們嚴格遵守隱私政策，您的個人健康資料會被安全加密儲存。',
                style: TextStyle(color: AppColors.textHint, fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
