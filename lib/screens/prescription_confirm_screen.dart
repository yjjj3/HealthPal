import '../models/medication_dose.dart';
import 'package:firebase_auth/firebase_auth.dart';
// lib/screens/prescription_confirm_screen.dart
// 處方箋辨識結果確認頁面

import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../models/prescription_model.dart';
import '../services/prescription_scan_service.dart';
import '../services/notification_service.dart';

class PrescriptionConfirmScreen extends StatefulWidget {
  final List<PrescriptionMedicine> medicines;
  final Map<String, dynamic>? hospitalInfo;
  final List<File> imageFiles;

  const PrescriptionConfirmScreen({
    super.key,
    required this.medicines,
    this.hospitalInfo,
    required this.imageFiles,
  });

  @override
  State<PrescriptionConfirmScreen> createState() =>
      _PrescriptionConfirmScreenState();
}

class _PrescriptionConfirmScreenState extends State<PrescriptionConfirmScreen> {
  final PrescriptionScanService _scanService = PrescriptionScanService();
  late List<PrescriptionMedicine> _medicines;
  final Map<int, String> _sources = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _medicines = List.from(widget.medicines);
    // 若 AI 有辨識到醫院名，預填給每個藥品
    final hospitalName = widget.hospitalInfo?['hospitalName'] as String?;
    if (hospitalName != null) {
      for (int i = 0; i < widget.medicines.length; i++) {
        _sources[i] = hospitalName;
      }
    }
  }

  // ============================================================
  // 編輯藥品
  // ============================================================
  void _editMedicine(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MedicineEditSheet(
        medicine: _medicines[index],
        initialSource: _sources[index],
        onSave: (updatedMedicine, updatedSource) {
          setState(() {
            _medicines[index] = updatedMedicine;
            if (updatedSource != null) {
              _sources[index] = updatedSource;
            } else {
              _sources.remove(index);
            }
          });
        },
      ),
    );
  }

  // ============================================================
  // 刪除藥品
  // ============================================================
  num _calcDisplayQty(PrescriptionMedicine med) => med.totalQuantity;

  void _deleteMedicine(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除「${_medicines[index].name}」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _medicines.removeAt(index);
              });
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 直接儲存藥品（使用已儲存或預設用餐時間）
  // ============================================================
  Future<void> _proceedToMealTimeSettings() async {
    if (_medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('請至少保留一個藥品'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    setState(() => _isSaving = true);

    try {
      // 載入已儲存設定，若無則使用預設值（早餐7:30/午餐12:00/晚餐18:30）
      final settings = await _scanService.loadMealTimeSettings();
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;

      // 轉換並儲存藥品
      final medications = await _scanService.convertToMedications(
        _medicines,
        settings,
        sources: _sources,
      );
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      await _scanService.saveMedications(medications);
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;

      // 排程提醒通知
      try {
        final notificationService = NotificationService();
        for (final med in medications) {
          for (int j = 0; j < med.times_of_day_list.length; j++) {
            final scheduledTime = med.times_of_day_list[j];
            final now = DateTime.now();
            var reminderTime = DateTime(now.year, now.month, now.day,
                scheduledTime.hour, scheduledTime.minute);
            if (reminderTime.isBefore(now)) {
              reminderTime = reminderTime.add(const Duration(days: 1));
            }
            await notificationService.scheduleMedicationReminder(
              id: med.name.hashCode + j,
              medicineName: med.name,
              dosage: med.dosage,
              scheduledTime: reminderTime,
              medicationId: '${med.name}_$j',
            );
          }
        }
      } catch (e) {
        debugPrint('排程通知失敗（不影響儲存）: $e');
      }

      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
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
          ),
        );
      }
    } catch (e) {
      debugPrint('儲存失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '確認辨識結果',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0.5,
      ),
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // 醫院資訊（如果有）
          if (widget.hospitalInfo != null) _buildHospitalInfo(),

          // 藥品列表
          Expanded(
            child: _medicines.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(AppDimensions.pagePadding),
                    itemCount: _medicines.length,
                    itemBuilder: (context, index) {
                      return _buildMedicineCard(_medicines[index], index);
                    },
                  ),
          ),

          // 底部按鈕
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildHospitalInfo() {
    final info = widget.hospitalInfo!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: AppColors.primaryLight,
      child: Row(
        children: [
          const Icon(
            Icons.local_hospital,
            color: AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info['hospitalName'] as String? ?? '未知醫院',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (info['departmentName'] != null ||
                    info['doctorName'] != null)
                  Text(
                    [
                      if (info['departmentName'] != null)
                        info['departmentName'] as String,
                      if (info['doctorName'] != null)
                        '${info['doctorName']} 醫師',
                    ].join(' - '),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (info['followUpDate'] != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.event,
                    color: AppColors.warning,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '回診: ${info['followUpDate']}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.medication_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '沒有辨識到藥品',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '請嘗試重新拍攝處方箋',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineCard(PrescriptionMedicine medicine, int index) {
    final confidenceColor = medicine.confidence >= 0.8
        ? AppColors.success
        : medicine.confidence >= 0.5
            ? AppColors.warning
            : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
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
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (medicine.englishName != null)
                        Text(
                          medicine.englishName!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                // 信心度指示
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: confidenceColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: confidenceColor),
                  ),
                  child: Text(
                    '${(medicine.confidence * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: confidenceColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 藥品資訊
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 基本資訊
                Row(
                  children: [
                    _buildInfoChip(
                      Icons.medication,
                      '${medicine.dosage} ${medicine.unit}',
                      AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    _buildInfoChip(
                      Icons.schedule,
                      medicine.frequency,
                      AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    _buildInfoChip(
                      Icons.restaurant,
                      medicine.timing,
                      const Color(0xFF9C27B0),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 天數和數量
                Row(
                  children: [
                    _buildInfoItem('天數', '${medicine.durationDays} 天'),
                    const SizedBox(width: 24),
                    _buildInfoItem('總量', '${_calcDisplayQty(medicine)} ${medicine.unit}'),
                    if (medicine.drugCode.isNotEmpty) ...[
                      const SizedBox(width: 24),
                      _buildInfoItem('代碼', medicine.drugCode),
                    ],
                  ],
                ),

                // 臨床用途
                if (medicine.clinicalUse != null) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          medicine.clinicalUse!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // 注意事項
                if (medicine.precautions != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            medicine.precautions!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 操作按鈕
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _editMedicine(index),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('編輯'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _deleteMedicine(index),
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('刪除'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 統計資訊
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.medication,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '共 ${_medicines.length} 種藥品',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 按鈕
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: const Text('重新掃描'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed:
                      _medicines.isNotEmpty ? _proceedToMealTimeSettings : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, size: 20),
                            SizedBox(width: 6),
                            Text(
                              '確認並儲存',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 藥品編輯 Bottom Sheet
// ============================================================
class _MedicineEditSheet extends StatefulWidget {
  final PrescriptionMedicine medicine;
  final Function(PrescriptionMedicine, String?) onSave;
  final String? initialSource;

  const _MedicineEditSheet({
    required this.medicine,
    required this.onSave,
    this.initialSource,
  });

  @override
  State<_MedicineEditSheet> createState() => _MedicineEditSheetState();
}

class _MedicineEditSheetState extends State<_MedicineEditSheet> {
  late TextEditingController _nameController;
  late TextEditingController _dosageController;
  late TextEditingController _totalQuantityController;
  late TextEditingController _durationController;
  late TextEditingController _sourceController;
  late TextEditingController _clinicalUseController;
  late TextEditingController _sideEffectsController;
  late TextEditingController _precautionsController;
  late TextEditingController _storageMethodController;
  late TextEditingController _appearanceController;

  late String _selectedUnit;
  late String _selectedFrequency;
  late String _selectedMealSession;
  late String _selectedMealTiming;
  late String _selectedRoute;
  late DateTime _selectedStartDate;

  String get _selectedTiming => _selectedMealSession == '不限'
      ? _selectedMealTiming
      : '$_selectedMealSession$_selectedMealTiming';

  final List<String> _mealSessions = ['不限', '早餐', '午餐', '晚餐', '睡前'];
  final List<String> _mealTimings = ['請確認', '飯前', '飯後', '隨餐', '空腹', '不限'];
  final List<String> _routes = ['請確認', '口服', '外用', '注射', '吸入', '點眼', '栓劑', '點滴', '其他'];

  final List<String> _units = ['請確認', '顆', '粒', 'ml', '包', '片', '錠'];
  final List<String> _frequencies = [
    '請確認',
    '每天1次',
    '每天2次',
    '每天3次',
    '每天4次',
    '每6小時',
    '每8小時',
    '每12小時',
    '需要時服用',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.medicine.name);
    _dosageController = TextEditingController(text: widget.medicine.dosage);
    // 若 AI 有給總數量就用，否則用推算值（劑量×次數×天數）
    final aiQty = widget.medicine.totalQuantity;
    _totalQuantityController = TextEditingController(text: '$aiQty');
    _durationController =
        TextEditingController(text: '${widget.medicine.durationDays}');
    _sourceController = TextEditingController(text: widget.initialSource ?? '');
    _clinicalUseController =
        TextEditingController(text: widget.medicine.clinicalUse ?? '');
    _sideEffectsController =
        TextEditingController(text: widget.medicine.sideEffects ?? '');
    _precautionsController =
        TextEditingController(text: widget.medicine.precautions ?? '');
    _storageMethodController =
        TextEditingController(text: widget.medicine.storageMethod ?? '');
    _appearanceController =
        TextEditingController(text: widget.medicine.appearance ?? '');

    _selectedUnit = _units.contains(widget.medicine.unit)
        ? widget.medicine.unit
        : _units.first;
    _selectedFrequency = _frequencies.contains(widget.medicine.frequency)
        ? widget.medicine.frequency
        : _frequencies.first;
    // 解析 AI 回傳的 timing，拆成餐次 + 時機
    final rawTiming = widget.medicine.timing;
    final sessionMatch = _mealSessions.firstWhere(
      (s) => s != '不限' && rawTiming.startsWith(s),
      orElse: () => '不限',
    );
    _selectedMealSession = sessionMatch;
    final timingPart = sessionMatch != '不限'
        ? rawTiming.replaceFirst(sessionMatch, '')
        : rawTiming;
    _selectedMealTiming = _mealTimings.contains(timingPart) ? timingPart : '請確認';
    _selectedRoute = _routes.contains(widget.medicine.route) ? widget.medicine.route : '請確認';
    _selectedStartDate = widget.medicine.startDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _totalQuantityController.dispose();
    _durationController.dispose();
    _sourceController.dispose();
    _clinicalUseController.dispose();
    _sideEffectsController.dispose();
    _precautionsController.dispose();
    _storageMethodController.dispose();
    _appearanceController.dispose();
    super.dispose();
  }

  void _save() {
    final doseError = MedicationDose.validate(_dosageController.text);
    final duration = int.tryParse(_durationController.text.trim());
    final quantity = num.tryParse(_totalQuantityController.text.trim());
    if (doseError != null || _nameController.text.trim().isEmpty || duration == null || duration < 0 || quantity == null || !quantity.isFinite || quantity < 0 ||
      [_selectedUnit, _selectedFrequency, _selectedMealTiming, _selectedRoute].contains('請確認')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(doseError ?? '請確認名稱、單位、頻率、時機、途徑及數量。')));
      return;
    }
    final updatedMedicine = widget.medicine.copyWith(
      name: _nameController.text.trim(),
      dosage: _dosageController.text.trim(),
      unit: _selectedUnit,
      frequency: _selectedFrequency,
      timing: _selectedTiming,
      durationDays: duration,
      totalQuantity: quantity,
      clinicalUse: _clinicalUseController.text.trim().isEmpty
          ? null
          : _clinicalUseController.text.trim(),
      sideEffects: _sideEffectsController.text.trim().isEmpty
          ? null
          : _sideEffectsController.text.trim(),
      precautions: _precautionsController.text.trim().isEmpty
          ? null
          : _precautionsController.text.trim(),
      storageMethod: _storageMethodController.text.trim().isEmpty
          ? null
          : _storageMethodController.text.trim(),
      appearance: _appearanceController.text.trim().isEmpty
          ? null
          : _appearanceController.text.trim(),
      route: _selectedRoute,
      startDate: _selectedStartDate,
    );

    final source = _sourceController.text.trim().isEmpty ? null : _sourceController.text.trim();
    widget.onSave(updatedMedicine, source);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖曳條
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 標題
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  '編輯藥品資訊',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 表單
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 藥品名稱
                  _buildTextField(
                    label: '藥品名稱',
                    controller: _nameController,
                  ),
                  const SizedBox(height: 16),

                  // 劑量和單位
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          label: '每次劑量',
                          controller: _dosageController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDropdown(
                          label: '單位',
                          value: _selectedUnit,
                          items: _units,
                          onChanged: (value) {
                            setState(() => _selectedUnit = value!);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 頻率
                  _buildDropdown(
                    label: '服用頻率',
                    value: _selectedFrequency,
                    items: _frequencies,
                    onChanged: (value) {
                      setState(() => _selectedFrequency = value!);
                    },
                  ),
                  const SizedBox(height: 16),

                  // 服用時機（餐次 + 時機）
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown(
                          label: '餐次',
                          value: _selectedMealSession,
                          items: _mealSessions,
                          onChanged: (value) {
                            setState(() => _selectedMealSession = value!);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDropdown(
                          label: '時機',
                          value: _selectedMealTiming,
                          items: _mealTimings,
                          onChanged: (value) {
                            setState(() => _selectedMealTiming = value!);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 給藥途徑
                  _buildDropdown(
                    label: '給藥途徑',
                    value: _selectedRoute,
                    items: _routes,
                    onChanged: (value) {
                      setState(() => _selectedRoute = value!);
                    },
                  ),
                  const SizedBox(height: 16),

                  // 開始日期
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedStartDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setState(() => _selectedStartDate = picked);
                    },
                    child: AbsorbPointer(
                      child: _buildTextField(
                        label: '開始日期',
                        controller: TextEditingController(
                          text: '${_selectedStartDate.year}/${_selectedStartDate.month.toString().padLeft(2,'0')}/${_selectedStartDate.day.toString().padLeft(2,'0')}',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 天數和總量
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          label: '天數',
                          controller: _durationController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          label: '總數量（可修改）',
                          controller: _totalQuantityController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 來源
                  _buildTextField(
                    label: '來源（藥局或醫院名稱）',
                    controller: _sourceController,
                  ),
                  const SizedBox(height: 16),

                  // 臨床用途
                  _buildTextField(
                    label: '臨床用途',
                    controller: _clinicalUseController,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),

                  // 副作用
                  _buildTextField(
                    label: '副作用',
                    controller: _sideEffectsController,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),

                  // 注意事項
                  _buildTextField(
                    label: '注意事項',
                    controller: _precautionsController,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),

                  // 儲存方式
                  _buildTextField(
                    label: '儲存方式',
                    controller: _storageMethodController,
                  ),
                  const SizedBox(height: 16),

                  // 藥品外觀
                  _buildTextField(
                    label: '藥品外觀',
                    controller: _appearanceController,
                  ),
                ],
              ),
            ),
          ),

          // 儲存按鈕
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
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
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '儲存修改',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(item),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
