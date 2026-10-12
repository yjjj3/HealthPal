# HealthPal 技術細節

## 架構與一致性

Flutter 畫面、服務、模型及共用元件分層；部分畫面仍直接操作 Firestore。Firebase 提供帳號、資料與檔案儲存，AIClient 共用 HTTP transport、JSON schema 驗證與 gateway。正式 AI 請求需 Firebase ID token，伺服器保存供應商金鑰；請求限額不等同費用上限。

- **服藥交易**：同一交易更新狀態、庫存、receipt 與日誌；取消回補原扣除量，重複操作不重複扣補。編輯合併實際修改欄位並檢查衝突。
- **療程提醒**：共用開始／結束日及頻率規則，規劃未來最多 30 日，以 60 則總通知為保守預算。容量不足顯示省略與涵蓋期限；App 關閉後不能無限補排。
- **紀錄完成率**：分母為已到期應服時段，依操作序號取最終狀態。歷史、日誌或快照不完整時不宣稱精確百分比；每日重置與服藥操作時間分開保存。
- **處方**：圖片／AI 回應驗證後人工確認；藥品與來源共用草稿身分。固定文件 ID 與批次標記防止重試重複新增或復活已刪文件。資料儲存與通知失敗分別回報。
- **帳號邊界**：UID 改變重建導覽、釋放監聽與快取；非同步結果驗證世代及原帳號。通知原生工作串列執行，切換帳號等待舊工作結束再清除。這些保護仍需真機及跨裝置驗證。

主要資料位於 `users/{uid}/medicine`、`medication_logs`、`health_records`、`diet_records`、`settings` 與家庭／聊天集合。規則及索引版本控制；模擬器不能證明正式索引已 READY。未使用的 prescriptions 路徑與 Storage 規則仍需個別評估，不假設所有資料已受完整保護。

## iOS 相容性

本機使用 Xcode 26.6／iOS SDK 26.5；Flutter 與 55 個 CocoaPods 依原鎖檔安裝，沒有升級版本。

| 範圍 | 有效最低版本／理由 |
| --- | --- |
| Runner／HealthWidgetExtension 的 Debug、Profile、Release | iOS 16，完整產物亦確認 minimum 16 |
| Pods | 保持原 Podfile／post_install 16；mobile_scanner／MLKit 至少 15.5，Firebase 至少 15 |
| RunnerTests | 繼承 project 13，未修改；尚未執行原生 XCTest |

健康 Widget 是 Bundle 唯一註冊項目；同步資料夾中的未註冊範例仍會編譯。WidgetConfigurationIntent、preview（iOS 17）、ControlWidget／intent（18）、ActivityKit／Dynamic Island（16.1）加入 availability；containerBackground（17）在 iOS 16 使用相容背景。沒有啟用新範例功能，也沒有需要 iOS 26 的來源 API。

mobile_scanner 6.0.2 鎖定 GoogleMLKit/BarcodeScanning 7，排除模擬器 i386／armv7／arm64。MLImage／MLKitCommon／MLKitVision 的 arm64 slice 為 device、x86_64 為 simulator；BarcodeScanning 是相依的靜態 fat library。沒有清除架構排除。iOS 26+ arm64 模擬器仍受限；device arm64 建置成功不能解除這項模擬器限制。

## 最短本機驗證

