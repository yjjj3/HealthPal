// lib/screens/health_sync_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/health_platform_service.dart';
import '../theme/app_colors.dart';

class HealthSyncScreen extends StatefulWidget {
  const HealthSyncScreen({super.key});

  @override
  State<HealthSyncScreen> createState() => _HealthSyncScreenState();
}

class _HealthSyncScreenState extends State<HealthSyncScreen> {
  final HealthPlatformService _healthService = HealthPlatformService();

  bool _isLoading = true;
  bool _isSyncing = false;
  Map<String, dynamic> _healthSummary = {};
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    setState(() => _isLoading = true);

    try {
      await _healthService.initialize();
      if (_healthService.isAuthorized) {
        // 已授權時自動同步最新數據
        await _autoSync();
      }
    } catch (e) {
      setState(() => _errorMessage = '初始化失敗：$e');
    }

    setState(() => _isLoading = false);
  }

  /// 自動同步（靜默執行，不顯示 loading）
  Future<void> _autoSync() async {
    final result = await _healthService.syncHealthData(days: 7);
    if (result.success && result.syncedRecords > 0) {
      debugPrint('[HealthSyncScreen] 自動同步完成：${result.syncedRecords} 筆記錄');
    }
    await _loadHealthSummary();
  }

  Future<void> _loadHealthSummary() async {
    final summary = await _healthService.getHealthSummary(days: 7);
    setState(() => _healthSummary = summary);
  }

  Future<void> _requestAuthorization() async {
    setState(() => _isLoading = true);

    final success = await _healthService.requestAuthorization();

    if (success) {
      // 授權成功後自動同步數據
      final result = await _healthService.syncHealthData(days: 7);
      await _loadHealthSummary();

      if (mounted) {
        final message = result.syncedRecords > 0
            ? '已成功連接並同步 ${result.syncedRecords} 筆健康記錄'
            : '已成功連接健康平台';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('授權失敗，請在系統設定中開啟權限'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _syncData() async {
    setState(() => _isSyncing = true);

    final result = await _healthService.syncHealthData(days: 7);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? AppColors.success : AppColors.error,
        ),
      );

      if (result.success) {
        await _loadHealthSummary();
      }
    }

    setState(() => _isSyncing = false);
  }

  Future<void> _disconnectPlatform() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認中斷連接'),
        content: Text('確定要中斷與${_healthService.platformName}的連接嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('中斷連接'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _healthService.revokeAuthorization();
      setState(() {
        _healthSummary = {};
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已中斷連接'),
            backgroundColor: AppColors.textSecondary,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '健康平台同步',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 平台連接狀態卡片
                  _buildConnectionCard(),

                  const SizedBox(height: 20),

                  // 如果已連接，顯示同步選項和數據摘要
                  if (_healthService.isAuthorized) ...[
                    _buildSyncSection(),
                    const SizedBox(height: 20),
                    _buildDataSummarySection(),
                    const SizedBox(height: 20),
                    _buildSupportedDataSection(),
                  ] else ...[
                    _buildConnectPrompt(),
                  ],

                  const SizedBox(height: 20),
                  _buildPrivacyNote(),
                ],
              ),
            ),
    );
  }

  Widget _buildConnectionCard() {
    final isConnected = _healthService.isAuthorized;
    final platformName = _healthService.platformName;
    final platformIcon = Platform.isIOS
        ? Icons.apple
        : Icons.health_and_safety_rounded;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected ? AppColors.success : AppColors.border,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isConnected
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  platformIcon,
                  size: 32,
                  color: isConnected ? AppColors.success : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      platformName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isConnected ? AppColors.success : AppColors.textHint,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? '已連接' : '未連接',
                          style: TextStyle(
                            fontSize: 14,
                            color: isConnected ? AppColors.success : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isConnected)
                IconButton(
                  icon: const Icon(Icons.link_off, color: AppColors.error),
                  onPressed: _disconnectPlatform,
                  tooltip: '中斷連接',
                ),
            ],
          ),
          if (_healthService.lastSyncTime != null) ...[
            const SizedBox(height: 15),
            const Divider(),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.sync, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  '上次同步：${DateFormat('yyyy/MM/dd HH:mm').format(_healthService.lastSyncTime!)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectPrompt() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(
            Platform.isIOS ? Icons.apple : Icons.health_and_safety_rounded,
            size: 60,
            color: AppColors.primary,
          ),
          const SizedBox(height: 20),
          Text(
            '連接${_healthService.platformName}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            Platform.isIOS
                ? '從 Apple 健康讀取您的血壓、心率、血糖、體重、睡眠和運動數據'
                : '從 Health Connect 讀取您的健康數據',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _requestAuthorization,
              child: const Text(
                '連接健康平台',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '同步設定',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 15),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.sync_rounded,
                color: AppColors.primary,
              ),
            ),
            title: const Text('手動同步'),
            subtitle: const Text('同步最近 7 天的數據'),
            trailing: _isSyncing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _syncData,
                    child: const Text('同步'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSummarySection() {
    // 如果沒有數據，不顯示此區塊
    if (_healthSummary.isEmpty) {
      return const SizedBox.shrink();
    }

    // 準備要顯示的數據項目
    final List<Map<String, dynamic>> summaryItems = [];

    if (_healthSummary['steps'] != null) {
      summaryItems.add({
        'icon': Icons.directions_walk_rounded,
        'label': '步數',
        'value': '${_healthSummary['steps']['average']}',
        'unit': '步/天',
        'color': AppColors.primary,
      });
    }
    if (_healthSummary['blood_pressure'] != null) {
      summaryItems.add({
        'icon': Icons.favorite_rounded,
        'label': '血壓',
        'value': '${_healthSummary['blood_pressure']['avg_systolic']}/${_healthSummary['blood_pressure']['avg_diastolic']}',
        'unit': 'mmHg',
        'color': AppColors.error,
      });
    }
    if (_healthSummary['blood_glucose'] != null) {
      summaryItems.add({
        'icon': Icons.water_drop_rounded,
        'label': '血糖',
        'value': '${_healthSummary['blood_glucose']['average']}',
        'unit': 'mg/dL',
        'color': AppColors.warning,
      });
    }
    if (_healthSummary['weight'] != null) {
      summaryItems.add({
        'icon': Icons.monitor_weight_rounded,
        'label': '體重',
        'value': (_healthSummary['weight']['latest'] as double).toStringAsFixed(1),
        'unit': 'kg',
        'color': AppColors.success,
      });
    }
    if (_healthSummary['sleep'] != null) {
      summaryItems.add({
        'icon': Icons.bedtime_rounded,
        'label': '睡眠',
        'value': '${_healthSummary['sleep']['avg_hours']}',
        'unit': '小時/天',
        'color': const Color(0xFF8B5CF6),
      });
    }
    if (_healthSummary['heart_rate'] != null) {
      summaryItems.add({
        'icon': Icons.monitor_heart_rounded,
        'label': '心率',
        'value': '${_healthSummary['heart_rate']['average']}',
        'unit': 'bpm',
        'color': const Color(0xFFE91E63),
      });
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '最近 7 天數據摘要',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 15),
          // 使用 GridView 確保每個卡片大小一致
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.6,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: summaryItems.length,
            itemBuilder: (context, index) {
              final item = summaryItems[index];
              return _buildSummaryCard(
                icon: item['icon'] as IconData,
                label: item['label'] as String,
                value: item['value'] as String,
                unit: item['unit'] as String,
                color: item['color'] as Color,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              fontSize: 11,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportedDataSection() {
    final dataTypes = [
      {'icon': Icons.favorite_rounded, 'label': '血壓', 'color': AppColors.error},
      {'icon': Icons.monitor_heart_rounded, 'label': '心率', 'color': const Color(0xFFE91E63)},
      {'icon': Icons.water_drop_rounded, 'label': '血糖', 'color': AppColors.warning},
      {'icon': Icons.monitor_weight_rounded, 'label': '體重', 'color': AppColors.success},
      {'icon': Icons.bedtime_rounded, 'label': '睡眠', 'color': const Color(0xFF8B5CF6)},
      {'icon': Icons.directions_walk_rounded, 'label': '步數', 'color': AppColors.primary},
      {'icon': Icons.fitness_center_rounded, 'label': '運動', 'color': const Color(0xFFFF5722)},
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '支援的數據類型',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 15),
          // 使用 GridView 確保每個項目大小一致
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: dataTypes.length,
            itemBuilder: (context, index) {
              final type = dataTypes[index];
              final color = type['color'] as Color;
              return Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      type['icon'] as IconData,
                      size: 16,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      type['label'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyNote() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.privacy_tip_outlined, size: 20, color: Colors.blue[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '隱私說明',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[900],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '• 本 App 僅讀取您的健康數據，不會將任何資料寫回${_healthService.platformName}\n'
                  '• 您的健康數據會安全地儲存在您的個人帳戶中\n'
                  '• 您可以隨時中斷連接並刪除同步的數據',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[800],
                    height: 1.5,
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
