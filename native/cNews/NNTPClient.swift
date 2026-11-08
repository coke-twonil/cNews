import Foundation
import Network
import CoreFoundation

enum NewsError: LocalizedError {
    case failure(String)
    var errorDescription: String? { if case .failure(let text) = self { return text }; return nil }
}

/// One connection per background operation; never runs on the main actor.
final class NNTPClient: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "org.cnews.nntp")
    private var buffer = Data()
    private var closed = false
    init(host: String, port: Int) throws {
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace || $0 == "/" }), let portValue = UInt16(exactly: port), portValue > 0 else { throw NewsError.failure("Server／Port 不正確") }
        let params: NWParameters = port == 563 ? .tls : .tcp
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: portValue)!, using: params)
        let ready = DispatchSemaphore(value: 0)
        let result = ConnectionResult()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: result.complete(nil, signal: ready)
            case .failed(let error): result.complete(error, signal: ready)
            case .cancelled: result.complete(NewsError.failure("連線已取消"), signal: ready)
            default: break
            }
        }
        connection.start(queue: queue)
        guard ready.wait(timeout: .now() + 20) == .success else { connection.cancel(); throw NewsError.failure("連線逾時") }
        if let error = result.error { connection.cancel(); throw error }
        do {
            let greeting = try line()
            guard greeting.hasPrefix("200") || greeting.hasPrefix("201") else { throw NewsError.failure(greeting) }
        } catch { connection.cancel(); throw error }
    }
    deinit { connection.cancel() }
    func close() { closed = true; connection.cancel() }
    private func send(_ command: String) throws {
        guard !closed, command.rangeOfCharacter(from: .newlines) == nil else { throw NewsError.failure("無效 NNTP 指令") }
        let signal = DispatchSemaphore(value: 0), result = ConnectionResult()
        connection.send(content: Data((command + "\r\n").utf8), completion: .contentProcessed { error in result.complete(error, signal: signal) })
        guard signal.wait(timeout: .now() + 20) == .success else { throw NewsError.failure("傳送逾時") }
        if let error = result.error { throw error }
    }
    private func lineData() throws -> Data {
        while true {
            if let range = buffer.range(of: Data([13,10])) {
                let value = Data(buffer[..<range.lowerBound]); buffer.removeSubrange(..<range.upperBound)
                return value
            }
            guard buffer.count < 24 * 1024 * 1024 else { throw NewsError.failure("NNTP 行太長") }
            let signal = DispatchSemaphore(value: 0), result = ConnectionResult()
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, complete, error in
                result.data = data; result.eof = complete; result.complete(error, signal: signal)
            }
            guard signal.wait(timeout: .now() + 25) == .success else { connection.cancel(); throw NewsError.failure("下載逾時，已保存完成嘅批次") }
            if let error = result.error { throw error }
            if let data = result.data, !data.isEmpty { buffer.append(data) }
            else { throw NewsError.failure("Server 中斷連線") }
        }
    }
    private func line() throws -> String { latin(try lineData()) }
    func command(_ command: String, code: String) throws -> String {
        try send(command)
        let response = try line()
        guard response.hasPrefix(code + " ") || response == code else { throw NewsError.failure(response) }
        return response
    }
    private func multiline(maxBytes: Int = 24 * 1024 * 1024) throws -> [Data] {
        var lines: [Data] = [], size = 0
        while true {
            var value = try lineData()
            if value == Data([46]) { return lines }
            if value.starts(with: [46,46]) { value.removeFirst() }
            size += value.count + 2
            guard size <= maxBytes else { throw NewsError.failure("回應過大，請減少下載數量") }
            lines.append(value)
        }
    }
    func groups() throws -> [String] {
        _ = try command("LIST ACTIVE", code: "215")
        return try multiline().compactMap { latin($0).split(separator: " ").first.map(String.init) }.sorted()
    }
    func select(_ group: String) throws {
        guard validGroup(group) else { throw NewsError.failure("群組名稱無效") }
        _ = try command("GROUP \(group)", code: "211")
    }
    func available(_ group: String) throws -> [Int] {
        guard validGroup(group) else { throw NewsError.failure("群組名稱無效") }
        _ = try command("LISTGROUP \(group)", code: "211")
        return try multiline().compactMap { Int(latin($0)) }.sorted()
    }
    func headers(group: String, numbers: [Int]) throws -> [NewsMessage] {
        try select(group)
        var ranges: [(Int,Int)] = []
        for number in Array(Set(numbers)).sorted() {
            if let last = ranges.last, number == last.1 + 1 { ranges[ranges.count-1].1 = number }
            else { ranges.append((number, number)) }
        }
        var result: [NewsMessage] = []
        for (start,end) in ranges {
            do { _ = try command("OVER \(start)-\(end)", code: "224") }
            catch {
                let description = error.localizedDescription
                if description.hasPrefix("423") { continue }
                guard description.hasPrefix("500") || description.hasPrefix("501") else { throw error }
                _ = try command("XOVER \(start)-\(end)", code: "224")
            }
            for data in try multiline() {
                let fields = latin(data).components(separatedBy: "\t")
                guard fields.count >= 6, let number = Int(fields[0]), numbers.contains(number), !fields[4].isEmpty else { continue }
                let refs = messageIDs(fields[5])
                var message = NewsMessage(id: fields[4], parentID: refs.last, author: decodeWords(fields[2]), body: "")
                message.articleNumber = number; message.subject = decodeWords(fields[1]); message.references = refs; message.bodyLoaded = false
                result.append(message)
            }
        }
        return result
    }
    /// Bulk source headers avoid fetching article bodies just to apply an IP block.
    func senderIPs(group: String, numbers: [Int]) throws -> [Int: String] {
        guard let first = numbers.min(), let last = numbers.max() else { return [:] }
        try select(group)
        var values: [Int: [String: String]] = [:]
        var supported = false
        for field in ["nntp-posting-host", "injection-info", "x-originating-ip", "x-trace"] {
            try send("HDR \(field) \(first)-\(last)")
            var response = try line()
            if response.hasPrefix("500") || response.hasPrefix("501") {
                try send("XHDR \(field) \(first)-\(last)"); response = try line()
            }
            if response.hasPrefix("225") || response.hasPrefix("221") {
                supported = true
                let wanted = Set(numbers)
                for data in try multiline() {
                    let text = latin(data)
                    if let space = text.firstIndex(of: " "), let number = Int(text[..<space]), wanted.contains(number) {
                        values[number, default: [:]][field] = String(text[text.index(after: space)...])
                    }
                }
            } else if !(response.hasPrefix("500") || response.hasPrefix("501") || response.hasPrefix("503") || response.hasPrefix("423")) {
                throw NewsError.failure(response)
            }
        }
        if !supported {
            for number in numbers {
                do {
                    _ = try command("HEAD \(number)", code: "221")
                    var raw = Data(); for line in try multiline() { raw.append(line); raw.append(contentsOf: [13,10]) }
                    values[number] = newsHeaderFields(raw)
                } catch { if !error.localizedDescription.hasPrefix("423") { throw error } }
            }
        }
        return values.compactMapValues { senderIPFromHeaders($0) }
    }
    func rawArticle(group: String, identifier: String) throws -> Data {
        guard Int(identifier) != nil || messageIDs(identifier) == [identifier] else { throw NewsError.failure("文章識別碼無效") }
        try select(group)
        _ = try command("ARTICLE \(identifier)", code: "220")
        let lines = try multiline(maxBytes: 30 * 1024 * 1024)
        var raw = Data()
        for line in lines { raw.append(line); raw.append(contentsOf: [13,10]) }
        return raw
    }
    func article(group: String, number: Int) throws -> DecodedArticle {
        let raw = try rawArticle(group: group, identifier: String(number))
        var decoded = try decodeArticle(raw); decoded.senderIP = senderIPFromHeaders(newsHeaderFields(raw)); return decoded
    }
    func post(_ article: Data) throws {
        _ = try command("POST", code: "340")
        var payload = Data()
        for line in latin(article).components(separatedBy: "\r\n") {
            if line.hasPrefix(".") { payload.append(46) }
            payload.append(latinData(line)); payload.append(contentsOf: [13,10])
        }
        payload.append(contentsOf: [46,13,10])
        let signal = DispatchSemaphore(value: 0), result = ConnectionResult()
        connection.send(content: payload, completion: .contentProcessed { error in result.complete(error, signal: signal) })
        guard signal.wait(timeout: .now()+40) == .success else { throw NewsError.failure("發送結果未確認；請先檢查，唔好重複發送") }
        if let error = result.error { throw error }
        let response = try line()
        guard response.hasPrefix("240") else { throw NewsError.failure(response) }
    }

}
private final class ConnectionResult: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    var error: Error?
    var data: Data?
    var eof = false
    func complete(_ error: Error?, signal: DispatchSemaphore) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }; finished = true
        self.error = error; signal.signal()
    }
}
func validGroup(_ group: String) -> Bool {
    !group.isEmpty && group.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [43,45,46,95].contains($0) }
}
func latin(_ data: Data) -> String { String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self) }
func latinData(_ text: String) -> Data { text.data(using: .isoLatin1) ?? Data(text.utf8) }
func messageIDs(_ text: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: "<[^<>\\s]+>")
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
}
func decodeCharset(_ data: Data, charset: String = "") -> String {
    let name = charset.lowercased()
    if name.contains("big5") || name.contains("cp950") {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)))
        if let text = String(data: data, encoding: encoding) { return text }
    }
    if let text = String(data: data, encoding: .utf8) { return text }
    if name.isEmpty {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        if let text = String(data: data, encoding: encoding) { return text }
    }
    if let cfName = name as CFString? {
        let cf = CFStringConvertIANACharSetNameToEncoding(cfName)
        if cf != kCFStringEncodingInvalidId, let text = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) { return text }
    }
    return latin(data)
}
func quotedPrintable(_ data: Data) -> Data {
    let bytes = Array(data); var result = Data(), i = 0
    while i < bytes.count {
        if bytes[i] == 61 {
            if i+2 < bytes.count, bytes[i+1] == 13, bytes[i+2] == 10 { i += 3; continue }
            if i+1 < bytes.count, bytes[i+1] == 10 { i += 2; continue }
            if i+2 < bytes.count, let n = UInt8(String(bytes: bytes[(i+1)...(i+2)], encoding: .ascii) ?? "", radix: 16) { result.append(n); i += 3; continue }
        }
        result.append(bytes[i]); i += 1
    }
    return result
}
func decodeWords(_ source: String) -> String {
    let regex = try! NSRegularExpression(pattern: "=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?=")
    var text = source.replacingOccurrences(of: "(?<=\\?=)[ \\t]+(?==\\?)", with: "", options: .regularExpression)
    for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
        let ns = text as NSString
        let charset = ns.substring(with: match.range(at: 1)), encoding = ns.substring(with: match.range(at: 2)), content = ns.substring(with: match.range(at: 3))
        let data = encoding.lowercased() == "b" ? Data(base64Encoded: content) : quotedPrintable(latinData(content.replacingOccurrences(of: "_", with: " ")))
        if let data, let range = Range(match.range, in: text) { text.replaceSubrange(range, with: decodeCharset(data, charset: charset)) }
    }
    return decodeCharset(latinData(text))
}
struct DecodedArticle { var body: String; var images: [Data]; var warnings: [String]; var senderIP: String? }
func decodeArticle(_ data: Data) throws -> DecodedArticle {
    var totalImages = 0
    func decodePart(_ data: Data, depth: Int) throws -> DecodedArticle {
        guard depth < 12 else { throw NewsError.failure("MIME 巢狀層數太多") }
        let raw = latin(data).replacingOccurrences(of: "\r\n", with: "\n")
        guard let separator = raw.range(of: "\n\n") else { return DecodedArticle(body: decodeCharset(data), images: [], warnings: []) }
        let headerText = String(raw[..<separator.lowerBound]).replacingOccurrences(of: "\n[ \\t]+", with: " ", options: .regularExpression)
        var headers: [String:String] = [:]
        for line in headerText.components(separatedBy: "\n") { if let colon = line.firstIndex(of: ":") { headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces) } }
        let type = headers["content-type"] ?? "text/plain"
        let body = String(raw[separator.upperBound...])
        func parameter(_ name: String) -> String? {
            let pattern = "(?:^|;)\\s*" + name + "\\s*=\\s*(?:\"([^\"]+)\"|([^;\\s]+))"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: type, range: NSRange(type.startIndex..., in: type)) else { return nil }
            let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
            return Range(range, in: type).map { String(type[$0]) }
        }
        if type.lowercased().hasPrefix("multipart/"), let boundary = parameter("boundary") {
            var parts: [String] = [], current: [String]? = nil
            for line in body.components(separatedBy: "\n") {
                if line == "--" + boundary || line == "--" + boundary + "--" {
                    if let current { parts.append(current.joined(separator: "\n")) }
                    current = line.hasSuffix("--") ? nil : []
                } else if current != nil { current!.append(line) }
            }
            var result = DecodedArticle(body: "", images: [], warnings: [])
            for part in parts {
                let decoded = try decodePart(latinData(part), depth: depth+1)
                if !decoded.body.isEmpty { if !result.body.isEmpty { result.body += "\n\n" }; result.body += decoded.body }
                result.images += decoded.images; result.warnings += decoded.warnings
            }
            return result
        }
        let transfer = headers["content-transfer-encoding"]?.lowercased() ?? ""
        let payload: Data
        if transfer == "base64" { guard let decoded = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else { throw NewsError.failure("附件 Base64 損壞") }; payload = decoded }
        else if transfer == "quoted-printable" { payload = quotedPrintable(latinData(body)) }
        else { payload = latinData(body) }
        if type.lowercased().hasPrefix("text/plain") { return DecodedArticle(body: decodeCharset(payload, charset: parameter("charset") ?? ""), images: [], warnings: []) }
        let mime = type.components(separatedBy: ";")[0].lowercased()
        if ["image/jpeg", "image/png", "image/gif", "image/webp"].contains(mime) {
            guard payload.count <= 10*1024*1024, totalImages + payload.count <= 20*1024*1024 else { return DecodedArticle(body: "", images: [], warnings: ["圖片超過閱讀上限（每張 10 MB／每篇 20 MB）"]) }
            totalImages += payload.count
            return DecodedArticle(body: "", images: [payload], warnings: [])
        }
        return DecodedArticle(body: "", images: [], warnings: ["暫未支援內容：\(mime)"])
    }
    return try decodePart(data, depth: 0)
}

