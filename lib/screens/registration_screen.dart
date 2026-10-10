import 'dart:io';
import '../theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../utils/password_validator.dart';
import 'login_screen.dart' hide AuthScreen;

const Color _primaryColor = AppColors.primary;
const Color _accentColor = Color(0xFF50C878);

class RegistrationScreen extends StatelessWidget {
  const RegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '建立新帳號',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        surfaceTintColor: Colors.white,
      ),
      backgroundColor: AppColors.background,
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20.0),
          child: _RegistrationForm(),
        ),
      ),
    );
  }
}

class _RegistrationForm extends StatefulWidget {
  const _RegistrationForm();

  @override
  State<_RegistrationForm> createState() => _RegistrationFormState();
}

class _RegistrationFormState extends State<_RegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');
  final TextEditingController _passwordController = TextEditingController();

  // Loading state
  bool _isLoading = false;

  // 社交登入狀態
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _isAppleAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkAppleSignInAvailability();
  }

  // 檢查 Apple 登入是否可用
  Future<void> _checkAppleSignInAvailability() async {
    if (Platform.isIOS || Platform.isMacOS) {
      final authService = AuthService();
      final available = await authService.isAppleSignInAvailable();
      if (mounted) {
        setState(() {
          _isAppleAvailable = available;
        });
      }
    }
  }

  // Google 快速註冊/登入
  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      final authService = AuthService();
      final userCredential = await authService.signInWithGoogle();

      if (userCredential?.user != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Google 登入成功'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  // Apple 快速註冊/登入
  Future<void> _signInWithApple() async {
    setState(() => _isAppleLoading = true);

    try {
      final authService = AuthService();
      final userCredential = await authService.signInWithApple();

      if (userCredential?.user != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Apple 登入成功'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAppleLoading = false);
    }
  }

  // Form Data States
  String _email = '';
  String _password = '';
  String _confirmPassword = '';
  String _fullName = '';
  String _gender = '未選擇';
  bool _isGenderExpanded = false;
  final List<String> _genders = ['男', '女', '其他'];
  DateTime? _dateOfBirth;
  String _height = '';
  String _weight = '';
  String _bloodType = '未選擇';
  bool _isBloodTypeExpanded = false;
  String _bloodTypeOther = '';
  final List<String> _bloodTypes = ['A 型', 'B 型', 'O 型', 'AB 型', '不確定', '其他'];

  // 慢性病史 - 多選
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
  final TextEditingController _otherChronicDiseaseController =
      TextEditingController();

  // 過敏史 - 多選
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
  void dispose() {
    _passwordController.dispose();
    _otherChronicDiseaseController.dispose();
    _otherAllergyController.dispose();
    super.dispose();
  }

  // Email 驗證
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return '電子郵件為必填欄位';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return '請輸入有效的電子郵件格式';
    }
    return null;
  }

  // 密碼驗證：使用共用密碼驗證器
  String? _validatePassword(String? value) {
    return PasswordValidator.validateSimple(value);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('zh', 'TW'),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _primaryColor),
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

  void _showSuccessDialogAndNavigate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const AuthScreen()),
              (Route<dynamic> route) => false,
            );
          }
        });

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.all(30.0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F4FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: _accentColor,
                  size: 60,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '註冊成功！',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '病歷資料已建立完成\n即將自動導向登入頁面...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getAllergiesString() {
    List<String> selected = [];
    _allergies.forEach((key, value) {
      if (value) {
        selected.add(key);
      }
    });
    selected.addAll(_otherAllergies);
    return selected.isEmpty ? '無' : selected.join('、');
  }

  String _getChronicDiseasesString() {
    List<String> selected = [];
    _chronicDiseases.forEach((key, value) {
      if (value) {
        selected.add(key);
      }
    });
    selected.addAll(_otherChronicDiseases);
    return selected.isEmpty ? '無' : selected.join('、');
  }


  Future<void> _submitRegistration() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      setState(() => _isLoading = true);

      try {
        final authService = AuthService();
        final userCredential = await authService.signUpWithEmail(
          email: _email.trim(),
          password: _password,
        );

        final userId = userCredential?.user?.uid;

        if (userId != null) {
          // 準備血型資料
          String finalBloodType = _bloodType;
          if (_bloodType == '其他' && _bloodTypeOther.isNotEmpty) {
            finalBloodType = _bloodTypeOther;
          }

          await FirebaseFirestore.instance.collection('users').doc(userId).set({
            'email': _email.trim(),
            'fullName': _fullName,
            'dateOfBirth': _dateOfBirth?.toIso8601String(),
            'gender': _gender == '未選擇' ? '' : _gender,
            'height': _height.isNotEmpty ? double.tryParse(_height) : null,
            'weight': _weight.isNotEmpty ? double.tryParse(_weight) : null,
            'bloodType': finalBloodType,
            'chronicDiseases': _getChronicDiseasesString(),
            'allergies': _getAllergiesString(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        if (mounted) {
          _showSuccessDialogAndNavigate();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('註冊失敗: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    String? Function(String?)? validator,
    required void Function(String?) onSaved,
    TextEditingController? controller,
    AutovalidateMode autovalidateMode = AutovalidateMode.onUserInteraction,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        autovalidateMode: autovalidateMode,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          prefixIcon: Icon(icon, color: _primaryColor),
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
            borderSide: const BorderSide(color: _primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16.0,
            horizontal: 16.0,
          ),
          fillColor: Colors.white,
          filled: true,
        ),
        keyboardType: keyboardType,
        obscureText: isPassword,
        validator: validator,
        onSaved: onSaved,
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 15.0),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: _primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: InkWell(
        onTap: () => _selectDate(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                color: _primaryColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '出生日期 *',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dateOfBirth == null
                          ? '請選擇日期'
                          : _dateFormat.format(_dateOfBirth!),
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            _dateOfBirth == null
                                ? Colors.grey[400]
                                : _primaryColor,
                        fontWeight:
                            _dateOfBirth == null
                                ? FontWeight.normal
                                : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeightWeightRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                labelText: '身高 (cm)',
                labelStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.height, color: _primaryColor),
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
                  borderSide: const BorderSide(color: _primaryColor, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 16.0,
                  horizontal: 16.0,
                ),
                fillColor: Colors.white,
                filled: true,
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final height = double.tryParse(value);
                  if (height == null || height < 100 || height > 250) {
                    return '請輸入有效身高';
                  }
                }
                return null;
              },
              onSaved: (value) => _height = value ?? '',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                labelText: '體重 (kg)',
                labelStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(
                  Icons.monitor_weight,
                  color: _primaryColor,
                ),
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
                  borderSide: const BorderSide(color: _primaryColor, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 16.0,
                  horizontal: 16.0,
                ),
                fillColor: Colors.white,
                filled: true,
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final weight = double.tryParse(value);
                  if (weight == null || weight < 30 || weight > 300) {
                    return '請輸入有效體重';
                  }
                }
                return null;
              },
              onSaved: (value) => _weight = value ?? '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownSelector({
    required String label,
    required IconData icon,
    required String selectedValue,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: DropdownButtonFormField<String>(
          initialValue: selectedValue,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.grey),
            prefixIcon: Icon(icon, color: _primaryColor),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16.0,
              horizontal: 16.0,
            ),
          ),
          dropdownColor: Colors.white,
          icon: const Icon(Icons.arrow_drop_down, color: _primaryColor),
          items:
              items.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
          onChanged: onChanged,
          validator:
              (value) => value == '未選擇' || value == null ? '請選擇一個選項' : null,
        ),
      ),
    );
  }

  Widget _buildExpandableCheckboxSection({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Map<String, bool> items,
    required Function(String, bool) onChanged,
    required List<String> otherItems,
    required Function(String) onAddOther,
    required Function(int) onRemoveOther,
    required TextEditingController otherController,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(icon, color: _primaryColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: _primaryColor,
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    ...items.entries.map((entry) {
                      return CheckboxListTile(
                        title: Text(entry.key),
                        value: entry.value,
                        onChanged: (bool? value) {
                          onChanged(entry.key, value ?? false);
                        },
                        activeColor: _primaryColor,
                        checkColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: EdgeInsets.zero,
                      );
                    }),
                    if (otherItems.isNotEmpty) ...[
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
                    ...List.generate(otherItems.length, (index) {
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
                                color: _primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  otherItems[index],
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                              InkWell(
                                onTap: () => onRemoveOther(index),
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
                            controller: otherController,
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
                                  color: _primaryColor,
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
                            color: _primaryColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            onPressed: () {
                              if (otherController.text.trim().isNotEmpty) {
                                onAddOther(otherController.text.trim());
                                otherController.clear();
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
              crossFadeState:
                  isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableRadioSection({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required String selectedValue,
    required List<String> items,
    required Function(String) onChanged,
    String? otherValue,
    Function(String)? onOtherChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(icon, color: _primaryColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          if (selectedValue != '未選擇')
                            Text(
                              selectedValue == '其他' &&
                                      otherValue != null &&
                                      otherValue.isNotEmpty
                                  ? otherValue
                                  : selectedValue,
                              style: const TextStyle(
                                fontSize: 14,
                                color: _primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: _primaryColor,
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    ...items.map((item) {
                      return Column(
                        children: [
                          RadioListTile<String>(
                            title: Text(item),
                            value: item,
                            groupValue: selectedValue,
                            onChanged: (String? value) {
                              if (value != null) {
                                onChanged(value);
                              }
                            },
                            activeColor: _primaryColor,
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (item == '其他' &&
                              selectedValue == '其他' &&
                              onOtherChanged != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 40,
                                bottom: 8,
                              ),
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: '請說明...',
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
                                      color: _primaryColor,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                onChanged: onOtherChanged,
                              ),
                            ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              crossFadeState:
                  isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
      ),
    );
  }

  // 社交登入按鈕建構器
  Widget _buildSocialLoginButton({
    required VoidCallback? onPressed,
    required bool isLoading,
    required Widget icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required Color borderColor,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          side: BorderSide(color: borderColor, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: foregroundColor,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: foregroundColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Google 圖示
  Widget _buildGoogleIcon() {
    return Image.asset(
      'assets/Google_icon.png',
      width: 22,
      height: 22,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ==================== 快速註冊區塊 ====================
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.flash_on, color: _primaryColor, size: 22),
                    SizedBox(width: 8),
                    Text(
                      '快速註冊',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '使用社交帳號快速註冊，無需填寫表單',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 16),

                // Google 按鈕
                _buildSocialLoginButton(
                  onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                  isLoading: _isGoogleLoading,
                  icon: _buildGoogleIcon(),
                  label: '使用 Google 帳號註冊',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  borderColor: Colors.grey.shade300,
                ),

                // Apple 按鈕（僅 iOS）
                if (_isAppleAvailable) ...[
                  const SizedBox(height: 10),
                  _buildSocialLoginButton(
                    onPressed: _isAppleLoading ? null : _signInWithApple,
                    isLoading: _isAppleLoading,
                    icon: const Icon(Icons.apple, size: 22, color: Colors.white),
                    label: '使用 Apple 帳號註冊',
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    borderColor: Colors.black,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 分隔線
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '或使用電子郵件註冊',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300)),
            ],
          ),

          _buildSectionHeader('1. 帳號設定'),
          _buildTextField(
            label: '電子郵件 *',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
            onSaved: (value) => _email = value!,
          ),
          _buildTextField(
            label: '密碼 *',
            icon: Icons.lock_rounded,
            isPassword: true,
            controller: _passwordController,
            validator: _validatePassword,
            onSaved: (value) => _password = value!,
          ),
          _buildTextField(
            label: '確定密碼 *',
            icon: Icons.lock_rounded,
            isPassword: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '請再次輸入密碼';
              }
              if (value != _passwordController.text) {
                return '兩次輸入的密碼不一致';
              }
              return null;
            },
            onSaved: (value) => _confirmPassword = value!,
          ),

          _buildSectionHeader('2. 基本資料'),
          _buildTextField(
            label: '姓名 *',
            icon: Icons.person_rounded,
            validator:
                (value) => (value == null || value.isEmpty) ? '姓名為必填欄位' : null,
            onSaved: (value) => _fullName = value!,
          ),
          _buildDateSelector(),
          _buildExpandableRadioSection(
            title: '性別 *',
            icon: Icons.wc_rounded,
            isExpanded: _isGenderExpanded,
            onToggle: () {
              setState(() {
                _isGenderExpanded = !_isGenderExpanded;
              });
            },
            selectedValue: _gender,
            items: _genders,
            onChanged: (value) {
              setState(() {
                _gender = value;
                _isGenderExpanded = false; // 選完後自動收起
              });
            },
          ),
          _buildHeightWeightRow(),

          _buildSectionHeader('3. 醫療健康資訊'),
          _buildExpandableRadioSection(
            title: '血型 *',
            icon: Icons.bloodtype_rounded,
            isExpanded: _isBloodTypeExpanded,
            onToggle: () {
              setState(() {
                _isBloodTypeExpanded = !_isBloodTypeExpanded;
              });
            },
            selectedValue: _bloodType,
            items: _bloodTypes,
            onChanged: (value) {
              setState(() {
                _bloodType = value;
                if (value != '其他') {
                  _isBloodTypeExpanded = false; // 非「其他」選完後自動收起
                }
              });
            },
            otherValue: _bloodTypeOther,
            onOtherChanged: (value) {
              setState(() {
                _bloodTypeOther = value;
              });
            },
          ),

          _buildExpandableCheckboxSection(
            title: '慢性病史 *',
            icon: Icons.sick_rounded,
            isExpanded: _isChronicDiseaseExpanded,
            onToggle: () {
              setState(() {
                _isChronicDiseaseExpanded = !_isChronicDiseaseExpanded;
              });
            },
            items: _chronicDiseases,
            onChanged: (key, value) {
              setState(() {
                if (key == '無' && value) {
                  _chronicDiseases.updateAll((k, v) => false);
                  _chronicDiseases['無'] = true;
                } else if (value) {
                  _chronicDiseases['無'] = false;
                }
                _chronicDiseases[key] = value;
              });
            },
            otherItems: _otherChronicDiseases,
            onAddOther: (value) {
              setState(() {
                _otherChronicDiseases.add(value);
                _chronicDiseases['無'] = false;
              });
            },
            onRemoveOther: (index) {
              setState(() {
                _otherChronicDiseases.removeAt(index);
              });
            },
            otherController: _otherChronicDiseaseController,
          ),

          _buildExpandableCheckboxSection(
            title: '過敏史 *',
            icon: Icons.warning_rounded,
            isExpanded: _isAllergyExpanded,
            onToggle: () {
              setState(() {
                _isAllergyExpanded = !_isAllergyExpanded;
              });
            },
            items: _allergies,
            onChanged: (key, value) {
              setState(() {
                if (key == '無' && value) {
                  _allergies.updateAll((k, v) => false);
                  _allergies['無'] = true;
                } else if (value) {
                  _allergies['無'] = false;
                }
                _allergies[key] = value;
              });
            },
            otherItems: _otherAllergies,
            onAddOther: (value) {
              setState(() {
                _otherAllergies.add(value);
                _allergies['無'] = false;
              });
            },
            onRemoveOther: (index) {
              setState(() {
                _otherAllergies.removeAt(index);
              });
            },
            otherController: _otherAllergyController,
          ),

          const SizedBox(height: 30),
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_primaryColor, Color(0xFF3A7BC8)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitRegistration,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child:
                  _isLoading
                      ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                      : const Text(
                        '註冊並建立病歷',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
