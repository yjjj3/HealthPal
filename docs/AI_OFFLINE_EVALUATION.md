# AI 可驗證性：免費離線第一階段

全部樣本為**虛構、非真實處方、不得醫療使用**。`SYNTH-*` 無真藥對應；不含患者資料。16 個文字 golden cases 是可稽核的欄位真值，不是影像 OCR benchmark。本輪沒有呼叫模型／gateway／正式 Firebase，沒有拍片或真機驗證。

## 重跑

需已安裝 Flutter 與本專案快取依賴；命令不執行 pub get。CLI 不提供真 transport，僅使用 MockClient／FakeFirestore。

```sh
python3 tool/evaluate_prescriptions.py --flutter <FLUTTER_PATH> \
  --predictions test/fixtures/prescription_eval/oracle.json --output /tmp/healthpal-ai-oracle.json
python3 tool/evaluate_prescriptions.py --flutter <FLUTTER_PATH> \
  --predictions test/fixtures/prescription_eval/synthetic_errors.json --output /tmp/healthpal-ai-errors.json
flutter --no-version-check test --no-pub test/prescription_eval_test.dart \
  test/prescription_scan_flow_test.dart test/prescription_unknown_save_test.dart
npm --prefix functions test
```

`golden.json`：case ID、情境、合成原文、逐欄真值、完整 unknownPaths、名稱容許 trim／大小寫正規化、逐案人工確認要求。`dataset.schema.json` 描述格式；`production-response-schema.json` 從 production Dart responseFormat 匯出，測試核對一致。`manifest.json` 記錄 SHA256；沒有處方圖片，沒有執行 OCR。driver 使用 PNG signature bytes 只驗證 image payload 契約，不能視為可供辨識的影像。未安裝新工具。

`oracle.json` 與 `synthetic_errors.json` 分離保存 raw 字串。前者是人工真值對照，後者刻意加入錯誤；**兩者均非模型輸出**。CLI 結果含原始 JSON／schema／service 分類、逐欄報告、model conversion 與 mapper 是否接受。結果不具模型 accuracy 意義。driver 測試未指定 CLI 環境時跳過；評分與 production 流程的其他測試仍由既有 Flutter CI 自動執行，未新增 CI 依賴或步驟。

## 計分與契約

- JSON 可解析率：原始 raw 可被 JSON decoder 解析的 case 數／golden case 數；JSON `null`／錯型別仍可解析，但 schema／service 拒絕。fenced JSON 為 raw 格式失敗，production parser 可接受，兩者各自記錄。
- 每個 golden 藥品的 15 欄，加每張 5 個 hospital 欄，共為 expectedFieldDenominator；known／unknown 分母分列。未知為明確 null，不等於空白、不等於鍵缺失，也不等於零。
- correct：已知值匹配，或存在的 unknown 欄為 null。incorrect：已知值不同／錯型別。missing：鍵缺失，或已知值為 null／空白。hallucinated：unknown 被填值、額外藥品。未知空字串也屬 hallucinated。報告另列 knownCorrect／unknownCorrect，避免大量 null 撐高表面數字。
- 以合成名稱識別配對，群組內用最低欄位錯誤的一對一匹配；同名不同外觀可換序。缺列計 missing；多列／重複列逐欄計 hallucinated penalty，不能當多一列正確。golden 最多 5 列、prediction 最多 20 列，超限拒絕，不截斷。陌生名稱保守視為缺列＋多列，不做藥名模糊推斷。
- name／englishName 僅依逐案白名單正規化；警語、用途、標點、換行逐字比對。整張精確匹配要求無欄位錯誤／缺多列、raw schema 通過、service 接受。raw 與 post-normalization 分開，conversion 的零值不回填真值。
- 缺 case 保留原分母並記 missing；多 case 列出 IDs 且 completeCaseSet=false，CLI exit 2。重複 ID／錯 record／無效輸入 JSON 拒絕並不保留陳舊結果。故意錯誤內容本身不讓評估 CLI fail，否則無法評估錯誤。

實際 production 路徑：AIClient mock HTTP envelope → PrescriptionScanService.recognizePrescriptionFromBytes → PrescriptionRecognition → PrescriptionMedicine.fromJson → PrescriptionMedicationMapper；沒有另造替代 parser。schema validator 僅診斷本專案 schema 的 object／array／primitive 子集。

契約來源為 `lib/services/prescription_scan_service.dart` 的 `_prescriptionPrompt`、`lib/models/ai/prescription_recognition.dart`、`lib/services/ai/ai_client.dart` 及 `functions/gateway.js`。代碼指定 `gpt-4o` alias、4096 max_tokens、temperature 0.1、image detail high；未固定模型 snapshot，未取得實際 serving 版本。結果保存來源 SHA256。Gateway 驗證 request 外框並只回傳 choices，不等於驗證模型欄位內容，也不保留 upstream usage／resolved model。

[OpenAI 官方 Structured Outputs 文件](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=chat) 說明 required 與 additionalProperties=false；本輪只讀官方文件，未查價格。production requested schema 符合此要求，但 Dart parser 仍接受 nullable 鍵缺失並保留額外 keys；負面測試與報告揭露差異，不把 mock 綠燈當 AI 可靠性。

## 已確認邊界