func newsHeaderFields(_ raw: Data) -> [String: String] {
    let text = latin(raw).replacingOccurrences(of: "\r\n", with: "\n")
    let head = text.components(separatedBy: "\n\n")[0].replacingOccurrences(of: "\n[ \t]+", with: " ", options: .regularExpression)
    var fields: [String: String] = [:]
    for line in head.components(separatedBy: "\n") {
        if let colon = line.firstIndex(of: ":") { fields[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces) }
    }
    return fields
}
func senderIPFromHeaders(_ fields: [String: String]) -> String? {
    // Never use Path, server IP or Message-ID as a sender address.
    for key in ["nntp-posting-host", "injection-info", "x-originating-ip", "x-trace"] {
        guard var value = fields[key] else { continue }
        if key == "injection-info" {
            guard let regex = try? NSRegularExpression(pattern: #"(?:^|;)\s*posting-host\s*=\s*(?:"([^"]+)"|([^;\s]+))"#, options: .caseInsensitive),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), let range = Range(match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1), in: value) else { continue }
            value = String(value[range])
        }
        if let ip = canonicalIP(value) { return ip }
        for token in value.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "();,\""))) {
            if let ip = canonicalIP(token) { return ip }
            // INN may publish posting-host="reverse.hostname:address".
            // Split once, preserving IPv6 colons; never resolve the hostname.
            if let colon = token.firstIndex(of: ":") {
                let host = String(token[..<colon])
                let address = String(token[token.index(after: colon)...])
                if host.range(of: #"\A[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\z"#, options: .regularExpression) != nil,
                   host.rangeOfCharacter(from: .letters) != nil,
                   let ip = canonicalIP(address) { return ip }
            }
        }
    }
    return nil
}
