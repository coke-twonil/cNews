# yrNewsEx 原生 iOS

開啟 `yrNewsEx.xcodeproj`，選 yrNewsEx scheme 及 iPhone Simulator，Run。最低 iOS 17；目前於 Xcode 27.2、iOS 27.2 Simulator 編譯及試讀。

## 試用

Device Hub → yrNewsEx → **news.twonil.hk · Live** 下面嘅 general.chat。Demo 區維持本機操作示例。

Live 直接用 Swift／Network.framework TCP 連 NNTP，唔依賴瀏覽器、localhost 或 Python helper。Server 設定 → Subscribe Group 由 LIST ACTIVE 載入目錄，搜尋／打剔／取消打剔，再返回按 Done 保存。Name／Email 屬 server 設定；發文前要填身份，未填亦可閱讀。既有 server 地址／port 固定以免快取混淆，另一地址請新增 server。

進群組只讀取本機快取；只按 Refresh 先用 LISTGROUP 取實際可用編號，超過 500 新文先問總數及下載數量：500、1,000、2,000、自訂、All。Next 從本機最新已下載編號之後向新取，Latest 取最新一批。略過舊文唔算新文；按最新用戶要求移除 Get Older Messages 入口，唔提供補下載舊文操作。每批最多 500 headers，完成一批先保存；中途錯誤保留完成批次。取消選單唔下載 headers。

文章正文及圖片按需以 ARTICLE 取得。支援 RFC2047、UTF-8／Big5／CP950、MIME multipart、base64／quoted-printable 文字及 JPEG／PNG／GIF／WebP 附件。每張圖片解碼後最多 10 MB、每篇合共 20 MB。HTML-only、UUencode／yEnc 等未支援內容會提示；圖片動畫播放及圖片放大仍未移植；支援平台網址已可內嵌（見下面最新驗證）。已取正文及圖片保存本機；未打開嘅文章只保存 headers，唔係全部正文已離線。

按 References／Message-ID 組 thread，唔按 subject 合併；缺失父文保留可見內容。已讀及快取分 server／group 保存。119 普通 NNTP；563 由系統驗證 TLS 憑證；其他 port 目前普通 TCP。暫未支援帳密登入或 STARTTLS。

Live 支援在目前 group 開新主題及回覆，實際由 server 決定是否接受 POST。Demo Send 只保存本機文章，Refresh 才以未讀加入。

## 操作及外觀

自訂平面藍色導覽列、頂部搜尋、全闊深灰工具列；文章無灰／藍背景 highlight。列表左右 swipe 都切換整串開／收狀態；保留層級縮排，移除 L 形連接符。UIKit 方向辨識器同垂直 scroll pan 協作，唔使用會搶走上下捲動嘅 SwiftUI DragGesture。

閱讀按 DFS 路線左右切換，串尾／串頭可跨至相鄰 thread；開文章前固定路線，唔受已讀篩選影響。Demo Reply 單一 TextEditor，引用目前訊息及三代父文，唔引用其他分支。視覺仍需真機對照，唔代表已逐像素完全一致。

## 2026-11-06 驗證

- 原生版本編譯成功，8 項模型＋12 項 NNTP／解碼測試通過。
- 本機測試 server 驗證 LIST ACTIVE、稀疏 LISTGROUP／OVER、References、ARTICLE dot unstuffing；無 POST 指令。
- 真實 news.twonil.hk:119 目錄載入成功。
- general.chat 實測當時 3,112 篇，Latest 500 下載成功，整理成 112 threads；打開兩篇，中文正文及其中一篇兩張 MIME 圖片成功顯示。
- 已讀由 500 減至 498，Refresh 保持；Get Older 顯示 2,612 篇；取消後不變。
- 之前已實測列表展開／收合、垂直捲動、跨 thread 左右閱讀，以及本機長文章捲到第 40 段再切換。
- 今輪只讀取，無真實發文。TLS 實作使用系統驗證，尚未對真實 563 server 端到端測試。

## 檢查

```sh
xcrun swiftc native/yrNewsEx/ReaderModel.swift native/Tests/main.swift -o /tmp/yrnewsex-model-tests
/tmp/yrnewsex-model-tests
xcrun swiftc native/yrNewsEx/ReaderModel.swift native/yrNewsEx/NNTPClient.swift native/NetworkTests/main.swift -o /tmp/yrnewsex-network-tests
python3 scripts/test_native_nntp.py
xcodebuild -project native/yrNewsEx.xcodeproj -scheme yrNewsEx \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath /tmp/yrnewsex-build CODE_SIGNING_ALLOWED=NO build
```

