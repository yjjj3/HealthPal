# HealthPal

以 iOS 為目標的 Flutter 個人健康管理專案：把健康紀錄、用藥與飲食整理成可追蹤的日常流程。

## 功能

- 健康紀錄、趨勢圖表、Apple HealthKit 同步與 PDF 匯出。
- 處方圖片辨識、人工確認、療程提醒、服藥紀錄與庫存交易。
- 飲食紀錄、營養估算與 AI 健康分析。
- 家庭分享、聊天室、Apple／Google／Email 登入與自選 App 解鎖。

AI 結果須人工核對；紀錄完成率不等同實際服藥，也不是醫療診斷。

App 解鎖預設關閉，逐帳號保存在本裝置。啟用需生物辨識、確認與儲存核對；已登入冷啟動或離開滿 60 秒後需 Face ID／生物辨識。取消可重試，或完成登出與通知清理後以 Email／Google 重新登入；不保存登入密碼、不加 App PIN。原閒置自動登出仍生效；解鎖後可正常鏡像，新版本尚未真機測試。

## 技術

Flutter／Dart、Firebase Auth／Firestore／Storage、受驗證的 AI gateway、HealthKit、WidgetKit、本機通知。交易維持服用／取消與庫存一致，帳號切換隔離頁面與非同步工作，處方重試使用固定 ID 與批次標記。詳見 [技術細節](docs/TECHNICAL_DETAILS.md)。

工程問題、設計取捨與驗證證據見 [工程案例紀錄](docs/ENGINEERING_CASE_STUDIES.md)。

## iOS 開發

先準備相容 Flutter、Xcode、CocoaPods，以及 Firebase CLI／FlutterFire CLI（若尚未產生 Firebase 設定）。版本依 `pubspec.lock`、`ios/Podfile.lock`，不要先升級套件。

在自己的 Firebase 專案啟用所需服務，以 `flutterfire configure --project YOUR_FIREBASE_PROJECT --platforms=ios` 產生 client 設定；另核對登入、HealthKit、App Groups 與 iOS 平台設定。這些 CLI 操作可能存取雲端，請在自己的授權環境操作。常用 Firebase 設定與本機環境檔已有 ignore 規則，但新增檔案仍須檢查追蹤狀態與內容。

```sh
cp .env.development.example.json .env.development.json
```

在此未追蹤檔案填入自己的 `AI_GATEWAY_URL`，`OPENAI_API_KEY` 保持空白；端點須與自己的 Firebase 專案一致。後端前提見 [gateway 設定](docs/TECHNICAL_DETAILS.md#gateway-設定)。請勿把 API 金鑰、服務帳號、簽署憑證或真實健康樣本放入原始碼、assets 或公開文件。Firebase client 識別設定不是伺服器秘密，但仍需限制金鑰並驗證規則。

```sh
flutter pub get --enforce-lockfile
cd ios && pod install --deployment && cd ..
flutter build ios --simulator --debug --no-codesign --no-pub --dart-define-from-file=.env.development.json
python3 tool/check_ios_compatibility.py
```

建置不會安裝或啟動 App。目前原生建置限制見技術文件；Ubuntu CI 綠燈不代表 iOS 建置或真機測試通過。以下僅是準備好測試環境後的開發啟動範例，本輪未執行：

```sh
flutter run --dart-define-from-file=.env.development.json
```

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

AI 驗證：[免費離線評估與限制](docs/AI_OFFLINE_EVALUATION.md)／[90 秒 Demo 故事板（未拍攝）](docs/DEMO_STORYBOARD.md)。

[第二階段零費用圖片／乾跑準備（未 live）](docs/AI_DRY_RUN_PREPARATION.md)。
