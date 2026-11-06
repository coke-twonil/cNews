# 原型 01 驗證記錄

2026-11-04，macOS，Codex in-app browser。本記錄只涵蓋瀏覽器原型，唔代表 iOS 真機測試。

## 已完成

- 原片長 224.126 秒；檢視每 2 秒抽幀嘅全部 8 張 contact sheets，整理功能及未確認項目。
- JavaScript 語法檢查通過；Node 22.22.0 嘅 5 項模型測試全部通過：逐篇／成串未讀數、搜尋／收藏／群組隔離、回覆歸串同最新回覆排序、新文章同空內容阻擋、設定驗證。
- 瀏覽器實際操作：Groups → general.chat → 展開 9 篇討論串 → 第 4／5 篇 → Reply → 輸入 → 示範圖片 → Send → 同串變 10 篇 → 打開第 10 篇，見到正文同圖片。
- 未讀總數由 26 變 24；重載頁面後仍係 24，同串回覆亦保留。
- 群組選單包含影片嘅 5 個操作；收藏篩選只顯示收藏串；搜尋「咖啡」只顯示匹配串。
- 設定頁顯示 Big5、119、2000／7500；輸入 65536 會被擋住並顯示錯誤。
- 320 × 740 及 390 × 844 手機版面目視檢查；搜尋、分數及底部 toolbar 可用。390 × 844 截圖：`docs/prototype-preview.jpg`。
- Git whitespace 檢查通過；原片同參考抽幀已忽略，唔加入公開原始碼。

## 尚未驗證／已知差異

- 呢個係第一輪外觀還原，未做到逐像素一致。自製 SVG 按鍵、字重、細節間距、status bar、sheet 位置仍需與同尺寸原機畫面覆核。
- Groups／server 設定嘅原生 modal 呈現、大標題隨捲動收縮、iOS 3D 翻頁動畫、邊緣返回、長按操作未完整還原。
- 已提供水平滑動逐篇閱讀、拉更新、鍵盤左右切篇，但觸控手勢未喺 iPhone 實測；左右跨串規則已按用戶補充修正（見下文），上下跳串按鍵仍待校準。
- Compose 目前簽名區、相片預覽同 native 文字編輯器有差異；相機拍攝未實作；原生版需用相片選擇器處理。
- 逐篇已讀、草稿、訂閱、模擬發佈等互動已可試；未對 2000 headers／7500 articles 作效能測試，未量度 FPS、Instruments 或網絡延遲。
- 未連接 NNTP；刷新／取舊文係本機示例。Big5／UTF-8 只儲存選擇，未解碼真文章；TLS、登入、MIME、真實 POST 及故障恢復待原生開發。
- 自選圖片唔寫入 localStorage；只喺本輪頁面記憶體存在，重新載入會消失。文字草稿每次輸入會保存。
- 未有完整 Xcode、iOS Simulator、簽名、TestFlight、GitHub remote 或上架設定。

## 下一輪驗收優先次序

1. 用戶以現有原版 reader 對照原型，指出字體、間距、按鍵／手勢差異；先修到符合熟悉操作。
2. 裝妥 Xcode 後建立 SwiftUI 原生版，以實際 iPhone 還原系統 sheet、文字輸入、滑動、動畫。
3. 連接用戶指定嘅 server，逐一驗證 Big5、內嵌圖片、未讀及回覆，再測試大量資料下嘅流暢度。

## 多層討論串及跨串閱讀修正（2026-11-04）

- 每篇加入 `parentId`，撰寫回覆保存 `replyTo`；以父子關係排出多層分支。示例包含一、二、三層及同層兄弟回覆，畫面加縮排及細連接線。
- 舊本機資料直接升級，保留已讀、收藏、草稿及文章；未知舊回覆嘅父節點只作根節點後備，唔聲稱能推斷原始關係。
- 左 swipe／Next Message／右方向鍵走下一篇，串尾接下一串第一篇；反方向由串頭接上一串最後一篇。閱讀路徑取當時群組列表同排序，標已讀唔會令路徑移位。
- 12 項模型測試全部通過，包括多層分支順序、回覆父節點保存／重載、跨串雙向邊界、未讀篩選路徑穩定、舊資料升級、缺失／循環引用，以及 swipe 方向／垂直捲動判別。
- 瀏覽器實際檢查：APM 串見到 1 → 2 → 3 → 2 → 1 層縮排；由單篇串按下一篇到下一串 `1 of 2`，再前進跨到 APM `1 of 10`，按上一篇返前串 `2 of 2`。
- 手機 touch handler 共用已測試嘅 swipe 方向及閱讀路徑函式；本輪未有實體 iPhone 觸控測試，唔將按鍵測試當成已驗證實機 swipe。

