# 真機試用

目前係開發簽名測試版本，未經 App Store／TestFlight 發佈。

## 安裝準備

1. 用支援資料傳輸嘅 USB 線直接接 Mac，解鎖 iPhone，按系統提示確認信任呢部 Mac。Finder 同 Xcode 必須真係見到可連線嘅實體裝置。
2. Xcode → Settings → Apple Accounts 登入自己的 Apple Account，選 Personal Team。建立簽名資產前由帳戶擁有人確認授權。
3. 個人 Team ID／bundle identifier 放入已忽略嘅 `LocalSigning.xcconfig`；共用範例係 `LocalSigning.example.xcconfig`。唔提交憑證、私鑰、profile 或個人設定。
4. 在 iPhone 設定 → 私隱與安全性 → 開發者模式開啟，按系統提示重啟及確認。呢步容許執行開發簽名 app，由手機擁有人親自完成。
5. Xcode 選實體 iPhone 作 Run destination，建立 provisioning profile、簽署及安裝。如果 iOS 顯示未信任開發者，到設定 → 一般 → VPN 與裝置管理，確認是自己的開發者身份後按信任／允許，再開 app。

Apple 文件：[開發者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)、[在裝置執行 app](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html)。

## 試用順序

- **閱讀**：Groups 揀 `news.twonil.hk · Live` 下面嘅 general.chat。手機同模擬器資料獨立；首次進 group 冇文章屬正常，手動按 Refresh 先下載。
- **下載**：超過 500 篇時確認總數；Latest 取最新一批，Next 從本機最新已下載編號之後向新取。入 group 唔自動刷新，冇 Get Older Messages。
- **列表**：左右 swipe 都切換 thread 展開／收起；子回覆保留縮排但冇 L 線；上下捲動唔誤開文章。所有訊息背景保持黑色。
- **閱讀手勢**：中間左／右 swipe 下一篇／上一篇，串尾／串頭跨 thread；由左邊緣右 swipe 返回 thread 清單，再由清單左邊緣右 swipe 返回 Groups。文章頂部冇篇數顯示。
- **圖片／embed**：打開已知有相片或社交網址嘅文章，確認圖片比例、IG／X／YouTube 內容及失敗時嘅原連結／預覽；播放、跳去已安裝 app 同預設瀏覽器要喺真機逐項驗收。
- **回覆**：建議先用 test.test 試新 post／回覆。先在 server 層設定 Name／Email；Send 會公開該身份、文字同附件，請用測試內容。最多三張相，Choose Existing／Take a New Photo 合計計數；相機由用戶按 iOS 提示授權。
- **引用／發送**：單一編輯框保留最多四代父鏈 history；發出後次序為新文字 → 相片 → history。成功返回發送前列表，手動 Refresh 先以未讀加入。
- **Refresh 數字**：底部係最近一次 Refresh 新增篇數，閱讀／收藏／篩選後不變；再次 Refresh 無新文就顯示 0。
- **文章工具列**：左至右 Reply、上一篇、下一篇、上一條 thread 第一篇、下一條 thread 第一篇、操作選單。文章選單試收藏／取消收藏及 Mark Thread Read；列表選單試全部已讀、未讀／收藏篩選及按最新回覆排序。
- **搜尋**：撳搜尋欄後試 Subject／Sender／Message。Message 會連線載入本機文章未快取內文；唔係搜尋整個 server，也唔會下載新文。
- **Block**：長按列表一篇 message，或點內文 header 右側 Block icon，確認 username／email／sender IP。Block 後同 server 其他 groups 同 IP 及其子分支都隱藏；到 Server Settings → Blocked Users 核對身份及 Unblock，確認恢復。冇 sender IP 嘅文章唔可以 Block；第一次要等舊快取來源 headers 讀取完成。
- **刪除 server**：Server Settings 底部 Delete Server，先核對確認視窗列出嘅 server。Cancel 應保留資料；確認會移除該 server 及所有本機資料，無法還原，其他 servers 不受影響，亦不刪 NNTP server 上文章。
- **草稿**：用未發草稿測試文字／附件重開後保存，失敗唔丟內容；「用新識別碼再試」唔會自動發文。

## 簽名期限

開發版以實際 provisioning profile 到期日為準；到期後需重新簽署安裝。更新時保留同一 bundle identifier，可更新既有 app；唔好為排錯先刪 app，避免丟失本機快取／草稿。

2026-11-06 已在 iPhone 18 Pro／iOS 27.0.1 完成真機簽名驗證、安裝及成功啟動。呢個結果唔代表上面所有真機功能已驗收；相機、觸感、外部 app 跳轉等仍由實際試用回饋確認。
