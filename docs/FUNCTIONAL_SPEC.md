# cNews：功能規格 v0.1

初稿日期：2026-11-04。目前 app 名稱為 **cNews**。

## 核心要求

cNews 係一個 iOS newsgroup reader，採用黑底、深灰 toolbar、系統藍操作按鈕及多層討論串閱讀介面。

流暢度驗收：返回保留捲動位置；逐篇閱讀即時反應；輸入期間唔重建整頁／丟失游標；大串採用增量更新；網絡同解碼唔阻塞 UI；避免重複發送。正式原生版以真機 Instruments 驗證滑動及切頁，目標維持裝置刷新率（60/120 Hz）、零明顯卡頓。瀏覽器原型未作真機效能認證，部分進階手勢效果仍待驗收。

## 來源同分析方法

需求根據開發交接及操作錄屏整理。原片、私人分享連結及本機路徑唔公開。原始錄屏長 224.126 秒。
已從本機原片每 2 秒抽畫面，覆蓋 0–224 秒，並檢視全部 contact sheets；另保留每 10 秒畫面於 `docs/reference/`（本機，唔提交公開 repo）。呢個係抽幀分析，唔代表逐幀檢查所有手勢。

## 影片觀察結果

| 時間 | 畫面／操作 | 可確定嘅功能 | 未能確定 |
| --- | --- | --- | --- |
| 00:02–00:06 | Groups 首頁；server 標題下係已訂閱群組 | 編輯、加 server、按 server 開設定；群組包含 club.arsenal、club.liverpool、club.manutd、club.spurs、game.ps4、general.chat、general.soccer_n_chat、talk.JapanTV、talk.MilkJapan、talk.ele_device | 編輯可刪除／排序與否未操作 |
| 00:08–00:12 | Add Server sheet | Server、Port（留空用預設）、Name、Email、Login Name（optional）、Password（optional）、Encoding；新 server 預設 UTF-8 | 完成新增未示範；TLS 選項未見 |
| 00:16–00:20 | 現有 server 設定 | 畫面地址 news.twonil.hk、port 119、Big5；Subscribe Group、每次最多取 2000 headers、每群最多留 7500 articles、Delete Server | 訂閱選擇器未開；119 唔等於已驗證現時可連線；唔從片內身份資料預填原型 |
| 00:24–00:40 | 群組文章清單、切換群組、重新整理 | 大標題、搜尋欄、作者／時間／大小；討論串右側 x/y；上下拉更新同最後更新時間；底部 compose、狀態、動作選單 | 搜尋範圍未示範；No New Messages 係更新結果，唔等於冇未讀 |
| 00:42–00:44 | 群組動作選單 | Mark All Read、Show Unread Only、Show Favourites Only、Get Older Messages、Sort Threads by Latest Reply | 選項存在已確認；收藏入口／排序切換結果未示範 |
| 00:48–01:10 | 新文章 composer | Group、Subject、正文、可編輯內容；Send 隨輸入變可用；預設簽名；右上角相機 | 簽名設定入口未見 |
| 01:10–01:22、02:08–02:34 | Attach Photo、相簿 | Take New、Choose Existing、Cancel；iOS 相片權限同相簿瀏覽 | 冇清楚見到成功加相發佈；相片數目、壓縮、MIME/yEnc 格式未確定 |
| 02:36–02:44 | 發文後新主題出現並打開 | 本次錄屏可見新主題加入頂部，閱讀頁顯示 1 of 1、作者、日期、正文 | 唔以此推定 server 實際 protocol 或去重策略 |
| 02:46–02:56 | 展開 APM 討論串同閱讀回覆 | 清單內縮排回覆；閱讀頁 n of total；正文包含分層引文、簽名；底部回覆、左右及上下切換鍵 | 鍵／手勢逐一語意未清楚示範；原型暫定左右逐篇、上下逐串 |
| 02:54–03:08 | 閱讀後未讀數下降、Mark Thread Read | x/y 分子會由 7 降至 3，再變 0；可合理判定係「未讀／總數」；可將成串標已讀 | 開啟後幾時算已讀、跨裝置同步未明 |
| 03:10–03:14 | 圖片文章、帶引文回覆 | 內文直接顯示圖片；回覆 subject 加 Re:；正文帶原文作者／時間及 > 引文 | 圖片放大／儲存、外部連結政策未示範 |
| 03:16–03:34 | 回覆後再逐篇閱讀 | 回覆加入同一串；巢狀引用；讀取中 spinner；退返清單保留展開串 | 發送失敗、離線、搜尋、收藏細節未示範 |
| 03:36–03:44 | 拉更新、返回 Groups | 清單更新後返回主頁，保持原有導覽結構 | 背景更新未示範 |

