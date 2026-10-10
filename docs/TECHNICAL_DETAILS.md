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
7. 用藥以 Firestore batch 寫入 medicine。另有 savePrescription 方法可寫入 prescriptions，但目前未找到呼叫點，且尚未配置對應規則。

檔案依副檔名決定 MIME，記憶體輸入固定 JPEG。沒有完整 JSON schema 驗證，confidence 未校準。劑量轉換只擷取第一段整數，0.5 顆等劑量需修正與測試。HTTP 呼叫沒有明確 timeout、重試與限流策略。

QR 解析支援 keyword、drugCode、code、id 參數及英數字路徑末段，未限制醫院網域。fetchDrugInfo 目前回傳 null，尚未串接正式醫院 API。

## 用藥、通知與健康同步

FirestoreService.toggleMedicationIntake 使用 transaction 讀取藥品並檢查時段狀態，再同步更新服藥狀態、庫存及新增日誌；取消服用也留下紀錄。

NotificationService 包含 FCM 初始化、token 儲存、本機通知、用藥及漏服提醒，以 timezone 處理排程。實際送達取決於裝置權限、背景限制與 Firebase 設定，需真機驗證；儲存庫未包含完整的伺服器端推播部署。

HealthPlatformService 讀取血壓、心率、血糖、體重、睡眠、步數及運動並同步到 health_records。iOS 使用 Apple 健康、Android 使用 Health Connect，各平台權限與資料可用性需驗證。

## 同步可靠性與效能

儀表板與健康檔案直接解析 snapshot，不再用監聽事件觸發另一輪 get。各資料來源分別追蹤載入與錯誤狀態；重試會先取消舊訂閱，再建立新訂閱，並以世代編號及 UID 避免過期結果更新畫面。個人資料使用固定文件 stream，ProfileScreen 在父元件資料更新時同步更新模型。

| 畫面／資料 | 查詢範圍 |
| --- | --- |
| 儀表板健康統計 | 最近 7 天 |
| 健康檔案最近紀錄 | 最新 20 筆 |
| 個人最新體重／家人單項健康卡 | 指定分類，最新 1 筆 |
| 健康分析圖表 | 最近 90 天，涵蓋 7／30／90 天切換 |
| 飲食首頁 | 當日，跨日後重新綁定 |
| 健康、飲食、用藥歷史／聊天與訊息 | 首批 50 筆，按需載入更多 |
| 儀表板家庭邀請 | pending 且符合目前使用者 email／電話 |

LiveQueryWindow 只維持一組 Firestore 訂閱，多個訂閱者共用快照，較晚加入者也會取得最新資料。載入更多會擴大 limit，保留已載入範圍的即時新增、修改與刪除，避免游標頁面在併發寫入時產生邊界缺漏。代價是每次擴大範圍會重新訂閱整個已載入視窗；目前並未對所有已載入紀錄設總上限。分類篩選在 Firestore 查詢端執行，聊天搜尋只搜尋已載入項目。新增舊訊息不會強制捲回聊天室底部。

AccountBoundary 包在 MaterialApp 外層：UID 改變或登出時，重新建立導覽及所有頁面並釋放舊訂閱。非同步資料載入、圖片讀取、登入及個人資料編輯補上 mounted／UID 防護；閒置計時器以世代檢查避免舊檢查誤登出新帳號。

NotificationService 合併同時初始化呼叫，成功後不再重複初始化；初始化失敗可重試。FCM 前景及 token 更新各保留一組應用生命週期訂閱。通知設定即時監聽，帳號綁定依序執行；切換帳號取消舊排程，同帳號重新開啟應用保留排程。排程等候設定載入並驗證帳號，避免沿用舊帳號設定；token 非同步結果僅寫回原帳號。

權限不足、登入失效、網路中斷、索引未就緒與空資料使用不同狀態。飲食讀取失敗不再放入示範紀錄，AI 回應解析失敗也不再產生測試營養數據；未成功取得或確認的分析不會因此寫入飲食紀錄。資料快照不再控制分析對話框的關閉。

複合索引包含 health_records 的 category／record_time、family_invites 的 status／目標 email 或電話，以及 chats 的 members／lastTime。部署前可檢查現有索引，避免覆蓋其他設定；部署命令：

```sh
firebase deploy --only firestore:indexes --project health-management-f046a
```

索引部署完成後仍需等待狀態 READY；Firestore 模擬器測試不能代替線上索引可用性檢查。

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

- settings 僅允許擁有者讀寫；prescriptions 尚未定義規則，呼叫儲存方法仍會被拒絕。
- 家庭健康分享由資料擁有者的 family_members 文件授權，血糖／血壓查詢必須限定 category，用藥依分享權限讀取；日誌僅允許擁有者新增及讀取。
- 接受邀請透過交易確認期限、對象及 pending 狀態，一次建立雙方關係。邀請者分享自己的資料；接受者預設不分享，需自行開啟。分享設定支援現有中文欄位別名。
- 新家庭關係含 inviteId，規則以已接受的邀請驗證雙方關係。缺少此驗證紀錄的舊關係需雙方移除後重新綁定；不會自動信任原先寬鬆規則建立的資料。
- 家庭移除一次刪除雙方關係；任何一方關係消失即停止授權。聊天室更新不可變更 members；新增訊息必須使用自己的 senderId。
- users 基本文件仍允許所有已登入者讀取；健康或私人欄位與公開基本資料的拆分仍待後續處理。
- Firestore 複合索引定義於 firestore.indexes.json；Storage rules 尚未納入。
- `.env` 被打包為 Flutter asset；不提交 Git 仍無法避免從發佈的應用取得金鑰。正式版應由後端保管金鑰、驗證使用者並限制額度。
- 辨識結果需人工核對，尚無完整 OCR 正確率、藥品校驗或跨平台驗證證據。

## 測試狀態

新增交易與同步測試及 Firestore 模擬器授權測試：

```sh
flutter test --no-pub
npm install
npm run test:rules
```

規則測試使用 demo-healthpal-priority1，本機需安裝 Firebase CLI 及其支援的 Java 版本。模擬器不會部署線上規則。正式規則需在新版應用及家庭關係重新綁定流程準備好後另行部署。

widget_test.dart 驗證帳號切換會清除舊導覽與頁面狀態。priority_two_test.dart 驗證即時視窗的新增、更新、刪除、載入更多、延後訂閱、釋放、分類查詢，以及初始化合併與失敗重試。真機通知、小數劑量、完整 JSON schema 與跨平台建置尚待後續驗證。
