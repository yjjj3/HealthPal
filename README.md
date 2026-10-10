# HealthPal — 個人健康管理

以 Flutter 與 Firebase 開發，整合健康紀錄、用藥、飲食、家庭聯繫與 AI 分析。本儲存庫收錄現有原始碼；完整建置與正式部署尚未驗證。

## 功能

- 健康紀錄、趨勢圖表與 AI 健康分析。
- 處方箋／藥袋圖片辨識、藥品確認、服藥提醒及日誌。
- 飲食紀錄、餐點影像分析與營養估算。
- 家庭邀請、成員管理與聊天室。
- PDF 報告、資料匯出與分享。
- Email、Google、Apple 登入，生物辨識與工作階段逾時。
- Apple HealthKit／Android Health Connect 健康資料讀取與同步。

## 技術組成

| 領域 | 技術 |
| --- | --- |
| UI | Flutter、Material、Google Fonts、繁體中文／英文語系 |
| 後端 | Firebase Auth、Cloud Firestore、Firebase Storage |
| AI | 共用 HTTP client、嚴格 JSON schema、Firebase AI gateway；模型 gpt-4o |
| 通知 | Firebase Messaging、flutter_local_notifications、timezone |
| 本機資料 | SharedPreferences、flutter_secure_storage、local_auth |
| 健康平台 | health、permission_handler |
| 圖表與報告 | fl_chart、pdf、printing、share_plus |
| 相機與 QR | image_picker、mobile_scanner、qr_flutter |

Dart SDK 要求為 `>=3.9.0 <4.0.0`；套件版本以 `pubspec.lock` 為準。

## 本機啟動

1. 安裝相容的 Flutter SDK 與目標平台工具鏈。
2. 執行 `flutter pub get`。
3. 執行 `cp .env.development.example.json .env.development.json`，將 `AI_GATEWAY_URL` 設為自己的已部署端點；此檔不提交 Git。本專案預設使用下方 HealthPal 線上端點，不需本機 OpenAI 金鑰；若要直接測試 OpenAI，僅在 debug 將 gateway 留空並填入開發用金鑰。
4. 在自己的 Firebase 專案啟用 Authentication、Firestore 與 Storage，透過 FlutterFire CLI 執行 `flutterfire configure`，產生 `lib/firebase_options.dart` 與平台設定。這些本機設定不提交 Git。
5. `firebase.json` 保留原專案 FlutterFire 對應資料，請重新產生為自己的設定；部署前檢查技術文件中的規則限制，並明確指定自己的 Firebase 專案。
6. 設定 Google／Apple 登入、相機、通知、健康平台權限，再執行 `flutter run --dart-define-from-file=.env.development.json`，或使用 VS Code 的「HealthPal 開發」設定。

`.env` 已移除 Flutter assets。直接呼叫 OpenAI 僅允許 debug；正式版使用 `--dart-define=AI_GATEWAY_URL=https://...`，金鑰由 Cloud Functions Secret Manager 保管。`functions/` 已提供驗證 Firebase ID token 與限制額度的後端，部署與設定方式見技術文件。本專案已部署預設端點；更換 Firebase 專案時必須以 `AI_GATEWAY_URL` 覆寫為自己的後端。

## 目錄與驗證

`lib/screens` 為畫面、`lib/services` 為服務、`lib/models` 為資料模型、`lib/widgets` 為共用元件、`lib/theme` 為視覺設定。`main.dart` 負責初始化、登入狀態與主導覽。

```sh
flutter analyze --no-pub
flutter test --no-pub
```

測試涵蓋資料交易、小數劑量、AI 回應驗證、限流與超時、即時分頁、初始化重試與帳號切換；Firestore 規則另以 `npm run test:rules` 在模擬器驗證。雖包含 Android、iOS、Web 與桌面平台資料夾，部分服務使用 `dart:io` 或裝置專屬套件，各平台需另外驗證。

詳見 [技術細節](docs/TECHNICAL_DETAILS.md)。

GitHub Actions 會執行靜態分析、Flutter／後端／Firestore 規則測試及 Android debug 建置。CI 使用公開 demo Firebase 設定，產出的 APK 只供建置驗證，未連接正式服務。

AI 端點已於 2026-10-11（台北時間）部署至 `asia-east1`：`https://asia-east1-health-management-f046a.cloudfunctions.net/healthAI`。新版 App 預設走此端點，需登入本專案的 Firebase 帳號；舊版 App 需重新建置／更新才能使用。
