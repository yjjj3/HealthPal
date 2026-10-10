// lib/screens/prescription_scan_screen.dart
// 處方箋智慧辨識主頁面

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../models/prescription_model.dart';
import '../services/prescription_scan_service.dart';
import 'qr_code_scanner_screen.dart';
import 'prescription_confirm_screen.dart';

class PrescriptionScanScreen extends StatefulWidget {
  const PrescriptionScanScreen({super.key});

  @override
  State<PrescriptionScanScreen> createState() => _PrescriptionScanScreenState();
}

class _PrescriptionScanScreenState extends State<PrescriptionScanScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final ImagePicker _picker = ImagePicker();
  final PrescriptionScanService _scanService = PrescriptionScanService();

  final List<File> _selectedImages = [];
  final List<String> _scannedDrugCodes = [];

  bool _isProcessing = false;
  String _processingStatus = '';
  double _processingProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ============================================================
  // 步驟一：選擇或拍攝照片
  // ============================================================
  Future<void> _pickImages(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        // 拍照模式：一次拍一張，可以繼續拍
        final XFile? image = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 90,
        );

        if (image != null) {
          setState(() {
            _selectedImages.add(File(image.path));
          });
        }
      } else {
        // 相簿模式：可選多張
        final List<XFile> images = await _picker.pickMultiImage(
          imageQuality: 90,
        );

        if (images.isNotEmpty) {
          setState(() {
            _selectedImages.addAll(images.map((x) => File(x.path)));
          });
        }
      }
    } catch (e) {
      debugPrint('選擇圖片失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('選擇圖片失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  // ============================================================
  // 步驟二：掃描 QR Code
  // ============================================================
  Future<void> _scanQRCodes() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => QRCodeScannerScreen(
          onDrugCodesScanned: (codes) {
            Navigator.pop(context, codes);
          },
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _scannedDrugCodes.addAll(result);
      });
    }
  }

  // ============================================================
  // 步驟三：開始 AI 辨識
  // ============================================================
  Future<void> _startRecognition() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('請先選擇或拍攝處方箋照片'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStatus = '正在分析處方箋...';
      _processingProgress = 0.0;
    });

    try {
      final List<PrescriptionMedicine> allMedicines = [];
      Map<String, dynamic>? hospitalInfo;

      for (int i = 0; i < _selectedImages.length; i++) {
        setState(() {
          _processingStatus = '正在辨識第 ${i + 1}/${_selectedImages.length} 張圖片...';
          _processingProgress = (i / _selectedImages.length);
        });

        final result = await _scanService.recognizePrescriptionImage(
          _selectedImages[i],
        );

        if (result.containsKey('error')) {
          debugPrint('辨識錯誤: ${result['error']}');
          continue;
        }

        // 解析藥品資訊
        if (result.containsKey('medicines')) {
          final medicinesList = result['medicines'] as List<dynamic>;
          for (final medicineData in medicinesList) {
            final medicine = PrescriptionMedicine.fromJson(
              medicineData as Map<String, dynamic>,
            );

            // 如果有掃描到的藥品代碼，補充到辨識結果
            for (final code in _scannedDrugCodes) {
              if (medicine.drugCode.isEmpty) {
                allMedicines.add(medicine.copyWith(drugCode: code));
                _scannedDrugCodes.remove(code);
                break;
              }
            }

            if (medicine.drugCode.isNotEmpty || medicine.name.isNotEmpty) {
              allMedicines.add(medicine);
            }
          }
        }

        // 解析醫院資訊（取第一張的資訊）
        if (hospitalInfo == null && result.containsKey('hospitalInfo')) {
          hospitalInfo = result['hospitalInfo'] as Map<String, dynamic>?;
        }
      }

      // 處理剩餘的藥品代碼（沒有對應到的）
      for (final code in _scannedDrugCodes) {
        allMedicines.add(PrescriptionMedicine(
          drugCode: code,
          name: '藥品代碼: $code',
          dosage: '1',
          unit: '顆',
          frequency: '每天1次',
          timing: '飯後',
          durationDays: 7,
          totalQuantity: 0,
        ));
      }

      setState(() {
        _processingProgress = 1.0;
        _processingStatus = '辨識完成！';
      });

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        // 導航到確認頁面
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PrescriptionConfirmScreen(
              medicines: allMedicines,
              hospitalInfo: hospitalInfo,
              imageFiles: _selectedImages,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('辨識失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('辨識失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '處方箋智慧辨識',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0.5,
      ),
      backgroundColor: AppColors.background,
      body: _isProcessing ? _buildProcessingView() : _buildMainView(),
    );
  }

  Widget _buildMainView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 說明卡片
          _buildInstructionCard(),
          const SizedBox(height: 24),

          // 步驟一：上傳照片
          _buildStepHeader(
            stepNumber: 1,
            title: '上傳處方箋照片',
            subtitle: '可一次選擇多張藥袋照片',
          ),
          const SizedBox(height: 12),
          _buildImagePickerSection(),
          const SizedBox(height: 24),

          // 步驟二：掃描 QR Code（可選）
          _buildStepHeader(
            stepNumber: 2,
            title: '掃描 QR Code（可選）',
            subtitle: '掃描藥袋上的 QR Code 可提高辨識準確度',
          ),
          const SizedBox(height: 12),
          _buildQRCodeSection(),
          const SizedBox(height: 32),

          // 開始辨識按鈕
          _buildStartButton(),
        ],
      ),
    );
  }

  Widget _buildInstructionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.document_scanner,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '智慧辨識處方箋',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '拍攝或上傳藥袋照片，AI 將自動辨識藥品資訊並建立用藥提醒',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepHeader({
    required int stepNumber,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              '$stepNumber',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
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
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImagePickerSection() {
    return Column(
      children: [
        // 選擇按鈕
        Row(
          children: [
            Expanded(
              child: _buildPickerButton(
                icon: Icons.photo_camera,
                label: '拍照',
                onTap: () => _pickImages(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildPickerButton(
                icon: Icons.photo_library,
                label: '從相簿選擇',
                onTap: () => _pickImages(ImageSource.gallery),
              ),
            ),
          ],
        ),

        // 已選擇的圖片預覽
        if (_selectedImages.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              itemBuilder: (context, index) {
                return _buildImagePreview(index);
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已選擇 ${_selectedImages.length} 張照片',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPickerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(int index) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      width: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              _selectedImages[index],
              width: 100,
              height: 120,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQRCodeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _scanQRCodes,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner,
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
                        '掃描藥品 QR Code',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '取得藥品代碼以提高辨識準確度',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),

          // 已掃描的藥品代碼
          if (_scannedDrugCodes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _scannedDrugCodes.asMap().entries.map((entry) {
                return Chip(
                  label: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 12),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      _scannedDrugCodes.removeAt(entry.key);
                    });
                  },
                  backgroundColor: AppColors.primaryLight,
                  labelStyle: const TextStyle(color: AppColors.primary),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    final isEnabled = _selectedImages.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isEnabled ? _startRecognition : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: isEnabled ? 2 : 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome),
            const SizedBox(width: 8),
            Text(
              isEnabled
                  ? '開始 AI 辨識 (${_selectedImages.length} 張照片)'
                  : '請先選擇處方箋照片',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingView() {
    return Container(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 脈衝動畫圖示
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.15),
                        AppColors.primary.withOpacity(0.05),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryLight,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.25),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.document_scanner,
                        size: 44,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // 狀態文字
              Text(
                _processingStatus,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // 進度條
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _processingProgress > 0 ? _processingProgress : null,
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'AI 分析中...',
                    style: TextStyle(fontSize: 12, color: AppColors.textHint),
                  ),
                  Text(
                    _processingProgress > 0
                        ? '${(_processingProgress * 100).toInt()}%'
                        : '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // 跳動點提示
              const _DotsLoadingIndicator(),
              const SizedBox(height: 12),
              const Text(
                '請稍候，這可能需要幾秒鐘',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _DotsLoadingIndicator extends StatefulWidget {
  const _DotsLoadingIndicator();

  @override
  State<_DotsLoadingIndicator> createState() => _DotsLoadingIndicatorState();
}

class _DotsLoadingIndicatorState extends State<_DotsLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final delay = i / 3;
            final value = (_controller.value - delay) % 1.0;
            final scale = value < 0.5
                ? 0.6 + value * 0.8
                : 0.6 + (1.0 - value) * 0.8;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.scale(
                scale: scale.clamp(0.6, 1.0),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(
                      alpha: (0.4 + scale * 0.6).clamp(0.4, 1.0),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
