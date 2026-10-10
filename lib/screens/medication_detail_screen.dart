import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import '../models/medication_model.dart';

class MedicationDetailScreen extends StatefulWidget {
  final medicine medication;
  final Function(medicine) onUpdate;
  final Function() onDelete;

  const MedicationDetailScreen({
    super.key,
    required this.medication,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  late medicine _editedMedication;
  late List<DateTime> _timesOfDays; 
  final _formKey = GlobalKey<FormState>();

  // 選項列表
  final List<String> frequencyOptions = ['每天1次', '每天2次', '每天3次', '每天4次', '隔日1次', '每週1次', '每周1次', '每周2次', '其他'];
  final List<String> routeOptions = ['口服', '外用', '注射', '吸入', '點眼', '栓劑', '點滴', '其他'];
  final List<String> mealSessionOptions = ['不限', '早餐', '午餐', '晚餐', '睡前'];
  final List<String> mealTimingOptions = ['飯前', '飯後', '隨餐', '空腹', '不限'];
  final List<String> unitOptions = ['顆', '粒', '錠', '包', 'ml', 'mg', '毫升', '克', '片', '次'];

  // 暫存劑量數字部分，解決 'int' is not a subtype of 'String' 的潛在問題
  late String _dosageNumString;
  late String _selectedMealSession;
  late String _selectedMealTiming;

  String get _currentInstruction => _selectedMealSession == '不限'
      ? _selectedMealTiming
      : '$_selectedMealSession$_selectedMealTiming';

  @override
  void initState() {
    super.initState();
    _editedMedication = widget.medication.copyWith();
    _timesOfDays = List.from(_editedMedication.times_of_day_list);
    _dosageNumString = _editedMedication.total_pills.toString();
    _adjustTimeList(_editedMedication.frequency);

    // 解析已存的 instruction 拆成餐次＋時機
    final raw = _editedMedication.instruction;
    final session = mealSessionOptions.firstWhere(
      (s) => s != '不限' && raw.startsWith(s),
      orElse: () => '不限',
    );
    _selectedMealSession = session;
    final timingPart = session != '不限' ? raw.replaceFirst(session, '') : raw;
    _selectedMealTiming = mealTimingOptions.contains(timingPart) ? timingPart : '飯後';
  }
  
  // 根據頻率調整時間點列表的長度 
  void _adjustTimeList(String? newFrequency) {
    if (newFrequency == null) return;
    
    int targetCount = 1; 
    if (newFrequency.contains('1次')) {
      targetCount = 1;
    } else if (newFrequency.contains('2次')) {
      targetCount = 2;
    } else if (newFrequency.contains('3次')) {
      targetCount = 3;
    } else {
      targetCount = 1; 
    }
    
    if (_timesOfDays.length != targetCount) {
      setState(() {
        if (_timesOfDays.length > targetCount) {
          _timesOfDays.removeRange(targetCount, _timesOfDays.length);
        } else if (_timesOfDays.length < targetCount) {
          int needed = targetCount - _timesOfDays.length;
          for (int i = 0; i < needed; i++) {
            // 新增一個預設時間點
            int defaultHour = 8;
            if (_timesOfDays.length == 1) defaultHour = 12; 
            if (_timesOfDays.length == 2) defaultHour = 18; 

            _timesOfDays.add(DateTime.now().copyWith(
              hour: defaultHour,
              minute: 0,
              second: 0,
              millisecond: 0,
              microsecond: 0,
            ));
          }
        }
      });
    }
  }

  // 彈出時間選擇器並更新列表中的特定時間
  Future<void> _selectTime(BuildContext context, int index) async {
    final initialTime = TimeOfDay.fromDateTime(_timesOfDays[index]);
    
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _timesOfDays[index] = DateTime.now().copyWith(
          hour: picked.hour,
          minute: picked.minute,
          second: 0,
          millisecond: 0,
          microsecond: 0,
        );
      });
    }
  }
  
  // 構建時間點選擇欄位
  Widget _buildTimePicker(BuildContext context, int index) {
    String formattedTime = 
      '${_timesOfDays[index].hour.toString().padLeft(2, '0')}:${_timesOfDays[index].minute.toString().padLeft(2, '0')}';
      
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _selectTime(context, index),
        child: InputDecorator(
          decoration: InputDecoration(
            // 修正：將標籤改回您圖中的 "服藥時間 X"，而不是通用的 "提醒用藥時間"
            labelText: '服藥時間 ${index + 1}', 
            prefixIcon: const Icon(Icons.access_time, color: AppColors.primary),
            border: const OutlineInputBorder(
               borderRadius: BorderRadius.all(Radius.circular(10.0)),
            ),
          ),
          child: Text(
            formattedTime,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }

  // ============== 通用 UI 函數 (保持一致的圓角樣式) ==============

  Widget _buildTextField({
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? initialValue,
    String? Function(String?)? validator,
    required void Function(String?) onSaved,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        validator: validator,
        onSaved: onSaved,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.primary),
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), 
          border: const OutlineInputBorder(
             borderRadius: BorderRadius.all(Radius.circular(10.0)), 
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required List<String> items,
    required String? initialValue,
    required void Function(String?) onSaved,
    void Function(String?)? onChanged,
  }) {
    final safeValue = (initialValue != null && items.contains(initialValue))
        ? initialValue
        : items.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: safeValue,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.primary),
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16).copyWith(right: 0), 
          border: const OutlineInputBorder(
             borderRadius: BorderRadius.all(Radius.circular(10.0)), 
          ),
        ),
        items: items.map((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(value, style: const TextStyle(fontSize: 16)),
          );
        }).toList(),
        onChanged: (val) {
          if (onChanged != null) onChanged(val);
          if (label.contains('頻率')) {
            setState(() {
              _editedMedication = _editedMedication.copyWith(frequency: val ?? '每天1次');
              _adjustTimeList(val);
            });
          }
        },
        onSaved: onSaved,
        validator: (value) => value == null ? '請選擇${label.substring(0, 2)}' : null,
        isExpanded: true, 
      ),
    );
  }

  Widget _buildOptionalTextField({
    required String label,
    required IconData icon,
    String? initialValue,
    required void Function(String?) onSaved,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: initialValue,
            onSaved: onSaved,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '選填',
              hintStyle: const TextStyle(color: AppColors.textHint),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============== 儲存和刪除邏輯 ==============

  void _saveChanges() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      // 1. 重新計算 dosage 字串和 total_pills
      final String finalDosage = '$_dosageNumString ${_editedMedication.unit}';
      final int finalPills = int.tryParse(_dosageNumString) ?? 0;
      final newTimesStatus = List<bool>.filled(_timesOfDays.length, false);

      // 2. 創建更新後的 medication 物件 
      final updatedMedication = _editedMedication.copyWith(
        dosage: finalDosage,
        total_pills: finalPills,
        times_of_day_list: _timesOfDays,
        times_status: newTimesStatus,
        instruction: _currentInstruction,
      );

      widget.onUpdate(updatedMedication);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDelete() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('確認刪除'),
          content: Text('您確定要刪除藥品 「${_editedMedication.name}」 嗎？此操作不可恢復。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('刪除'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      widget.onDelete();
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }


  // ============== 主要 Build 函數 (移除黃色方塊和紅色按鈕) ==============
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('用藥詳情', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            tooltip: '刪除藥品',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 1. 用藥名稱
                _buildTextField(
                  label: '用藥名稱',
                  icon: Icons.local_hospital,
                  initialValue: _editedMedication.name,
                  validator: (value) => value == null || value.isEmpty ? '請輸入用藥名稱' : null,
                  onSaved: (val) => _editedMedication = _editedMedication.copyWith(name: val ?? _editedMedication.name),
                ),

                // 2. 每次服用劑量 & 單位
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildTextField(
                        label: '每次服用劑量', 
                        icon: Icons.format_list_numbered,
                        keyboardType: TextInputType.number,
                        initialValue: _dosageNumString, 
                        validator: (value) => value == null || int.tryParse(value) == null ? '請輸入有效數字' : null,
                        onSaved: (val) {
                          _dosageNumString = val ?? '0';
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: _buildDropdownField(
                        label: '單位',
                        icon: Icons.archive,
                        items: unitOptions,
                        initialValue: _editedMedication.unit,
                        onSaved: (val) {
                          _editedMedication = _editedMedication.copyWith(unit: val);
                        },
                      ),
                    ),
                  ],
                ),

                // 服用頻率
                _buildDropdownField(
                  label: '服用頻率',
                  icon: Icons.repeat,
                  items: frequencyOptions,
                  initialValue: _editedMedication.frequency,
                  onSaved: (val) => _editedMedication = _editedMedication.copyWith(frequency: val ?? '每天1次'),
                ),
                
                // 5. 用藥提醒開關
                Container(
                  margin: const EdgeInsets.only(bottom: 16, top: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SwitchListTile(
                    secondary: Icon(
                      Icons.notifications_active_rounded,
                      color: _editedMedication.reminderEnabled
                          ? AppColors.primary
                          : Colors.grey,
                    ),
                    title: const Text(
                      '啟用用藥提醒',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      _editedMedication.reminderEnabled
                          ? '服藥時間到會收到通知提醒'
                          : '已關閉此藥物的提醒',
                      style: TextStyle(
                        fontSize: 12,
                        color: _editedMedication.reminderEnabled
                            ? AppColors.textSecondary
                            : Colors.grey,
                      ),
                    ),
                    value: _editedMedication.reminderEnabled,
                    onChanged: (value) {
                      setState(() {
                        _editedMedication = _editedMedication.copyWith(
                          reminderEnabled: value,
                        );
                      });
                    },
                    activeColor: AppColors.primary,
                  ),
                ),

                // 6. 動態時間點輸入欄位
                if (_editedMedication.reminderEnabled) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0, top: 8.0),
                    child: Text(
                      '提醒用藥時間',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),

                  ..._timesOfDays.asMap().entries.map((entry) {
                    int index = entry.key;
                    return _buildTimePicker(context, index);
                  }),
                ],

                // 6. 服用指示（餐次 + 時機）
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildDropdownField(
                        label: '餐次',
                        icon: Icons.restaurant,
                        items: mealSessionOptions,
                        initialValue: _selectedMealSession,
                        onSaved: (_) {},
                        onChanged: (val) => setState(() => _selectedMealSession = val ?? '不限'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDropdownField(
                        label: '時機',
                        icon: Icons.access_time,
                        items: mealTimingOptions,
                        initialValue: _selectedMealTiming,
                        onSaved: (_) {},
                        onChanged: (val) => setState(() => _selectedMealTiming = val ?? '飯後'),
                      ),
                    ),
                  ],
                ),

                // 7. 給藥途徑
                _buildDropdownField(
                  label: '給藥途徑',
                  icon: Icons.route,
                  items: routeOptions,
                  initialValue: _editedMedication.route,
                  onSaved: (val) => _editedMedication = _editedMedication.copyWith(route: val ?? '口服'),
                ),

                // 持續天數
                _buildOptionalTextField(
                  label: '持續天數',
                  icon: Icons.calendar_today_outlined,
                  initialValue: _editedMedication.duration_days > 0 ? '${_editedMedication.duration_days}' : null,
                  onSaved: (val) {
                    final days = int.tryParse(val ?? '');
                    if (days != null && days > 0) {
                      _editedMedication = _editedMedication.copyWith(
                        duration_days: days,
                        remaining_days: days,
                      );
                    }
                  },
                ),

                // 8. 選填資訊
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 12),
                  child: Text('選填資訊', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
                ),
                _buildOptionalTextField(
                  label: '來源（藥局或醫院名稱）',
                  icon: Icons.local_pharmacy_outlined,
                  initialValue: _editedMedication.source,
                  onSaved: (val) => _editedMedication = _editedMedication.copyWith(source: val?.isEmpty == true ? null : val),
                ),
                _buildOptionalTextField(
                  label: '臨床用途',
                  icon: Icons.medical_information_outlined,
                  initialValue: _editedMedication.clinicalUse,
                  onSaved: (val) => _editedMedication = _editedMedication.copyWith(clinicalUse: val?.isEmpty == true ? null : val),
                ),
                _buildOptionalTextField(
                  label: '副作用',
                  icon: Icons.warning_amber_outlined,
                  initialValue: _editedMedication.sideEffects,
                  onSaved: (val) => _editedMedication = _editedMedication.copyWith(sideEffects: val?.isEmpty == true ? null : val),
                ),
                _buildOptionalTextField(
                  label: '注意事項',
                  icon: Icons.info_outline,
                  initialValue: _editedMedication.precautions,
                  onSaved: (val) => _editedMedication = _editedMedication.copyWith(precautions: val?.isEmpty == true ? null : val),
                ),
                _buildOptionalTextField(
                  label: '儲存方式',
                  icon: Icons.inventory_2_outlined,
                  initialValue: _editedMedication.storageMethod,
                  onSaved: (val) => _editedMedication = _editedMedication.copyWith(storageMethod: val?.isEmpty == true ? null : val),
                ),
                _buildOptionalTextField(
                  label: '藥品外觀',
                  icon: Icons.visibility_outlined,
                  initialValue: _editedMedication.appearance,
                  onSaved: (val) => _editedMedication = _editedMedication.copyWith(appearance: val?.isEmpty == true ? null : val),
                ),

                const SizedBox(height: 10),

                // 儲存編輯按鈕
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveChanges,
                    icon: const Icon(Icons.save, size: 28),
                    label: const Text('儲存編輯'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: AppColors.primary, 
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 5,
                    ),
                  ),
                ),
                const SizedBox(height: 15), // 確保底部有足夠間距
              ],
            ),
          ),
        ),
      ),
    );
  }
}