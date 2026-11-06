# 正文內嵌內容

2026-11-05。呢份文件記錄瀏覽器原型已實作嘅範圍，唔代表原生 iPhone 已驗證。

## 顯示規則

正文同引用內嘅支援網址會保留原連結，下面直接載入官方貼文／播放器。同一篇文章重複引用同一個內容只建立一個 embed，但每條原連結仍可點。未知平台、首頁、未支援嘅分享短網址只保留普通連結。

| 平台 | 本輪支援 | 載入方式 |
| --- | --- | --- |
| Instagram | `/p/`、`/reel/`、`/reels/` | 官方 oEmbed + 官方載入程式 |
| X／Twitter | `/{user}/status/{id}` 及 ID 形式識別 | 官方 oEmbed + widgets；保留作者路徑，部分無作者 URL 可能需後備連結 |
| Threads | 新舊域名、`/@user/post/`、`/t/` | 官方 oEmbed + 官方載入程式 |
| Facebook | `/{user}/posts/`、`/reel/` | 官方 post／video oEmbed |
| YouTube | watch、youtu.be、Shorts、live、embed | 官方 iframe；保留時間戳 |
| TikTok | `@user/video/id`、`@user/photo/id` | 官方 Embed Player |
| Vimeo | 數字 video ID，保留 unlisted hash | 官方播放器 |
| Spotify | track、album、playlist、episode、show、artist | 官方 iframe |

只喺捲到附近時載入，換文章會移除舊 observer、訊息接收器及 timeout。唔會先開外部 app；如想睇原站，可以隨時點原連結。

載入錯誤／逾時會顯示可重試提示，原連結仍可用。私人、刪除、禁止嵌入、登入要求、地區限制及平台故障仍可能令內容不能觀看。iframe 載入成功只代表播放器／貼文框已建立，唔保證平台一定容許播放；平台本身亦可能喺框內顯示限制訊息。

## 本機啟動

```sh
python3 -B scripts/serve.py
```

- `127.0.0.1:8765`：reader，同原有預覽地址。
- `127.0.0.1:8766`：獨立 embed origin，唔提供 reader 原始碼、草稿或文章庫。
- 如果原有 8765 靜態預覽已經開緊，只啟動 `python3 -B scripts/embed_server.py` 即可。本輪 live 驗證就係呢個方式。

父頁只交付對應平台嘅內容 URL，唔傳整篇 message 或其餘引用。嵌入服務只請求固定平台 API，唔按用戶網址任意抓取網站。官方 HTML 會移除 inline script、事件屬性、未知載入程式及不允許嘅 iframe。HTML 放喺另一 origin 嘅 sandbox iframe，無法讀取 reader 嘅 localStorage。

iframe 回報只接受已知 origin、對應 frame window 同本次 token，僅處理高度及成功／失敗狀態；唔接受跳轉、寫入或其他程式指令。embed URL 唔寫 request log。公開嵌入 HTML 有最多 128 筆、5 分鐘記憶體快取；唔保存登入憑證。

## 驗證

- 34 項 JavaScript 測試 + 7 項 Python 測試，共 41 項通過。
- 實際讀到 IG 貼文內容、X Developers 貼文、Threads 貼文、YouTube 播放器、TikTok 播放器、Vimeo 播放器及 Facebook 公開貼文。
- Spotify 顯示真實封面／曲目，但此測試內容有地區播放限制；唔視為已驗證可播放。
- 無效 IG 貼文顯示後備提示及原連結，冇虛構貼文內容。
- 測試中修正 IG 官方 script 轉用 `platform.instagram.com`、X 轉用 `publish.x.com`／`platform.x.com`，以及 X oEmbed 需要保留有作者嘅 URL 路徑。
- 修正 iframe 展開時 reader 捲動錨點跳位；第三方播放器仍可能攔截其範圍內嘅手勢，原生版需用原生容器處理手勢協調。
- 已驗證顯示及播放器控制項，未逐一登入、留言、按讚或完整播放所有媒體。

## 原生版接續

用獨立、非持久 WKWebView 或同等隔離容器承載平台 embed；外部連結交 `ExternalLinkOpener`，唔將任意網頁 JS 接駁到有寫入權限嘅 app bridge。需喺 iPhone 驗證自動高度、捲動／左右 swipe、播放器、返回位置及 app／預設瀏覽器後備。

## 官方來源

- [Meta 官方嵌入實作及免 token 端點](https://github.com/meta/meta-embeds-for-wordpress)
- [X 嵌入貼文](https://help.x.com/en/using-x/how-to-embed-a-post)
- [YouTube 播放器](https://developers.google.com/youtube/player_parameters)
- [TikTok Embed Player](https://developers.tiktok.com/docs/en/embed-player)
- [Vimeo oEmbed](https://developer.vimeo.com/api/oembed/videos)
- [Spotify Embeds](https://developer.spotify.com/documentation/embeds)

2026-11-05：支援 Threads `/share/{code}` 分享短網址，由 helper 限定喺官方 Threads 網域內解析轉址，取得原帖後再用官方 oEmbed。原連結保留。真實文章「是日花生」嘅 `BAVHcta3-N` 可轉到 `DfUyW25Eroh`，但當時官方 oEmbed 回 HTTP 400／code 24（無法內嵌）；唔推斷貼文已刪除或私人，亦唔捏造內容。JS／Python 測試覆蓋分享網址及跨網域轉址阻擋。


2026-11-05：補齊 Facebook `/share/p/{code}` 同 `story.php?story_fbid=…&id=…`。分享短網址限定經 Facebook 官方 HEAD 轉址，正規化為作者／posts permalink 再查官方 oEmbed；原連結保留。實際「原來咁大」嘅分享連結可解析，官方亦回傳 embed HTML；但當前內置瀏覽器嘅官方 plugin frame 顯示 refused to connect。官方 SDK 及直接 plugin frame 均重現；保留原有 SDK 路徑，未聲稱該貼文已成功內嵌，亦未將原因歸為登入／私人貼文。
