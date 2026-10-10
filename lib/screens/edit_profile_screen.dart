import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'profile_screen.dart'; // 引入 UserProfile 模型

// =================================================================
// EditProfileScreen 類別
// =================================================================

class EditProfileScreen extends StatefulWidget {
  // 接收 ProfileScreen 傳入的初始資料
  final UserProfile initialUser;

  const EditProfileScreen({super.key, required this.initialUser});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

// =================================================================
// _EditProfileScreenState 狀態管理
// =================================================================

class _EditProfileScreenState extends State<EditProfileScreen> {
  // 用於表單驗證的 GlobalKey
  final _formKey = GlobalKey<FormState>();

  // 用於儲存欄位值 (初始化為傳入的初始資料)
  late String _name;
  late String _gender;
  late DateTime? _dateOfBirth;
  late String _phoneNumber;
  late String _height;
  late String _weight;
  late String _bloodType;

  // 慢性病史 - Checkbox 模式
  bool _isChronicDiseaseExpanded = false;
  final Map<String, bool> _chronicDiseases = {
    '無': false,
    '高血壓': false,
    '糖尿病': false,
    '心臟病': false,
    '氣喘': false,
    '腎臟病': false,
  };
  final List<String> _otherChronicDiseases = [];
  final TextEditingController _otherChronicDiseaseController = TextEditingController();

  // 過敏史 - Checkbox 模式
  bool _isAllergyExpanded = false;
  final Map<String, bool> _allergies = {
    '無': false,
    '花粉過敏': false,
    '塵蟎過敏': false,
    '海鮮過敏': false,
    '堅果過敏': false,
    '藥物過敏': false,
  };
  final List<String> _otherAllergies = [];
  final TextEditingController _otherAllergyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 使用傳入的初始資料來初始化 State 變數
    _name = widget.initialUser.name;
    _gender = widget.initialUser.gender;
    _dateOfBirth = widget.initialUser.dateOfBirth;
    _phoneNumber = widget.initialUser.phoneNumber;
    _height = widget.initialUser.height;
    _weight = widget.initialUser.weight;
    _bloodType = widget.initialUser.bloodType;

    // 初始化慢性病選項
    if (widget.initialUser.chronicDiseaseList.isNotEmpty) {
      for (final disease in widget.initialUser.chronicDiseaseList) {
        if (_chronicDiseases.containsKey(disease)) {
          _chronicDiseases[disease] = true;
        } else if (disease != '無') {
          _otherChronicDiseases.add(disease);
        }
      }
      // 如果有選擇任何慢性病，確保「無」是未選中的
      if (widget.initialUser.chronicDiseaseList.any((d) => d != '無')) {
        _chronicDiseases['無'] = false;
      }
    }

    // 初始化過敏史選項
    if (widget.initialUser.allergies.isNotEmpty && widget.initialUser.allergies != '無') {
      // 將逗號或頓號分隔的過敏史字串轉換為列表
      final allergyList = widget.initialUser.allergies.split(RegExp(r'[、,，]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

      for (final allergy in allergyList) {
        if (_allergies.containsKey(allergy)) {
          _allergies[allergy] = true;
        } else if (allergy != '無') {
          _otherAllergies.add(allergy);
        }
      }

      // 如果有選擇任何過敏，確保「無」是未選中的
      if (allergyList.any((a) => a != '無')) {
        _allergies['無'] = false;
      }
    } else {
      // 如果沒有過敏史或是「無」，則勾選「無」
      _allergies['無'] = true;
    }
  }

  @override
  void dispose() {
    _otherChronicDiseaseController.dispose();
    _otherAllergyController.dispose();
    super.dispose();
  }

  // 處理日期選擇器
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
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
    if (picked != null && picked != _dateOfBirth) {
      setState(() {
        _dateOfBirth = picked;
      });
    }
  }

  // 儲存表單資料的函式
  void _saveForm() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      // 從 Checkbox 和其他項目收集慢性病列表
      List<String> chronicDiseaseList = [];
      _chronicDiseases.forEach((key, value) {
        if (value) {
          chronicDiseaseList.add(key);
        }
      });
      chronicDiseaseList.addAll(_otherChronicDiseases);

      // 將慢性病列表轉換為顯示字串
      final chronicDiseaseString = chronicDiseaseList.isEmpty
          ? '無'
          : chronicDiseaseList.join('、');

      // 從 Checkbox 和其他項目收集過敏史列表
      List<String> allergyList = [];
      _allergies.forEach((key, value) {
        if (value) {
          allergyList.add(key);
        }
      });
      allergyList.addAll(_otherAllergies);

      // 將過敏史列表轉換為顯示字串
      final allergyString = allergyList.isEmpty
          ? '無'
          : allergyList.join('、');