1. 掃描頁原本 `containsKey('error')` 把 schema-complete `error:null` 成功結果跳過。實際畫面＋production service mock 回歸先失敗（確認頁無藥），改成非 null 才跳過；非 null 錯誤不得增加辨識藥品，仍需人工確認。
2. English-only 時 parser 將 englishName 複製到 name，raw unknown 的 name 被補值；兩階段計分揭露，不能用補值掩蓋遺漏。
3. 整體 confidence 被複製到每個藥品，沒有 reject threshold；UI 百分比是模型自報，**不是測得的逐欄機率或校準可信度**。0 confidence 仍可進人工確認。
4. 實際確認／save 的 null＋missing 14 項 fake 測試：dose／unit／frequency／timing／route 阻止儲存；durationDays／totalQuantity 轉 0 後可成功存入。unknown→0 是現有儲存語義限制，不算明確零真值。本輪不改 schema／model／資料；後續若修，最小範圍需保留未知到 model、編輯 UI、確認儲存驗證，另經審閱，不需先遷移正式資料。

## 證據與限制

本輪基準 `af611d8`，日期 2026-10-12；原始結果見 [oracle](../test/fixtures/prescription_eval/results/oracle.json) 與 [刻意錯誤](../test/fixtures/prescription_eval/results/synthetic_errors.json)。驗證數字以此文件收尾快照為準。

最終本機快照：Flutter 全套 **269 項通過**（原 229 項保留、新增 40 項；另 1 項 CLI driver 無輸入時跳過，已由兩次實際 CLI 另行通過）、相關專項 **90 項通過**；backend **8 項**、localhost rules **18 項**通過，均 exit 0。分析 **0 error／10 warning／348 info**，exit 1，無新增診斷。iOS `flutter --no-version-check build ios --debug --no-codesign --no-pub` exit 0（199.8 秒）；App／Widget arm64、minimum 16、未簽署。既有 MLKit arm64 simulator 警示保留；這是 device compile，非 simulator／真機功能驗證。

| 合成輸出 | raw JSON／16 | schema／16 | service／16 | raw 整張精確／16 | 正規化整張精確／16 |
| --- | --- | --- | --- | --- | --- |
| oracle（非模型） | 16 | 16 | 16 | 16 | 15 |
| 刻意錯誤（非模型） | 15 | 11 | 9 | 1 | 1 |

兩組 expected 欄位分母均 **350（known 169、unknown 181）**。oracle raw 為 correct 350；刻意錯誤 raw 為 correct 289／incorrect 3／missing 51／hallucinated 22，其中多列 penalty 15，故分類合計為 365，不能除以 350 當單一 accuracy。其餘 hallucinated 來自 unknown 被補值；逐欄 known／unknown 與警語可見原始結果。CLI 缺 case exit 2、重複 case exit 1，失敗不留陳舊結果。原始執行 logs 保留於本機，公開結果只含合成資料與相對命令，不含本機私人路徑。

| 證據 | 能支持 | 不能支持 |
| --- | --- | --- |
| prescription_eval_test／scan_flow／unknown_save | 評分器與真解析流程、人工確認與假儲存邊界 | 模型 accuracy、影像 OCR、臨床效用 |
| priority_three_test、backend gateway tests | 格式／timeout／refusal／truncation、fake auth／quota 防護 | 正式部署、真 token／上游穩定性 |
| prescription_session_test | 舊頁／帳號變更、重試與 reserved ID 假資料行為 | 所有原生並發、server 已接受提交可撤銷 |
| medication_consistency_test | 扣補庫存 receipt、編輯衝突的 fake 交易回歸 | 真跨裝置離線同步完整保證 |
| priority_one_test | health sync store 去重與寫入分批 | HealthKit 實機授權／讀取／整個同步實測 |
| localhost Firestore rules tests | demo 資料的未授權拒絕與分享授權規則 | 正式規則已部署、正式資料狀態 |

今早外層已核對 `af611d8`，以既有 Xcode Run 在同台 iPhone 覆蓋安裝；觀察到 Successfully installed／Successfully launched Runner，最後停登入頁。這是該提交的已觀察安裝／啟動證據，不是本輪自動實測。登入後、Face ID、通知、HealthKit、跨日／離線跨裝置仍未真機驗證；本輪新差異未裝機。iOS no-codesign 編譯不等於真機啟動。

## 第二階段（待費用與操作核准，不執行）

建議固定這 16 例各 1 次，加選定 4 例重跑，共 20 次；先補可讀合成影像與 manifest，再用授權的真模型測試，另保留未參與 prompt 調整的樣本，不能僅用這個小集合宣稱泛化。現行程式仍為 gpt-4o alias；若需 pin snapshot，須先審閱 gateway 允許名單變更，不能假稱已固定版本。

成本核准前記錄每張尺寸／detail、文字 input tokens、影像計費估算、實際 usage 的 input/output/total tokens 與 resolved model；現有 gateway 缺 usage，因此需經批准的觀測方案，不能憑 choices 推算實際 token。保守 output 上界：20 × 4096，AIClient 若每次發生一次明確 429 重試則最多 40 次嘗試、40 × 4096；應另計 image/input、服務費及匯率／稅。實際成本依當日官方價格與 token/影像規則核對；本輪未查價，不填美元。

提案總費用上限 **NT$100（待使用者明確核准）**，涵蓋 AI 與任何 gateway 額外用量；先預估最壞上界低於核准額，否則不執行／減樣本。Blaze 或先前月預算不代表本階段授權；不能以 budget alert 當硬性停止。免費離線第一階段未產生模型／正式雲端用量。
