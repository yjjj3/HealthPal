import '../theme/app_colors.dart';
import 'package:flutter/material.dart';

// =================================================================
// 關於你的帳號詳細頁面
// =================================================================
class AccountDetailsScreen extends StatelessWidget {
  const AccountDetailsScreen({super.key});

  // 模擬用戶資料
  static const String _userName = '用戶暱稱';
  static const String _userEmail = 'user.example@email.com';
  static const String _userId = 'UID-98765-ABCDEF';
  static const String _accountCreationDate = '2023年01月15日';

  Widget _buildInfoItem({required String label, required String value, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          if (icon != null) Icon(icon, color: Colors.blueGrey, size: 20),
          if (icon != null) const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, color: Colors.black54),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('關於你的帳號', 
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 帳號總覽區塊
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 25, 20, 10),
              child: Text(
                '基本資料',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  _buildInfoItem(
                    label: '暱稱',
                    value: _userName,
                    icon: Icons.person_outline,
                  ),
                  const Divider(indent: 16, endIndent: 16, height: 1),
                  _buildInfoItem(
                    label: '註冊信箱',
                    value: _userEmail,
                    icon: Icons.email_outlined,
                  ),
                  const Divider(indent: 16, endIndent: 16, height: 1),
                  _buildInfoItem(
                    label: '用戶 ID (UID)',
                    value: _userId,
                    icon: Icons.vpn_key_outlined,
                  ),
                  const Divider(indent: 16, endIndent: 16, height: 1),
                  _buildInfoItem(
                    label: '帳號創建日期',
                    value: _accountCreationDate,
                    icon: Icons.date_range_outlined,
                  ),
                ],
              ),
            ),

            // 帳號操作區塊
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 30, 20, 10),
              child: Text(
                '帳號操作',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                title: const Text(
                  '刪除帳號',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  // 模擬刪除帳號提示
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('模擬：即將進入刪除帳號流程...'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
