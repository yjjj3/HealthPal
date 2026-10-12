# App-session 合成處方 benchmark

2026-10-12，基準 `c05f472`。已完成本機接線與唯讀複核；本次模型 HTTP 呼叫 **0**，新版本未安裝／啟動／真機測試。這不是模型可靠度或臨床證據，也不重部署 healthAI。

## 邊界與流程

- 唯一產品入口是帳號設定的 debug tile：`kDebugMode && ENABLE_AI_BENCHMARK`；預設關閉，release wrapper 與 runtime 都拒絕啟用。沒有任意 URL／照片輸入，固定既有 healthAI endpoint。未執行 release binary 內容排除檢查。
- 正常 Firebase 非匿名 App session，UID＋登出世代＋App 解鎖＋成本 gate 均需有效。token 只在記憶體及 HTTPS Authorization header，不記錄、不匯出、不使用 admin auth。登入仍待使用者確認，不阻擋 fake 測試。
- frozen 16 圖及 S03/S11/S12/S16 repeats 來自既有 manifest；Dart bundle 與原圖逐 byte／SHA256 驗證，不改已 QA 像素。S11 是幾何遮蔽，沒有真模糊 OCR 覆蓋。request 復用 production prompt/schema/high detail，仍不代表 live OCR 已跑。
- begin 不送模型；每筆必須手動 send。journal 決定全實驗下一個 ordinal，reserve 再核對 sample。重開頁面或顯式新 run 不從 S01 重排，不自動續跑／自動送出。
- 每次先鎖固定 journal 的獨立 lock 檔，同 isolate queue＋OS lock，寫入並 flush 預留後才取 token／送 HTTP。20 次累計預留上限包含失敗、timeout、停止與未送出的保守預留；跨 UID／run／程序重啟不退款、不重置。`sendBoundaryReached` 是保守送出邊界，不能當 server 已收到的證明。
- 每筆固定預留 NT17.32608；model envelope NT346.5216／20 次，cloud NT200、安全留白 NT300，總 NT846.5216。條件仍是 gpt-4o input $2.50/M、output $10/M、context 128000、max output 4096、FX≤40、費用倍率≤1.2；不是實際匯率／稅額或帳單保證。tokenizer 未驗證，硬上界使用 context，不以 10000 假設冒充量測。
- UI 開始前必須明確勾選 live 授權及上述成本條件仍成立。沒有自動查帳能力；如無法核實雲端／稅費／FX 就不得勾選或送出。預算與 count 在每筆重新檢查。NT1000 的全部費用上限仍需 operator 核對。
- 單次 transport 不經 AIClient 的 429 retry，禁止 redirects。序列化且 reserve／實際 send 邊界皆檢查至少 12 秒間隔；未到期拒絕並停下，不做真 sleep 或自動排程。
- response 保存 raw、usage、resolved_model、finish_reason、latency 與 outcome；缺 usage／不一致／未知或舊價 snapshot／非 stop finish／超界即停止。usage-based estimate 不等於含稅／雲端實際花費；null 不當 0。raw 保存不代表 parser 成功或辨識正確。
- stop／logout／lock 不等待 pending token／HTTP；遲到結果記 stale，不重新解鎖或影響新世代。已送出／server 接受的工作无法收回，預留不退。timeout 關閉 client；沒有隱性 retry、warmup 或免費 probe。
- journal 位於 App sandbox Application Support；只含 owner UID 的 SHA256（仍是可連結識別，勿當匿名）、合成結果與計量。損壞／既有空檔 fail closed，不自動修復。刪 App／刪 journal／備份回復／磁碟或 OS 故障不在跨重啟保證內；不得清空 journal 繞上限。

## 重跑與證據

```sh
python3 tool/generate_benchmark_bundle.py --output /tmp/frozen_images.dart
flutter --no-version-check test --no-pub test/benchmark
flutter --no-version-check test --no-pub
flutter --no-version-check analyze --no-pub --no-fatal-warnings --no-fatal-infos
npm --prefix functions test
python3 -m unittest discover -s tool/ai_dry_run -p 'test_*.py' -v
flutter --no-version-check build ios --debug --no-codesign --no-pub --dart-define=ENABLE_AI_BENCHMARK=true
```

既有依賴／工具需已齊全；命令不代表安裝或啟動 App。Ubuntu CI 既有 Flutter test 自動涵蓋 benchmark，Python stdlib 步驟仍 18 項，不新增 CI 依賴／artifact。

| 本機結果 | 2026-10-12 |
|---|---|
| benchmark fake／素材／enabled panel | 29 pass，包含 OS 子程序競態、跨新 run／新頁面 ordinal、ack/begin/manual send/stop、logout stale |
| Flutter 全套 | 301 pass、1 既有 restoration skip |
| backend／Python | 11／18 pass，無正式服務 |
| analyze | exit 0（no-fatal flags），0 error／10 warning／348 info，無新增 |
| iPhone debug（入口 define=true） | exit 0；App／Widget arm64、minimum iOS16、codesign 檢查 exit1：未簽署 |
| fixture bundle | 16 圖原 bytes/hash 全同，stdlib 再生成 byte-identical bundle；不宣稱整個 build byte-identical |

## 最小下一步（本輪不執行）

使用者先核對可計費條件仍成立，再批准更新測試機 App；以正常 Email／Google 登入並完成 App 解鎖。授權後才由 debug 帳號設定進入口，勾選條件、建立新 run、手動逐筆 send；任何停止須人工檢查 journal 再明確建立新 run。不得匯出 ID token。結果取出／評分及真機登入、Face ID、網路斷線行為仍未驗證；不把 mock 綠燈當 live 成功。