未完成原生項目：真機相機及完整功能驗收、圖片放大、cache retention／儲存容量管理。Bundle identifier 暫用 `org.yrnewsex.reader`；正式發佈前改成擁有人帳戶可用識別碼。模擬器唔需要付費開發者會籍。

最新介面修正：移除 Get Older Messages 按鈕及下載選單內嘅補舊文提示；保留 Refresh／Next／Latest，既有快取保留。上文驗證記錄描述移除前測試。

最新閱讀介面：移除文章頂部篇數（例如 2／504）；保留 Back 同底部切換按鍵。下載新訊息完全手動，進 group 唔檢查新文；打開未快取正文嘅文章仍按需讀取該篇正文。

最新手勢：由畫面左邊緣（24 pt 內）開始向右 swipe，文章返回 thread 清單，thread 清單返回 Groups；一般右 swipe 只接收邊緣範圍以外嘅觸點，維持上一篇／展開 thread。兩種操作用獨立方向辨識器分流；非當前畫面及呈現回覆／下載選單時停用返回辨識器。已於模擬器實測兩層邊緣返回，並確認正文中間右 swipe 仍上一篇、清單中間右 swipe 仍展開，無篇數標題恢復或自動刷新。


## 原生 embed 修正（2026-11-06）

`NativeMessageBody` 按網址位置插入官方內嵌內容，保留原文及可點擊原網址；同一 canonical 貼文只 embed 一次。新增 WebKit 元件，唔依賴本機 Python server。支援辨識 IG、X、YouTube、Facebook、Threads、TikTok、Vimeo、Spotify；連登以 LinkPresentation 顯示標題／圖片預覽，唔冒充整篇討論串 embed。其他網址維持普通連結。

WebKit 使用 non-persistent data store，只接受主 frame 傳入嘅有限高度／載入狀態，無原生資料存取橋樑；嵌入連結用系統 Universal Links／預設瀏覽器開啟。載入失敗提供原連結及重試，捲動取消下載唔當成平台錯誤。第三方元件會向各平台下載該條連結嘅公開內容，唔傳送整篇 NNTP message。

實測 test.test「試野」（1062）：IG 成功見到 Tatler 原貼相片；X 成功見到貼文內容及回覆數；YouTube 成功見到影片播放器；連登成功取標題／圖片。Facebook 分享連結官方重導到 group permalink，oEmbed 回 HTTP 400，已補支援該類重導格式，失敗時改顯示原生預覽卡及清楚提示，唔宣稱已做到完整 Facebook post embed，亦唔推斷係需要登入。Threads／其他平台今輪只驗證辨識及元件，未逐個真實內容驗收。

33 項原生測試通過（既有 20 項 + 13 項 embed 辨識、去重及網址驗證）。新增：

```sh
xcrun swiftc native/yrNewsEx/EmbedModel.swift native/EmbedTests/main.swift -o /tmp/yrnewsex-embed-tests
/tmp/yrnewsex-embed-tests
```

