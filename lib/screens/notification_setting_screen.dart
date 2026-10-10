import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../services/health_alert_service.dart';

// =================================================================
// NotificationSettingScreen Widget
// 這是「通知設定」頁面
// =================================================================
class NotificationSettingScreen extends StatefulWidget {
  const NotificationSettingScreen({Key? key}) : super(key: key);

  @override
  State<NotificationSettingScreen> createState() =>
      _NotificationSettingScreenState();
}

class _NotificationSettingScreenState extends State<NotificationSettingScreen> {
  // 通知開關的狀態
  bool _isAllNotificationsEnabled = true;
  bool _isActivityAlertsEnabled = true;
  bool _isHealthRemindersEnabled = true;
  bool _isFamilyAlertsEnabled = false;
  bool _isAppUpdatesEnabled = true;
  bool _isLoading = true;

  // 健康量測提醒設定
  bool _bloodPressureReminderEnabled = false;
  TimeOfDay _bloodPressureReminderTime = const TimeOfDay(hour: 8, minute: 0);
  bool _bloodGlucoseReminderEnabled = false;
  TimeOfDay _bloodGlucoseReminderTime = const TimeOfDay(hour: 7, minute: 30);

  // 漏吃提醒設定
  bool _missedDoseReminderEnabled = true;
  int _missedDoseIntervalMinutes = 30;
  int _missedDoseMaxReminders = 2;

  // 健康警示設定
  bool _bloodPressureAlertEnabled = true;
  bool _bloodGlucoseAlertEnabled = true;
  bool _heartRateAlertEnabled = true;
  final HealthAlertService _healthAlertService = HealthAlertService();

  // 最多提醒次數選項
  final List<Map<String, dynamic>> _maxRemindersOptions = [
    {'value': 1, 'label': '1 次'},
    {'value': 2, 'label': '2 次'},
    {'value': 3, 'label': '3 次'},
    {'value': 0, 'label': '持續提醒直到服藥'},
  ];

  // 設定名稱對照表
  final Map<String, String> _settingNames = {
    'all': '所有通知',
    'activity': '活動提醒',
    'health': '健康提醒',
    'family': '家人關係通知',
    'updates': '應用程式更新',
  };

