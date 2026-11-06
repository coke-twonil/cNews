// Native URL routing for message links and embedded content.
// UIApplication handles installed apps and the user's default browser.
// https://developer.apple.com/documentation/uikit/uiapplication/openexternalurloptionskey/universallinksonly
#if canImport(UIKit)
import UIKit

@MainActor
enum ExternalLinkOpener {
    /// Tries the installed app registered for this URL, then normal system
    /// URL handling. Keep the original URL, including its path/query/fragment.
    /// Never use an embedded browser or guess third-party URL schemes.
    static func open(_ url: URL, completion: @escaping @Sendable (Bool) -> Void = { _ in }) {
        guard let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host != nil,
              url.user == nil, url.password == nil else {
            completion(false)
            return
        }
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
            Task { @MainActor in
                if opened {
                    completion(true)
                } else {
                    UIApplication.shared.open(url, options: [:], completionHandler: completion)
                }
            }
        }
    }
}
#endif