## 列表 swipe 展開／收起（2026-11-04）

- 列表使用 Pointer Events 辨識橫向手勢，支援觸控及桌面拖動；以手勢起點所屬 message 對應成條 thread，右 swipe 展開，左 swipe 從任何回覆收起成串。
- 手勢後阻止同一次滑動誤觸文章；下一次正常輕觸仍然可用。垂直捲動、取消／多指操作唔會當作展開或收起。
- 深層回覆收起後將根文章保留喺可見範圍；唔改動未讀狀態。
- 13 項模型測試全數通過。新增驗證右展開／左收起嘅單向操作、重複同方向唔 toggle、垂直及短距離操作無效。
- 瀏覽器實際拖動：APM 原文向右成功展開；第三層回覆向左成功收起；再展開並捲到第 9 篇，向左成功收起，根文章仍可見。前後未讀總數維持 16，停留喺列表。
- 本輪已測試瀏覽器拖動事件；實體 iPhone 觸控、系統邊緣手勢及手感仍待真機測試。

## 四代父系引用 history（2026-11-04）

- 新回覆由目標 message 起沿父節點取最多四篇，重建作者／時間及巢狀引文；每篇只抽取自己嘅正文，唔再次複製已引用 history。
- 16 項模型測試全部通過。新增具交錯分支嘅 E → D → C → B 選取、排除第五代／兄弟、重複引用防護、模擬發佈後再次回覆截斷、祖先不足／缺失／循環停止。
- 瀏覽器實測回覆 APM 第三層文章，composer 包 Film fan → 小文 → 散步的人 → Coffee lover 四篇，唔包含其他分支。
- 本機模擬發佈後閱讀頁顯示 4 個 blockquote，最大巢狀深度 4；再回覆新文章時引用 示例讀者 → Film fan → 小文 → 散步的人，原文 Coffee lover 成為第五代並排除。
- 試用頁留喺新回覆 composer，方便檢視四層引用；呢篇新草稿未發佈。之前用嚟驗證嘅文章只係本機示例，冇傳送到 NNTP。

## Send → 返回討論串 → Refresh（2026-11-04）

- 修正送出後冇定位新回覆、深層新回覆可能喺畫面外嘅問題：原串展開，新回覆藍色高亮並捲到可見位置。
- Refresh 由只顯示訊息改成重新讀取本機文章庫；同一分頁整頁 reload 亦會恢復最近送出回覆嘅群組／展開狀態／定位。
- 新文章先保存成功再採用更新狀態；儲存失敗保留草稿，重試唔重複 append。新回覆時間採用實際香港時間。
- 18 項模型測試通過，新增保存／重新讀取／父節點／四代引文同儲存失敗保留草稿測試。
- 瀏覽器完整實測：回覆 APM 第三層文章，輸入「試到喇！Send 之後返回 thread，Refresh 都見到呢篇回覆。」→ Send → 新增第 14 篇，父節點仍係原第三層文章，列表顯示藍色高亮、當時時間 22:58，且喺可見範圍內。
- 按 Refresh 後確認同一 message ID 保留，再整頁 reload 仍返到原列表、原串及同一篇高亮回覆，冇再次新增。
- 呢個係本機持久化及刷新測試，冇對實際 NNTP 發文，唔代表已驗證網絡發送。

## 移除回覆背景高亮（2026-11-04）

- 按用戶要求移除藍色選取底色同選取文字配色；新回覆沿用普通回覆列樣式。
- 保留 Send／Refresh／重新載入後展開及捲動定位到新回覆嘅功能。
- 本輪只修改 CSS 外觀及現行規格，未重跑與外觀無關嘅模型測試。

## Send 後保留舊列表，手動 Refresh 先載入（2026-11-04；取代上一輪即時顯示行為）