## 首版產品範圍（根據影片提出，未逐項獲用戶確認）

### 用戶已確認嘅討論串／swipe 行為（2026-11-04 追加）

- 每篇 message 記錄所回覆嘅 message ID；以真正父子關係顯示多層縮排及分支，唔可以只顯示一層回覆。回覆文章時保留該篇父節點。
- 討論串列表向右 swipe 展開該串；已展開嘅 thread 喺原文或任何深度嘅回覆向左 swipe，會收起整串。重複向右唔會收起；未展開時向左亦唔會打開文章。收起後保留原串標題喺畫面。
- 列表 swipe 只控制展開／收起，唔標記已讀，唔觸發文章輕觸開啟；垂直捲動仍然係捲動，拉更新只識別明確向下手勢。
- 串內閱讀跟展開清單嘅層級順序（父文章後跟子回覆，再同層下一個分支）。
- 向左 swipe：下一篇；到串尾就接下一條 thread 第一篇。
- 向右 swipe：上一篇；到串頭就返上一條 thread 最後一篇。
- 同一群組／篩選結果嘅第一篇同最後一篇會停止，唔循環跳返頭尾或走入其他群組。
- 左右按鍵及鍵盤共用同一閱讀規則。上下 thread 按鍵仍係直接跳串，具體語意按後續確認更新。
- 打開文章時記低當時列表／排序嘅閱讀路徑；逐篇標記已讀唔會令「只睇未讀」嘅閱讀次序突然改變。
- 舊原型示例會補上示例父子關係；之前已發嘅本機回覆冇保存目標文章 ID，無法還原精確父節點，暫掛喺原文之下。新回覆會保存正確父節點。

### 回覆引用 history（用戶已確認）

- 以正被回覆嗰篇為第一篇，沿 `parentId` 向上追，最多引用四篇；唔按時間／陣列位置選取，唔引用兄弟或其他分支。
- 例如 A → B → C → D → E，回覆 E 嘅新文章引用 E、D、C、B，唔包含 A。不足四代就引用已有祖先；父節點缺失或重複會停止。
- 每篇帶作者／時間，按 >、> >、> > >、> > > > 保留巢狀層級。閱讀頁將同一段引文呈現為巢狀引文框。
- 由每篇自己寫嘅正文重建 history，唔直接複製內含嘅舊 quote；避免重複祖先，亦避免第五代經舊引文夾返入去。發佈後再回覆會重新計算四代。
- 原有文字草稿唔會自動改寫，避免覆蓋已編輯內容；新建回覆套用呢套規則。

### 文章連結開啟（用戶已確認）

- 正文同引用入面嘅 HTTP／HTTPS 網址可點擊，亦支援 www. 開頭網址；中文句末標點唔會加落 URL。
- Facebook、Instagram、Threads、連登連結應優先交畀已安裝、可處理該 URL 嘅 app；否則使用手機預設瀏覽器，唔用內置網頁檢視器。其他網站同樣交由系統處理。
- 保留原 URL 嘅路徑、query 同 fragment，唔改成 app 首頁；唔猜測未經驗證嘅第三方 URL scheme。
- 原生開啟元件位於 `native/ExternalLinkOpener.swift`：先 `UIApplication.open` + `universalLinksOnly`，失敗後用正常系統 open 開原 URL。Universal Links 是否生效取決於對方 app／網站對該 URL 嘅支援、安裝狀態及系統設定，唔保證同一域名所有 URL 都能跳 app。[Apple Universal Links 文件](https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content/)
- 瀏覽器原型只提供一般外部連結，新頁開啟以保留 reader；無法查出手機裝咗邊啲 app，亦唔代表已驗證 iOS 預設瀏覽器或第三方 app 跳轉。
- 實機驗收要逐項測 Facebook／Instagram／Threads／連登內容連結、有／冇安裝 app、預設 Safari／其他瀏覽器、對方唔支援嘅 URL，以及返回 reader 後仍保留閱讀位置。

### 文章內嵌內容（用戶已確認）

