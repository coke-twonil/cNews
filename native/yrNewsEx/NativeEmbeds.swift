import SwiftUI
import WebKit
import LinkPresentation

struct NativeMessageBody: View {
    var bodyText: String
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(mediaPieces(bodyText)) { piece in
                if let text = piece.text { Text(text).font(.system(size: 17)).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading) }
                if let url = piece.link {
                    Button { ExternalLinkOpener.open(url) } label: { Text(url.absoluteString).font(.system(size: 17)).multilineTextAlignment(.leading).foregroundStyle(.blue) }.buttonStyle(.plain)
                }
                if let item = piece.embed { NativeEmbedCard(item: item).padding(.vertical, 12) }
            }
        }
    }
}
struct NativeEmbedCard: View {
    let item: EmbedItem
    @State private var markup: String?
    @State private var error: String?
    @State private var height: CGFloat = 350
    @State private var ready = false
    @State private var previewHeight: CGFloat = 180
    @State private var attempt = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if item.provider == "preview" { NativeLinkPreview(url: item.original, height: $previewHeight).frame(height: previewHeight).clipped() }
            else {
                if let markup { EmbedWebView(markup: markup, height: $height, ready: $ready, error: $error).frame(height: height).id(attempt) }
                if !ready && error == nil { ProgressView("\(item.label) · 載入中…").font(.footnote) }
                if let error {
                    if item.provider == "facebook" { NativeLinkPreview(url: item.original, height: $previewHeight).frame(height: previewHeight).clipped() }
                    Text("\(item.label)：\(error)").font(.footnote).foregroundStyle(.secondary)
                    Button("重試") { markup = nil; self.error = nil; ready = false; attempt += 1 }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .task(id: attempt) {
                guard item.provider != "preview", markup == nil else { return }
                self.error = nil
                do { markup = try await EmbedLoader.html(item) }
                catch is CancellationError { return }
                catch let failure as URLError where failure.code == .cancelled { return }
                catch { self.error = "平台暫未提供此貼文嘅內嵌內容，可點上面原連結開啟。" }
            }
    }
}
private final class ProviderRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum EmbedLoader {
    static func escaped(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
    static func canonical(_ item: EmbedItem) async throws -> URL {
        guard item.url.path.hasPrefix("/share/") else { return item.url }
        let session = URLSession(configuration: .ephemeral, delegate: ProviderRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var url = item.url
        for _ in 0..<4 {
            var request = URLRequest(url: url); request.httpMethod = "HEAD"; request.timeoutInterval = 8
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (300...399).contains(response.statusCode), let location = response.value(forHTTPHeaderField: "Location"), let next = URL(string: location, relativeTo: url)?.absoluteURL, let parsed = EmbedItem.parse(next), parsed.provider == item.provider else { throw NewsError.failure("分享連結未能解析") }
            url = parsed.url
            if !url.path.hasPrefix("/share/") { return url }
        }
        throw NewsError.failure("分享連結重導過多")
    }
    static func html(_ item: EmbedItem) async throws -> String {
        let url = try await canonical(item)
        if item.provider == "x" {
            let id = url.lastPathComponent
            guard id.allSatisfy(\.isNumber) else { throw NewsError.failure("X post ID 無效") }
            return document("<div id=\"xpost\"></div><script src=\"https://platform.twitter.com/widgets.js\" charset=\"utf-8\" onload=\"twttr.widgets.createTweet('\(id)',document.getElementById('xpost'),{theme:'dark',dnt:true}).then(function(e){if(!e)window.webkit.messageHandlers.layout.postMessage({failed:true});});\"></script>")
        }
        if ["youtube","vimeo","spotify","tiktok"].contains(item.provider) {
            let height = ["youtube":230,"vimeo":230,"spotify":352,"tiktok":580][item.provider] ?? 350
            return document("<iframe src=\"\(escaped(url.absoluteString))\" width=\"100%\" height=\"\(height)\" frameborder=\"0\" allow=\"fullscreen; encrypted-media; picture-in-picture\" referrerpolicy=\"strict-origin-when-cross-origin\" allowfullscreen></iframe>")
        }
        let endpoint: String
        switch item.provider {
        case "instagram": endpoint = "https://graph.facebook.com/v25.0/instagram_oembed"
        case "threads": endpoint = "https://graph.threads.com/oembed"
        case "facebook": endpoint = "https://graph.facebook.com/v25.0/" + (url.path.contains("/reel/") ? "oembed_video" : "oembed_post")
        case "x": endpoint = "https://publish.x.com/oembed"
        default: throw NewsError.failure("未支援平台")
        }
        var components = URLComponents(string: endpoint)!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "maxwidth", value: "500"), URLQueryItem(name: "dnt", value: "true"), URLQueryItem(name: "theme", value: "dark")]
        var request = URLRequest(url: components.url!); request.timeoutInterval = 15
        let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count <= 1024*1024,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let html = json["html"] as? String, !html.isEmpty else { throw NewsError.failure("平台無法提供 embed") }
        return document(html)
    }
    static func document(_ html: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="strict-origin-when-cross-origin"><style>html,body{padding:0;margin:0;background:#000;color:#aaa;font-family:-apple-system;width:100%;overflow:hidden}#embed{width:100%;display:flow-root}iframe,blockquote{max-width:100%!important;margin-left:0!important;margin-right:0!important}a{color:#0a84ff}</style></head><body><div id="embed">\(html)</div><script>
        let sent=false;
        function layout(){const e=document.getElementById('embed');const ready=!!e.querySelector('iframe');window.webkit.messageHandlers.layout.postMessage({height:Math.ceil(e.getBoundingClientRect().height),ready:ready});if(ready)sent=true;}
        new ResizeObserver(layout).observe(document.getElementById('embed'));
        new MutationObserver(layout).observe(document.getElementById('embed'),{subtree:true,childList:true,attributes:true});
        window.addEventListener('load',layout);setTimeout(layout,1500);setTimeout(()=>{if(!sent)window.webkit.messageHandlers.layout.postMessage({failed:true});},20000);
        </script></body></html>
        """
    }
}
struct EmbedWebView: UIViewRepresentable {
    var markup: String
    @Binding var height: CGFloat
    @Binding var ready: Bool
    @Binding var error: String?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(context.coordinator, name: "layout")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false; view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        view.loadHTMLString(markup, baseURL: URL(string: "https://yrnewsex.invalid/"))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.configuration.userContentController.removeScriptMessageHandler(forName: "layout"); view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: EmbedWebView
        init(_ parent: EmbedWebView) { self.parent = parent }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let data = message.body as? [String: Any] else { return }
            if let height = data["height"] as? Double, height.isFinite { parent.height = max(120, min(2400, height)) }
            if data["ready"] as? Bool == true { parent.ready = true; parent.error = nil }
            if data["failed"] as? Bool == true && !parent.ready { parent.error = "未能載入內容，可點上面原連結開啟。" }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                ExternalLinkOpener.open(url); decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.error = "載入失敗，可點上面原連結開啟。" }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.error = "載入失敗，可點上面原連結開啟。" }
    }
}
struct NativeLinkPreview: UIViewRepresentable {
    var url: URL
    @Binding var height: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }
    func makeUIView(context: Context) -> LPLinkView {
        let view = LPLinkView(url: url)
        view.clipsToBounds = true
        let provider = LPMetadataProvider(); provider.timeout = 12
        context.coordinator.provider = provider
        provider.startFetchingMetadata(for: url) { [weak view] metadata, _ in
            DispatchQueue.main.async {
                if let metadata, let view {
                    view.metadata = metadata
                    view.layoutIfNeeded()
                    let size = view.sizeThatFits(CGSize(width: max(220, view.bounds.width), height: .greatestFiniteMagnitude))
                    context.coordinator.height.wrappedValue = max(80, min(650, size.height))
                }
            }
        }
        return view
    }
    func updateUIView(_ view: LPLinkView, context: Context) {}
    static func dismantleUIView(_ view: LPLinkView, coordinator: Coordinator) { coordinator.provider?.cancel() }
    final class Coordinator {
        var provider: LPMetadataProvider?
        var height: Binding<CGFloat>
        init(height: Binding<CGFloat>) { self.height = height }
    }
}
