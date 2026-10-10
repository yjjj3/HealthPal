# HealthPal 技術細節

依目前原始碼整理，不代表所有功能已通過整合測試。

## 架構與啟動

畫面、服務、模型、共用元件與主題分層。狀態主要使用 StatefulWidget、setState 與 StreamBuilder；部分畫面直接操作 Firestore，尚未全面抽象為 repository。

main.dart 初始化 Flutter 綁定、Firebase、通知與截圖保護，再啟動應用。個別初始化失敗會記錄後繼續，啟動成功不代表所有後端服務就緒。AuthScreen 監聽 Firebase Auth 切換登入頁及主畫面；主導覽含儀表板、紀錄、用藥、分析、飲食及個人頁，並追蹤操作支援逾時登出。

## 處方箋辨識流程

核心為 `lib/services/prescription_scan_service.dart` 與 `lib/models/prescription_model.dart`。

1. 依圖片內容識別 JPEG、PNG、GIF、WebP，拒絕不支援的格式、空檔與超過 10 MiB 的輸入，再編碼為 Base64；這是格式簽章檢查，不代表完整圖片解碼驗證。
2. 由共用 AIClient 發送請求：gpt-4o、圖片 detail high、temperature 0.1、max_tokens 4096。正式版走 Firebase AI gateway，debug 可使用本機開發金鑰。
3. 使用 strict JSON schema，並以 PrescriptionRecognition 再驗證欄位型別、非負數量、日期與 0–1 confidence。拒絕、截斷、空白或不合法回應會回報錯誤，不保存原始回應或產生假資料。
4. 不明劑量、頻率、時機、單位與給藥途徑保留空值，確認畫面要求人工補齊；不自動猜成每天一顆。副作用與注意事項保留模型回傳原文，仍需與原圖核對。
5. 多張圖片依序處理；任何一張失敗都中止該批，不將部分結果當作完整辨識。
6. PrescriptionMedicationMapper 負責轉換；MedicationDose 統一處理小數、分數、半顆與頻率。0.5 顆從建立、編輯、庫存到服藥日誌皆保留小數；不支援的複雜用法要求確認。PRN 不建立固定提醒；不明頻率不猜測。編輯時保留相同時段的服藥狀態。
7. 用藥以 Firestore batch 寫入 medicine。另有未被畫面使用的 savePrescription 方法，prescriptions 尚未配置規則。

JSON schema 只能約束格式，不能證明辨識正確；confidence 未經校準，尚未建立 OCR 正確率或藥品資料庫交叉校驗。結構化輸出依 [OpenAI 官方文件](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=chat) 設定，拒絕與截斷仍由客戶端另外處理。

QR 解析支援 keyword、drugCode、code、id 參數及英數字路徑末段，只接受 HTTP(S) 且不含帳密的網址，未限制醫院網域；不會直接存取該網址。fetchDrugInfo 目前回傳 null，尚未串接正式醫院 API。

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
- `.env` 不再打包。debug 開發金鑰仍可由開發 APK 取得，僅供本機使用；release/profile 不讀取此金鑰，必須設定受驗證的後端。
- 辨識結果需人工核對，尚無完整 OCR 正確率、藥品校驗或跨平台驗證證據。

## 測試狀態

新增交易與同步測試及 Firestore 模擬器授權測試：

```sh
flutter test --no-pub
npm install
npm run test:rules
```

規則測試使用 demo-healthpal-priority1，本機需安裝 Firebase CLI 及其支援的 Java 版本。模擬器不會部署線上規則。正式規則需在新版應用及家庭關係重新綁定流程準備好後另行部署。

