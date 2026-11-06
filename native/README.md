# yrNewsEx 原生 iOS

開啟 `yrNewsEx.xcodeproj`，選 yrNewsEx scheme 及 iPhone Simulator，Run。最低 iOS 17；目前於 Xcode 27.2、iOS 27.2 Simulator 編譯及試讀。

## 試用

Device Hub → yrNewsEx → **news.twonil.hk · Live** 下面嘅 general.chat。Demo 區維持本機操作示例。

Live 直接用 Swift／Network.framework TCP 連 NNTP，唔依賴瀏覽器、localhost 或 Python helper。Server 設定 → Subscribe Group 由 LIST ACTIVE 載入目錄，搜尋／打剔／取消打剔，再返回按 Done 保存。Name／Email 屬 server 設定；今階段只讀，未填身份亦可閱讀。既有 server 地址／port 固定以免快取混淆，另一地址請新增 server。

進群組只讀取本機快取；只按 Refresh 先用 LISTGROUP 取實際可用編號，超過 500 新文先問總數及下載數量：500、1,000、2,000、自訂、All。Next 從本機最新已下載編號之後向新取，Latest 取最新一批。略過舊文唔算新文；按最新用戶要求移除 Get Older Messages 入口，唔提供補下載舊文操作。每批最多 500 headers，完成一批先保存；中途錯誤保留完成批次。取消選單唔下載 headers。

文章正文及圖片按需以 ARTICLE 取得。支援 RFC2047、UTF-8／Big5／CP950、MIME multipart、base64／quoted-printable 文字及 JPEG／PNG／GIF／WebP 附件。每張圖片解碼後最多 10 MB、每篇合共 20 MB。HTML-only、UUencode／yEnc 等未支援內容會提示；圖片動畫播放及圖片放大仍未移植；支援平台網址已可內嵌（見下面最新驗證）。已取正文及圖片保存本機；未打開嘅文章只保存 headers，唔係全部正文已離線。

按 References／Message-ID 組 thread，唔按 subject 合併；缺失父文保留可見內容。已讀及快取分 server／group 保存。119 普通 NNTP；563 由系統驗證 TLS 憑證；其他 port 目前普通 TCP。暫未支援帳密登入或 STARTTLS。

Live **test.test 已開放真實相片回覆**；其他群組保持 Read only。Demo Send 仍只保存本機回覆，Refresh 才以未讀加入。

## 操作及外觀

自訂平面藍色導覽列、頂部搜尋、全闊深灰工具列；文章無灰／藍背景 highlight。列表右 swipe 展開，任一子回覆左 swipe 收起整串。UIKit 方向辨識器同垂直 scroll pan 協作，唔使用會搶走上下捲動嘅 SwiftUI DragGesture。

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

未完成原生項目：其他群組發文／回覆、新主題發文、真機相機驗收、圖片放大、收藏、cache retention／儲存容量管理、真 iPhone 驗收及簽名。Bundle identifier 暫用 `org.yrnewsex.reader`；正式發佈前改成擁有人帳戶可用識別碼。模擬器唔需要付費開發者會籍。

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