  // NotificationService 實例
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotificationSettings();
    });
  }

  // 從 Firebase 載入用戶的通知設定
  Future<void> _loadNotificationSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('notifications')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _isAllNotificationsEnabled = data['all'] ?? true;
          _isActivityAlertsEnabled = data['activity'] ?? true;
          _isHealthRemindersEnabled = data['health'] ?? true;
          _isFamilyAlertsEnabled = data['family'] ?? false;
          _isAppUpdatesEnabled = data['updates'] ?? true;

          // 載入健康量測提醒設定
          _bloodPressureReminderEnabled = data['bloodPressureEnabled'] ?? false;
          if (data['bloodPressureTime'] != null) {
            final parts = (data['bloodPressureTime'] as String).split(':');
            _bloodPressureReminderTime = TimeOfDay(
              hour: int.parse(parts[0]),
              minute: int.parse(parts[1]),
            );
          }
          _bloodGlucoseReminderEnabled = data['bloodGlucoseEnabled'] ?? false;
          if (data['bloodGlucoseTime'] != null) {
            final parts = (data['bloodGlucoseTime'] as String).split(':');
            _bloodGlucoseReminderTime = TimeOfDay(
              hour: int.parse(parts[0]),
              minute: int.parse(parts[1]),
            );
          }

          // 載入漏吃提醒設定
          _missedDoseReminderEnabled = data['missedDoseEnabled'] ?? true;
          _missedDoseIntervalMinutes = data['missedDoseInterval'] ?? 30;
          _missedDoseMaxReminders = data['missedDoseMaxReminders'] ?? 2;

          _isLoading = false;
        });

        // 載入到 NotificationService
        await _notificationService.loadUserNotificationSettings();

        // 載入健康警示設定
        await _healthAlertService.loadAlertSettings();
        final alertSettings = _healthAlertService.alertSettings;
        setState(() {
          _bloodPressureAlertEnabled = alertSettings['bloodPressureAlert'] ?? true;
          _bloodGlucoseAlertEnabled = alertSettings['bloodGlucoseAlert'] ?? true;
          _heartRateAlertEnabled = alertSettings['heartRateAlert'] ?? true;
        });
      } else {
        // 如果沒有設定，使用預設值並儲存
        setState(() => _isLoading = false);
        await _saveSettings();
      }
    } catch (e) {
      debugPrint('❌ 載入通知設定失敗: $e');
      setState(() => _isLoading = false);
    }
  }

  // 儲存設定到 Firebase
  Future<void> _saveSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('notifications')
          .set({
        'all': _isAllNotificationsEnabled,
        'activity': _isActivityAlertsEnabled,
        'health': _isHealthRemindersEnabled,
        'family': _isFamilyAlertsEnabled,
        'updates': _isAppUpdatesEnabled,
        // 健康量測提醒設定
        'bloodPressureEnabled': _bloodPressureReminderEnabled,
        'bloodPressureTime':
            '${_bloodPressureReminderTime.hour.toString().padLeft(2, '0')}:${_bloodPressureReminderTime.minute.toString().padLeft(2, '0')}',
        'bloodGlucoseEnabled': _bloodGlucoseReminderEnabled,
        'bloodGlucoseTime':
            '${_bloodGlucoseReminderTime.hour.toString().padLeft(2, '0')}:${_bloodGlucoseReminderTime.minute.toString().padLeft(2, '0')}',
        // 漏吃提醒設定
        'missedDoseEnabled': _missedDoseReminderEnabled,
        'missedDoseInterval': _missedDoseIntervalMinutes,
        'missedDoseMaxReminders': _missedDoseMaxReminders,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ 通知設定已儲存');
    } catch (e) {
      debugPrint('❌ 儲存通知設定失敗: $e');
    }
  }

  // 處理開關狀態變更
  void _onSwitchChanged(String setting, bool newValue) async {
    setState(() {
      switch (setting) {
        case 'all':
          _isAllNotificationsEnabled = newValue;
          // 總開關連動所有子開關
          _isActivityAlertsEnabled = newValue;
          _isHealthRemindersEnabled = newValue;
          _isFamilyAlertsEnabled = newValue;
          _isAppUpdatesEnabled = newValue;
          break;
        case 'activity':
          _isActivityAlertsEnabled = newValue;
          break;
        case 'health':
          _isHealthRemindersEnabled = newValue;
          break;
        case 'family':
          _isFamilyAlertsEnabled = newValue;
          break;
        case 'updates':
          _isAppUpdatesEnabled = newValue;
          break;
      }
    });

    // 顯示中文名稱的 SnackBar
    final settingName = _settingNames[setting] ?? setting;
    _showSnackbar('「$settingName」已${newValue ? '開啟' : '關閉'}');

    // 儲存到 Firebase
    await _saveSettings();

    // 同步更新 NotificationService 的設定快取
    await _notificationService.loadUserNotificationSettings();

    // 如果健康提醒關閉，取消所有健康相關通知
    if (setting == 'health' && !newValue) {
      await _notificationService.cancelNotification(1001);
      await _notificationService.cancelNotification(1002);
    }
  }

  // 選擇提醒時間
  Future<void> _selectReminderTime(String type) async {
    final currentTime = type == 'bloodPressure'
        ? _bloodPressureReminderTime
        : _bloodGlucoseReminderTime;

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: currentTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (type == 'bloodPressure') {
          _bloodPressureReminderTime = picked;
        } else {
          _bloodGlucoseReminderTime = picked;
        }
      });
      await _saveSettings();
      await _scheduleHealthReminders();
      _showSnackbar('提醒時間已設定為 ${picked.format(context)}');
    }
  }

  // 切換健康提醒開關
  Future<void> _toggleHealthReminder(String type, bool enabled) async {
    setState(() {
      if (type == 'bloodPressure') {
        _bloodPressureReminderEnabled = enabled;
      } else {
        _bloodGlucoseReminderEnabled = enabled;
      }
    });

    await _saveSettings();
    await _scheduleHealthReminders();

    final typeName = type == 'bloodPressure' ? '血壓' : '血糖';
    _showSnackbar('$typeName提醒已${enabled ? '開啟' : '關閉'}');
  }

  // 切換漏吃提醒開關
  Future<void> _toggleMissedDoseReminder(bool enabled) async {
    setState(() {
      _missedDoseReminderEnabled = enabled;
    });
    try {
      await _saveSettings();
      await _notificationService.loadUserNotificationSettings();
      _showSnackbar('漏吃提醒已${enabled ? '開啟' : '關閉'}');
    } catch (e) {
      debugPrint('❌ 切換漏吃提醒失敗: $e');
      setState(() {
        _missedDoseReminderEnabled = !enabled;
      });
      _showSnackbar('操作失敗，請重試');
    }
  }

  // 更新漏吃提醒間隔
  Future<void> _updateMissedDoseInterval(int minutes) async {
    setState(() {
      _missedDoseIntervalMinutes = minutes;
    });
    try {
      await _saveSettings();
      await _notificationService.loadUserNotificationSettings();
      _showSnackbar('漏吃提醒間隔已設為 $minutes 分鐘');
    } catch (e) {
      debugPrint('❌ 更新提醒間隔失敗: $e');
      _showSnackbar('更新失敗，請重試');
    }
  }

  // 顯示間隔時間輸入對話框
  Future<void> _showIntervalInputDialog() async {
    final controller =
        TextEditingController(text: _missedDoseIntervalMinutes.toString());

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Center(
          child: Text('設定提醒間隔'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '服藥時間過後多久提醒您？',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 120,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '1 - 60',
                  suffixText: '分鐘',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.warning, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                autofocus: true,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value >= 1 && value <= 60) {
                Navigator.pop(context, value);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('請輸入 1 到 60 之間的數字'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child: const Text('確定'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _updateMissedDoseInterval(result);
    }
  }

  // 更新漏吃提醒次數
  Future<void> _updateMissedDoseMaxReminders(int count) async {
    setState(() {
      _missedDoseMaxReminders = count;
    });
    try {
      await _saveSettings();
      await _notificationService.loadUserNotificationSettings();

      final label = _maxRemindersOptions
          .firstWhere((o) => o['value'] == count)['label'];
      _showSnackbar('最多提醒次數已設為 $label');
    } catch (e) {
      debugPrint('❌ 更新提醒次數失敗: $e');
      _showSnackbar('更新失敗，請重試');
    }
  }

  // 切換健康警示開關
  Future<void> _toggleHealthAlert(String type, bool enabled) async {
    setState(() {
      switch (type) {
        case 'bloodPressure':
          _bloodPressureAlertEnabled = enabled;
          break;
        case 'bloodGlucose':
          _bloodGlucoseAlertEnabled = enabled;
          break;
        case 'heartRate':
          _heartRateAlertEnabled = enabled;
          break;
      }
    });

    _healthAlertService.setAlertEnabled('${type}Alert', enabled);

    final typeName = {
      'bloodPressure': '血壓',
      'bloodGlucose': '血糖',
      'heartRate': '心率',
    }[type] ?? type;

    _showSnackbar('$typeName異常警示已${enabled ? '開啟' : '關閉'}');
  }

  // 排程健康提醒
  Future<void> _scheduleHealthReminders() async {
    // 取消現有的健康提醒
    await _notificationService.cancelNotification(1001);
    await _notificationService.cancelNotification(1002);

    // 檢查是否啟用通知
    if (!_isHealthRemindersEnabled || !_isAllNotificationsEnabled) {
      return;
    }

    // 排程血壓提醒
    if (_bloodPressureReminderEnabled) {
      final now = DateTime.now();
      var scheduledTime = DateTime(
        now.year,
        now.month,
        now.day,
        _bloodPressureReminderTime.hour,
        _bloodPressureReminderTime.minute,
      );
      // 如果時間已過，設定為明天
      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      await _notificationService.scheduleHealthReminder(
        id: 1001,
        type: 'blood_pressure',
        scheduledTime: scheduledTime,
      );
      debugPrint('✅ 已排程血壓提醒: $scheduledTime');
    }

    // 排程血糖提醒
    if (_bloodGlucoseReminderEnabled) {
      final now = DateTime.now();
      var scheduledTime = DateTime(
        now.year,
        now.month,
        now.day,
        _bloodGlucoseReminderTime.hour,
        _bloodGlucoseReminderTime.minute,
      );
      // 如果時間已過，設定為明天
      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      await _notificationService.scheduleHealthReminder(
        id: 1002,
        type: 'blood_glucose',
        scheduledTime: scheduledTime,
      );
      debugPrint('✅ 已排程血糖提醒: $scheduledTime');
    }
  }

  // 顯示操作結果的 SnackBar
  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
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

  // 建立健康提醒項目（含時間選擇）
  Widget _buildHealthReminderItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required TimeOfDay time,
    required ValueChanged<bool> onToggle,
    required VoidCallback onTimeTap,
  }) {
    final timeString =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

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
      child: Column(
        children: [
          SwitchListTile(
            secondary:
                Icon(icon, color: enabled ? AppColors.primary : Colors.grey),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
            value: enabled,
            onChanged: onToggle,
            activeColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          if (enabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const SizedBox(width: 24),
              title: const Text('提醒時間', style: TextStyle(fontSize: 14)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      timeString,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.access_time, size: 20, color: Colors.grey),
                ],
              ),
              onTap: onTimeTap,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ],
        ],
      ),
    );
  }

  // 建立整合的用藥提醒區塊（包含用藥提醒開關 + 漏吃提醒設定）
  Widget _buildMedicationReminderSection() {
    final isEnabled = _isHealthRemindersEnabled && _isAllNotificationsEnabled;

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
      child: Column(
        children: [
          // 用藥提醒主開關
          SwitchListTile(
            secondary: Icon(
              Icons.medication_rounded,
              color: isEnabled ? AppColors.primary : Colors.grey,
            ),
            title: const Text('用藥提醒', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('服藥時間到時會收到通知提醒', style: TextStyle(fontSize: 12)),
            value: isEnabled,
            onChanged: _isAllNotificationsEnabled
                ? (newValue) => _onSwitchChanged('health', newValue)
                : null,
            activeColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),

          // 漏吃提醒設定（僅在用藥提醒開啟時顯示）
          if (isEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),

            // 漏吃提醒開關
            SwitchListTile(
              secondary: Icon(
                Icons.notification_important_rounded,
                color: _missedDoseReminderEnabled
                    ? AppColors.warning
                    : Colors.grey,
                size: 22,
              ),
              title: const Text('漏吃提醒',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
              subtitle: const Text(
                  '服藥時間過後若未標記已服用，會再次提醒',
                  style: TextStyle(fontSize: 11)),
              value: _missedDoseReminderEnabled,
              onChanged: _toggleMissedDoseReminder,
              activeColor: AppColors.warning,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              dense: true,
            ),

            // 漏吃提醒詳細設定（僅在漏吃提醒開啟時顯示）
            if (_missedDoseReminderEnabled) ...[
              // 間隔時間設定（點擊輸入）
              ListTile(
                leading: const SizedBox(width: 24),
                title: const Text('提醒間隔', style: TextStyle(fontSize: 14)),
                subtitle: const Text('服藥時間過後多久提醒',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: GestureDetector(
                  onTap: _showIntervalInputDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.warning.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_missedDoseIntervalMinutes 分鐘',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.edit,
                          size: 14,
                          color: AppColors.warning,
                        ),
                      ],
                    ),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                dense: true,
              ),

              // 最多提醒次數設定
              ListTile(
                leading: const SizedBox(width: 24),
                title: const Text('最多提醒次數', style: TextStyle(fontSize: 14)),
                subtitle: const Text('超過次數後不再提醒',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<int>(
                    value: _missedDoseMaxReminders,
                    underline: const SizedBox(),
                    isDense: true,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                    items: _maxRemindersOptions.map((option) {
                      return DropdownMenuItem<int>(
                        value: option['value'] as int,
                        child: Text(option['label'] as String),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _updateMissedDoseMaxReminders(value);
                      }
                    },
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                dense: true,
              ),
            ],
          ],
        ],
      ),
    );
  }

  // 建立健康警示設定區塊
  Widget _buildHealthAlertSection() {
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
      child: Column(
        children: [
          // 說明文字
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '當記錄的健康數值超出正常範圍時，顯示警示提醒',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 血壓警示
          SwitchListTile(
            secondary: Icon(
              Icons.favorite_rounded,
              color: _bloodPressureAlertEnabled ? AppColors.error : Colors.grey,
              size: 22,
            ),
            title: const Text('血壓異常警示',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            subtitle: const Text('收縮壓 >140 或 舒張壓 >90 時提醒',
                style: TextStyle(fontSize: 11)),
            value: _bloodPressureAlertEnabled,
            onChanged: (value) => _toggleHealthAlert('bloodPressure', value),
            activeColor: AppColors.error,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            dense: true,
          ),

          const Divider(height: 1, indent: 56, endIndent: 16),

          // 血糖警示
          SwitchListTile(
            secondary: Icon(
              Icons.water_drop_rounded,
              color: _bloodGlucoseAlertEnabled ? AppColors.warning : Colors.grey,
              size: 22,
            ),
            title: const Text('血糖異常警示',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            subtitle: const Text('空腹 >100 或 餐後 >140 時提醒',
                style: TextStyle(fontSize: 11)),
            value: _bloodGlucoseAlertEnabled,
            onChanged: (value) => _toggleHealthAlert('bloodGlucose', value),
            activeColor: AppColors.warning,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            dense: true,
          ),

          const Divider(height: 1, indent: 56, endIndent: 16),

          // 心率警示
          SwitchListTile(
            secondary: Icon(
              Icons.monitor_heart_rounded,
              color: _heartRateAlertEnabled ? const Color(0xFFE91E63) : Colors.grey,
              size: 22,
            ),
            title: const Text('心率異常警示',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            subtitle: const Text('心率 <60 或 >100 時提醒',
                style: TextStyle(fontSize: 11)),
            value: _heartRateAlertEnabled,
            onChanged: (value) => _toggleHealthAlert('heartRate', value),
            activeColor: const Color(0xFFE91E63),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            dense: true,
          ),
        ],
      ),
    );
  }

  // 建立設定項目，使用 SwitchListTile
  Widget _buildSwitchItem({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
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
      child: SwitchListTile(
        secondary: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知設定',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // --- 區塊 1: 總開關 ---
                  _buildSectionTitle('主要控制'),
                  _buildSwitchItem(
                    icon: Icons.notifications_active_rounded,
                    title: '接收所有通知',
                    subtitle: '一鍵開啟或關閉所有應用程式通知',
                    value: _isAllNotificationsEnabled,
                    onChanged: (newValue) => _onSwitchChanged('all', newValue),
                  ),

                  // --- 區塊 2: 用藥提醒（整合漏吃提醒）---
                  _buildSectionTitle('用藥提醒'),
                  _buildMedicationReminderSection(),

                  // --- 每日量測提醒 ---
                  if (_isHealthRemindersEnabled && _isAllNotificationsEnabled) ...[
                    _buildSectionTitle('每日量測提醒'),
                    _buildHealthReminderItem(
                      icon: Icons.favorite_rounded,
                      title: '血壓量測提醒',
                      subtitle: '每天提醒您量測血壓',
                      enabled: _bloodPressureReminderEnabled,
                      time: _bloodPressureReminderTime,
                      onToggle: (value) =>
                          _toggleHealthReminder('bloodPressure', value),
                      onTimeTap: () => _selectReminderTime('bloodPressure'),
                    ),
                    _buildHealthReminderItem(
                      icon: Icons.water_drop_rounded,
                      title: '血糖量測提醒',
                      subtitle: '每天提醒您量測血糖',
                      enabled: _bloodGlucoseReminderEnabled,
                      time: _bloodGlucoseReminderTime,
                      onToggle: (value) =>
                          _toggleHealthReminder('bloodGlucose', value),
                      onTimeTap: () => _selectReminderTime('bloodGlucose'),
                    ),
                  ],

                  // --- 健康警示設定 ---
                  _buildSectionTitle('健康警示'),
                  _buildHealthAlertSection(),

                  const SizedBox(height: 30),
                  // 提示訊息
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '您可以在系統設定中管理應用程式的整體通知權限。',
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