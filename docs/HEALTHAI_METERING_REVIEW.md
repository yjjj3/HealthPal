# healthAI 計量窄修（已複核，尚未部署）

2026-10-12，基準 `34823cd`。使用者批准本次 NT$1000 總 cap（部署／OpenAI／雲端／服務費／稅／FX），取代早期 NT$100 計畫；最多 20 actual HTTP attempts，失敗／retry／warmup 都計入。healthAI 部署窄修已獲授權，但執行仍等本機複核、commit／CI 與使用者通知；本輪沒有部署或模型請求。其他 functions、rules、安全設定與憑證不改。

## Source 與可回復證據

[allowlisted evidence](healthai_metering/evidence.json) 來自既有 Firebase CLI 正常內部 auth 的唯讀 metadata，沒有擷取／顯示 token、env、secret、IAM 或健康資料。部署前 revision **healthai-00001-juk**、100% traffic；更新時間 2026-10-10T16:51:57.666847278Z、source generation **1791651025322002**。

依使用者批准下載指定 generation 的 archive，只開必要 `index.js`／`gateway.js`／`package.json`／`package-lock.json`；四檔逐 byte 與 baseline 相同。working 僅 gateway 有本次 additive 計量差異，index／套件與 lock 未變；沒有假設雲端等於 Git。archive SHA256 與四檔 hashes 已保存，archive 本身只留本機、不提交。未開其他 archive 檔／secret 檔，未宣稱整包全面安全或所有檔與 Git 相同。