- Send 只更新 repository，暫時唔採用新文章到畫面 cache；保留舊列表、展開、捲動、篩選同數量。自己發嘅新回覆亦設為未讀。
- 儲存草稿／已讀狀態時會合併 repository 未下載文章，避免舊 cache 覆蓋待刷新的新回覆；亦保留遠端新增整條 thread。
- 20 項模型測試通過，新增送出後 cache 不變、兩則新回覆同次刷新變未讀、未刷新時讀舊文唔遺失新訊息，以及連續送出保存順序測試。
- 瀏覽器實測「有冇人用緊新 reader？」：Send 後仍係 0/2，新回覆不見；再讀一篇舊文返回仍係 0/2。
- 另一個臨時測試分頁送出另一則回覆，主分頁仍係 0/2；按 Refresh 後變 2/4，底部總未讀由 16 變 18，提示 2 New Messages。
- DOM 檢查兩篇新回覆均沒有 read class、白字 rgb(255,255,255)、背景同普通回覆一樣 rgb(51,51,53)；舊已讀回覆係灰字。冇藍色高亮。
- 另一個臨時測試分頁已關閉；以上係本機模擬 repository，唔聲稱已連接實際 server。

## 移除展開回覆區灰底（2026-11-04）

- 灰底來自 reply-row 原有固定背景，唔係已讀／未讀狀態。已移除，回覆列沿用黑底；保留縮排、連接線同白字／灰字及未讀藍點。
- 本輪只改 CSS 外觀，檢查灰底及 selected 高亮規則均已移除、CSS 括號配對；未重跑無關模型測試。

## 三張相片上限及實際加相測試

- UI 選取、示範圖同 Send 資料層統一上限 3 張；顯示 Photos: n/3，加滿停用相機，移除後重新開放；相片讀取期間阻止重複選取及 Send。
- 瀏覽器透過真實 file chooser 一次選 4 張本專案示例截圖 JPEG：只加入頭 3 張，顯示其餘 1 張未加入。全部預覽成功解碼。
- 移除第 2 張後顯示 2/3，相機重新可用；補一張示範圖後恢復 3/3 並停用相機。
- 測試中發現混合自選圖片及持久化示範圖，Refresh 只還原示範圖嘅缺陷；已改為優先還原完整頁面記憶體附件清單，保留原有三張同次序，並加入回歸測試。
- 重試兩張真實 JPEG 加一張示範圖 → Send → 保留舊列表 → Refresh → 打開新回覆：文章內有 3 張圖片，全部 complete=true，尺寸依次 390×844、665×822、640×420。
- 23 項模型測試全部通過，包括超額批量選取、刪除補位、Send 阻擋 4 張並保留草稿，以及混合圖片刷新回歸測試；JavaScript 語法及 whitespace 檢查通過。
- 界線仍係本機原型；自選圖片只喺本次頁面記憶體保存，整頁 reload 後會消失，未驗證真實 NNTP 附件傳送。

## 外部連結及原生開啟元件（2026-11-05）

- 正文及引用內網址轉為可點連結，保留路徑／query／fragment；處理中文標點、平衡括號及 Unicode path；文字及 href 分別安全轉義。
- 28 項測試全部通過（23 原有 + 5 網址測試），涵蓋四個指定平台、Threads 新舊域名、其他網站、引用、標點、特殊 scheme／userinfo 阻擋及 HTML 轉義。
- 瀏覽器新建「外部連結測試」本機示例，Send → Refresh → 閱讀後見到 Facebook、Instagram、Threads、連登、其他網站及引用內 Threads 六條可點連結。
- 實際點一般網站連結，成功開新分頁（Example Domain），原 reader 保持原畫面。新分頁已核對內容並關閉。
- 原生開啟元件採用 Apple 官方 Universal Links／UIApplication API；尚未整合可建置 iOS target，未有 UIKit 編譯或 iPhone app 安裝／預設瀏覽器測試，唔將桌面新頁測試當成手機跳 app 驗證。

## 多平台內嵌內容（2026-11-05）