widget_test.dart 驗證帳號切換會清除舊導覽與頁面狀態。priority_two_test.dart 驗證即時視窗的新增、更新、刪除、載入更多、延後訂閱、釋放、分類查詢，以及初始化合併與失敗重試。priority_three_test.dart 驗證小數劑量、未知處方拒絕轉換、欄位驗證、回應拒絕／截斷、HTTP 超時、限流、佇列上限、帳號切換及 AI 查詢範圍。functions/test 驗證驗證身分、額度與錯誤資訊清理。真機通知、實際 AI 辨識品質及跨平台建置仍需額外驗證。

## 共用 AI 與資料結構

AIService、OpenAIService 相容入口與 PrescriptionScanService 共用 AIClient／AIConfig，不再各自維護 HTTP 與金鑰狀態。提示詞、schema、資料驗證與處方轉換分開存放；既有畫面仍可使用 map adapter，並未全面重寫所有 UI 狀態管理。

AIClient 同時最多 2 項工作、等候最多 8 項；每項傳送與重試共用 45 秒期限。只有明確 429 限流會等待 1–5 秒後重試一次；額度不足、逾時及其他失敗不重送。帳號變更會拒絕尚未發送的舊資料與舊結果。取消飲食分析會忽略後續結果；已傳送的遠端工作可能仍完成。

NutritionAnalysis 要求真正布林值、必填文字、非負有限營養數字與 1–10 整數評分；非食物必須有說明。不再從敘述中猜 JSON，或用預設營養值補齊損壞回應。營養分析仍為模型估計，需由使用者確認。

HealthContextRepository 共用有上限的查詢：健康最近 30 天最多 100 筆；服藥與飲食最近 7 天各最多 50 筆；藥品最多 100 筆。讀取失敗向上回報，不偽裝成沒有紀錄；超出範圍的歷史不會納入本次分析。

## AI gateway 部署與開發設定

`functions/` 使用 Node 22、Firebase Functions v2，部署區域 asia-east1。只接受非匿名 Firebase ID token，並驗證模型、訊息、圖片 data URI、token 與請求大小；不接受外部圖片網址。伺服器在 Secret Manager 讀取 OPENAI_API_KEY，錯誤回應不暴露上游文字或金鑰。

Firestore 交易限額：每位使用者每分鐘 10 次、每日 50 次，整個專案每日 1000 次；日期以 UTC 計算。請求開始即計數，失敗不退還。`_ai_usage` 只有 Admin SDK 使用，客戶端規則預設拒絕。此限制控制請求數，並不等同供應商費用上限；正式運作仍需監控費用。

```sh
npm --prefix functions ci
npm --prefix functions test
firebase functions:secrets:set OPENAI_API_KEY --project health-management-f046a
firebase deploy --only functions:healthpal-ai --project health-management-f046a
flutter build apk --release --dart-define=AI_GATEWAY_URL=https://YOUR_DEPLOYED_ENDPOINT
```

部署需先完成專案的 Cloud Functions API 與必要計費設定。後端原始碼與測試已提供，端點及伺服器金鑰需在正式部署後設定；本文件不表示後端已上線。本機 debug 使用 `.env.development.json` 與 `--dart-define-from-file`，檔案被 Git 忽略；也可在 debug 設定 gateway 直接測試登入驗證。

## 持續驗證

`.github/workflows/validate.yml` 使用 Flutter 3.41.9、Node 22、Java 21，執行 Flutter 測試、AI gateway 測試、Firestore 規則模擬器及 Android debug 建置。靜態分析遇到 error 會失敗，既有 warning/info 尚未全部清理。`tool/bootstrap_ci.py` 僅在 CI 產生缺少的公開 demo Firebase 設定，不替換既有設定，不包含正式憑證；CI APK 不用於正式服務。

Android 建置使用 Gradle 8.14、AGP 8.13.1、Kotlin 2.3.20，Java/Kotlin target 17。依健康套件需求設定 minSdk 26（Android 8.0），並啟用通知套件要求的 core library desugaring。Kotlin／Gradle 相容範圍參考 [Kotlin 官方文件](https://kotlinlang.org/docs/gradle-configure-project.html)。