實際 config：Node.js 22、asia-east1、1 vCPU／256MiB、60 秒、maxInstances 2、concurrency 10、startup CPU boost=true。舊 build SUCCESS、timeout 1800s；machineType 未明列，依[Cloud Build schema](https://docs.cloud.google.com/build/docs/build-config-file-schema#machinetype) 省略時為預設 e2-standard-2。新 build 必須重新核對，不能用舊 build 當未來機型保證。

## 回退計畫（僅步驟，未執行）

1. 先停止 benchmark 新 attempts；保存部署後 revision/config/hash，確認旧 revision 仍可用。不刪舊 revision／source generation／artifact。
2. **精確 revision 快速回退**：既有 Google Cloud Console → Cloud Run → 本專案 healthai／asia-east1 → Revision history → Manage traffic → 指定 **healthai-00001-juk 100%**，不選 latest。唯讀核對 traffic／ready revision；不 POST 模型測健康檢查。gcloud 本機未安裝，不為回退安裝工具；若既有權限拒絕，停止，不改 IAM。
3. 此法回復 serving traffic，不重建 source，也不把 Cloud Functions 最新 metadata 改成舊版。Google 說明流量切換非即時，在途請求會完成；不能把已接受工作／费用撤銷。[官方 revision rollback](https://docs.cloud.google.com/run/docs/rollouts-rollbacks-traffic-migration?hl=en)
4. **source-generation 重建替代**：若舊 revision 不可用，核對本機 before metadata 的 bucket／object／generation；用既有 CLI 內部 auth 呼叫 Functions v2 PATCH，僅 `updateMask=buildConfig.source`、name=既有 healthAI、`buildConfig.source.storageSource`=原 bucket/object/**1791651025322002**。不送 serviceConfig／env／secret／IAM 欄，不取出 token；保留既有配置。這需要再做 rebuild／費用與寫入確認，不自動執行。[PATCH 契約](https://docs.cloud.google.com/functions/docs/reference/rest/v2/projects.locations.functions/patch)
5. 若 generation 已不存在，本機完整原 archive SHA256 可用於經核准的原 source 重建；不得用目前 working tree 猜舊雲端版本。重建仍須原runtime/config、原依賴及正常部署權限，寫入能力本輪未試。secret 值不匯出／不輪替。

後續 normal deploy 只 scope 既有 codebase 的 healthAI：`firebase deploy --only functions:healthpal-ai:healthAI --project YOUR_FIREBASE_PROJECT`。執行前核對 scope、source diff、原 revision 可回退、費用 gate；不 deploy rules／其他 functions。

## Additive 契約

200 保留原 `choices`，新增 `usage`、`resolved_model`、`finish_reason`。usage 僅非負 safe integer 的 prompt_tokens／completion_tokens／total_tokens 且合計一致；其餘／缺值為 null，不轉發任意 metadata。resolved_model 僅接受 gpt-4o 日期 snapshot；alias gpt-4o 回 null，不假稱 resolved。finish_reason 投影既有列舉，缺失／未知回 null。非200保留原錯誤契約，不捏造 usage。choices/parser/refusal/truncation／quota/auth 不改；malformed choices 為既有範圍限制，不擴此次修正。

## Context 成本 dry-run

[OpenAI gpt-4o 官方頁](https://developers.openai.com/api/docs/models/gpt-4o) 本輪核對：context 128000、input US$2.50/M、output US$10/M。固定 gpt-4o、無tools／audio／stream、max_tokens≤4096 的單次模型上界保守計為 **128000×2.50/M＋4096×10/M＝US$0.36096**；input 含圖像與 framing，不依賴未測的10000假設。context 是 input/output 共同限制，將128000 input再加4096 output是刻意保守的超額計法。20 attempts＝**US$7.2192**，不計 cached/free tier優惠。alias價目／context 若改變，停止重新核對。

[台銀官方](https://rate.bot.com.tw/xrt?Lang=en-US) 2026/10/12 14:42 USD spot sell32.02／cash sell32.24 支持 FX40 作 reserve；不是本次實際付款匯率。1.2 是稅／費門檻，不是實際稅率：

`7.2192×40×1.2 = NT346.5216 API envelope`

另暫預留 **NT200 部署／雲端／storage／network／logging／Firestore**、**NT300 安全留白**，合計 **NT846.5216**，仍剩 **NT153.4784**。可量化假設：一次部署＋一次source rebuild回退，各按30分鐘 e2-standard-2，`2×30×$0.006=$0.36`；60秒×20次、2 vCPU／0.25GiB作request reserve，CPU `$0.0576`＋RAM `$0.00075`＋requests `$0.000008`。startup／idle／網路／quota交易／持續儲存另由200覆蓋，不把此request小計冒充全部雲端上界。[Build價格](https://cloud.google.com/build/pricing)／[Run價格](https://cloud.google.com/run/pricing)

**目前不能宣稱總账單硬保證**：新build機型／timeout、billing計費模式、實際稅費、card FX、artifact大小／儲存期及併發其他用量尚需 gate；初步 horizon 為新增artifact 30天，持續storage不會自動截止。[Artifact價格](https://cloud.google.com/artifact-registry/pricing) 沒有憑免費額度保證；不擅刪artifact或改retention。任何前提不符合，先停止／降低attempt數／重分配reserve，不能付費probe試算。另須將已用部署費從同一NT1000總額扣除後再啟用模型。

[context dry result](healthai_metering/context_dry_result.json) 只模擬20 attempts，逐次SQLite持久原子reserve $0.36096、失败不退，沿用停止／不resume／虛擬限速；[cost envelope](healthai_metering/cost_envelope.json) 明示 liveReady=false、actualCost=null。原14項dryrun保留，加4項context budget回歸。舊10000/image token假設的歷史結果不改寫。

## Live runner 尚未完成

目前 Python context dry工具沒有network／credential，**不是正常App-session live runner**。尚無App內 benchmark入口與durable預留接線，登入也未確認；本輪不以桌面admin auth冒充Firebase用戶token。原AIClient會explicit429 retry一次，不能直接把一次complete算一attempt；後續須單次transport每HTTP送前原子reserve、無隱性retry，UID／同UID世代與停止／timeout結果隔離，token只在App既有session記憶體內用于請求header，不落檔／不log／不新建持續存取。

token_precheck仍未驗證，本機沒有tokenizer／cached encoding、不安裝下載；模型成本方案改以context上界支撐，這不證明實測input tokens。正常登入、App接線、部署後additive契約及成本gate未完成前絕不呼叫模型；不讓此獨立blocker擴大healthAI計量窄修。

本機驗證：backend 11／Python context與dry-run 18／Flutter全套272項通過（另1個離線driver無輸入跳過），exit 0；分析0 error／10 warning／348 info（exit 1，無新增）。未做iOS、App登入、deployment或模型live。
