# HealthPal

以 iOS 為目標的 Flutter 個人健康管理專案：把健康紀錄、用藥與飲食整理成可追蹤的日常流程。

## 功能

- 健康紀錄、趨勢圖表、Apple HealthKit 同步與 PDF 匯出。
- 處方圖片辨識、人工確認、療程提醒、服藥紀錄與庫存交易。
- 飲食紀錄、營養估算與 AI 健康分析。
- 家庭分享、聊天室、Apple／Google／Email 登入與生物辨識。

AI 結果須人工核對；紀錄完成率不等同實際服藥，也不是醫療診斷。

## 技術

Flutter／Dart、Firebase Auth／Firestore／Storage、受驗證的 AI gateway、HealthKit、WidgetKit、本機通知。交易維持服用／取消與庫存一致，帳號切換隔離頁面與非同步工作，處方重試使用固定 ID 與批次標記。詳見 [技術細節](docs/TECHNICAL_DETAILS.md)。

## iOS 開發

使用相容 Flutter、Xcode 與 CocoaPods；版本依 `pubspec.lock`、`ios/Podfile.lock`，不要先升級套件。

```sh
flutter pub get --enforce-lockfile
cd ios && pod install --deployment && cd ..
flutter build ios --simulator --debug --no-codesign --no-pub
python3 tool/check_ios_compatibility.py
```

建置不會安裝或啟動 App。目前原生建置限制見技術文件；Ubuntu CI 綠燈不代表 iOS 建置或真機測試通過。

自行準備 Firebase 平台設定與登入／HealthKit／App Groups 能力。常用 Firebase 設定與本機環境檔已有 ignore 規則，但新增檔案仍須檢查追蹤狀態與內容。AI 使用自己的受驗證 gateway，透過未追蹤的 `.env.development.json` 設定 `AI_GATEWAY_URL`。請勿把 API 金鑰、服務帳號、簽署憑證或真實健康樣本放入原始碼、assets 或公開文件。Firebase client 識別設定不是伺服器秘密，但仍需限制金鑰並驗證規則。

## 驗證

```sh
flutter analyze --no-pub
flutter test --no-pub
npm ci
npm --prefix functions ci
npm --prefix functions test
npm run test:rules
```

上述 npm ci 依 package-lock.json 安裝依賴。規則測試另需已安裝的 Firebase CLI 與 Java 21 以上、相容的 Firestore emulator；缺少 emulator 時 CLI 可能下載，執行前確認環境。測試指定 demo-healthpal-priority1，只使用本機模擬器；Flutter 測試使用假資料。GitHub 的 Ubuntu CI 執行 Flutter 分析／測試、backend 與 Firestore rules 驗證，不產生 APK、不驗證 iOS 原生建置。

真機待驗：通知權限與容量、App 關閉後跨日／跨週提醒、省電及時區變化、跨裝置離線同步、HealthKit、登入與 Widget 更新。請使用測試帳號與虛構資料。
