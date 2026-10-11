# HealthPal 技術細節

## 架構

Flutter 畫面、服務、模型及共用元件分層；部分畫面仍直接操作 Firestore。Firebase 提供帳號、資料與檔案儲存，AIClient 共用 HTTP transport、JSON schema 驗證與 gateway。正式 AI 請求需 Firebase ID token，伺服器保存供應商金鑰；請求限額不等同費用上限。

## 核心一致性

- **服藥交易**：同一交易更新狀態、庫存、receipt 與日誌；取消回補原扣除量，重複操作不重複扣補。編輯合併實際修改欄位並檢查衝突。
- **療程與提醒**：共用開始／結束日及頻率規則，排程未來最多 30 日，以 60 則總通知為保守預算。容量不足公開省略與涵蓋期限；App 關閉後不能無限補排，需期限前再開啟。
- **紀錄完成率**：分母為已到期應服時段，依操作序號取最終狀態。歷史、日誌或快照不完整時不宣稱精確百分比；每日重置時間與最後服藥操作時間分開保存。
- **處方**：圖片格式／大小及 AI 回應驗證後人工確認；藥品與來源共用草稿身分。固定文件 ID 與批次標記避免回應遺失後重試重複新增，亦避免刪除後重試復活文件。資料已儲存但通知失敗會分別回報。
- **帳號邊界**：UID 改變重建導覽、釋放監聽與快取；非同步結果驗證世代及原帳號。通知原生工作串列執行，帳號切換等待舊工作結束再清除。

Firestore 主要路徑為 `users/{uid}/medicine`、`medication_logs`、`health_records`、`diet_records`、`settings` 與家庭／聊天資料。規則及複合索引各自版本控制；模擬器不能證明正式索引已 READY。未使用的 prescriptions 儲存路徑、Storage 規則與公開基本資料欄位仍需個別評估，不應假設所有資料已受完整保護。

## iOS 原生核對（2026-10-11）

本機 Xcode 26.6，iOS SDK 26.5，已有 iOS 17–26 模擬器。Flutter 與 CocoaPods 依原鎖檔補齊，`pod install --deployment` 成功，未升級版本。

| 範圍 | 原設定 | 本輪有效設定／需求 |
| --- | --- | --- |
| Runner（Debug／Profile／Release） | 15 | 16，符合既有 Podfile；mobile_scanner／MLKit 至少 15.5，Firebase 至少 15 |
| HealthWidgetExtension（三組配置） | 26.2 | 16，以 availability／背景 fallback 通過 SDK 編譯 |
| RunnerTests | 繼承 project 13 | 未修改；本輪沒有執行 Xcode 原生 XCTest |
| Pods | post_install 16 | 保持 16，55 個 pods 安裝成功 |

健康 Widget 是 Bundle 唯一註冊項目。同步資料夾中的範例也會編譯：`WidgetConfigurationIntent`（17）、`ControlWidget`／相關 intent（18）、ActivityKit／Dynamic Island（16.1）、Widget／Activity preview（17）均加 availability。`containerBackground`（17）在 iOS 16 改用系統背景；沒有啟用新範例功能。已安裝 SDK 嚴格 typecheck 驗證 device 與 simulator 的 iOS 16 target 均無診斷；來源沒有需要 iOS 26 的 API，不必因範例提高整 App 最低版本。

mobile_scanner 6.0.2 鎖定 GoogleMLKit/BarcodeScanning 7，podspec 排除模擬器 i386／armv7／arm64。MLImage／MLKitCommon／MLKitVision 二進位 arm64 為 device（平台 2）、x86_64 為 simulator（平台 7）；BarcodeScanning 也是靜態 fat library，不能把 arm64 等同 simulator slice。沒有清除架構排除或升級套件。iOS 26+ arm64 模擬器仍受限；x86_64 編譯成功不代表可以在該模擬器啟動。

本輪命令與原生證據（只建置，不安裝／啟動／簽署）：公開命令以 `<SIMULATOR_ID>` 代替本機 UUID；用 `xcrun simctl list devices available` 查得既有 iOS 18.2／x86_64 裝置 ID 再替換，實測 UUID 僅留本機 log。

