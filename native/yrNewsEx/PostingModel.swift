import Foundation
import CryptoKit

func replyTextSections(_ text: String) -> (own: String, history: String) {
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    let start = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") } ?? lines.count
    return (lines[..<start].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), lines[start...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
}
func postingFingerprint(text: String, photos: [ReplyPhoto], name: String, email: String, subject: String, refs: [String]) -> String {
    let data = try! JSONEncoder().encode([text, name, email, subject, refs.joined(separator: " ")] + photos.map { $0.mime + ":" + SHA256.hash(data: $0.data).description })
    return SHA256.hash(data: data).description
}
func buildReply(draft: ReplyDraft, server: NewsServer, group: String, subject: String, refs: [String]) throws -> Data {
    guard validGroup(group), !server.name.trimmingCharacters(in: .whitespaces).isEmpty,
          server.email.range(of: "\\A[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\\z", options: .regularExpression) != nil,
          server.name.rangeOfCharacter(from: .newlines) == nil, subject.rangeOfCharacter(from: .newlines) == nil,
          refs.allSatisfy({ messageIDs($0) == [$0] }), draft.photos.count <= 3 else { throw NewsError.failure("請檢查 server Name／Email、回覆資料及最多三張相片") }
    let sections = replyTextSections(draft.text)
    guard !sections.own.isEmpty || !draft.photos.isEmpty else { throw NewsError.failure("請輸入新內容或加相") }
    func encodedWords(_ text: String) -> String {
        var chunks: [String] = [], chunk = ""
        for character in text { if (chunk + String(character)).utf8.count > 42 { chunks.append(chunk); chunk = "" }; chunk.append(character) }
        if !chunk.isEmpty { chunks.append(chunk) }
        return chunks.map { "=?UTF-8?B?\(Data($0.utf8).base64EncodedString())?=" }.joined(separator: "\r\n ")
    }
    func base64(_ data: Data) -> String {
        let text = data.base64EncodedString()
        return stride(from: 0, to: text.count, by: 76).map { offset in
            let start = text.index(text.startIndex, offsetBy: offset), end = text.index(start, offsetBy: min(76, text.count-offset))
            return String(text[start..<end])
        }.joined(separator: "\r\n")
    }
    let boundary = "yrnewsex_" + draft.id
    let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.timeZone = TimeZone(secondsFromGMT: 0); date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    var lines = ["From: \(encodedWords(server.name)) <\(server.email)>", "Newsgroups: \(group)", "Subject: \(encodedWords(subject))", "Date: \(date.string(from: Date()))", "Message-ID: \(draft.messageID)", "User-Agent: yrNewsEx/0.1", "MIME-Version: 1.0"]
    if !refs.isEmpty { lines += ["References: " + refs.joined(separator: "\r\n "), "In-Reply-To: " + refs.last!] }
    lines += ["Content-Type: multipart/mixed; boundary=\"\(boundary)\"", ""]
    func appendText(_ text: String) { lines += ["--"+boundary, "Content-Type: text/plain; charset=utf-8", "Content-Transfer-Encoding: base64", "", base64(Data(text.utf8))] }
    appendText(sections.own)
    for (index, photo) in draft.photos.enumerated() {
        guard photo.data.count <= 5*1024*1024 else { throw NewsError.failure("每張相最多 5 MB") }
        let isJPEG = photo.data.starts(with: [0xff,0xd8,0xff]), isPNG = photo.data.starts(with: [137,80,78,71,13,10,26,10])
        guard (photo.mime == "image/jpeg" && isJPEG) || (photo.mime == "image/png" && isPNG) else { throw NewsError.failure("附件格式無效") }
        let ext = isPNG ? "png" : "jpg"
        lines += ["--"+boundary, "Content-Type: \(photo.mime)", "Content-Disposition: attachment; filename=\"photo-\(index+1).\(ext)\"", "Content-Transfer-Encoding: base64", "", base64(photo.data)]
    }
    if !sections.history.isEmpty { appendText(sections.history) }
    lines += ["--"+boundary+"--", ""]
    return Data(lines.joined(separator: "\r\n").utf8)
}
func articleHeaders(_ raw: Data) -> [String: String] {
    let text = latin(raw).replacingOccurrences(of: "\r\n", with: "\n")
    let head = text.components(separatedBy: "\n\n")[0].replacingOccurrences(of: "\n[ \\t]+", with: " ", options: .regularExpression)
    var headers: [String: String] = [:]
    for line in head.components(separatedBy: "\n") {
        if let colon = line.firstIndex(of: ":") { headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces) }
    }
    return headers
}
func matchingArticle(_ actual: Data, _ expected: Data) throws -> Bool {
    let a = articleHeaders(actual), b = articleHeaders(expected)
    for key in ["from", "newsgroups", "subject", "references", "in-reply-to", "message-id"] {
        if decodeWords(a[key] ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ") != decodeWords(b[key] ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ") { return false }
    }
    let left = try decodeArticle(actual), right = try decodeArticle(expected)
    return left.body.trimmingCharacters(in: .whitespacesAndNewlines) == right.body.trimmingCharacters(in: .whitespacesAndNewlines) && left.images == right.images
}
