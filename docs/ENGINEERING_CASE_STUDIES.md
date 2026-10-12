# HealthPal 工程問題與解法紀錄

HealthPal 是以 iOS 為目標的 Flutter／Firebase 健康管理專案，整合健康紀錄、處方辨識、用藥提醒與家庭分享。本文記錄問題的成因、設計取捨與驗證證據，補充 [專案介紹](../README.md) 與 [技術細節](TECHNICAL_DETAILS.md)。

**版本基準：2026-10-11，已提交至 `df26ae3`。** 以下區分已提交修正與進行中項目；測試數量是該版本的驗證快照。

## 專案角色與協作方式

原畢業專題由六人合作，我擔任組長，主要負責前端與整合。後續改善使用 Codex 協助實作、Claude 協助交叉審查；我負責確認需求、修正優先順序及產品取捨，包括以 iOS 為目標、控制雲端成本與保護個人資料。本文記錄專案層級成果，不將 AI 協作產出的所有程式碼歸為個人手寫。

審查意見須比對當前原始碼，再以具體反例與測試確認。每項成果以 commit、測試及建置紀錄說明，保留尚未驗證的範圍。

## 1. 用藥狀態、庫存與跨裝置編輯的一致性

**問題與影響**：服用後修改劑量，再取消紀錄，可能回補錯誤庫存；零庫存或庫存不足時也不能直接加回完整劑量。另一裝置的舊編輯畫面可能覆蓋較新的服藥狀態。只比較「已服用／未服用」，無法辨識服用、取消、再服用之後的過期操作。

**根因**：取消操作依賴目前劑量，缺少原始扣除明細；整份文件覆寫與布林狀態不足以表示修改衝突及操作版本。

**解法與取捨**：

- 在同一 Firestore transaction 更新狀態、庫存、扣除明細與日誌；取消時依原明細回補實際扣除量。

- 編輯只合併表單真正修改的欄位；同欄位衝突要求重新載入，時段重排依時刻保留狀態。

- 以遞增操作序號拒絕過期重播；操作跨日或舊明細不足時停止，避免猜測使用者意圖或庫存。

