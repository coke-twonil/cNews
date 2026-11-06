import Foundation
func check(_ value: @autoclosure () -> Bool, _ label: String) { guard value() else { fatalError(label) }; print("PASS \(label)") }
func parse(_ text: String) -> EmbedItem? { EmbedItem.parse(URL(string: text)!) }
check(parse("https://www.instagram.com/p/DfYl0uRlEpb/?xtok=tracking")?.url.absoluteString == "https://www.instagram.com/p/DfYl0uRlEpb/", "IG real post canonical")
check(parse("https://x.com/bricsinfo/status/2118535892541280746?a=tracking&s=46")?.provider == "x", "X real link")
check(parse("https://youtu.be/au2BEoOb77o?si=tracking")?.url.absoluteString.contains("/embed/au2BEoOb77o") == true, "YouTube short link")
check(parse("https://www.youtube.com/watch?v=au2BEoOb77o&t=1m30s")?.url.absoluteString.contains("start=90") == true, "YouTube timestamp")
check(parse("https://www.facebook.com/share/p/1GfeZmGC6E/?mibextid=tracking")?.provider == "facebook", "Facebook share link")
check(parse("https://www.facebook.com/story.php?id=123&story_fbid=456")?.url.absoluteString == "https://www.facebook.com/123/posts/456/", "Facebook story canonical")
check(parse("https://www.threads.net/@user/post/ABC123/")?.url.absoluteString == "https://www.threads.com/t/ABC123/", "Threads canonical")
check(parse("https://lih.kg/4177169")?.provider == "preview", "Lihkg link preview")
check(parse("https://www.instagram.com.attacker.test/p/ABC/") == nil, "spoofed host rejected")
check(parse("https://user:pass@www.instagram.com/p/ABC/") == nil, "credential URL rejected")
let pieces = mediaPieces("一行\nhttps://x.com/user/status/123\n下一行\nhttps://twitter.com/user/status/123")
check(pieces.filter { $0.embed != nil }.count == 1, "canonical embed deduplication")
check(pieces.filter { $0.link != nil }.count == 2 && pieces.contains { $0.text?.contains("下一行") == true }, "original links and text retained")

check(parse("https://www.facebook.com/groups/hongkongersmkgirl/permalink/1428489742252766/?tracking=1")?.provider == "facebook", "Facebook group permalink redirect")
