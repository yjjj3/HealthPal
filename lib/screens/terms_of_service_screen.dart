import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 服務條款頁面
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '服務條款',
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
              '1. 服務說明',
              '''本健康管理應用程式（以下簡稱「本服務」）提供以下功能：

• 健康數據記錄（血壓、血糖、體重、運動、睡眠）
• 用藥管理與提醒
• 飲食記錄與營養分析
• AI 健康助手「小安」諮詢
• 家庭成員健康資料共享
• 健康趨勢分析與報告

本服務旨在協助您管理日常健康資訊，但不提供醫療診斷或治療建議。''',
            ),
            _buildSection(
              '2. 使用資格',
              '''使用本服務，您需要：

• 年滿 13 歲（未滿 18 歲需經家長或監護人同意）
• 擁有有效的電子郵件地址
• 同意本服務條款及隱私權政策

您需對帳號安全負責：
• 保護您的登入憑證
• 不與他人分享帳號
• 發現未經授權使用時立即通知我們''',
            ),
            _buildSection(
              '3. 使用規範',
              '''使用本服務時，您同意：

正當使用
• 僅記錄真實的健康資訊
• 不使用自動化工具存取本服務
• 不嘗試破壞或干擾服務運作

禁止行為
• 提供虛假或誤導性資訊
• 冒充他人或未經授權存取他人資料
• 使用本服務進行任何違法活動
• 上傳惡意程式碼或有害內容
• 規避任何安全措施或存取控制''',
            ),
            _buildSection(
              '4. AI 健康助手使用條款',
              '''關於 AI 健康助手「小安」：

服務內容
• 小安使用 OpenAI 技術提供智慧回應
• 小安會參考您的健康紀錄提供個人化建議
• 對話內容會發送至 OpenAI 處理

重要限制
• 小安提供的資訊僅供參考
• 小安不是醫療專業人員
• 不應將小安的建議視為醫療診斷或處方
• 有健康疑慮請務必諮詢專業醫師

使用責任
• 您需自行判斷小安建議的適用性
• 依據小安建議採取的行動由您自行負責''',
            ),
            _buildSection(
              '5. 智慧財產權',
              '''本服務的智慧財產權：

我們擁有的權利
• 應用程式的設計、程式碼、圖形介面
• 「小安」AI 助手的名稱與形象
• 服務中的文字、圖像及其他內容

您擁有的權利
• 您輸入的個人健康資料
• 您上傳的照片與內容

您授予我們的權利
• 處理您的資料以提供服務的權利
• 匿名化後用於改善服務的權利''',
            ),
            _buildSection(
              '6. 免責聲明',
              '''重要免責聲明：

非醫療服務
• 本服務不構成醫療建議、診斷或治療
• 不應取代專業醫療人員的意見
• 緊急情況請立即撥打急救電話

服務可用性
• 我們盡力維持服務穩定運作
• 不保證服務 100% 無中斷或無錯誤
• 可能因維護、更新或不可抗力因素暫停服務

資料準確性
• 我們依賴您提供的資料進行分析
• 不保證分析結果的絕對準確性
• AI 建議可能存在錯誤或不適用的情況''',
            ),
            _buildSection(
              '7. 責任限制',
              '''在法律允許的最大範圍內：

• 我們不對因使用或無法使用本服務造成的任何直接、間接、附帶、特殊或衍生性損害負責

• 我們不對您依據本服務資訊採取或未採取行動所導致的健康後果負責

• 我們的最大責任金額不超過您過去 12 個月支付的服務費用（如本服務為免費，則為新台幣 100 元）''',
            ),
            _buildSection(
              '8. 服務變更與終止',
              '''服務變更
• 我們可能隨時更新、修改或終止部分功能
• 重大變更將提前通知

帳號終止
• 您可隨時刪除帳號
• 我們可能因違反條款而終止您的帳號
• 終止後您的資料將依隱私權政策處理

終止後的影響
• 您將無法存取本服務
• 我們可能保留部分資料用於法律遵循''',
            ),
            _buildSection(
              '9. 條款修改',
              '''我們保留修改本條款的權利：

• 修改後的條款將公布於本頁面
• 重大修改將透過應用程式通知
• 繼續使用本服務視為同意新條款
• 如不同意新條款，請停止使用本服務並刪除帳號''',
            ),
            _buildSection(
              '10. 準據法與管轄',
              '''本條款的解釋與適用：

• 以中華民國法律為準據法
• 因本條款產生的爭議，雙方同意以台灣台北地方法院為第一審管轄法院

如有任何問題，請聯繫：
電子郵件：support@healthapp.example.com''',
            ),
            const SizedBox(height: 40),
            _buildMedicalDisclaimer(),
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

  Widget _buildMedicalDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.red.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_hospital_rounded,
                color: Colors.red.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '醫療免責聲明',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '本應用程式不是醫療器材，提供的所有資訊僅供參考，不能替代專業醫療諮詢、診斷或治療。使用本應用程式前請諮詢您的醫師或其他合格醫療專業人員。如遇緊急醫療狀況，請立即撥打 119 或前往最近的急診室。',
            style: TextStyle(
              fontSize: 14,
              color: Colors.red.shade900,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
