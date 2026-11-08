# cNews — 操作原型 01

目標：提供操作順暢嘅 iOS newsgroup reader。先分析使用者錄屏，再做可操作原型，之後接原生 iPhone／NNTP。

## 試用

喺專案根目錄執行（Python 3，無須安裝套件）：

```sh
python3 -B scripts/serve.py
```

開啟 <http://127.0.0.1:8765/prototype/>。唔好用 file://，ES modules 需要經 HTTP 載入。

Groups → general.chat → 按右邊分數展開多層回覆 → 開文章 → 底部切換／Reply。向左 swipe 讀下一篇，串尾接下一串第一篇；向右反向讀，串頭接上一串最後一篇。左右按鍵／鍵盤亦用同一規則。右下角有原片同款群組選單；Demo 嘅 Send 加到本機示例；Live 嘅 Send 會公開發到 NNTP server。

相片附件每篇最多 3 張；超額選取只加入剩餘位置，移除後可補返。相機按鍵會喺加滿時停用，Send 亦會檢查上限。

原型保留設定、訂閱、文章、已讀、收藏及文字草稿喺瀏覽器 localStorage。自行選取嘅附件只保留喺頁面記憶體，重載後會消失；示範圖片可保留。原片／抽幀只供本機對照，已加入 `.gitignore`，唔應推上公開 repo。

討論串列表向右 swipe（桌面可拖動）展開；喺已展開 thread 嘅原文或任何回覆向左 swipe，收起整串。呢個列表手勢唔會開文章或標記已讀。

Reply 會引用正被回覆嗰篇及沿父節點向上嘅三篇（最多四篇），保留巢狀引文；唔引用其他分支，亦唔直接複製舊 quote 而重複祖先。

Send 保存後返回原有列表，暫時唔加入新回覆或改變文章數量。撳 Refresh 先載入自己同其他新訊息，全部用未讀樣式顯示，冇藍色背景。保存失敗保留草稿；未刷新的新回覆亦唔會被之後嘅草稿／已讀儲存覆蓋。Demo 使用本機文章庫；Live 會向真實 NNTP server 發送。

## 文件

- [功能規格及錄屏時間碼](docs/FUNCTIONAL_SPEC.md)
- [驗證結果及已知差異](docs/VALIDATION.md)
- [支援平台、內嵌顯示及本機啟動](docs/EMBEDS.md)
- [新增 server／訂閱群組／500 篇下載選擇及新片時間碼](docs/SERVER_GROUPS_AND_DOWNLOADS.md)
- `scripts/extract-video.swift`：用 macOS AVFoundation 抽幀；輸出影格同 contact sheets。受 sandbox 限制時需要批准本機解碼。

## 檢查

Node 22 或更新：

```sh
node --check prototype/app.js
node --test tests/*.test.mjs
python3 -B -m unittest discover -s tests -p 'test_*.py'
```

無須安裝套件。普通文章由本機供應；含內嵌網址嘅文章會按捲動位置載入相應平台嘅官方內容，唔傳送整篇 message。唔需要提供帳密或 API key。

文章正文同引用內網址可點擊；支援嘅 IG、X、Threads、Facebook、YouTube、TikTok、Vimeo、Spotify 內容會先喺 body 內嵌，原連結一直保留。未知／失敗內容可點連結開原站。普通連結用新頁開啟；原生開啟元件喺 `native/ExternalLinkOpener.swift`，按 Universal Links 優先開已安裝 app，再交系統預設瀏覽器。手機跳 app 要喺原生版真機驗證。

## 現階段界線

呢個係操作同視覺驗證原型，未係可安裝嘅 iOS app。已接通 NNTP 閱讀、POST 同文字編碼轉換；Demo 設定頁嘅 Big5 選項仍只儲存設定，Live 依文章 charset 解碼。未建立 GitHub repo，未選定 license，未發佈。現機已安裝 Xcode 27.2／iOS 27.2 Simulator；`native/cNews.xcodeproj` 已支援原生 NNTP 真實閱讀、目錄及批次下載（發文仍未移植），詳見 [原生進度](native/README.md)。

下一階段係按原型回饋校準視覺同手勢，再用 SwiftUI 建立原生專案，延續已接通嘅 NNTP 閱讀／發文／回覆，完善圖片檢視同真機體驗。唔需要將密碼交畀開發者。

