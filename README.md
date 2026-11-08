# cNews

cNews 係一個 iOS newsgroup reader。

## 原生 iPhone app

用 Xcode 開啟 [`native/cNews.xcodeproj`](native/cNews.xcodeproj)，選 **cNews** scheme 及 iPhone Simulator，再按 Run。最低 iOS 17，目前已在 iOS 27.2 Simulator 驗證。模擬器唔需要付費 Apple Developer 會籍；真機簽名請使用自己嘅開發帳戶及 bundle identifier。

現有功能：

- 直接連線 NNTP：119 普通 TCP、563 TLS；載入群組目錄及訂閱／取消訂閱。
- References／Message-ID 多層 thread，支援展開／收起及跨 thread 逐篇閱讀。
- 黑底、平面藍色按鈕；左邊緣右 swipe 返回上一頁，中間 swipe 控制文章／thread。
- 新訊息只按 Refresh 下載；超過 500 篇可揀數量、Next／Latest 或 All，分批儲存。
- UTF-8／Big5 文字、MIME 圖片及本機快取／已讀狀態。
- IG、X、YouTube 等內容內嵌；不支援／受平台限制內容保留原連結或預覽。
- 新主題及回覆，相片最多三張、四代父鏈引用、草稿／附件保存及重試查核；發送後手動 Refresh 先顯示新文章。
- 按 sender IP 封鎖、收藏、搜尋及 group 拖動排序。

帳密登入、完整相機真機驗收、圖片放大及容量管理等仍待完善。詳細功能、驗證及限制見 [`native/README.md`](native/README.md)。

## 操作 prototype

保留網頁版作互動對照：

```sh
python3 -B scripts/serve.py
```

打開 <http://127.0.0.1:8765/prototype/>。NNTP helper 需要 Python 3.9–3.12（Python 3.13 已移除標準庫 nntplib）。原生 app 唔依賴呢個 helper。詳見 [prototype 指南](docs/PROTOTYPE_GUIDE.md)。

## 測試

網頁／helper：Node.js 22 或更新、Python 3.9–3.12，無第三方套件。

```sh
node --check prototype/app.js
node --test tests/*.test.mjs
python3 -B -m unittest discover -s tests -p 'test_*.py'
```

原生模型、NNTP、embed 及相片回覆測試指令見 [原生測試說明](native/README.md)。本機 fixture 測試唔會向公開 server 發文；Live Send 會真實公開發佈，測試請用 test.test。

## 文件與原始資料

- [功能規格](docs/FUNCTIONAL_SPEC.md)
- [server／訂閱與下載行為](docs/SERVER_GROUPS_AND_DOWNLOADS.md)
- [驗證記錄](docs/VALIDATION.md)
- [embed 說明](docs/EMBEDS.md)

原始錄屏、私人分享連結、抽幀、測試截圖、帳密及本機文章快取唔隨 repo 發佈。文件中部分本機截圖路徑只作驗證記錄，公開 repo 唔包含該等圖片。

## 授權

程式碼公開；正式開源授權條款尚待選定。
