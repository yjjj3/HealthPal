import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'clinic_add_screen.dart';

class Clinic {
  final String name;
  final String department;
  final String doctor;
  final String address;
  final String phone;
  final String? nextVisit;
  final String? note;

  Clinic({
    required this.name,
    required this.department,
    required this.doctor,
    required this.address,
    required this.phone,
    this.nextVisit,
    this.note,
  });
}

class ClinicsScreen extends StatefulWidget {
  const ClinicsScreen({super.key});

  @override
  State<ClinicsScreen> createState() => _ClinicsScreenState();
}

class _ClinicsScreenState extends State<ClinicsScreen> {
  /// 預設假資料
  List<Clinic> clinicList = [
    Clinic(
      name: '台大醫院',
      department: '新陳代謝科',
      doctor: '王醫師',
      address: '台北市中正區中山南路7號',
      phone: '02-2312-3456',
      nextVisit: '2024/10/15 14:00',
      note: '記得帶健保卡和上次的檢查報告',
    ),
    Clinic(
      name: '仁愛醫院',
      department: '心臟內科',
      doctor: '李醫師',
      address: '台北市大安區仁愛路四段10號',
      phone: '02-2709-3600',
    ),
    Clinic(
      name: '康寧診所',
      department: '家醫科',
      doctor: '陳醫師',
      address: '台北市內湖區成功路四段168號',
      phone: '02-2634-5678',
    ),
  ];

  /// 收藏功能
  final Set<String> _favoriteKeys = {}; // 'name|address' 作為唯一 key
  String _favKey(Clinic c) => '${c.name}|${c.address}';

  List<Clinic> get _sortedClinics {
    final list = [...clinicList];
    list.sort((a, b) {
      final fa = _favoriteKeys.contains(_favKey(a));
      final fb = _favoriteKeys.contains(_favKey(b));
      if (fa == fb) return a.name.compareTo(b.name);
      return fb ? 1 : -1; // 收藏的排前面
    });
    return list;
  }

  /// 回診倒數邏輯
  DateTime? _parseNextVisit(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      final parts = s.split(' ');
      final d = parts[0].split('/');
      final t = parts.length > 1 ? parts[1].split(':') : ['09', '00'];
      return DateTime(
        int.parse(d[0]),
        int.parse(d[1]),
        int.parse(d[2]),
        int.parse(t[0]),
        int.parse(t[1]),
      );
    } catch (_) {
      return null;
    }
  }

  String _countdownText(DateTime? dt) {
    if (dt == null) return '未設定';
    final diff = dt.difference(DateTime.now());
    final days = diff.inDays;
    if (days >= 0) return '倒數 $days 天';
    return '已過期';
  }

  /// 加到 Google 行事曆
  Future<void> _addToGoogleCalendar({
    required String title,
    required DateTime start,
    required Duration duration,
    String? location,
    String? details,
  }) async {
    String two(int v) => v.toString().padLeft(2, '0');
    String fmt(DateTime dt) =>
        '${dt.year}${two(dt.month)}${two(dt.day)}T${two(dt.hour)}${two(dt.minute)}00';
    final end = start.add(duration);
    final url = Uri.parse(
      'https://calendar.google.com/calendar/render'
      '?action=TEMPLATE'
      '&text=${Uri.encodeComponent(title)}'
      '&dates=${fmt(start)}/${fmt(end)}'
      '&details=${Uri.encodeComponent(details ?? "")}'
      '&location=${Uri.encodeComponent(location ?? "")}',
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// 新增與刪除
  void _addClinic(Clinic clinic) {
    setState(() {
      clinicList.add(clinic);
    });
  }

  void _deleteClinic(int index) {
    setState(() {
      clinicList.removeAt(index);
    });
  }

  /// 地圖與電話功能
  void _openMap(String address) async {
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _makePhoneCall(String phone) async {
    final url = Uri.parse('tel:${phone.replaceAll('-', '')}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  /// 畫面主體
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
          '我的診所',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_rounded,
                color: AppColors.primary, size: 28),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ClinicAddScreen(),
                ),
              );
              if (result is Clinic) {
                _addClinic(result);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('診所已新增成功'),
                    backgroundColor: AppColors.success,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _sortedClinics.length,
        itemBuilder: (context, index) {
          final clinic = _sortedClinics[index];
          return _buildClinicCard(context, clinic: clinic);
        },
      ),
    );
  }

  /// 卡片 UI
  Widget _buildClinicCard(BuildContext context, {required Clinic clinic}) {
    final fav = _favoriteKeys.contains(_favKey(clinic));
    final nextDt = _parseNextVisit(clinic.nextVisit);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// 標頭區塊
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_hospital,
                    color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clinic.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${clinic.department} · ${clinic.doctor}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              /// 收藏星星
              IconButton(
                tooltip: fav ? '取消收藏' : '收藏',
                onPressed: () {
                  setState(() {
                    if (fav) {
                      _favoriteKeys.remove(_favKey(clinic));
                    } else {
                      _favoriteKeys.add(_favKey(clinic));
                    }
                  });
                },
                icon: Icon(
                  fav ? Icons.star_rounded : Icons.star_border_rounded,
                  color:
                      fav ? const Color(0xFFFFC107) : const Color(0xFFBDBDBD),
                ),
              ),

              /// 刪除選單
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                onSelected: (value) {
                  if (value == 'delete') {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('確認刪除'),
                        content: const Text('確定要刪除此診所嗎？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () {
                              final idx = clinicList.indexOf(clinic);
                              if (idx >= 0) _deleteClinic(idx);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('診所已刪除'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            },
                            child: const Text(
                              '刪除',
                              style: TextStyle(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('刪除診所'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 15),

          /// 地址與電話
          _buildInfoRow(Icons.location_on_outlined, clinic.address),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.phone_outlined, clinic.phone),

          /// 回診資訊
          if (clinic.nextVisit != null) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '下次回診：${clinic.nextVisit}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      _countdownText(nextDt),
                      style: const TextStyle(color: Color(0xFFEF6C00)),
                    ),
                    backgroundColor: const Color(0xFFFFE0B2),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    onPressed: nextDt == null
                        ? null
                        : () {
                            _addToGoogleCalendar(
                              title: '回診 - ${clinic.name}',
                              start: nextDt,
                              duration: const Duration(hours: 1),
                              location: clinic.address,
                              details: '請攜帶健保卡與上次檢查報告',
                            );
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFEF6C00),
                    ),
                    icon:
                        const Icon(Icons.event_available_rounded, size: 18),
                    label: const Text('加到行事曆'),
                  ),
                ],
              ),
            ),
          ],

          /// 備註
          if (clinic.note?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.note_outlined,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      clinic.note!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 15),

          /// 底部按鈕
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openMap(clinic.address),
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('導航'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _makePhoneCall(clinic.phone),
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text('電話'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
