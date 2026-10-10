import '../theme/app_colors.dart';
// lib/screens/medication_add_screen.dart

import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import 'package:intl/intl.dart'; // 💡 新增：確保 intl 引用，即使在這個檔案中未使用 DateFormat


class MedicationAddScreen extends StatefulWidget {
  // 由於 MedicationScreen 是透過 Navigator.push 接收結果，我們不需要 onSave 參數。
  // 如果要與之前的版本兼容，可以保留，但為了簡潔，我們專注於返回 medicine 物件。
  const MedicationAddScreen({super.key}); 

  @override
  State<MedicationAddScreen> createState() => _MedicationAddScreenState();
}

class _MedicationAddScreenState extends State<MedicationAddScreen> {
  final _formKey = GlobalKey<FormState>();

  // --- 狀態變數 ---
  String _name = '';
  String _currentDose = '1';
  String _currentUnit = '顆';
  String _frequency = '每天1次';
  String _mealSession = '不限';
  String _mealTiming = '飯後';
  String _route = '口服';
  String? _source;
  String? _clinicalUse;
  String? _sideEffects;
  String? _precautions;
  String? _storageMethod;
  String? _appearance;

  String get _instruction => _mealSession == '不限'
      ? _mealTiming
      : '$_mealSession$_mealTiming';
  int _durationDays = 28; // 預設用藥持續天數
  DateTime _startDate = DateTime.now(); // 預設開始日期
  
  // 核心：用於動態生成時間欄位
  List<DateTime> _reminderTimes = [
    DateTime.now().copyWith(hour: 8, minute: 0, second: 0, millisecond: 0, microsecond: 0),
  ];
  
  // 頻率對應的每日次數，用於動態生成時間欄位
  int _timesPerDay = 1;

  // --- 選項列表 (與 detail 頁面保持一致) ---
  final List<String> unitOptions = [
    '顆', '粒', '錠', '包', 'ml', 'mg', 'μg', '單位', 'cc',
  ];
  final List<String> routeOptions = ['口服', '外用', '注射', '吸入', '栓劑', '點滴']; // 將 usageOptions 改名為 routeOptions
  final List<String> mealSessionOptions = ['不限', '早餐', '午餐', '晚餐', '睡前'];
  final List<String> mealTimingOptions = ['飯前', '飯後', '隨餐', '空腹', '不限'];
  final List<String> frequencyOptions = ['每天1次', '每天2次', '每天3次', '每天4次', '隔日1次', '每週1次']; 

  @override
  void initState() {
    super.initState();
    _updateTimesPerDay(_frequency, updateState: false);
    _syncReminderTimesLength();
  }

  // -------------------------
  // --- 時間與頻率同步邏輯 ---
  // -------------------------

  void _updateTimesPerDay(String frequency, {bool updateState = true}) {
    if (updateState) setState(() {
      _frequency = frequency;
      
      final match = RegExp(r'每天(\d+)次').firstMatch(frequency);
      if (match != null && match.group(1) != null) {
        _timesPerDay = int.tryParse(match.group(1)!) ?? 1;
      } else {
        // 對於 '隔日1次', '每週1次' 等，時間數固定為 1
        _timesPerDay = 1;
      }
      
      _syncReminderTimesLength();
    });
  }
  
  // 確保時間列表的長度與 _timesPerDay 一致
  void _syncReminderTimesLength() {
    final now = DateTime.now();
    // 儲存舊的時間，以防列表縮短後再次增長時保留設定過的時間
    final oldTimes = List<DateTime>.from(_reminderTimes);

    if (oldTimes.length > _timesPerDay) {
      // 減少時間欄位
      _reminderTimes = oldTimes.sublist(0, _timesPerDay);
    } else if (oldTimes.length < _timesPerDay) {
      // 增加時間欄位，用預設時間初始化
      _reminderTimes = List<DateTime>.from(oldTimes); // 複製舊的
      int diff = _timesPerDay - _reminderTimes.length;
      for (int i = 0; i < diff; i++) {
        // 初始化為當天 8:00, 12:00, 18:00... (嘗試更合理的預設間隔)
        int defaultHour;
        if (_timesPerDay == 2) {
            defaultHour = (i == 0) ? 8 : 18; // 8:00, 18:00
        } else if (_timesPerDay == 3) {
            defaultHour = (i == 0) ? 8 : (i == 1) ? 14 : 20; // 8:00, 14:00, 20:00
        } else {
            // 預設從 8 點開始，間隔 4 小時
            defaultHour = 8 + (_reminderTimes.length + i) * 4; 
        }
        
        defaultHour = defaultHour % 24; 
        
        _reminderTimes.add(DateTime(now.year, now.month, now.day, defaultHour, 0, 0, 0, 0));
      }
    }
    // 如果 _timesPerDay=1，確保時間列表只有一個元素
    if (_timesPerDay == 1 && _reminderTimes.isEmpty) {
        _reminderTimes.add(DateTime.now().copyWith(hour: 8, minute: 0, second: 0, millisecond: 0, microsecond: 0));
    }
  }


