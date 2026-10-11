// lib/screens/meal_time_settings_screen.dart
// 用餐時間設定頁面

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medication_model.dart';
import '../utils/account_page_session.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../models/prescription_model.dart';
import '../services/prescription_scan_service.dart';
import '../services/notification_service.dart';

class MealTimeSettingsScreen extends StatefulWidget {
  final List<PrescriptionMedicine> medicines;
  final Map<String, dynamic>? hospitalInfo;

  const MealTimeSettingsScreen({
    super.key,
    this.medicines = const [],
    this.hospitalInfo,
  });

  @override
  State<MealTimeSettingsScreen> createState() => _MealTimeSettingsScreenState();
}

class _MealTimeSettingsScreenState extends State<MealTimeSettingsScreen> {
  final PrescriptionScanService _scanService = PrescriptionScanService();
  late final AccountPageSession _session;
  String? get _ownerUid => _session.ownerUid;
  List<medicine>? _pendingMedications;
  bool get _active => mounted && _session.active;

  late MealTimeSettings _settings;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _session = AccountPageSession(
      () => FirebaseAuth.instance.currentUser?.uid,
      FirebaseAuth.instance.authStateChanges().map((u) => u?.uid),
    );
    _session.addListener(() {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        if (mounted) setState(() {});
      }
    });
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _scanService.loadMealTimeSettings();
    if (!mounted || !_active) return;
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  Future<void> _selectTime(String mealType) async {
    if (!_active || _isSaving || _pendingMedications != null) return;
    TimeOfDay initialTime;
    switch (mealType) {
      case 'breakfast':
        initialTime = _settings.breakfastTime;
        break;
      case 'lunch':
        initialTime = _settings.lunchTime;
        break;
      case 'dinner':
        initialTime = _settings.dinnerTime;
        break;
      case 'bed':
        initialTime = _settings.bedTime;
        break;
      default:
        return;
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && _active && _pendingMedications == null) {
      setState(() {
        switch (mealType) {
          case 'breakfast':
            _settings = _settings.copyWith(breakfastTime: picked);
            break;
          case 'lunch':
            _settings = _settings.copyWith(lunchTime: picked);
            break;
          case 'dinner':
            _settings = _settings.copyWith(dinnerTime: picked);
            break;
          case 'bed':
            _settings = _settings.copyWith(bedTime: picked);
            break;
        }
      });
    }
  }

  Future<void> _skipAndSaveWithoutReminders() async {
    if (!_active || _isSaving) return;
    setState(() {
      _isSaving = true;
    });

    try {
      final medications = await _scanService.convertToMedications(
        widget.medicines,
        _settings,
        sources: null,
      );
      if (!mounted || !_active) return;
      _pendingMedications ??= _scanService.prepareMedications(
        medications.map((m) => m.copyWith(reminderEnabled: false)).toList(),
      );
      await _scanService.saveMedications(
        _pendingMedications!,
        expectedUid: _ownerUid,
        isActive: () => _active,
      );
      if (!mounted || !_active) return;

      if (mounted && _active) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('藥品已成功加入用藥清單！'),
              ],
            ),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && _active) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      }
    } catch (e) {
      debugPrint('儲存失敗: $e');
      if (mounted && _active) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _isSaving = false;
        });
    }
  }

  Future<void> _saveSettingsOnly() async {
    if (!_active || _isSaving) return;
    setState(() {
      _isSaving = true;
    });
    try {
      await _scanService.saveMealTimeSettings(
        _settings,
        expectedUid: _ownerUid,
      );
      if (!mounted || !_active) return;
      if (mounted && _active) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('用餐時間設定已儲存'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted && _active) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _isSaving = false;
        });
    }
  }

  Future<void> _saveAndCreateReminders() async {
    if (!_active || _isSaving) return;
    setState(() {
      _isSaving = true;
    });

    try {
      // 1. 儲存用餐時間設定
      await _scanService.saveMealTimeSettings(
        _settings,
        expectedUid: _ownerUid,
      );
      if (!mounted || !_active) return;

      // 2. 將處方箋藥品轉換為用藥模型
      final medications = await _scanService.convertToMedications(
        widget.medicines,
        _settings,
        sources: null,
      );

      // 3. 儲存藥品到 Firestore
      if (!mounted || !_active) return;
      _pendingMedications ??= _scanService.prepareMedications(medications);
      await _scanService.saveMedications(
        _pendingMedications!,
        expectedUid: _ownerUid,
        isActive: () => _active,
      );
      if (!mounted || !_active) return;

      // Medication reminders are rebuilt by the account-level listener.
      var reminderFailed = false;
      try {
        // 5. 回診提醒
        if (widget.hospitalInfo != null &&
            widget.hospitalInfo!['followUpDate'] != null) {
          final followUpDateStr =
              widget.hospitalInfo!['followUpDate'] as String;
          final followUpDate = DateTime.tryParse(followUpDateStr);
          if (followUpDate != null && followUpDate.isAfter(DateTime.now())) {
            final reminderDate = followUpDate.subtract(const Duration(days: 1));
            final reminderTime = DateTime(
              reminderDate.year,
              reminderDate.month,
              reminderDate.day,
              9,
              0,
            );
            await NotificationService().scheduleHealthReminder(
              id: 'followup_${followUpDate.millisecondsSinceEpoch}'.hashCode,
              type: 'follow_up',
              scheduledTime: reminderTime,
            );
          }
        }
      } catch (e) {
        reminderFailed = true;
        debugPrint('排程通知時發生錯誤: ${e.runtimeType}');
      }

      if (mounted && _active) {
        final msg = reminderFailed ? '藥品已儲存，但回診提醒排程失敗。' : '藥品已成功加入用藥清單！';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(msg)),
              ],
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && _active) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      }
    } catch (e) {
      debugPrint('儲存失敗: $e');
      if (mounted && _active) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '儲存失敗: ${e.toString().replaceAll('Exception: ', '')}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _isSaving = false;
        });
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_session.active) {
      return const Scaffold(body: Center(child: Text('帳號已變更，請返回重新開啟設定。')));
    }
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '設定用餐時間',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0.5,
        actions: [
          if (widget.medicines.isNotEmpty)
            TextButton(
              onPressed: _isSaving ? null : _skipAndSaveWithoutReminders,
              child: const Text(
                '略過',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 說明卡片
                  _buildInfoCard(),
                  const SizedBox(height: 24),

                  // 用餐時間設定
                  const Text(
                    '用餐時間',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTimeSettingsCard(),
                  const SizedBox(height: 24),

                  // 飯前飯後設定
                  const Text(
                    '提醒時間設定',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildReminderOffsetCard(),
                  const SizedBox(height: 24),

                  // 藥品預覽（僅在有處方箋藥品時顯示）
                  if (widget.medicines.isNotEmpty) ...[
                    const Text(
                      '用藥提醒預覽',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildMedicinePreviewList(),
                  ],
                ],
              ),
            ),
          ),

          // 底部按鈕
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.access_time,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '設定您的用餐時間',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '系統將根據藥品的服用時機（飯前/飯後），自動計算最佳的用藥提醒時間',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildTimeRow(
            icon: Icons.wb_sunny_outlined,
            iconColor: Colors.orange,
            label: '早餐',
            time: _settings.breakfastTime,
            onTap: () => _selectTime('breakfast'),
          ),
          const Divider(height: 1),
          _buildTimeRow(
            icon: Icons.wb_sunny,
            iconColor: Colors.amber,
            label: '午餐',
            time: _settings.lunchTime,
            onTap: () => _selectTime('lunch'),
          ),
          const Divider(height: 1),
          _buildTimeRow(
            icon: Icons.nights_stay_outlined,
            iconColor: Colors.indigo,
            label: '晚餐',
            time: _settings.dinnerTime,
            onTap: () => _selectTime('dinner'),
          ),
          const Divider(height: 1),
          _buildTimeRow(
            icon: Icons.bedtime,
            iconColor: Colors.deepPurple,
            label: '睡前',
            time: _settings.bedTime,
            onTap: () => _selectTime('bed'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(time),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit, size: 16, color: AppColors.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderOffsetCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildOffsetSlider(
            label: '飯前提前',
            value: _settings.beforeMealMinutes,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(beforeMealMinutes: value);
              });
            },
          ),
          const SizedBox(height: 16),
          _buildOffsetSlider(
            label: '飯後延後',
            value: _settings.afterMealMinutes,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(afterMealMinutes: value);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOffsetSlider({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$value 分鐘',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: 60,
          divisions: 12,
          activeColor: AppColors.primary,
          inactiveColor: AppColors.border,
          onChanged: (newValue) => onChanged(newValue.toInt()),
        ),
      ],
    );
  }

  Widget _buildMedicinePreviewList() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: widget.medicines.asMap().entries.map((entry) {
          final index = entry.key;
          final medicine = entry.value;
          final times = _settings.calculateReminderTimes(
            timing: medicine.timing,
            frequency: medicine.frequency,
          );

          return Column(
            children: [
              if (index > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
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
                            medicine.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${medicine.dosage} ${medicine.unit} · ${medicine.timing} · ${medicine.frequency}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: times.map((time) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.successLight,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.success.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.alarm,
                                      size: 14,
                                      color: AppColors.success,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatDateTime(time),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: EdgeInsets.only(
        left: AppDimensions.pagePadding,
        right: AppDimensions.pagePadding,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSaving
              ? null
              : widget.medicines.isEmpty
              ? _saveSettingsOnly
              : _saveAndCreateReminders,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle),
                    const SizedBox(width: 8),
                    Text(
                      widget.medicines.isEmpty ? '儲存設定' : '確認並建立提醒',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDateTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
