# HealthPal 技術細節

依目前原始碼整理，不代表所有功能已通過整合測試。

## 架構與啟動

畫面、服務、模型、共用元件與主題分層。狀態主要使用 StatefulWidget、setState 與 StreamBuilder；部分畫面直接操作 Firestore，尚未全面抽象為 repository。

main.dart 初始化 Flutter 綁定、Firebase、通知、dotenv 與截圖保護，再啟動應用。個別初始化失敗會記錄後繼續，啟動成功不代表所有後端服務就緒。AuthScreen 監聽 Firebase Auth 切換登入頁及主畫面；主導覽含儀表板、紀錄、用藥、分析、飲食及個人頁，並追蹤操作支援逾時登出。

## 處方箋辨識流程

核心為 `lib/services/prescription_scan_service.dart` 與 `lib/models/prescription_model.dart`。

1. 讀取圖片檔案或 Uint8List，編碼為 Base64。
2. HTTP POST 至程式設定的 `/v1/chat/completions`，模型 gpt-4o、圖片 detail high、temperature 0.1、max_tokens 4096。
3. Prompt 要求回傳 medicines、hospitalInfo 與 confidence，保留副作用與注意事項原文；這是模型指示，不是正確性保證。
4. 移除 Markdown code fence 並解析 JSON；失敗回傳 error、rawContent、confidence 0。
5. 多張圖片依序處理，單張失敗後繼續，結果可能只含部分成功資料或為空。
6. 確認畫面提供人工核對；依用餐時間、服用時機與頻率轉換用藥模型和提醒時間。
7. 處方箋存入 prescriptions；用藥以 Firestore batch 寫入 medicine。兩項儲存不是同一個原子交易。

檔案依副檔名決定 MIME，記憶體輸入固定 JPEG。沒有完整 JSON schema 驗證，confidence 未校準。劑量轉換只擷取第一段整數，0.5 顆等劑量需修正與測試。HTTP 呼叫沒有明確 timeout、重試與限流策略。

QR 解析支援 keyword、drugCode、code、id 參數及英數字路徑末段，未限制醫院網域。fetchDrugInfo 目前回傳 null，尚未串接正式醫院 API。

## 用藥、通知與健康同步

FirestoreService.toggleMedicationIntake 使用 transaction 讀取藥品並檢查時段狀態，再同步更新服藥狀態、庫存及新增日誌；取消服用也留下紀錄。

NotificationService 包含 FCM 初始化、token 儲存、本機通知、用藥及漏服提醒，以 timezone 處理排程。實際送達取決於裝置權限、背景限制與 Firebase 設定，需真機驗證；儲存庫未包含完整的伺服器端推播部署。

HealthPlatformService 讀取血壓、心率、血糖、體重、睡眠、步數及運動並同步到 health_records。iOS 使用 Apple 健康、Android 使用 Health Connect，各平台權限與資料可用性需驗證。

## 資料路徑

| Firestore 路徑 | 用途 |
| --- | --- |
| users/{uid} | 基本資料與 FCM token 等 |
| users/{uid}/medicine | 藥品與服藥狀態 |
| users/{uid}/medication_logs | 服用與取消日誌 |
| users/{uid}/prescriptions | 處方箋 |
| users/{uid}/health_records | 健康紀錄 |
| users/{uid}/diet_records | 飲食紀錄 |
| users/{uid}/settings | 設定 |
| users/{uid}/family_members | 家庭成員 |
| family_invites/{inviteCode} | 邀請 |
| chats/{chatId}/messages | 訊息 |

SharedPreferences 儲存用餐時間等本機設定；flutter_secure_storage 與 local_auth 提供安全儲存及生物辨識能力，不代表所有雲端資料有額外應用層加密。

AIAssistantService 與 HealthAIAnalyzer 蒐集個人資料、健康、用藥、服藥及飲食紀錄供分析；實際請求內容會傳送至外部 AI 服務，正式產品需清楚告知並取得適當同意。

## 資料存取與目前限制

- firestore.rules 對健康、飲食、用藥與日誌要求擁有者權限；日誌僅允許新增及讀取。
- prescriptions 與 settings 沒有允許規則，按此規則部署後相關操作會被拒絕。
- users 文件允許所有已登入者讀取，不宜放入其他帳號不應看見的私人資料。
- family_invites 允許任意已登入者更新，family_members 允許任意已登入者建立，需補邀請有效性與授權檢查。
- 聊天成員可更新聊天室，但未限制 members 欄位變更，需增加欄位驗證。
- 未包含 Storage rules 與 Firestore index 定義，後端部署尚不完整。
- `.env` 被打包為 Flutter asset；不提交 Git 仍無法避免從發佈的應用取得金鑰。正式版應由後端保管金鑰、驗證使用者並限制額度。
- 辨識結果需人工核對，尚無完整 OCR 正確率、藥品校驗或跨平台驗證證據。

## 測試狀態

現有 widget test 是計數器範本。後續應優先驗證 JSON 解析、小數劑量、提醒時間換算、Firestore transaction、存取規則與真機通知。平台資料夾存在不等於已通過建置或功能驗證。