## 真實 NNTP 試用（2026-11-05）

Groups 右上角「＋」→ 填 Server、Port、Name、Email、Encoding → 完成。點 server 標題進設定 → Subscribe Group → 搜尋、打剔 → 完成 → 再完成返回 Groups。取消訂閱可取消打剔，或 Groups → 編輯 → 移除該 group；本機快取及已讀會保留，方便重新訂閱。

每次進 group／Refresh 先用 LISTGROUP 取真實文章編號，按手機已下載最新編號計新文數。超過 500 篇先彈總數及數量／範圍選單：500、1,000、2,000、更多自訂、All；Next 由本機最新已下載文章之後向新順序取，Latest 取 server 最新一批。揀 Latest 跳過嘅舊文可以 Get Older Messages 下載，唔會混入 Next。All 會分成每批最多 500 headers 下載，逐批儲存及顯示進度；取消選單唔下載 headers。已讀／收藏／閱讀位置會保留，新下載文章全未讀。

Live server 個標題可載入真實群組目錄並切換訂閱。可新增公開 NNTP server；119 用普通 NNTP，563 用驗證憑證嘅 TLS，暫未支援登入；本機 NNTP helper 喺 `127.0.0.1:8767`。瀏覽器唔可以直接講 TCP NNTP，所以由 Python 3.9–3.12 標準庫 `nntplib` 橋接（Python 3.13 已移除此模組）。`scripts/serve.py` 一次開齊 UI、embed 同 NNTP helper。只容許本機 reader origin；連線按所選 server 設定，拒絕本機／私人網絡目的地，DNS 解析後固定連去已驗證嘅公開 IP；唔接受跨群組發文。

支援 RFC 2047 header、UTF-8／Big5／CP950 純文字正文、MIME transfer decoding。Live 已支援 MIME JPEG／PNG／GIF／WebP 圖片附件；暫未支援 HTML-only 正文；真實 Send／Reply 已啟用。示例模式嘅 Send 行為維持本機測試。

圖片附件只喺本次頁面記憶體保存，唔寫入 localStorage；重開文章會按需重新下載缺失圖片，已讀／收藏不變。舊版只讀文字嘅快取亦會自動重取。每張解碼後最多 10 MB，每篇合共 20 MB；超額／不支援格式會顯示提示，唔靜默漏相。呢個閱讀上限同發文最多 3 張相係兩回事。


## 真實 Send／Reply（2026-11-05）

Live → test.test → New Message，或者開文章再 Reply。Name／Email 喺 server 設定一次（會公開顯示），打 message 唔再重填；Send 用該 server 嘅身份真實 POST。建議先用 test.test 試操作。

Reply 預先讀取最多四篇父訊息正文，包含冇喺目前 header cache 入面嘅父節點；用正確 References／In-Reply-To 接返原 thread。圖片最多三張，每張 5 MB。Big5 文字以 MIME 傳輸；包含 Big5 冇嘅字／emoji 時自動轉 UTF-8。

Server 回 240 接受先顯示 Sent；返到發送前嘅 thread 清單，按 Refresh 先見新訊息（未讀樣式）。失敗保留草稿。每份草稿用固定 Message-ID；同一發送重試會查收錄狀態／去重，連線結果未確認時唔自動重發。相片草稿仍只喺頁面記憶體，重載會失去未發附件。

Attach Photo 有 Take a New Photo（手機系統相機入口）同 Choose Existing；桌面通常仍會用檔案選擇器，手機相機有待真機驗證。兩者合計最多三張。

如果 server 回 duplicate，helper 會核實可讀文章同附件是否完全相同；未能確認時保留草稿並提供「用新識別碼再試」。此按鈕只準備新 ID，之後由你再撳 Send 發佈。改正文／加相會自動為新版本建立新 Message-ID，相同內容重試則維持 ID。更新重載前請留意：舊版未發附件只留喺頁面記憶體，重載後要重新揀相。

回覆附件次序為新內容 → 相片 → history。編輯畫面正文同 history 共用原本同一個編輯框；發文 MIME 及讀回內容會將相片放喺 history 前；舊式尾部附件亦會顯示喺引用之前。
