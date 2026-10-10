import '../theme/app_colors.dart';
import 'package:flutter/material.dart';

class DataExportScreen extends StatelessWidget {
  const DataExportScreen({super.key});

  // 建立數據項目清單
  Widget _buildDataItem(BuildContext context, String title, String subtitle) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.description_rounded, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: ElevatedButton(
          onPressed: () {
            // 修正: 縮短 SnackBar 顯示時間
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('正在準備匯出 $title...'),
                duration: const Duration(milliseconds: 800), 
              ),
            );
          },
          // !!! 這裡是修正的關鍵：刪除了多餘的 '}' 符號
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('匯出', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
  
  // 新增: 建立分享與列印操作的項目
  Widget _buildShareReportItem(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: InkWell(
        onTap: () {
          // 模擬導航到分析報告頁面進行分享和列印
          ScaffoldMessenger.of(context).showSnackBar(
            // 修正: 縮短 SnackBar 顯示時間
            const SnackBar(
              content: Text('導航至分析報告畫面，準備分享/列印...'),
              duration: Duration(milliseconds: 800),
            ),
          );
          // TODO: 實際應用中，您應該導航到 ReportShareScreen 或 AnalyticsScreen
          /*
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const ReportShareScreen()),
          );
          */
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.1),
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            children: [
              Icon(Icons.analytics_rounded, color: AppColors.primary, size: 28),
              SizedBox(width: 15),
              Expanded(
                child: Text(
                  '分享報告後列印',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Icon(Icons.print_rounded, color: AppColors.primary),
              Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('數據匯出與管理',
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
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                '您可以選擇性地查看和匯出您的健康數據，以方便備份或分享給醫療專業人員。',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),

            // 新增的「分享報告後列印」項目
            _buildShareReportItem(context),
            
            // 數據匯出列表
            _buildDataItem(
              context, 
              '個人健康數據 (PDF/JSON)', 
              '包括體重、血壓、血糖、血氧等歷史記錄。',
            ),
            _buildDataItem(
              context, 
              '運動與活動數據 (CSV)', 
              '包括步數、里程、卡路里消耗和GPS軌跡。',
            ),
            _buildDataItem(
              context, 
              '用藥與提醒記錄 (CSV)', 
              '所有服藥提醒和完成記錄。',
            ),

            const SizedBox(height: 30),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '匯出文件將以加密方式儲存至您的設備或發送到您的電子郵件。',
                style: TextStyle(color: AppColors.textHint, fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
