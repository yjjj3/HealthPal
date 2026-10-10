import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 隱私權政策頁面
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '隱私權政策',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLastUpdated(),
            const SizedBox(height: 24),
            _buildSection(
              '1. 資料收集',
              '''本應用程式為提供健康管理服務，會收集以下資料：

個人基本資料
• 姓名、性別、出生日期
• 電子郵件（用於帳號登入）
• 身高、體重、血型

健康相關資料
• 血壓、血糖、體重等健康數值紀錄
• 用藥資訊與服藥紀錄
• 飲食紀錄與營養分析
• 運動與睡眠紀錄

裝置資訊
• 裝置型號與作業系統版本（用於問題排除）
• 推播通知 Token（用於發送提醒通知）''',
            ),
            _buildSection(
              '2. 資料使用方式',
              '''我們收集的資料將用於：

• 提供個人化健康管理服務
• 生成健康趨勢分析與建議
• 發送用藥提醒與健康通知
• AI 健康助手「小安」提供個人化回應
• 改善應用程式功能與使用者體驗
• 與您授權的家庭成員分享健康資訊

我們不會將您的個人資料出售給第三方。''',
            ),
            _buildSection(
              '3. 資料儲存與安全',
              '''資料儲存
• 您的資料儲存於 Google Firebase 雲端服務
• 資料中心位於亞太地區（新加坡/東京）

安全措施
• 所有資料傳輸採用 TLS/SSL 加密
• Firebase 提供業界標準的資料加密儲存
• 密碼經過雜湊加密處理，我們無法查看您的密碼

存取控制
• 每位使用者只能存取自己的資料
• 家庭成員資料共享需經雙方同意''',
            ),
            _buildSection(
              '4. 第三方服務',
              '''本應用程式使用以下第三方服務：

Firebase（Google）
• 用途：帳號驗證、資料儲存、推播通知
• 隱私政策：https://firebase.google.com/support/privacy

OpenAI
• 用途：AI 健康助手「小安」的智慧回應
• 您與小安的對話內容會發送至 OpenAI 處理
• 隱私政策：https://openai.com/privacy

Apple HealthKit / Google Fit（選用）
• 用途：同步健康資料
• 僅在您授權後才會存取
• 資料僅儲存於您的裝置與本應用程式''',
            ),
            _buildSection(
              '5. 您的權利',
              '''您擁有以下權利：

查閱權
• 您可以隨時在應用程式中查看所有個人資料

更正權
• 您可以隨時編輯並更正個人資料

刪除權
• 您可以透過「帳號設定」中的「刪除帳號」功能
• 刪除帳號將永久移除所有相關資料

資料可攜權
• 您可以透過「健康檔案」功能匯出您的健康紀錄

撤回同意
• 您可以隨時在裝置設定中關閉通知權限
• 您可以在應用程式中取消與家庭成員的資料共享''',
            ),
            _buildSection(
              '6. 兒童隱私',
              '''本應用程式不專門針對 13 歲以下兒童設計。

如果您是家長或監護人，發現您的孩子在未經同意的情況下向我們提供了個人資訊，請聯繫我們，我們將採取措施刪除相關資訊。''',
            ),
            _buildSection(
              '7. 政策變更',
              '''我們可能會不時更新本隱私權政策。

當政策有重大變更時，我們會：
• 在應用程式內發送通知
• 更新本頁面的「最後更新日期」

建議您定期查閱本政策以了解最新資訊。''',
            ),
            _buildSection(
              '8. 聯絡我們',
              '''如果您對本隱私權政策有任何疑問，請透過以下方式聯繫：

電子郵件：support@healthapp.example.com

我們將在收到您的來信後 7 個工作天內回覆。''',
            ),
            const SizedBox(height: 40),
            _buildDisclaimer(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdated() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.update_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '最後更新日期：2025 年 1 月 1 日',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              content,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Colors.orange.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '重要聲明',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '本應用程式提供的健康資訊僅供參考，不構成醫療建議。如有健康疑慮，請諮詢專業醫療人員。',
            style: TextStyle(
              fontSize: 14,
              color: Colors.orange.shade900,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
