# 第二階段：零費用離線準備（已複核）

2026-10-12，基準 `f340275`。僅合成圖片與本機乾跑；**没有 OCR／live 模型、正式 gateway、雲端用量、真機或拍片**。付費第二階段仍未批准；NT$100 不是批准。

## 素材與分層真值

[16 張圖與 manifest](../test/fixtures/prescription_images/manifest.json)：`S01.png`–`S16.png` 均 1024×1536、PNG、每張 ≤1 MiB，醒目標示合成測試／非真實處方／不得醫療使用，SYNTH 無真藥對應。沒有患者、地址、電話或信箱。沿用原 16 例，舊 golden 不變，不宣稱補足既有已知欄位／regimen coverage。

- sourceImageTruth 是實際圖上欄位真值；visibility 逐欄標 visible／blank／geometric_occlusion，unknown 是真正留白或幾何遮蔽，不印 `[不可辨識]`。
- expectedOutputContract 分開記 production prompt 容許的轉換：S03 圖上 name 留白，但 English-only 名稱可按契約補到 name；transformations 記錄來源，不把此正常契約補值當模型錯誤。confidence 只要求 0–1 自報、不得当 field probability；本輪不擴 scorer／不執行模型評分。
- S11 沿用舊情境名稱，但實際是三欄黑色幾何遮蔽，**不是光學 blur、不涵蓋真模糊 OCR**。無藏在遮罩下可評分的真藥資料。
- `visual_qa.json` 綁定全部 image hashes，記錄外層與 Codex 均逐張 view_image 觀察，不只是 contact sheet：字體／警語清楚、無裁切重疊、S03 留白、雙列／Unicode／換行／零／日期可讀。hash 改變需重看該圖。

生成參數、Pillow／Python 版本、STHeiti Medium 字體 hash、generator hash、圖檔 SHA256／尺寸／bytes、來源 golden hash 均在 manifest。未複製系統字體。使用相同既有字體／Pillow 在 `/tmp` 重渲染，16/16 hash 相同，见 `reproducibility.json`；只保證此次固定本機環境，不保證跨平台 byte-identical。

```sh
# 需既有 Pillow、CJK 字體；缺少則不安裝，以已生成素材＋stdlib核對為fallback。
python3 tool/ai_dry_run/generate_images.py --font /System/Library/Fonts/STHeiti\ Medium.ttc \
  --output /tmp/healthpal-images-NEW
python3 -m unittest discover -s tool/ai_dry_run -p 'test_*.py' -v
python3 tool/ai_dry_run/token_precheck.py --output /tmp/healthpal-token-precheck.json
python3 tool/ai_dry_run/runner.py --new-run-dir /tmp/healthpal-dry-NEW \
  --run-id EXPLICIT-NEW-ID --fixtures test/fixtures/prescription_images/dry_run_fixtures.json
```

本輪本機驗證：Python stdlib **14 項通過**、Flutter **272 項通過**（另1個離線評估driver無輸入跳過）、backend **8 項通過**，exit 0；分析 **0 error／10 warning／348 info**（exit 1，無新增）。dry fixture run 20 attempts／20 logical sample instances，虛擬限速與條件預留可核對；16圖重渲染hash全吻合。CI新增stdlib unittest命令，結果以對應提交的Actions紀錄核對；無production／scorer變更，未重跑iOS或正式服務。

## 圖檔入口

[S01.png](../test/fixtures/prescription_images/S01.png) · [S02.png](../test/fixtures/prescription_images/S02.png) · [S03.png](../test/fixtures/prescription_images/S03.png) · [S04.png](../test/fixtures/prescription_images/S04.png)

[S05.png](../test/fixtures/prescription_images/S05.png) · [S06.png](../test/fixtures/prescription_images/S06.png) · [S07.png](../test/fixtures/prescription_images/S07.png) · [S08.png](../test/fixtures/prescription_images/S08.png)