      // 建立一個新的 UserProfile 物件，包含更新後的資料
      final updatedUser = UserProfile(
        name: _name,
        gender: _gender,
        dateOfBirth: _dateOfBirth,
        phoneNumber: _phoneNumber,
        chronicDisease: chronicDiseaseString,
        chronicDiseaseList: chronicDiseaseList,
        allergies: allergyString,
        height: _height,
        weight: _weight,
        bloodType: _bloodType,
        profileImagePath: widget.initialUser.profileImagePath, // 保持大頭貼路徑不變
      );

      // 返回更新後的資料給 ProfileScreen (實現跨畫面資料同步和持久化)
      Navigator.of(context).pop(updatedUser);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('編輯個人資料',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        elevation: 1,
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            // 預留底部空間給按鈕
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // --- 基本資訊 ---
                _buildTitle('基本資訊'),
                _buildTextFormField(
                  label: '姓名',
                  initialValue: _name,
                  validator: (value) => value == null || value.isEmpty ? '請輸入姓名' : null,
                  onSaved: (value) => _name = value!,
                ),
                const SizedBox(height: 15),
                _buildDropdownFormField(
                  label: '性別',
                  value: _gender,
                  items: ['男', '女', '其他', '未設定'],
                  onChanged: (newValue) => setState(() => _gender = newValue!),
                  onSaved: (value) => _gender = value!,
                ),
                const SizedBox(height: 15),
                // 修正後的生日欄位
                _buildDateFormField(
                  label: '出生日期',
                  value: _dateOfBirth,
                  onTap: () => _selectDate(context),
                  onSaved: () {}, 
                ),
                const SizedBox(height: 30),

                // --- 身體測量資訊 ---
                _buildTitle('身體測量'),
                _buildTextFormField(
                  label: '身高 (公分)',
                  initialValue: _height.replaceAll(' 公分', ''),
                  keyboardType: TextInputType.number,
                  validator: (value) => value == null || value.isEmpty ? '請輸入身高' : null,
                  onSaved: (value) => _height = '$value 公分',
                ),
                const SizedBox(height: 15),
                _buildTextFormField(
                  label: '體重 (公斤)',
                  initialValue: _weight.replaceAll(' 公斤', ''),
                  keyboardType: TextInputType.number,
                  validator: (value) => value == null || value.isEmpty ? '請輸入體重' : null,
                  onSaved: (value) => _weight = '$value 公斤',
                ),
                const SizedBox(height: 15),
                _buildDropdownFormField(
                  label: '血型',
                  value: _bloodType,
                  items: ['A 型', 'B 型', 'O 型', 'AB 型', '未設定'],
                  onChanged: (newValue) => setState(() => _bloodType = newValue!),
                  onSaved: (value) => _bloodType = value!,
                ),
                const SizedBox(height: 30),

                // --- 健康與聯繫資訊 ---
                _buildTitle('健康與聯繫'),
                // 慢性病多選
                _buildChronicDiseaseSelector(),
                const SizedBox(height: 15),
                // 過敏史多選
                _buildAllergySelector(),
                const SizedBox(height: 15),
                _buildTextFormField(
                  label: '手機號碼（選填）',
                  initialValue: _phoneNumber,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    // 改為選填：只有在有輸入時才驗證格式
                    if (value != null && value.isNotEmpty && value.length < 10) {
                      return '號碼格式不正確（至少 10 碼）';
                    }
                    return null;
                  },
                  onSaved: (value) => _phoneNumber = value ?? '',
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
      
      // 固定底部的儲存按鈕
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _saveForm,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('儲存變更', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  // =================================================================
  // Helper Widgets
  // =================================================================

  // Helper Widget: 區塊標題
  Widget _buildTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  // Helper Widget: 文本輸入欄位
  Widget _buildTextFormField({
    required String label,
    required String initialValue,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    void Function(String?)? onSaved,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: TextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF9E9E9E)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        ),
        validator: validator,
        onSaved: onSaved,
      ),
    );
  }