- 已加入 Instagram、X、Threads、Facebook、YouTube、TikTok、Vimeo、Spotify 內容識別及官方內嵌，按可見位置載入；保留原連結及逾時／錯誤重試。
- 8766 獨立 origin 承載平台 HTML／JS，冇 reader localStorage；伺服器固定 API allowlist、HTML 清理及 CSP；父頁驗證 origin／frame／token，唔接受遠端程式操作。
- 34 項 JavaScript + 7 項 Python 測試全部通過，共 41 項。修正 IG／X 官方新域名同 X 作者路徑，並加入回歸測試。
- 實際載入並觀察 IG 真實貼文、X Developers 真實貼文、Threads、Facebook 內容，以及 YouTube／TikTok／Vimeo 播放器。Spotify 真實內容顯示地區限制，唔聲稱可播放。
- 無效 IG 內容成功後備到可點原連結。隔離 iframe 動態高度同捲動按位置載入已驗證；原生 iPhone 手勢／播放／登入仍待實機驗證。
- 詳見 [EMBEDS.md](EMBEDS.md)。

## 新 app 命名為 yrNewsEx（2026-11-05）

- 已統一介面標題、Groups 底部名稱、撰寫簽名、輔助說明、文件、package 名稱、embed 訊息協定及 User-Agent。
- 文章庫及分頁定位使用新儲存名稱，首次讀取會搬移舊資料；保留文章、訂閱、已讀、收藏同文字草稿，唔重設原型。新資料優先，唔被舊分頁覆蓋。
- 原始操作錄屏及舊版驗證截圖係歷史素材，冇重製或修改。
- 37 項 JavaScript + 7 項 Python 測試通過，共 44 項；包含儲存搬移、既有新資料優先及搬移失敗仍可讀舊資料測試。


## 2026-11-05 Live NNTP

- 實際連接 news.twonil.hk:119，無登入讀取成功，server INN 2.6.3。
- general.chat 首次 500 個 headers 載入成功；server 當時共 3,130 篇。
- UI 展開 APM Cupping Room 討論串，9 篇文章，最深 5 層；父子關係由 References 決定。
- UI 開啟真實中文原文及下一篇回覆，顯示實際作者、日期及正文，唔額外加示例簽名。
- 自動測試覆蓋 References 分支／缺失父節點、舊文合併去重、已讀／正文／收藏保留、新文未讀、Big5／UTF-8 header 及 MIME 純文字解碼。
- Live 圖片附件與 HTML-only 正文未支援，發文端點未實作。


## 2026-11-05 文章手勢修正

- 原因：文章頁只監聽 Touch Events，桌面滑鼠／觸控板冇導航事件；原生選取文字／拖曳亦會搶走 pointer stream。
- 統一 Pointer Events，按下時 capture；橫向 wheel 累積門檻後切文，同一輪慣性只觸發一次，即使換咗文章 DOM。保留垂直捲動、觸控縮放及連結點擊。
- 瀏覽器真實輸入測試：文章 1 → 向左拖動 → 2 → 向右拖動 → 1；串頭向右接上一串 9/9，再向左返下一串 1/7；橫向 wheel 由 1/7 去 2/7。
- 自動測試：滑鼠、touch、取消、多點觸控、implicit capture 轉移、trackpad 慣性跨 DOM、垂直捲動／pinch 及 cleanup。手機真機仍待驗證；第三方 iframe 內嘅操作由平台接收，請從正文／空白位置 swipe。


## 2026-11-05 Facebook 連結點擊修正

- 「原來咁大」嘅 Facebook 分享連結重現無反應。修 swipe 時 pointerdown capture 到文章容器，令連結 click 被改派；改成連結／互動控制輕撳保留原生事件，橫向拖動先 capture。
- 開新頁使用同步 window.open；阻擋／失敗時 fallback 同頁導航，開出嘅視窗先移除 opener，再轉到原網址。保留修正鍵／中鍵原生行為及 swipe 後 ghost-click 阻擋。
- 測試時發現重載仍使用舊版 module；加入入口／相關 module 版本網址，靜態伺服器改為 Cache-Control: no-cache，之後本機修改會重新驗證。
- 修正後實際從該篇文章點擊，成功新開 Facebook，抵達要求登入嘅 Facebook 頁面。冇登入或輸入帳密。截圖 facebook-link-open-preview.jpg。
- 網頁原型驗證瀏覽器開啟；手機跳相應 app 仍需原生版真機驗證。


## 2026-11-05 Facebook 分享網址 embed