[S09.png](../test/fixtures/prescription_images/S09.png) · [S10.png](../test/fixtures/prescription_images/S10.png) · [S11.png](../test/fixtures/prescription_images/S11.png) · [S12.png](../test/fixtures/prescription_images/S12.png)

[S13.png](../test/fixtures/prescription_images/S13.png) · [S14.png](../test/fixtures/prescription_images/S14.png) · [S15.png](../test/fixtures/prescription_images/S15.png) · [S16.png](../test/fixtures/prescription_images/S16.png)

## 乾跑限額與證據

runner 只有 sqlite3／decimal／json／pathlib／argparse，無 HTTP、endpoint、credentials、live flag 或環境金鑰讀取路徑；只執行 fixture outcome。既有 CI 新增獨立 Python stdlib unittest 命令，不裝 pip/npm 依賴、不在 CI 渲染字體。PNG尺寸／hash／QA綁定可由 stdlib 驗證。

候選為 16 張＋固定 hard repeats **S03、S11、S12、S16**。**實際 attempts 總上限 20**，不是 20 成功樣本再加免費 retry。retry、timeout、rate limit、錯誤、warmup 都消耗 attempts；若使用它們，完整 16＋4 覆蓋可能做不完。無自動 retry／warmup。logical sample ID 与 attempt 分列，同一 logical 的重試有獨立 attempt。

每 attempt 先 SQLite BEGIN IMMEDIATE 原子／持久預留完整条件成本，再執行 fixture；獨立連線競爭有回歸。失敗／timeout／中斷不退預留。尚未執行的持久 reserved 記錄不捏造成功；停止與完成後拒絕繼續。已有 run 目錄不可重開／覆寫，重啟須明確新目錄＋run ID，永不自動续跑／冒充 live 授權。SQLite journal 是稽核來源，JSON export 是快照。

循序虛擬 clock 的相鄰 attempt 至少 12 秒，每個半開 60 秒窗最多 5 次；不使用真 sleep。raw 字串、finish_reason、model／usage（缺失 null）、模拟 latency、attempt／outcome 全保存。提供的 usage／model 僅 fixture 值，actualCostUsd 永遠 null、billingVerified=false。`dry_run_result.json` 是 20 attempts 的模擬結果，不是 20 次 API 呼叫或花費。

## Token 與費用：未核准、條件假設

本機 tiktoken／tokenizers 未安裝；沒有可驗證本地 GPT-4o tokenizer/cache，因此 `token_precheck.json` 為 **unverified**。只列 production prompt／schema hash、UTF-8 bytes 与圖像尺寸；不呼叫可能下載 encoding 的 get_encoding/from_pretrained，不把字數／10000 當實測 token。真正計價還包含 API framing／schema 與 serving 差異，須批准後另驗。

外層官方審閱提供的**計畫假設**：gpt-4o input $2.50/M、output $10/M；high 1024×1536 圖估 1105 image tokens，非圖像 input 暫 10000，output 4096。條件計畫 reserve = `(10000+1105)*2.50/M + 4096*10/M` = **$0.0687225/attempt**；20 attempts = **$1.37445 API**，不含雲端／稅／匯率。本輪未自行查當前價格。token 未驗證，所以這**不是已證實 live 最壞成本上界或嚴格實際計價**；乾跑的預留可測，不代表已有安全 live budget gate。

現 production gateway 只回 choices，缺 upstream usage／resolved model；本輪不改它。live 的可行路徑須另經明確授權：選定執行環境與費用總上限／範圍、確認當日價格、驗證非圖像 token 上界與圖像規則、選擇可保留 usage／resolved model 的受控 runner／後端觀測方案，並由使用者在其環境設定 server secret 或登入取得 token（不得提交／顯示）。任何 backend 變更／部署／費用需獨立批准；本乾跑工具不能切換成 live。若仍經現 gateway，缺失欄位只能記 null，不能據此宣稱實際計費已核對。

未完成：live runner、安全憑證配置、usage／resolved model觀測、token實测、真模型／OCR評估、光學模糊／真版面／泛化、真機登入後流程與影片。零費用素材準備不自動授權以上操作。