- IG 及其他支援平台先喺 message body 內嵌，唔需要先跳外部 app；本輪涵蓋 Instagram、X、Threads、Facebook、YouTube、TikTok、Vimeo、Spotify 嘅內容連結。
- 正文同引用均識別；同一內容只建立一次 embed。原網址一直保留，載入失敗／私人／地區限制時可點連結走原本 app／瀏覽器流程。首頁同未支援嘅 URL 唔當成貼文。
- 按可見位置載入、唔主動 autoplay；換文章清理載入程序，唔阻塞閱讀。平台自行提供貼文外觀及限制訊息，唔偽造 preview 當完整內容。
- 詳細支援路徑、隔離方式、官方來源、測試同原生接續見 [EMBEDS.md](EMBEDS.md)。

### 相片附件上限（用戶已確認）

- 每篇新文章／回覆最多 3 張相片。一次選超過剩餘位置，只加入可容納嘅前幾張，提示其餘未加入。
- composer 顯示 Photos: n/3；滿 3 張後停用加相，移除一張會重新開放。示範相同自選相一齊計數。
- 讀取相片期間停用 Send／再次加相／移除，避免並行操作超額；Send 資料層亦會拒絕 4 張或以上，保留草稿。
- Send 後依照手動 Refresh 流程，刷新先載入新回覆；同一頁面內保留完整附件次序。自選相片目前只放頁面記憶體，整頁 reload／關閉後不保留，正式原生版仍需實作持久儲存及 MIME 傳輸。

### Send 與手動 Refresh（以用戶最新確認為準）

- 按 Send 先成功保存至 repository（本機模擬 server），再清除草稿並返回列表。列表保留送出前嘅文章、數量、未讀數、排序、篩選、展開狀態及捲動位置；唔立即加入新回覆，亦唔定位或高亮新文章。
- 撳 Refresh（或拉更新）先從 repository 載入自己及其他新訊息，一次更新列表；所有新送出回覆初始係未讀，包括自己發嘅回覆。新回覆用原有白字／藍點樣式，唔加藍色或灰色背景。展開回覆沿用黑底，以縮排及細連接線表示層級。
- 未 Refresh 期間可以繼續讀舊文、儲存草稿或再發文；保存舊 cache 時必須保留 repository 已收到但尚未顯示嘅新文章，唔可以覆蓋或誤標已讀。
- 同一個分頁整頁 reload 屬重新載入資料，亦會取得已送出文章；原 thread 同最近送出位置可以恢復。一般 Send 返回列表唔會執行呢個資料刷新。
- 保存失敗留喺撰寫頁，保留草稿／附件及原串；唔聲稱送出成功。原串已刪除時唔另開一條 Re: 新串。
- 此階段 repository 係本機 localStorage，未連接真實 NNTP；其他新訊息以另一個測試分頁模擬。真實 server POST／取新文仍待連線階段驗證。

P0：server 管理、群組訂閱、清單／討論串展開、逐篇閱讀、可靠未讀狀態、刷新／較舊文章、本機搜尋、Big5／UTF-8、新文章／引文回覆、內嵌圖片與相片附件、整串／全部標已讀。保留影片熟悉嘅黑底、藍色操作、列表密度、底部 toolbar；支援系統字體大小及 VoiceOver。

P1：收藏及篩選、最新回覆排序、可自訂簽名、可調快取上限、斷線重試、草稿恢復。收藏篩選同排序入口雖然片內存在，具體行為仍待確認。

未證實需求：全站全文搜尋、封鎖作者、批量二進位下載、多裝置同步、iPad 專用 layout。唔當成已確認首版範圍。

## 第一個可操作原型

採用無依賴本機 HTML/CSS/JS，先驗證操作流程，唔代表最終 iOS 技術選擇。現機只有 Command Line Tools，冇完整 Xcode／iOS Simulator，所以本輪唔聲稱已完成 iOS build。

- Groups → 設定／訂閱 → 群組清單 → 展開回覆 → 閱讀 → 引文回覆／新文章 → 本機模擬發佈。
- 使用重新編寫嘅示例文章及虛構身份，唔複製片內私人 email、相簿或文章內容。
- 未讀數由各篇文章狀態計算；重開保留已讀、收藏、訂閱、server 表單同文字草稿。
- 搜尋暫定本機主題、作者、正文；最新回覆排序、未讀／收藏篩選、取較舊示例文章都可操作。
- 圖片使用自己製作嘅示例圖或使用者自行選取；附件只保留本輪記憶體，唔上載；相機拍攝交由原生版處理。
- 發佈只加入本機示例資料；明示「模擬發佈」。刷新唔假裝連接真 server。
- 原型可儲存多個示例 server 設定；唔收集真實密碼、唔作網絡連線。
- 新加／刪除 server、訂閱入口屬原型設計；唔聲稱已從影片觀察到完整細節。

