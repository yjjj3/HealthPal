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