- 修正 `/share/p/…` 未建立 embed 嘅問題；增加 story.php canonicalization。
- 官方短網址 → story.php → posts permalink → oEmbed HTML 成功；JS／Python 覆蓋識別、原連結保留、轉址及未知網域／login／userinfo 拒絕。
- 瀏覽器實測仍顯示 Facebook frame refused to connect，無法驗證貼文內容成功呈現；官方直接 plugin 方式亦同樣失敗，未採用此替代方式。

## 2026-11-05 真實 MIME 圖片

- 「呢件蒙古妹做乜撚野」原文 808515 係 multipart/mixed，含純文字及三個 base64 image/jpeg 附件；實際解碼分別 39,059／38,569／59,828 bytes。
- 真實瀏覽器三張圖片均 complete=true、naturalWidth=1080，高度分別 797／808／1435，唔係示例圖片或假 placeholder。
- 重載頁面再快速進入文章，三張仍全部載入。修正咗 header refresh 同文章 fetch 同時進行時，結果被寫入舊 message object 嘅競態；依 Message-ID 更新現有 cache。
- 舊文字快取升級、圖片不寫 localStorage／重開補取、Big5 文字及 MIME 圖片、原始 bytes／次序、image-only、WebP octet-stream、拒絕 SVG／偽裝 HTML、單張及總容量限制均有自動測試。
- 未加入圖片全屏檢視；仍未支援 uuencode／yEnc。

## 2026-11-05 真實 POST／Reply

- 真實 server 專用 test.test 原本空白；只公開發出一篇「yrNewsEx 功能測試（請忽略）2026-11-05」及其一篇回覆，使用 yrNewsEx 測試／yrnewsex-test@example.invalid，冇用使用者私人身份。新帖含一張程式產生嘅 16×16 PNG 測試圖。
- 兩次都收到 server 240。新帖 Big5 中文＋圖片重新讀取成功；回覆包含 emoji 自動改 UTF-8，References 指向新帖，原文引用同 emoji 重新讀取均正確。
- UI test.test Refresh 載入兩篇，顯示 2/2 未讀及一層真實父子關係；截圖 live-send-reply-preview.jpg。UI 開回覆、Reply 會取得原文並預填兩篇引用；Name／Email 未填時 Send disabled，填有效公開身份後 enabled。該 UI 草稿最後取消，冇額外發出第三篇。
- Helper 重開後，以原 Message-ID／原 payload 重試只確認既有文章；群組篇數仍 2，冇重複發文。
- 自動測試覆蓋四篇父訊息／不引用兄弟／不插入可見 cache、Big5／UTF-8／三圖 MIME round-trip、header injection／超額圖片拒絕、Origin guard、正常收據去重、結果不確定時只查詢而唔再 POST、helper 重開後 STAT 去重。
- Live Send 成功分支唔新增可見 thread／message，只清草稿保存身份及待 Refresh 嘅 Message-ID；手動 Refresh 跟原本 mergeHeaders 以未讀加入。

## 2026-11-05 Send disabled 原因提示

- 使用者現有 test.test 草稿 Name 已填，Email 欄位非空但瀏覽器格式驗證不通過，Send 因身份驗證而停用；冇修改該身份／正文，冇發文。
- composer 加入即時原因及 Email aria-invalid／aria-describedby；Name、Email、Subject、正文、加相中／發送中各有提示，資料有效後原因清空及啟用 Send。
- UI 在原草稿驗證 Email 格式提示、aria-invalid=true、Send disabled。僅截取提示區，冇將身份或正文放入驗證截圖。草稿保留。

## 2026-11-05 duplicate／拍照入口