**驗證**：[庫存與併發測試](../test/medication_consistency_test.dart) 涵蓋劑量變更、零庫存、同欄位衝突及時段重排；[邊界測試](../test/medication_boundary_test.dart) 涵蓋過期重播與交易期間跨日。修正見 [df4b965](https://github.com/yjjj3/HealthPal/commit/df4b965788a2fe28092641abfd702a5f5309bb70)、[efc572a](https://github.com/yjjj3/HealthPal/commit/efc572a65322b1f185e6199c5ceec7044d3bed8a)。

**剩餘限制**：已用假 Firestore 驗證反例，兩台真實裝置的離線操作與重連仍待測試；舊資料缺少明細時需要人工核對。

## 2. 療程提醒的日期規則與裝置容量

**問題與影響**：只排今天或明天的提醒，無法完整表達未來開始、隔日、每週或療程結束。不同入口建立通知、同名藥品及通知重建交錯，也可能留下過期提醒。

**根因**：日期規則與通知建立分散在頁面；通知身分及工作順序不一致，且未充分表達裝置可容納的通知上限。

**解法與取捨**：

- 用 `MedicationRegimen` 共用療程起訖、頻率及應服時段；資料不明確時要求確認，不自行推定服藥規則。

- 以藥品文件 ID 與應服日期時刻識別通知；集中排程，透過版本檢查與串列佇列淘汰舊工作，帳號切換時等待原生工作結束後清除。

- 規劃未來最多 30 日，採 60 則待發通知的保守總預算，扣除其他類型通知。容量不足時顯示省略數與涵蓋期限；漏服提醒不跨越下一劑、午夜或療程結束。

**驗證**：[療程與排程測試](../test/medication_567_test.dart) 涵蓋隔日／每週規則、容量不足、關閉提醒、刪除藥品、交錯重建及帳號清理。修正見 [4f19d64](https://github.com/yjjj3/HealthPal/commit/4f19d645ccc46ac53f183aecbf8e83406a099b5c)。

**剩餘限制**：60 則是專案的保守預算，不是送達保證。App 關閉後無法無限補排；通知權限、省電、時區變更與實際跨日送達仍需真機驗證。

## 3. 避免誤導的「紀錄完成率」

**問題與影響**：若只從已有日誌計算比例，漏記時段不會進入分母；服用後取消、裝置時間不同或查詢資料不完整，都可能產生錯誤的高完成率。

**根因**：操作筆數不等於應服次數；目前療程不能代表過去療程，藥品與日誌的分開查詢也不一定得到一致快照。每日重置與真正服藥操作共用時間欄位，會混淆完整性判斷。

**解法與取捨**：

- 分母取分析期間內「已到期的固定應服時段」，依療程版本重建；同一時段以交易序號最後狀態為準。

- 分開保存每日狀態更新時間與最後服藥操作時間，核對日誌、序號及目前狀態。

- 查詢截斷、歷史不足或狀態矛盾時回報資料不完整，不輸出精確百分比。採有界查詢控制讀取量，並明確揭露因此產生的限制。

**驗證**：[計算測試](../test/medication_567_test.dart) 包含「應服十次、只記錄一次為 10%」、取消後最終狀態及快照矛盾；[操作時間測試](../test/medication_operation_time_test.dart) 區分每日重置與舊操作。修正見 [4f19d64](https://github.com/yjjj3/HealthPal/commit/4f19d645ccc46ac53f183aecbf8e83406a099b5c)、[efc572a](https://github.com/yjjj3/HealthPal/commit/efc572a65322b1f185e6199c5ceec7044d3bed8a)、[57a32ef](https://github.com/yjjj3/HealthPal/commit/57a32ef91d88fc7a2cfbf361d7d5aba76fa16397)。

**剩餘限制**：此指標只描述目前仍存在藥品的紀錄完成情形，不含已刪藥品及需要時才服用的 PRN，也不能證明實際吞服、療效或臨床依從性。

## 4. 處方來源、儲存重試與帳號隔離

**問題與影響**：刪除處方列表中間一項後，依位置保存的來源可能配到其他藥品；儲存已成功但回應遺失時，重試可能重複新增。若使用者已刪除該批藥品，僅靠固定 ID 仍可能讓舊重試重新建立資料。等待中的確認頁也不能跟著登入帳號切換而寫入另一帳號。

**根因**：列表位置被當成身分；畫面收到失敗不代表伺服器未寫入；文件不存在也不代表從未提交。單次 UID 比較不足以辨識「切走後又切回」的舊頁面。

**解法與取捨**：

- 以 `PrescriptionDraftEntry` 綁定藥品及來源，刪除或修改依草稿身分處理。

- 預留固定文件 ID，並在 transaction 寫入批次提交標記。重試回讀現存資料，不覆寫庫存與歷史；標記存在但藥品已刪除時，停止並提示核對。

- 頁面綁定原登入工作階段，失效後不因切回同帳號而復活；資料儲存與通知排程分別回報結果。

**驗證**：[處方工作階段測試](../test/prescription_session_test.dart) 涵蓋切換帳號、雙擊儲存與回應遺失；[刪除後重試測試](../test/prescription_deleted_retry_test.dart) 涵蓋全刪及部分刪除；[規則測試](../test/firestore/priority_one.test.mjs) 確認提交標記刪藥後保留且僅擁有者可存取。修正見 [4f19d64](https://github.com/yjjj3/HealthPal/commit/4f19d645ccc46ac53f183aecbf8e83406a099b5c)、[07d4dc5](https://github.com/yjjj3/HealthPal/commit/07d4dc5fca2eb86608dfed771d0858117c3aa499)、[acfe247](https://github.com/yjjj3/HealthPal/commit/acfe247810633cb081ad836d5464e9c8e616d599)。

**剩餘限制**：批次標記增加資料與生命週期管理成本；處方辨識仍需人工核對。假資料測試不代表真實影像辨識準確率或正式網路環境已驗證。

## 5. iOS 最低版本與原生建置證據

**問題與影響**：Runner 與 Widget 的最低版本不一致，Widget 範例包含較新 API。Flutter 測試或 Ubuntu CI 通過，仍無法回答原生 iOS 是否能編譯。

**根因**：App、extension、Pods 與 API availability 各有約束；未註冊到 Widget Bundle 的範例檔案仍可能參與編譯。套件的 arm64 device 二進位也不能直接當成 arm64 simulator 使用。

**解法與取捨**：

- 將 Runner 與 Widget 的三組建置配置統一為 iOS 16；較新 API 加入 availability，iOS 16 使用相容背景。

- 保留鎖定依賴及既有架構排除，新增 [相容性檢查](../tool/check_ios_compatibility.py)，對 iOS 16 device／simulator 執行 Widget 嚴格 typecheck。

- 分別記錄模擬器建置、未簽署 device 建置與執行測試，避免混用證據。

**驗證**：`b607541` 通過既有 iOS 18.2／x86_64 目的地建置及 Widget typecheck；`a149059` 通過未簽署 arm64 device debug 建置，App／Widget 產物 minimum 均為 16.0。[修正 commit](https://github.com/yjjj3/HealthPal/commit/b607541b2b1a421d8b1b7091d6de43361de6345f) 與 [建置紀錄](https://github.com/yjjj3/HealthPal/blob/18420a54afac53f413396bf0f34db36c81c85769/docs/TECHNICAL_DETAILS.md) 分開保存。

**剩餘限制**：MLKit 依賴的 iOS 26+ arm64 模擬器限制仍存在。尚未完成簽署、安裝／啟動、iOS 16 實際執行及原生 XCTest；HealthKit、登入、Widget 更新與通知送達也需裝置驗證。

## 6. 真實登出與逐欄分享邊界

**已提交修正**：2026-10-11，[4711df4](https://github.com/yjjj3/HealthPal/commit/4711df4ea13d0a273141231f500fb3cc9f318d02)。此節補充原 `df26ae3` 基準之後的成果，不代表正式 Firebase 規則已部署。

**登出問題與解法**：手動與逾時登出共用協調器，以實際認證狀態確認完成；失敗與通知清理失敗可見，不以導航假裝成功。真正認證與必要憑證操作保留串列順序；非認證網路工作獨立執行，避免離線 Firestore 寫入一直等待回呼而阻擋 `signOut`。帳號世代失效後取消呼叫端等待，遲到成功／錯誤不更新新帳號或同 UID 的新世代；既有生物辨識憑證保留策略未變。

**分享問題與解法**：完整 `users` 文件限本人讀取；每位家人的十項個人欄位與三類紀錄逐項選擇、預設全關、可撤回。共享投影只保存實際同意欄位，姓名／email 也可不分享；家人頁不回退讀取私密文件。規則拒絕未知欄位、偽造授權與已移除關係，邀請及聊天使用最小識別資料。刪除、拒絕邀請與分享交易釘住原關係／投影版本，包含 legacy null，重試不採用新綁定或覆蓋較新的撤回。

**驗證**：[登出測試](../test/logout_coordinator_test.dart)、[分享與畫面測試](../test/family_profile_test.dart) 保留原 14 項登出回歸，並重現不釋放 Completer 的離線等待、遲到完成、重新登入／重綁、撤回後重試及舊載入錯誤提示；[規則測試](../test/firestore/priority_one.test.mjs) 使用 localhost emulator 驗證資料邊界。程式提交的 [CI 38147105347](https://github.com/yjjj3/HealthPal/actions/runs/38147105347) 成功，artifact 為 0。

**剩餘限制**：取消等待不能收回伺服器已接受的 commit，也不會清除舊版 SDK 已排入的寫入；未知結果需重連核對。正式規則尚未部署，舊版需依 [相容與部署順序](FAMILY_PROFILE_SHARING.md) 更新。原生離線回呼、跨裝置重連及通知清理仍需真機驗證；未安裝／啟動真機 App。帳號刪除與一般個資日誌整改不在此次修正範圍。

## 7. 展示選擇：移除 iOS 畫面遮罩

2026-10-12，使用者回報以虛構測試資料安裝到 iPhone 後可開啟 App，但鏡像被「健康資料受到保護」遮罩擋住；這是使用者回報，不是自動真機測試。使用者選擇直接移除展示遮罩，不採 debug 限定開關。

此次移除 iOS 螢幕擷取、截圖與背景事件監聽、遮罩及其 Dart 服務／初始化／設定開關；原開關「防止螢幕截圖和錄影」的說明一併移除。iOS 不再以此機制遮蔽錄影、鏡像或多工預覽；Firebase 資料權限、登出、生物辨識、HealthKit 與通知程式保留。舊本機偏好值不再讀寫，不刪除 App 資料。Android 原生保護不在此次 iOS 修改範圍。

本機 Flutter 162 項回歸通過；分析為 0 error、10 warning、350 info（exit 1），無新增診斷。iOS arm64 device debug no-codesign／no-pub 編譯成功（exit 0）；既有 MLKit 的 arm64 simulator 警示仍存在，未作模擬器建置。移除後實際鏡像、背景返回與多工預覽仍待使用者更新 App 驗證；本次移除遮罩的新版本尚未安裝，也未進行真機測試；舊版安裝成功僅為使用者回報。

## 8. 自選 App 解鎖，移除密碼快登（本次驗證快照，已複核）

2026-10-12，使用者選擇將 Email／密碼生物辨識快登改為登入 session 的 App 解鎖，不另加 App PIN。每個 UID 在本裝置預設關閉；成功生物辨識、明確確認及設定寫入讀回相符後才啟用，可關閉。舊快登 Email／密碼／開關逐項清除，舊開關不代表新同意；不再保存或使用密碼快登，不記錄憑證內容。

**邊界與取捨**：根層閘門在所有受保護路由之前，鎖定時不掛載敏感 Navigator；公共登入使用獨立導覽，不能以 back、deep link 或 restoration 放行。已啟用者冷啟動恢復 session 先鎖、離開滿 60 秒需驗證；Face ID 自身的 inactive／resumed 不循環誤鎖，真正背景會使待驗證結果失效。成功 Email／Google 登入作為本世代 fresh 驗證，不立刻再要求 Face ID；舊 UID／同 UID 舊世代 async 結果無效。

取消／不可用／錯誤可留鎖頁重試，或選擇完成真正 signOut 與通知清理後重新登入；失敗不只導航。設定或舊資料清除失敗有明確提示並拒絕放行。原有預設 5 分鐘、可調閒置登出仍保留，根層維持計時，resume／驗證前後以牆鐘核對期限以涵蓋 OS 背景凍結；成功解鎖算活動。短返回以已載入設定同步核對期限，仍有效才保留原導覽；未知或到期先阻擋。此機制不是 capture／mirror 遮罩，正常解鎖後可鏡像。

設定寫入／讀回跨背景或 resume 時，確認值仍同步到當前世代；待確認期間先阻擋並保留離開時間，完成後依 60 秒與閒置期限判定，不把背景設定完成算成活動。F1 先以兩項失敗回歸重現，再覆蓋啟用／停用、59／60 秒、讀回與 resume 並行、儲存失敗及切帳號／同 UID 新世代遲到完成。

**本機驗證**：本次已複核驗證快照（基準 `0697335`），Flutter 全套 229 項通過（原 162 項保留），其中解鎖／登出專項 83 項、解鎖新增 67 項。涵蓋預設 OFF、確認與設定寫入失敗、逐 UID／same UID 世代、legacy 清除錯誤、59／60 秒、prompt、fallback 清理、實際 Flutter restoration，以及 Firebase 回傳 UID 與 fresh 驗證相符。分析 0 error、10 warning、348 info（exit 1，無新增）；iOS arm64 device debug no-codesign／no-pub 編譯 exit 0，App／Widget minimum 16、未簽署；MLKit simulator 警示仍存在。

**限制**：本次新版本未連手機、未安裝／啟動、未真機測試；舊版可啟動僅為使用者回報。Face ID 系統 lifecycle、OS 背景計時、重新登入與通知清理仍需真機驗證。本次不修改 Firebase rules、不部署、不改簽署或新增依賴；取消等待不能收回伺服器已接受的提交。以上為本機驗證；GitHub CI 結果另以對應提交的 Actions 紀錄核對。

## 驗證快照與證據索引

2026-10-11，`df26ae3` 的 [GitHub Actions run 38137150945](https://github.com/yjjj3/HealthPal/actions/runs/38137150945) 已完成：

| 檢查 | 結果 | 證據範圍 |
| --- | --- | --- |
| Flutter 測試 | 119 項通過 | 假資料與回歸情境 |
| Backend 測試 | 7 項通過 | 模擬 gateway 測試 |
| Firestore rules 測試 | 10 項通過 | 本機 emulator，非正式部署 |
| Dart 分析 | 0 error、13 warning、368 info | CI 將 warning／info 設為非致命；仍有待清理項目 |
| CI 產物 | 0 個 artifact | Ubuntu 工作流未執行 iOS 原生建置 |

原生建置的版本、環境與限制見 [技術文件的驗證矩陣](TECHNICAL_DETAILS.md)。上述數字不可外推為後續所有版本的測試結果，也不代表正式後端、真實健康資料或臨床效益已通過驗證。

### 2026-10-11：`4711df4` 修正驗證快照

本機證據來自該提交的相同程式差異；本次只有提交，未再更改程式。上述 `df26ae3` 歷史快照保留。

| 檢查 | 結果 | 證據範圍 |
| --- | --- | --- |
| Flutter 測試 | 162 項通過，其中登出／分享專項 43 項 | 本機 fake 回歸；CI 亦成功 |
| Backend 測試 | 7 項通過 | 本機模擬 gateway；CI 亦成功 |
| Firestore rules 測試 | 18 項通過 | localhost emulator；CI 亦成功，非正式部署 |
| Dart 分析 | 0 error、10 warning、352 info，無新增診斷 | 本機 exit 1；CI 使用非致命 warning／info 設定 |
| iOS device 編譯 | arm64 debug no-codesign 成功 | 本機 App／Widget minimum 16.0、未簽署；未安裝或執行 |
| CI | completed／success，0 artifact | [run 38147105347](https://github.com/yjjj3/HealthPal/actions/runs/38147105347)，Ubuntu 不提供 iOS 原生建置證據 |

另有兩項維護調整：

- [6e190c3](https://github.com/yjjj3/HealthPal/commit/6e190c36cce822f79ce9086d7bf4292f5aa71997)：停止自動產生 Android APK，保留分析與測試，配合 iOS 開發方向。

- [df26ae3](https://github.com/yjjj3/HealthPal/commit/df26ae30bcec7b82b98c5b334609a52a09d513cc)：取消追蹤 62 個 iOS 建置快取，加入 ignore 規則，移除未經確認的範例聯絡資訊；此變更不清除既有 Git 歷史。

## 工程重點

1. **先定義不變條件**：取消只能回補原扣除量；重試不能重複新增或復活已刪資料；舊工作不能跨帳號繼續生效。
2. **把失敗情境寫成測試**：回應遺失、跨日、併發修改及資料缺漏，比單一路徑成功更能檢驗設計。
3. **讓結論符合證據**：資料不完整就揭露限制；編譯、模擬測試與真機執行分開記錄；尚在實作的項目不列為完成成果。

這份紀錄呈現的是可追查的工程判斷、修正與驗證過程。後續仍需補上真機及跨裝置測試，才能進一步評估實際使用情境。

## 9. 將 AI 辨識宣稱拆成可核對證據（已複核）

2026-10-12，以 `af611d8` 為基準、已完成唯讀複核的本次驗證快照。16 個非真實處方／不得醫療使用的合成文字樣本，逐欄標記 unknown、名稱正規化白名單與人工確認要求；oracle／刻意錯誤輸出分離，均非模型結果。CLI 走 production AIClient／scan service／parser／model／mapper，分開計 raw 與正規化結果、逐字警語、缺列／多列／重複列及整張匹配。

**確證修正**：schema 成功要求 `error:null`，原掃描畫面卻因鍵存在跳過藥品。實際 widget 流程與 fake transport 回歸先失敗，再窄修非 null 判斷，保留人工確認與錯誤拒絕。

**限制揭露**：parser 不完全 enforce requested strict schema；英文名稱補入 name、整體 confidence 複製至各藥品且無拒絕閾值，不能當逐欄機率。實際假確認／儲存證明未知療程／數量會轉 0 後成功存入，本輪不改儲存語義；缺必要文字用法欄位仍拒絕。無模型／正式服務用量，沒有 live OCR 或臨床效用結果；外層今早已核對 `af611d8` 的 Xcode 覆蓋安裝／啟動成功並停登入頁；登入後／Face ID／HealthKit 未驗證，本輪新差異未裝機。

原始結果、錯誤分類、代碼／prompt 契約來源與既有帳號／庫存／同步證據映射見 [AI 離線評估](AI_OFFLINE_EVALUATION.md)；[90 秒故事板](DEMO_STORYBOARD.md) 只交付規劃，未拍片。第二階段樣本、tokens／影像估算與總費用上限待另行核准；本輪未查價格、不編美元。

**本輪驗證快照**：Flutter 269 全套／90 專項通過（另 1 項 CLI driver 無輸入跳過，已經兩次離線 CLI 執行）；backend 8、localhost rules 18 通過；分析 0 error／10 warning／348 info，exit 1、無新增。iOS arm64 device no-codesign／no-pub exit 0，App／Widget minimum 16、未簽署，既有 MLKit simulator 警示保留。oracle raw 整張 16/16、正規化 15/16；刻意錯誤 1/16。這些比例只校驗評分器，不是模型 accuracy；本輪未部署／裝機；GitHub CI 以對應提交的 Actions 紀錄核對。

**離線精確性補充（`988c886` 後，已複核）**：僅修工具／測試，數值整數型別含大整數、name fallback 白名單及轉換時間欄分離先有失敗回歸。相同輸入的評分摘要／非時間 conversion 穩定，非 byte-identical 保證；production 不變。16 例不增加，以 coverage 表明列已知內容與 name-only／多樣 regimen 缺口，不以 parser 綠燈補足模型證據。

窄修最終本機驗證：Flutter **272 全套／93 專項通過**，另 1 個 CLI driver 無輸入時跳過、兩組 CLI 已另行執行；分析 **0 error／10 warning／348 info**（exit 1、無新增）。兩組 oracle／刻意錯誤整張匹配維持 raw 16/16 與 1/16，正規化 15/16 與 1/16；350 欄位分母不變。只改離線 tool／test／docs／結果，未重跑 backend、rules 或 iOS；前輪結果為歷史證據。本輪未裝機／部署／呼叫模型；GitHub CI 以對應提交的 Actions 紀錄核對。

## 10. 零費用圖像與執行邊界準備（已複核）

2026-10-12，`f340275` 基準。沿原16例建立分離image benchmark，醒目合成／不得醫療使用標誌；逐欄可見性與契約補值分開，English-only正常補名不當AI錯誤。16圖逐張像素QA、同字體/Pillow本機重渲染hash全吻合；S11為幾何遮蔽，沒有真blur/OCR。乾跑工具沒有network/credential入口，以持久原子預留、20 total attempts、虛擬clock、停後不續跑及缺usage=null做回歸。token未實測、費用未批准、無模型/正式服務用量；[素材、命令及未完成清單](AI_DRY_RUN_PREPARATION.md)。

本輪本機驗證：Python stdlib **14 項通過**、Flutter **272 項通過**（另1個離線評估driver無輸入跳過）、backend **8 項通過**，exit 0；分析 **0 error／10 warning／348 info**（exit 1，無新增）。dry fixture run 20 attempts／20 logical sample instances，虛擬限速與條件預留可核對；16圖重渲染hash全吻合。CI新增stdlib unittest命令，結果以對應提交的Actions紀錄核對；無production／scorer變更，未重跑iOS或正式服務。

healthAI 計量窄修（2026-10-12，`34823cd` 基準，已複核）：choices向後相容，新增有界usage／resolved_model／finish_reason。已取得原revision／source generation、下載指定archive僅比較必要4檔與baseline完全相同；回退、NT1000 context成本envelope與App-session未接線blocker見 [窄修紀錄](HEALTHAI_METERING_REVIEW.md)。本輪未部署／模型live，費用批准不代表已驗證所有費用前提。

本機驗證：backend 11／Python context與dry-run 18／Flutter全套272項通過（另1個離線driver無輸入跳過），exit 0；分析0 error／10 warning／348 info（exit 1，無新增）。未做iOS、App登入、deployment或模型live。