```sh
flutter --no-version-check pub get --enforce-lockfile
# exit 0；pubspec.lock 未變
(cd ios && COCOAPODS_DISABLE_STATS=true pod install --deployment)
# exit 0；Podfile.lock 未變，55 pods
flutter --no-version-check build ios --simulator --debug --no-codesign --no-pub
# 修正前 exit 0，449.4s，Runner x86_64；App minimum 15、Widget 26.2
# 修正後 exit 0，32.8s；兩者 minimum 16，Runner x86_64
python3 tool/check_ios_compatibility.py
# exit 0；arm64 device／simulator Widget typecheck，warnings-as-errors
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>,arch=x86_64' "BUILD_DIR=$PWD/build/ios" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
# exit 0；既有 iOS 18.2，BUILD SUCCEEDED，0 error；沒有安裝／啟動
```

原始 Widget 使用 `xcrun swiftc -typecheck ios/HealthWidget/*.swift -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target arm64-apple-ios16.0-simulator` 重現 exit 1，首要 error 為 ConfigurationAppIntent 的 perform availability；補齊型別及 preview availability 後，嚴格編譯通過。完整 App build 的 MLKit 架構與 UIScene 提示是警告，並非最終失敗。

本機完整輸出留在 `/tmp/healthpal-ios-pub.log`、`healthpal-ios-pods.log`、`healthpal-ios-build.log`、`healthpal-ios-build-final.log`、`healthpal-ios-compatibility.log`、`healthpal-ios-simulator18.log`，不提交建置日誌或本機設定。原生 build 仍有既有套件／UIScene 相容性警告；純 Widget 回歸沒有新增警告。

## 驗證紀錄與限制

2026-10-11，原生修正 `b607541`（基準 `6e190c3`）：修正前後本機 Flutter 全套 **119 項通過**；靜態分析 **0 error、13 warning、368 info**，均為既有問題。本輪 localhost rules 10 項、backend 假測試 7 項通過；先前亦以 FakeFirestore、假 AI transport、假排程器驗證一致性邊界；沒有以正式健康資料或真實 AI 驗證本階段。

用藥／處方一致性修正保留於 `4f19d64`、`efc572a`、`57a32ef`、`07d4dc5`、`acfe247`。`6e190c3` 的 Ubuntu CI 成功、artifact 數量 0；CI 保留分析、Flutter／backend／rules 測試，不做 iOS 原生建置或簽署。

整 App arm64 device 建置、iOS 16 實際執行、Xcode XCTest 與簽署皆未測；沒有新增 runtime／全域工具。已確認 plist 語法、權限說明及 App Group 交集，但這不代表平台授權、登入或正式服務可用。

## Gateway 設定

使用自己的 Firebase 專案與已安裝 Firebase CLI／Node 22，依 functions/package-lock.json 安裝後端依賴。下列只供自行部署參考，可能產生雲端費用，本輪未執行：

```sh
npm --prefix functions ci
firebase functions:secrets:set OPENAI_API_KEY --project YOUR_FIREBASE_PROJECT
firebase deploy --only functions:healthpal-ai --project YOUR_FIREBASE_PROJECT
```

供應商金鑰僅存 Secret Manager。將自己的函式 URL 寫入未追蹤環境檔的 AI_GATEWAY_URL，必須覆寫 App 的既有預設；不要將金鑰填進 client 或文件。規則／索引及登入設定需另行審閱，後端部署不代表整個專案已安全配置。

## 真機驗證清單

以測試帳號與虛構資料逐項驗證，正式服務操作另行授權：

1. 拒絕／允許通知；多療程達容量時核對顯示的期限與省略數。
2. 關閉 App，跨日、隔日及每週提醒；取消、編輯、再服用與時區變更。
3. 省電、長時間背景及重新開啟後補排，核對實際送達與日誌。
4. 兩裝置離線服用／取消後重連；核對庫存、最終狀態及不完整依從率提示。
5. 登出／換帳號時等待中的掃描、儲存、通知與 Widget 不沿用舊資料。
6. 虛構處方掃描→確認→編輯／刪除→儲存；故意斷線重試，確認無重複／復活藥品。
7. HealthKit、相機、登入及 App Groups 權限；模擬器不能證明其真機行為。

62 個已追蹤 `ios/build` 快取的取消追蹤與 ignore 方案另行準備，尚未套用；公開歷史不改。隱私政策與法律文字保持原樣。