  Future<void> _selectTime(BuildContext context, int index) async {
    final initialTime = TimeOfDay.fromDateTime(_reminderTimes[index]);

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: AppColors.primary,
            colorScheme: const ColorScheme.light(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        // 只更新 List<DateTime> 中的時間部分
        _reminderTimes[index] = DateTime(
          _reminderTimes[index].year,
          _reminderTimes[index].month,
          _reminderTimes[index].day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }
  
  // 選擇日期的輔助函數
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (pickedDate != null && pickedDate != _startDate) {
      setState(() {
        _startDate = pickedDate;
      });
    }
  }


  // -------------------------
  // --- 提交與返回邏輯 ---
  // -------------------------
  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      // 🚨 確保 _reminderTimes 列表在保存時是正確長度
      _syncReminderTimesLength();

      // 將劑量字串轉換為整數 (total_pills, 單次用藥數量)
      final int totalPills = int.tryParse(_currentDose) ?? 1;

      // 構建新的 medicine 物件
      final newMedication = medicine(
        // 核心欄位
        name: _name,
        dosage: '$_currentDose $_currentUnit',
        unit: _currentUnit,
        total_supply: 0, // 不再使用庫存功能
        total_pills: totalPills, // 每次服用數量
        remaining_days: _durationDays, // 使用持續天數作為剩餘天數

        // 頻率與指示
        frequency: _frequency,
        instruction: _instruction,
        route: _route,

        // 日期與狀態
        start_date: _startDate,
        duration_days: _durationDays,

        // 時間列表
        times_of_day_list: _reminderTimes,
        times_status: List<bool>.filled(_reminderTimes.length, false),

        // 選填資訊
        source: _source,
        clinicalUse: _clinicalUse,
        sideEffects: _sideEffects,
        precautions: _precautions,
        storageMethod: _storageMethod,
        appearance: _appearance,
      );
      
      // 返回給 MedicationScreen
      Navigator.pop(context, newMedication);
    }
  }

  // -------------------------
  // --- UI 構建方法 (詳細) ---
  // -------------------------

  Widget _buildTextField({
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? initialValue,
    String? Function(String?)? validator,
    required void Function(String?) onSaved, // ✅ 修正：onSaved 參數為 String?
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
          border: const OutlineInputBorder(),
        ),
      ),
    );
}

  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required List<T> items,
    required IconData icon,
    required void Function(T?) onChanged,
  }) {
    final safeValue = items.contains(value) ? value : items.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<T>(
        value: safeValue,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.primary),
          border: const OutlineInputBorder(),
        ),
        items: items.map((T item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Text(item.toString()),
          );
        }).toList(),
        onChanged: onChanged,
        // onSaved 使用 onChanged 的值，因為這是 DropdownFormField
        onSaved: (val) {
            if (val != null) {
                // 這裡我們假設 onChanged 已經更新了狀態變數
            }
        },
      ),
    );
  }
  
  // 動態生成時間輸入欄位
  Widget _buildTimeFields() {
    return Column(
      children: List.generate(_timesPerDay, (index) {
        if (index >= _reminderTimes.length) return const SizedBox.shrink();

        final time = _reminderTimes[index];
        final timeString = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        
        return GestureDetector(
          onTap: () => _selectTime(context, index),
          child: AbsorbPointer( // 禁用鍵盤輸入，只能點擊選擇
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                key: ValueKey('timeField$index'),
                decoration: InputDecoration(
                  labelText: '服藥時間 ${index + 1}',
                  prefixIcon: const Icon(
                    Icons.access_time,
                    color: AppColors.primary,
                  ),
                  suffixIcon: const Icon(
                    Icons.arrow_drop_down,
                    color: AppColors.primary,
                  ),
                  border: const OutlineInputBorder(),
                ),
                controller: TextEditingController(text: timeString),
              ),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 1,
        backgroundColor: Colors.white,
        title: const Text(
          '新增用藥', 
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.primary),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // 1. 用藥名稱
              _buildTextField(
                label: '用藥名稱',
                icon: Icons.medication_rounded,
                onSaved: (val) => _name = val ?? '',
                validator: (v) => v!.isEmpty ? '名稱不能為空' : null,
              ),

              // 2. 每次服用劑量 & 單位
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: _currentDose,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        onSaved: (val) => _currentDose = val ?? '1',
                        decoration: const InputDecoration(
                          labelText: '每次服用劑量 (例如：1)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty || int.tryParse(value) == null || int.parse(value)! <= 0) {
                            return '請輸入有效的正整數劑量';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        value: _currentUnit,
                        decoration: const InputDecoration(
                          labelText: '單位',
                          border: OutlineInputBorder(),
                        ),
                        items: unitOptions.map((String item) {
                          return DropdownMenuItem<String>(
                            value: item,
                            child: Text(item),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() => _currentUnit = newValue);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // 3. 服藥頻率
              _buildDropdownField<String>(
                label: '服藥頻率',
                value: _frequency,
                items: frequencyOptions,
                icon: Icons.schedule,
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    _updateTimesPerDay(newValue);
                  }
                },
              ),
              
              // 5. 服藥時間 (動態欄位)
              _buildTimeFields(),
              
              // 6. 服用指示（餐次 + 時機）
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildDropdownField<String>(
                      label: '餐次',
                      value: _mealSession,
                      items: mealSessionOptions,
                      icon: Icons.restaurant,
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() => _mealSession = newValue);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildDropdownField<String>(
                      label: '時機',
                      value: _mealTiming,
                      items: mealTimingOptions,
                      icon: Icons.access_time,
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() => _mealTiming = newValue);
                        }
                      },
                    ),
                  ),
                ],
              ),
              
              // 7. 給藥途徑
              _buildDropdownField<String>(
                label: '給藥途徑',
                value: _route,
                items: routeOptions,
                icon: Icons.add_box_outlined,
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _route = newValue);
                  }
                },
              ),
              
              // 8. 開始日期 (DatePicker)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GestureDetector(
                  onTap: () => _selectDate(context),
                  child: AbsorbPointer(
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: '開始日期',
                        prefixIcon: const Icon(Icons.calendar_today, color: AppColors.primary),
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(
                        DateFormat('yyyy-MM-dd').format(_startDate),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ),
              
              // 9. 用藥持續天數
              _buildTextField(
                label: '用藥持續天數 (例如: 7)',
                icon: Icons.calendar_month,
                keyboardType: TextInputType.number,
                initialValue: _durationDays.toString(),
                onSaved: (val) => _durationDays = int.tryParse(val ?? '30') ?? 30,
                validator: (value) {
                  if (value == null || value.isEmpty || int.tryParse(value) == null || int.parse(value)! <= 0) {
                    return '請輸入有效的持續天數';
                  }
                  return null;
                },
              ),

              // 選填資訊區塊
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('選填資訊', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
              ),
              _buildTextField(
                label: '來源（藥局或醫院名稱）',
                icon: Icons.local_pharmacy_outlined,
                onSaved: (val) => _source = val?.isEmpty == true ? null : val,
              ),
              _buildTextField(
                label: '臨床用途（此藥用來治療什麼）',
                icon: Icons.medical_information_outlined,
                onSaved: (val) => _clinicalUse = val?.isEmpty == true ? null : val,
              ),
              _buildTextField(
                label: '副作用',
                icon: Icons.warning_amber_outlined,
                onSaved: (val) => _sideEffects = val?.isEmpty == true ? null : val,
              ),
              _buildTextField(
                label: '注意事項',
                icon: Icons.info_outline,
                onSaved: (val) => _precautions = val?.isEmpty == true ? null : val,
              ),
              _buildTextField(
                label: '儲存方式',
                icon: Icons.inventory_2_outlined,
                onSaved: (val) => _storageMethod = val?.isEmpty == true ? null : val,
              ),
              _buildTextField(
                label: '藥品外觀',
                icon: Icons.visibility_outlined,
                onSaved: (val) => _appearance = val?.isEmpty == true ? null : val,
              ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('新增用藥', style: TextStyle(fontSize: 18, color: Colors.white)),
                  onPressed: _submitForm,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}