實作參考：X 官方 [embed 說明](https://help.x.com/en/using-x/how-to-embed-a-post)、Meta 官方 [oEmbed plugin 說明](https://github.com/facebook/meta-embeds-for-wordpress/blob/main/README.md)。最終顯示仍取決於原貼可用性及平台限制。


## test.test 原生相片回覆（2026-11-06）

已用原生 UI 完成一次公開回覆：test.test 原有「yrNewsEx 功能測試（請忽略）2026-11-05」thread，文章編號 **1063**，Message-ID `<yrnewsex.8ffa6cb1-f373-4441-a41a-105827b2e813@yrnewsex.invalid>`。使用明確測試身份及產生嘅漸層圖，唔用私人相片；完成後 server Name／Email 還原原先空白。公開測試文章保留，未刪除。照片只加入模擬器 Photos，唔修改使用者真機相庫。

驗證：只新增一篇；server 讀回 JPEG 6,581 bytes，References 接原父文；MIME 為 text/plain → image/jpeg → text/plain（history）。Send 收到 240 先成功，返回原清單未有新回覆；手動 Refresh 後未讀數由 4 升至 5，開回覆成功見新文字、測試圖、history 正確次序。截圖 `docs/native-photo-reply-readback-preview.png`。

附件最多三張，每張 JPEG／PNG 最大 5 MB（原生相片選擇／相機輸入轉 JPEG）。Choose Existing 用系統 PhotosPicker 只讀選中相片，Take a New Photo 使用真機相機；模擬器顯示無相機。草稿文字、附件及 Message-ID 保存在 Application Support，失敗保留；Name／Email 只喺 server 層設定。首次 Send 前讀取最多四篇父鏈 history，未能取得時保留錯誤及 Retry，唔默默省略 history。

固定每次內容嘅 Message-ID，改文字／相片／身份會換新 ID；發送前先 ARTICLE 查收錄，重複時核對 header、正文同所有圖片 bytes，唔將 duplicate 盲當成功。發送結果未確認會保留狀態，下次只查收錄，唔自動再 POST。「用新識別碼再試」只準備新 ID，仍需另按 Send。尚未新增一般群組發文或新主題；目前只開放 test.test 方便驗收。

44 項原生測試通過（原有 33 + 11 項發文／MIME／相片／去重／本機 POST 讀回）。測試發現 Swift Character 對 CRLF 嘅辨識差異，已改以 newline character set 驗證 header／command，避免注入。

```sh
xcrun swiftc native/yrNewsEx/ReaderModel.swift native/yrNewsEx/NNTPClient.swift native/yrNewsEx/PostingModel.swift native/PostingTests/main.swift -o /tmp/yrnewsex-posting-tests
python3 scripts/test_native_nntp.py /tmp/yrnewsex-posting-tests
```


## 真機簽名設定

共用設定由 `native/Signing.xcconfig` 載入；個人 Team ID 及專用 bundle identifier 放入已忽略嘅 `native/LocalSigning.xcconfig`，唔推上公開 repo。可參考 `LocalSigning.example.xcconfig`，將 YOUR_TEAM_ID 換成 Xcode Apple Account 嘅 Team ID，並用自己可註冊嘅 bundle identifier。Debug／Release 都使用同一個本機覆寫；模擬器可繼續唔簽名編譯。

真機安裝仍需 Xcode 實際連通並信任 iPhone，以及有效 development certificate／profile。成功編譯未簽名 ARM64 app 唔代表已裝落手機。

真機安裝及逐項試用步驟見 [DEVICE_TESTING.md](DEVICE_TESTING.md)。2026-11-06 已完成一次 iPhone 18 Pro／iOS 27.0.1 真機安裝及啟動；個人憑證／profile 只保留本機。


## 2026-11-07 真機回饋修改

- Threads：左右 swipe 都 toggle 整串；左邊緣右 swipe 仍返回 Groups。回覆保留縮排、移除 L 線；多篇 thread 以圓角框顯示未讀／總數，零未讀為灰色，其他為藍色。
- 底部中間保存最近一次手動 Refresh 實際新增文章數（每 server／group 獨立）；閱讀、收藏、Block 及篩選唔改變該數字。未曾 Refresh 或更新前冇歷史數值則顯示 0，下一次零新文 Refresh 亦更新為 0。取消下載選單保留上次數值，部分下載失敗保存已完成批次數。
- 左下 New Post 支援標題、文字及最多三張相；身份沿用 server Name／Email。新主題冇 References／In-Reply-To，成功後保持原列表，手動 Refresh 先加入。右下係操作選單（唔係分享）：Mark All Read、Show Unread Only、Show Favourites Only、Sort Threads by Latest Reply、Cancel；冇 Get Older Messages。
- Search 啟動後顯示 Subject／Sender／Message 三段選擇同取消。搜尋範圍係本機已下載文章；Message 搜尋會按需載入呢批文章嘅未快取正文，顯示進度，只保存搜尋文字，唔一併快取圖片；唔下載新文章或自動 Refresh。
- 文章底部依次 Reply、上一篇、下一篇、上一條 thread 第一篇、下一條 thread 第一篇、操作選單。選單有 Mark As Favourite／Remove Favourite、Mark Thread Read、Cancel。收藏及已讀持久保存，前後閱讀維持原 DFS 路線，冇恢復頂部篇數。
- 長按列表任何 message 或撳內文 email 行右邊 Block icon，確認視窗顯示 username、email、sender IP。按文章 sender IP（唔係 email）封鎖，同一 server 所有 groups 生效；相同 IP 文章及整串子回覆隱藏，原快取保留。Server Settings 的 Blocked Users 列出三項身份並可 Unblock，恢復文章。
- Sender IP 讀取 NNTP-Posting-Host、Injection-Info posting-host、X-Originating-IP 或 X-Trace；唔用 relay/server IP 或 DNS 猜測。支援 IPv4／IPv6 正規化；無有效來源 IP 時停用 Block 並提示。HDR／XHDR 批次讀取，舊 server 用 HEAD；首次 Block 會補取該 server 已快取文章來源 headers（包括已取消訂閱但仍有快取嘅 groups），唔改已讀或 Refresh 數值。
- Block 名單只保存本機，每 server 獨立。IP 並非永久個人身份：共用 IP 一同受影響，對方換 IP 後唔會按原 IP 命中。

今輪測試不向公開 newsgroup 發文；新 POST MIME／相片與來源 headers 使用 localhost fixture，UI 新主題使用 Demo。真 server 只讀檢查 source headers，最近三篇有兩篇提供有效 sender IP。


本輪驗證：70 項原生測試通過（25 模型、19 NNTP／解碼、13 發文、13 embed）。模擬器實測左右兩方向重複 toggle、Sender／Message 搜尋、Demo 新主題發送後手動 Refresh 先出現、閱讀後 Refresh 數字不變、文章六個按鈕及收藏、長按 Block、Server Settings 三項身份與 Unblock 恢復。Block 測試只修改模擬器本機設定，完成後已解除；無新增公開測試文章。


## Delete Server

Server Settings 底部新增紅色 Delete Server。確認視窗會顯示 server 名稱，列明本機資料移除及無法還原；Cancel 保留全部資料。確認後移除該 server、訂閱、文章快取（包括收藏）、草稿、待刷新 Demo 回覆、Refresh 數字及 Block 名單，不向 NNTP server 發送刪除文章指令。其他 servers 資料保留；載入中暫停用刪除。保存移除標記，避免預設 Live server 或 Demo 測試文章重開 app 後自動出現。

新增 6 項刪除資料隔離及持久化測試，模型測試共 31 項通過。


## INN sender IP 格式修正

支援 `Injection-Info` 內 `posting-host="hostname:IPv4"`，以及 hostname 後接完整 IPv6／方括號 IPv6；只解析 header 內已有嘅數字 IP，唔做 DNS 查詢，唔將 logging-data 或 relay 位址當來源。修正前部分 news.twonil.hk 文章其實有 IP 但被顯示成未有提供。

首次更新會保留有效 IP、正文、已讀及 Block 名單，只重設舊版本冇抽到 IP 嘅查詢標記，令長按 Block 可以再讀來源 header。已有 Block 名單嘅 server，進 group 會補讀已快取文章嘅未檢查來源 headers，唔下載新 messages，唔改 Refresh 數字。新增 7 項 header 解析測試及 5 項快取遷移測試；模型 36 項、NNTP 26 項通過。

修正後真 server 只讀抽查：general.chat 最新 20 篇、general.soccer_n_chat 最新 20 篇、test.test 全部 7 篇，app parser 均讀到來源 IP。模擬器沿用舊快取，長按 test.test「試野」已成功顯示 IP 並啟用 Block；取消確認，未封鎖該用戶，無發文。抽查結果不代表所有歷史文章。


## 回覆加圖及工具列修正

新主題／回覆統一將相片 camera icon 放在右上角 Send 左邊，保留 Choose Existing／Take a New Photo，但移除可見 Attach Photo 文字、0/3 計數及底部 Send 提示。最多三張相限制不變；三張後停用 icon，刪除附件可再加入。

加圖流程修正：PhotosPicker 關閉後才開始匯入，固定每次選擇器的剩餘名額，忽略空選擇及重複觸發。保留原始 HEIC/JPEG 資料交 ImageIO 在 worker task 解碼為最長邊 2048 px、方向修正後的 JPEG（最多 5 MB）；不在主執行緒壓縮原尺寸照片。相機照片亦在 worker 縮圖及壓縮。附件預覽只讀 240 px 縮圖，避免每次重畫解碼整幅照片；匯入提供進度及取消，離開畫面取消工作，取消後不插入遲到結果。

原本每次編輯草稿／加相會在主執行緒編碼及寫入整份文章快取。改用 serial background writer 原子寫入，合併等待中的快照並保持最新版本順序，寫入失敗回報；文字、圖片、已讀及其他文章保留。未改 Send 成功後手動 Refresh 才加入文章的流程。

驗證：6 項 PhotoTests（24 MP、EXIF 方向、大小限制、metadata、預覽縮圖及損壞檔案）、4 項 PersistenceTests（最新草稿順序、相片 bytes、文章快取及寫入錯誤）、13 項既有發文測試通過。模擬器 Demo 回覆實際匯入產生的 24 MP 色塊照片，仍可打字、再加入兩張產生的測試圖；三張後 icon 停用，取消編輯再開草稿保留文字及三張圖。沒有公開發文，沒有修改真機相庫。相機實拍仍需真機驗收。

```sh
xcrun swiftc native/yrNewsEx/ReaderModel.swift native/yrNewsEx/PhotoPreparation.swift native/PhotoTests/main.swift -o /tmp/yrnewsex-photo-tests
/tmp/yrnewsex-photo-tests
xcrun swiftc native/yrNewsEx/ReaderModel.swift native/yrNewsEx/SnapshotFileWriter.swift native/PersistenceTests/main.swift -o /tmp/yrnewsex-persistence-tests
/tmp/yrnewsex-persistence-tests
```


## 相簿操作及頂部附件縮圖

依操作參考改為 camera → 底部 Attach Photo 選單（Take New、Choose Existing、Cancel）→ 相簿列表 → 四欄相片格仔 → 揀相 → 完成。依剩餘名額限制選擇，跨相簿保留選擇；讀取選中照片支援 iCloud 及取消，處理／儲存維持背景工作。附件最多三張，選完縮圖放在編輯畫面最頂工具列中間，每張有移除鈕，唔放在內文下方；camera 保留在 Send 左邊。

相簿列表用 PhotoKit，首次 Choose Existing 由 iOS 要求相片權限。有限存取只顯示已獲允許嘅相片；拒絕存取時顯示說明及 Open Settings，不存取或修改未獲允許嘅相庫內容。模擬器權限只用於開發測試，真機由使用者親自選擇。相簿／相片 metadata 不會因開啟選擇器上載；只有 Send 時選中的附件隨文章發送。參考 Apple [PhotoKit 權限及有限存取](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app)。

發送成功移除 Sent／Saved locally 提示及 OK 步驟，直接關閉新主題／回覆畫面。回覆保留既有返回原 thread 列表行為，成功後唔自動插入文章；手動 Refresh 先加入。失敗及未確認結果仍保留草稿、附件同錯誤，唔自動關閉。

驗證：模擬器實測底部選單、相簿列表、四欄相片格仔及完成後三張附件顯示在頂部；只剩一個名額時不能多選第二張。Demo 相片回覆按 Send 後直接返回原列表，無成功提示及無新回覆即時插入；無公開發文。圖片、持久化及 MIME 23 項回歸測試通過。


## 2026-11-08：下拉更新、三相片 Send、Group 拖動排序

- Threads 到頂向下拉執行同 Refresh 按鈕相同的檢查／下載流程，包括超過 500 篇的數量及 Next／Latest 選擇。只有下拉或按鈕觸發，進 group 不自動取新文。使用原生 refresh control，加上按頂部實際座標／完成拖動方向及距離判斷的 SwiftUI 路徑，避免短列表或零初速手勢漏判；兩路共用防重複入口，普通上下捲動及左右 thread swipe 保留。
- Choose Existing 直接開四欄圖片庫，移除相簿列表第一步；頂部附件縮圖、完成／取消及最多三張不變。
- 修正附件 Base64 分行使用 String 從頭逐段定位的平方時間問題，改用 Foundation 一次性編碼。Send 前縮圖、指紋計算、MIME 建立全在背景進行，只建立一次 payload 後交給 NNTP transport。
- 新相片最長邊 1280px、JPEG 最多 512KB；已有合規 JPEG 不再重壓，舊草稿大相在正常 Send 前縮細。未確認／duplicate 的舊發送保留原 payload 及 Message-ID 供查收錄，避免修改內容後誤判／重複發文。實際圖片 bytes 仍隨文章發送，頂部縮圖只作預覽；新文字 → 相片 → history 次序不變。
- Groups 每行最右加三橫拖動把手，按住直接拖，無長按等待。只改同 server 的 group 次序，放手保存；其他區域仍開 group，其他 server 排列及文章不變。重開保持次序，取消手勢不會鎖住捲動。

驗證：40 項模型、8 項圖片、17 項發文／附件測試通過。三張各 1 MB 測試附件建立 MIME 約 0.002 秒，localhost POST／讀回 bytes 及 history 一致。原生模擬器 Live 流程亦實際發出三張測試圖到 localhost fixture：收到一篇文章及三個 JPEG，整篇約 313KB；畫面顯示 Sending 並成功返回原列表，無公開發文。UI 實測圖片庫直入、頂部三縮圖、把手即拖／反向拖／重開保存，下拉合併待刷新 Demo 回覆、再次下拉零新文變 0，以及左右 thread swipe 保留。暫時 localhost server 只存在模擬器，不會加入真機或 repo；私人資料及相片未提交 GitHub。


字體微調：Groups 的 group 名稱以 18pt 為標準字級並繼續跟 Dynamic Type 縮放；threads message 標題 17→18pt；message 正文、history 及原文網址 17→18pt，額外行距保持 5pt。