Firebase 平台設定與開發環境前提見 [README](../README.md#ios-開發)。以下只編譯，不安裝／啟動 App：

```sh
flutter pub get --enforce-lockfile
(cd ios && COCOAPODS_DISABLE_STATS=true pod install --deployment)
FLUTTER_SUPPRESS_ANALYTICS=true flutter --no-version-check build ios --debug --no-codesign --no-pub
flutter --no-version-check build ios --simulator --debug --no-codesign --no-pub
python3 tool/check_ios_compatibility.py
```

若要重現既有 iOS 18.2／x86_64 目的地建置，先以 `xcrun simctl list devices available` 查得並替換 `<SIMULATOR_ID>`：

```sh
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>,arch=x86_64' "BUILD_DIR=$PWD/build/ios" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

## 驗證矩陣（2026-10-11）

| 檢查 | 原始碼 commit | 結果／範圍 |
| --- | --- | --- |
| 完整 iPhone device debug no-codesign | a149059 | exit 0；App／Widget 都是 iphoneos、arm64、minimum 16.0；codesign 確認未簽署，無簽章目錄／provisioning profile |
| 完整 simulator debug／指定 iOS 18.2 目的地 | b607541 | exit 0；App x86_64、App／Widget minimum 16.0；未啟動 |
| Widget 嚴格 SDK typecheck | b607541 | iOS 16 arm64 device／simulator 通過，warnings-as-errors；不是整 App 執行測試 |
| Flutter 全套／backend／localhost rules | b607541 | 119／7／10 項通過，假資料與本機模擬器 |
| Dart 分析 | b607541 | 0 error、13 warning、368 info；既有問題未增加，分析命令因既有診斷 exit 1 |
| GitHub Ubuntu CI | a149059 | success、artifact 0；分析／Flutter／backend／rules，不做 iOS 原生建置 |

登出與家庭授權修正另於 2026-10-11，以 `df26ae3` 為基準的本機差異驗證：Flutter 162 項、backend 7 項、localhost rules 18 項通過；分析 0 error／10 warning／352 info（exit 1，無新增診斷）。完整 iPhone debug no-codesign exit 0，App／Widget 均 arm64、minimum 16、未簽署；Widget 嚴格 typecheck 通過。此結果未代表正式規則已部署或真機功能已通過。

原生建置仍有既有套件及 UIScene 相容性提示；MLKit 的模擬器警告不是 device 建置失敗。編譯成功不證明登入、權限、正式服務或資料安全全面通過；未以正式健康資料／真實 AI 驗證。

## Gateway 設定

使用自己的 Firebase 專案、已安裝 Firebase CLI／Node 22。部署可能產生費用，須自行確認專案與授權：

```sh
npm --prefix functions ci
firebase functions:secrets:set OPENAI_API_KEY --project YOUR_FIREBASE_PROJECT
firebase deploy --only functions:healthpal-ai --project YOUR_FIREBASE_PROJECT
```

金鑰僅存 Secret Manager；自己的 URL 填入未追蹤環境檔 AI_GATEWAY_URL，覆寫既有預設。規則／索引及登入設定另行審閱，勿將秘密放入 client 或文件。

## 登出與認證邊界

手動與 timeout 共用登出協調器，重複操作合併；Firebase 登出失敗保留登入狀態並顯示重試，通知清理失敗與認證成功分開呈現。只有認證變更及必要憑證儲存加入 auth 序列；Firestore 資料工作獨立守衛，離線 pending 不阻擋真正 signOut。登出及成功登入使舊資料工作失效，遲到結果不報成功；導航由 auth 狀態決定。原生通知工作排空後再清除，FCM token 更新不阻塞帳號 ready。2026-10-12 的 App 解鎖改動移除密碼快登；原生通知及 provider 行為仍需真機驗證。

## App 解鎖（2026-10-12，本次驗證快照，已複核）

根層閘門位於所有受保護 Navigator／路由之前，未解鎖不掛載敏感頁面；公共登入 Navigator 不採用受保護的 deep link／restoration 路由。UID 與認證世代綁定 async 結果，Email／Google 成功登入發布本世代 fresh 驗證，冷啟動恢復的 Firebase session 不算 fresh。這不是螢幕擷取遮罩，解鎖後可鏡像。

逐 UID 的裝置設定預設 OFF；Face ID／生物辨識成功、使用者確認、Keychain 寫入並讀回相符後才報啟用。啟用者冷啟動先鎖、離開滿 60 秒再鎖；短暫系統 prompt 不觸發 60 秒鎖，Face ID 自身 inactive／resumed 不循環鎖，真正 paused 使待驗證結果失效。local_auth 僅 biometricOnly、不新增 App PIN；不可用／取消／錯誤留鎖頁。

舊 `user_email`／`user_credential`／`biometric_enabled` 逐項刪除並核對結果，不繼承舊同意、不記錄內容；新讀寫或遷移失敗拒絕放行且可重試。重新登入必須真正 signOut 並完成通知清理。閒置計時改由根層持有，避免卸載鎖頁下方主頁就停止計時；預設 5 分鐘與既有可調設定保留，resume／驗證前後核對牆鐘期限，成功解鎖才記為活動。短返回僅在已載入設定的同步期限仍有效時保留原導覽；未知或到期先阻擋。

設定寫入／讀回跨背景或 resume 時，確認值仍同步到當前世代；待確認期間先阻擋並保留離開時間，完成後依 60 秒與閒置期限判定，不把背景設定完成算成活動。F1 先以兩項失敗回歸重現，再覆蓋啟用／停用、59／60 秒、讀回與 resume 並行、儲存失敗及切帳號／同 UID 新世代遲到完成。

本次已複核驗證快照（基準 `0697335`）：Flutter 229 項（含原 162 項）／解鎖與登出專項 83 項通過；分析 0 error、10 warning、348 info（exit 1，無新增）；arm64 device debug no-codesign／no-pub exit 0，App／Widget minimum 16、未簽署。fake 含設定 UI、59／60 秒、生命週期、遲到結果與實際 Flutter restoration；未連手機、安裝或執行，既有 MLKit simulator 警示保留。

## 家庭 profile 授權

完整 `users/{uid}` 僅本人可讀；每位家人獨立、預設全關的欄位投影與記錄授權，撤回清除舊值，未知／缺值不推定同意。邀請及聊天不依賴對方私密 profile；舊關係缺投影顯示未分享。規則、資料格式與需新版客戶端的切換順序見 [家庭授權](FAMILY_PROFILE_SHARING.md)，正式環境尚未切換。移除／拒絕使用讀取前提交易，原關係與投影版本避免舊 retry 刪到重綁關係或覆蓋新撤回；取消等待不能收回已接受的伺服器提交。

## 真機待驗

整 App arm64 device **編譯**已驗證；簽署、安裝／啟動、iOS 16 實際執行與原生 XCTest 尚未驗證。使用測試帳號與虛構資料檢查：

1. 通知拒絕／允許及容量提示；關閉 App 後跨日、隔日／每週與省電送達。
2. 服用→取消→再服用、編輯療程及時區變更後的日誌與補排。
3. 兩裝置離線操作後重連：庫存、最終狀態及資料不完整提示。
4. 切換帳號時待完成的掃描、儲存、通知與 Widget 不沿用舊資料。
5. 虛構處方確認、編輯／刪除、斷線重試：無重複或復活藥品。
6. HealthKit、相機、登入及 App Groups 權限與 Widget 更新。
7. 每位家人逐項分享、撤回、移除／重綁與離線重連；登出失敗及通知清理失敗提示。

## AI 離線可驗證性（2026-10-12）

以 `af611d8` 為基準，新增 16 例純合成 golden 與分離的 oracle／刻意錯誤 raw outputs。離線 CLI 經實際 AIClient／scan service／Dart parser／model／mapper，以逐欄 known／unknown 分母和整張匹配分開報告。已修掃描頁將 `error:null` 誤判失敗的分支；保留人工確認。schema／parser 寬鬆差異、英文名補值、unknown→0 及自報 confidence 未校準均揭露，未改既有資料。結果、命令、第二階段費用待核准方案見 [AI 離線評估](AI_OFFLINE_EVALUATION.md)；[Demo](DEMO_STORYBOARD.md) 尚未拍攝。這不代表模型 accuracy、live OCR、臨床效用或登入後真機通過。

本輪最終本機快照：Flutter 269 項（另 1 個 CLI driver 無輸入跳過，兩次 CLI 已通過）、相關專項 90 項、backend 8 項、localhost rules 18 項均通過；分析 0 error／10 warning／348 info（exit 1，無新增）。arm64 device debug no-codesign／no-pub exit 0，App／Widget minimum 16、未簽署；既有 MLKit simulator 警示保留。本輪未裝機，外層另已觀察 `af611d8` 覆蓋安裝／啟動停登入頁，登入後／Face ID／HealthKit 尚未驗證。