- 唯讀檢查 test.test，當時只見先前兩篇測試文，未見使用者帶相回覆；冇重新發送使用者草稿或附件。
- 修正 duplicate 分類：收到 441/435 Duplicate 後必須重新讀取並比較 From／群組／主題／References／純文字／每張附件 bytes；相符先當成功，STAT/ARTICLE 430 唔當成功。保留 duplicate receipt，重試先查詢，唔反覆 POST 同一 ID。
- 前端按正文、身份、引用及附件嘅 SHA-256 版本決定 Message-ID：相同內容重試保持 ID，改文字／加相則換 ID。明確 duplicate 未核實時保留草稿及記憶體附件，提供「用新識別碼再試」；按此按鈕只準備新 ID，唔會自動發文。
- 自動測試覆蓋 history duplicate + unreadable、duplicate 後文章遲來可讀、相同 ID 但附件不同不當成功、內容改變 ID 更新、明確換 ID 不改草稿；實際唯讀比對既有兩篇（含測試圖）均匹配。
- Attach Photo 同時有 Take a New Photo／Choose Existing；camera input 為 image/*、capture=environment，沿用相同照片讀取／格式／5 MB／三張上限。瀏覽器實測選單及 input 屬性；未觸發實體相機，手機真機待驗證。桌面瀏覽器可能仍然提供檔案選擇器。
- 舊版未發圖片只喺原頁記憶體，更新重載後需要重新附加；文字草稿保存。測試未改用戶草稿或發出內容。

## 2026-11-05 附件放喺 history 前

- Composer 分成新內容 textarea、附件縮圖、可編輯 history textarea；兩個文字區合併保存，冇刪除引用。實際 Reply DOM 順序為 body → attachments → history。
- NNTP MIME 次序改為新文字 → 圖片附件 → 引用文字；decoder 回 contentParts、contentVersion 3，讀文保留圖片位置；舊版文字＋尾部圖片亦會將圖顯示喺 history 之前。
- 新增 MIME round-trip 與前端次序／引用 header 不分離測試；duplicate signature 唔會因純文字分成兩個 MIME part 而誤報內容不同。發文 payload 加 layoutVersion，按內容版本產生 ID。
- 示範頁 tests/fixtures/attachment-history.html 使用內置示範圖片，確認新文字、圖片、history 垂直位置遞增；截圖 attachment-before-history-preview.jpg。此輪冇發出 NNTP 新文。

## 2026-11-05 還原單一回覆編輯框

- 按使用者回饋移除獨立 history textarea 及其高度／resize／scrollbar 樣式；正文連同完整 history 共用原本 #body，直接保存原字串，唔拆開或重新合併。
- UI 在既有回覆草稿驗證 textareaCount=1、separateHistory=false、historyInBody=true、scrollbarWidth=none。冇修改或發送該草稿。
- 發文 MIME／讀文嘅新內容 → 附件 → history 次序保留，相關 JS／Python round-trip 測試通過。


## 2026-11-05 新操作片及 Server／Groups／500 篇下載

- 已讀使用者新片（205.785s），每 3s 抽幀，檢視五張 contact sheets 及關鍵大圖，記錄新表單／搜尋打剔／Next-Newest alert 流程；見 SERVER_GROUPS_AND_DOWNLOADS.md。
- 真實新增 Name=yrNewsEx UI Test、公開代用 email 嘅臨時 server，連線測試成功。Subscribe 搜尋 general、多選、Done 返回設定再 Done；Groups 編輯取消訂閱成功，重新訂閱後 3,101 篇 cache 保留。
- 實際 general.chat 初次提示當時 3,100 篇；Cancel 後仍 0 unread。Next 500 成功 → 再次提示 2,601 新篇；More=1500 正確更新按鈕；Latest 500 後 cache 1,000。Get Older 顯示 2,101 舊篇，All 分五批完成後 3,101 unread。期間 server 有新文，所以每個提示以當時 snapshot 為準。
- 原文章已讀／收藏以既有 merge 邏輯保存；新增未讀。新訊息計數使用 LISTGROUP，實際 CLI 計數與編號數量一致；headers endpoint 返回 500，全部屬所選編號。
- Composer DOM Name=0、Email=0，填主題／正文後 Send enabled，使用所屬 server profile，未公開發出測試訊息。
- 臨時測試草稿取消。刪除臨時 server 首次被自動審批拒絕，使用者明確授權後只刪除該測試 server／cache，確認原有兩個 server 保留。
- 額外以原先未訂閱嘅 club.arsenal 驗證下載 dialog 置中於 phone 內（中心差 0）；Cancel 不下載 headers，再取消臨時訂閱，恢復原選擇。
- Socket 範圍、DNS/IP 固定、防私人地址、TLS 選擇、無 netrc、精確 headers 範圍、500/501 邊界、Next cursor／Latest gaps／More／All、去重／過期編號均有回歸測試。現有 60 個 JS＋35 個 Python 測試通過。
- 目前公開不需登入 NNTP 可用；登入 server 尚未接通。
