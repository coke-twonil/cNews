# Server／Groups／下載流程（2026-11-05）

參考使用者提供嘅 `ScreenRecording_11-05-2026 16-12-58_1.MP4`，長 205.785 秒。本機以每 3 秒抽幀，檢視全部五頁 contact sheets，再細看 84s、114s、180s 畫面。原片同抽幀只作本機參考，唔推上公開 repo。

| 時間 | 片中流程 | cNews 行為 |
| --- | --- | --- |
| 3–12s | Groups 右上角＋，Add Server | ＋開表單；Server、Port、Name、Email、Encoding |
| 12–72s | 填 server 及身份，揀 Big5，完成 | 連線測試通過先新增；身份按 server 保存 |
| 78–108s | Server 設定 → Subscribe Group → 搜尋／打剔 → 完成 | 獨立群組頁，真實目錄、多選、搜尋、取消／完成；返回設定再完成保存 |
| 114–120s | 顯示總新 headers，Get next／Get newest／Cancel | >500 篇時顯示精確數目；500／1000／2000／更多／All；Next／Latest／Cancel |
| 138–156s | 其他 groups、少量新 headers | <=500 篇按設定自動下載，不額外彈大批量詢問 |
| 177–204s | Groups 編輯／server 設定 | 編輯可移除訂閱，或 Subscribe Group 取消打剔；保留本機 cache／已讀作重新訂閱用途 |

## 使用者補充為準嘅下載語義

Next 500 = **本機已下載嘅最新一篇之後**，按文章編號由舊至新取下一批。Latest 500 = server 最新一批。初次未下載過，Next 由 server 最舊仍存在嘅文章開始。

Latest 跳過嘅舊文唔計入「新文」或 Next；可以 Get Older Messages 補回。下載數量用 LISTGROUP 實際存在編號計，唔直接用 last − first 推算，避免 gaps／過期文誤算。

All 以每批 <=500 個所選編號向 helper 下載，逐批保存。每批 HTTP API 喺同一 NNTP 連線按連續編號範圍查 OVER；唔額外查未選擇嘅文章 headers。完成標示本次新增數目，新文未讀；原有已讀／收藏／閱讀位置保留。取消對話框唔下載 headers，已完成批次不回退。

## 身份及連線

Name／Email 喺 server level 設定，composer 唔再提供身份欄位。新增、繼續草稿及 Send 都以草稿所屬 server 嘅身份為準。每個 server／group 嘅下載游標獨立。

目前支援公開、不需登入嘅 NNTP，119 普通連線、563 驗證 TLS。Login Name／Password 保留 Optional 外觀但未啟用。只容許公開 IP；解析 DNS 後直接連該已驗證 IP，唔二次解析，亦唔自動讀本機 netrc。已建立 server 嘅 endpoint 固定；其他地址用＋另加 server，避免混用原有 cache。