## 驗收流程

1. 開 Groups，切入 general.chat；展開一串回覆，開閱讀頁睇到 n/total、作者、引文。
2. 下一篇只標記該篇已讀，退返清單分子同底部未讀總數正確減少；重載後狀態仍在。
3. 選單只顯示未讀／收藏、排序、取舊文章；冇結果時有清楚空白狀態。
4. 回覆保留 Re: 同 > 引文；取消會留文字草稿；新文章同回覆模擬發佈後回到正確群組／原串。
5. 加相有預覽、可移除，發佈後文章內顯示；冇實際上載／NNTP POST。
6. 設定 Big5、2000／7500 等表單有效值可存；錯誤 port／空 server 會阻止儲存；唔儲存帳密。
7. 320px 窄屏同桌面都可用；原型測試同正式 NNTP 驗證分開記錄。

## 原生實作建議（待原型回饋後落實）

SwiftUI + NavigationStack；Transport、NNTP client、MIME/charset decoder、thread builder、repository、view model 分層。文章以 server ID + Message-ID 定位；References/In-Reply-To 建串，subject 只作後備；讀取區間與收藏本機儲存；憑證只放 Keychain。

先實作只讀 NNTP（連線、capabilities、群組、headers、body）同 UTF-8/Big5 fixture 驗證，再加入 MIME 圖片及 POST。發文前顯示目的 server／群組，處理失敗保留草稿，重試先做去重判定。TLS／認證／編碼細節要對實際 server 測試，唔可以由錄屏推斷。

## 下一步待確認

- 地址係咪用影片嘅 news.twonil.hk？現時 port、TLS、登入同發文限制要另外驗證，暫時毋須提供密碼。
- 左右 swipe 同逐篇切換已確認（見上文）；上下跳串按鍵及其他手勢仍待確認。
- 收藏入口、簽名、相片格式／壓縮、舊文保存期限；需要完整離線內文定只存已讀內容？
- app 正式名稱、最低 iOS／iPad、license、GitHub owner 同上架帳戶留待原型回饋後決定。


### Live NNTP prototype（2026-11-05）

Groups → Connect NNTP 加入獨立 Live server；固定 news.twonil.hk:119 唯讀、無需登入。真實群組目錄、最近 500 個文章編號範圍、References hierarchy、按需正文、Refresh 新文及 Get Older Messages 已接通。初次文章全未讀，後續保留已讀／收藏／已下載正文。Demo 與 Live 分開；Live 發文及回覆暫停用。純文字 charset／MIME 解碼已支援；真實圖片、HTML-only、TLS／登入設定留待後續。


### Live 圖片附件（2026-11-05）

MIME base64／binary 附件會解碼後按 MIME 次序顯示 JPEG、PNG、GIF、WebP。以內容 signature 識別格式，唔插入 SVG／HTML。首次開文取得圖片、同頁 Refresh 保留記憶體圖片；重載後按 imageCount 缺失重新讀取，舊 text-only cache 按 contentVersion 升級。圖片 bytes 唔寫入 localStorage，避免 quota 塞爆。未做全屏圖片檢視或 uuencode／yEnc。


### Live 發文／回覆（2026-11-05）

啟用真實 POST，Name／Email 喺 composer 填寫並公開顯示。只喺 server 240 確認後清草稿，返回發送前清單；手動 Refresh 才合併 server 新文，全部新文未讀。父訊息引用會先取得最多四個祖先實際正文，再引用；References／In-Reply-To 保持 NNTP 父子關係。最多三張 JPEG／PNG／GIF／WebP、每張 5 MB；Big5 無法表示內容時改 UTF-8，唔替換文字。失敗／結果未確認保留草稿，固定 Message-ID 防止重試重複發文。


### 新操作片：Server／Groups／大量下載（2026-11-05）

詳見 SERVER_GROUPS_AND_DOWNLOADS.md 嘅完整時間碼及使用者補充。＋新增真實公開 NNTP server；Name／Email 移到 server level，各 server 獨立，composer 移除身份欄位。Subscribe Group 為獨立可搜尋多選頁，取消打剔或 Groups 編輯可移除訂閱，cache／已讀保留。

每次 Refresh 先計實際新文章編號；超過 500 提示總數，提供 500、1000、2000、自訂更多、All 及 Next／Latest。Next 以本機最新已下載文章為起點向新，Latest 取 server 最新嗰批；跳過舊文留待 Get Older Messages。All 分批最多 500、逐批保存及顯示進度，Cancel 不下載 headers。