  // Helper Widget: 下拉選單欄位
  Widget _buildDropdownFormField({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?)? onChanged,
    required void Function(String?)? onSaved,
  }) {
    String? selectedValue = items.contains(value) ? value : '未設定';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: DropdownButtonFormField<String>(
        initialValue: selectedValue,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF9E9E9E)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        ),
        icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
        items: items.map<DropdownMenuItem<String>>((String item) {
          return DropdownMenuItem<String>(
            value: item,
            child: Text(item, style: const TextStyle(color: Colors.black87)),
          );
        }).toList(),
        onChanged: onChanged,
        validator: (value) {
          if (value == null || value == '未設定') {
            return '請選擇 $label';
          }
          return null;
        },
        onSaved: onSaved,
      ),
    );
  }

  // 修正後的 Helper Widget: 日期選擇欄位 (實現靠左對齊和日曆圖示在左側)
  Widget _buildDateFormField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    required VoidCallback onSaved,
  }) {
    // 創建一個 TextEditingController 來顯示格式化後的日期
    final TextEditingController dateController = TextEditingController(
      text: value == null ? '' : DateFormat('yyyy/MM/dd').format(value),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Builder(
        builder: (context) {
          // 確保每次日期更新時，controller 的 text 都能刷新
          dateController.text = value == null ? '' : DateFormat('yyyy/MM/dd').format(value);

          return TextFormField(
            controller: dateController,
            readOnly: true, // 設定為只讀，只能透過點擊日曆圖示選擇
            onTap: onTap, // 點擊輸入框時觸發日期選擇
            
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: Color(0xFF9E9E9E)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
              
              // 將日曆圖示放在左側 (Prefix Icon)
              prefixIcon: IconButton(
                icon: const Icon(Icons.calendar_today, size: 20, color: AppColors.primary),
                onPressed: onTap, // 點擊圖示也觸發日期選擇
                padding: const EdgeInsets.only(left: 10, right: 10),
              ),
            ),
            
            textAlign: TextAlign.left, // 確保文字內容靠左對齊
            
            validator: (text) {
              if (value == null) {
                return '請選擇 $label';
              }
              return null;
            },
            onSaved: (text) => onSaved(),
          );
        }
      ),
    );
  }

  // Helper Widget: 慢性病 Checkbox 列表（可展開式）
  Widget _buildChronicDiseaseSelector() {
    const Color primaryColor = AppColors.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isChronicDiseaseExpanded = !_isChronicDiseaseExpanded;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Container(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  const Icon(Icons.sick_rounded, color: primaryColor, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '慢性病史',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isChronicDiseaseExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: primaryColor,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  ..._chronicDiseases.entries.map((entry) {
                    return CheckboxListTile(
                      title: Text(entry.key),
                      value: entry.value,
                      onChanged: (bool? value) {
                        setState(() {
                          if (entry.key == '無' && value == true) {
                            _chronicDiseases.updateAll((k, v) => false);
                            _chronicDiseases['無'] = true;
                          } else if (value == true) {
                            _chronicDiseases['無'] = false;
                          }
                          _chronicDiseases[entry.key] = value ?? false;
                        });
                      },
                      activeColor: primaryColor,
                      checkColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                  if (_otherChronicDiseases.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '其他項目：',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ...List.generate(_otherChronicDiseases.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F4FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _otherChronicDiseases[index],
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _otherChronicDiseases.removeAt(index);
                                });
                              },
                              child: const Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _otherChronicDiseaseController,
                          decoration: InputDecoration(
                            hintText: '新增其他項目...',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey[300]!,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey[300]!,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: primaryColor,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          onPressed: () {
                            if (_otherChronicDiseaseController.text.trim().isNotEmpty) {
                              setState(() {
                                _otherChronicDiseases.add(_otherChronicDiseaseController.text.trim());
                                _chronicDiseases['無'] = false;
                                _otherChronicDiseaseController.clear();
                              });
                            }
                          },
                          icon: const Icon(Icons.add, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            crossFadeState: _isChronicDiseaseExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  // Helper Widget: 過敏史 Checkbox 列表（可展開式）
  Widget _buildAllergySelector() {
    const Color primaryColor = AppColors.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isAllergyExpanded = !_isAllergyExpanded;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Container(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: primaryColor, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '過敏史',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isAllergyExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: primaryColor,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  ..._allergies.entries.map((entry) {
                    return CheckboxListTile(
                      title: Text(entry.key),
                      value: entry.value,
                      onChanged: (bool? value) {
                        setState(() {
                          if (entry.key == '無' && value == true) {
                            _allergies.updateAll((k, v) => false);
                            _allergies['無'] = true;
                          } else if (value == true) {
                            _allergies['無'] = false;
                          }
                          _allergies[entry.key] = value ?? false;
                        });
                      },
                      activeColor: primaryColor,
                      checkColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                  if (_otherAllergies.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '其他項目：',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ...List.generate(_otherAllergies.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.warning,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _otherAllergies[index],
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _otherAllergies.removeAt(index);
                                });
                              },
                              child: const Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _otherAllergyController,
                          decoration: InputDecoration(
                            hintText: '新增其他項目...',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey[300]!,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey[300]!,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: primaryColor,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          onPressed: () {
                            if (_otherAllergyController.text.trim().isNotEmpty) {
                              setState(() {
                                _otherAllergies.add(_otherAllergyController.text.trim());
                                _allergies['無'] = false;
                                _otherAllergyController.clear();
                              });
                            }
                          },
                          icon: const Icon(Icons.add, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            crossFadeState: _isAllergyExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }
}