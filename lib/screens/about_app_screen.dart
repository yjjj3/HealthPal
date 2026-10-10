import '../theme/app_colors.dart';
import 'package:flutter/material.dart';

// =================================================================
// 匯入其他頁面檔案 (關鍵修正)
// 在實際專案中，這些檔案應位於正確的路徑，此處使用檔名進行模擬。
// =================================================================
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';

// =================================================================
// AboutAppScreen Widget
// 這是「關於本應用程式」頁面，顯示版本、法律聲明等資訊。
// =================================================================
class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  // 建立操作項目 (使用 ListTile)
  Widget _buildActionItem({
    required String title,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const String appName = 'HealthPal';

    return Scaffold(
      appBar: AppBar(
        title: const Text('關於本應用程式',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            // --- 應用程式 Logo 與名稱 ---
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 60),
            ),
            const SizedBox(height: 15),
            const Text(
              appName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 40),

            // --- 隱私政策 (導航到 PrivacyPolicyScreen) ---
            _buildActionItem(
              title: '隱私政策',
              icon: Icons.lock_outline_rounded,
              onTap: () {
                // 使用匯入的 PrivacyPolicyScreen
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
                );
              },
            ),
            
            // --- 服務條款與使用者協議 (導航到 TermsOfServiceScreen) ---
            _buildActionItem(
              title: '服務條款與使用者協議',
              icon: Icons.policy_rounded,
              onTap: () {
                // 使用匯入的 TermsOfServiceScreen
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const TermsOfServiceScreen()),
                );
              },
            ),

            // --- 版權與版本資訊 ---
            const SizedBox(height: 60),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                '本應用程式旨在協助健康管理，不可取代專業醫療建議。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '© 2025 HealthPal 版權所有',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
