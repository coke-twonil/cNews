import Foundation
func check(_ value: @autoclosure () -> Bool, _ label: String) {
    guard value() else { fatalError(label) }; print("PASS \(label)")
}
check(decodeWords("=?UTF-8?B?5Lit5paH?=") == "中文", "RFC2047 UTF8")
check(decodeWords("=?UTF-8?Q?hello_world?=") == "hello world", "RFC2047 Q encoding")
let big5 = Data([0xa4,0xa4,0xa4,0xe5])
check(decodeCharset(big5, charset: "big5") == "中文", "Big5 decode")
check(decodeWords("=?Big5?B?" + big5.base64EncodedString() + "?=") == "中文", "RFC2047 Big5")
let mime = Data("Content-Type: multipart/mixed; boundary=demo\r\n\r\n--demo\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nHello=20world=0A=E4=B8=AD=E6=96=87\r\n--demo\r\nContent-Type: image/png\r\nContent-Transfer-Encoding: base64\r\n\r\naGVsbG8=\r\n--demo--\r\n".utf8)
let article = try decodeArticle(mime)
check(article.body.contains("Hello world\n中文"), "MIME text quoted printable")
check(article.images == [Data("hello".utf8)], "MIME image bytes")
var first = NewsMessage(id: "<a@x>", author: "a", body: ""); first.references = ["<root@x>"]; first.articleNumber = 2
var second = NewsMessage(id: "<b@x>", author: "b", body: ""); second.references = ["<root@x>", "<a@x>"]; second.parentID = "<a@x>"; second.articleNumber = 4
let threads = liveThreads(LiveGroupCache(messages: [second, first]), server: "s", group: "g")
check(threads.count == 1 && threads[0].tree.map { $0.depth } == [0,1], "References links missing-root thread")
check(downloadSelection(available: [3,4,7,9], newestDownloaded: 7, count: 500, latest: false) == [9], "Next excludes skipped older holes")
if CommandLine.arguments.count > 1 {
    let port = Int(CommandLine.arguments[1])!
    let client = try NNTPClient(host: "127.0.0.1", port: port); defer { client.close() }
    let groups = try client.groups(); check(groups == ["test.fixture"], "LIST ACTIVE")
    let available = try client.available("test.fixture"); check(available == [1,3], "LISTGROUP sparse numbers")
    let headers = try client.headers(group: "test.fixture", numbers: [1,3])
    check(headers.count == 2 && headers[1].parentID == "<root@fixture>", "OVER sparse range and References")
    let ips = try client.senderIPs(group: "test.fixture", numbers: [1,3])
    check(ips[1] == "192.0.2.24" && ips[3] == "2001:db8::1", "HDR downloads source IP for unread articles")
    let oldIPs = try client.senderIPs(group: "test.xhdr", numbers: [1])
    check(oldIPs[1] == "192.0.2.24", "Legacy XHDR source header fallback")
    let headIPs = try client.senderIPs(group: "test.head", numbers: [1])
    check(headIPs[1] == "198.51.100.18", "HEAD fallback when bulk headers unavailable")
    let body = try client.article(group: "test.fixture", number: 1)
    check(body.body.contains(".dot stuffed"), "ARTICLE dot unstuffing")
}

check(senderIPFromHeaders(["nntp-posting-host": "192.0.2.24"]) == "192.0.2.24", "NNTP posting host is sender IP")
check(senderIPFromHeaders(["injection-info": "news.invalid; posting-host=\"2001:db8::1\"; logging-data=123"]) == "2001:db8::1", "Injection-Info IPv6 posting host")
check(senderIPFromHeaders(["x-trace": "news.invalid 1790000000 1234 192.0.2.24 (date)"]) == "192.0.2.24", "X-Trace sender IP excludes timestamp and server name")
check(senderIPFromHeaders(["path": "192.0.2.1!not-for-mail", "message-id": "<x@192.0.2.2>"]) == nil, "Never infer sender IP from relay headers")
