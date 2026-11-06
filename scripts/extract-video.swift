import Foundation
import AVFoundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("Usage: swift extract-video.swift video output-directory [interval-seconds]") }
let url = URL(fileURLWithPath: args[1])
let directory = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let asset = AVURLAsset(url: url)
let duration = CMTimeGetSeconds(asset.duration)
let step = args.count > 3 ? Double(args[3])! : 10.0
print("Duration: \(duration) seconds")
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 390, height: 844)
var frames: [(Double, NSImage)] = []
for second in stride(from: 0.0, to: duration, by: step) {
    let cg = try generator.copyCGImage(at: CMTime(seconds: second, preferredTimescale: 600), actualTime: nil)
    let bitmap = NSBitmapImageRep(cgImage: cg)
    let name = String(format: "frame-%04d.jpg", Int(second))
    try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!.write(to: directory.appendingPathComponent(name))
    frames.append((second, NSImage(cgImage: cg, size: .zero)))
}
let columns = 5, cellWidth = 195, cellHeight = 447
for start in stride(from: 0, to: frames.count, by: 15) {
    let page = Array(frames[start..<min(start+15, frames.count)])
    let sheet = NSImage(size: NSSize(width: columns * cellWidth, height: ((page.count + columns - 1) / columns) * cellHeight))
    sheet.lockFocusFlipped(true)
    NSColor.white.setFill(); NSRect(origin: .zero, size: sheet.size).fill()
    for (index, frame) in page.enumerated() {
        let x = (index % columns) * cellWidth, y = (index / columns) * cellHeight
        frame.1.draw(in: NSRect(x: x, y: y+22, width: cellWidth, height: cellHeight-22), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        ("\(Int(frame.0))s" as NSString).draw(at: NSPoint(x: x+6, y: y+2), withAttributes: [.foregroundColor: NSColor.black, .font: NSFont.systemFont(ofSize: 14)])
    }
    sheet.unlockFocus()
    let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
    try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!.write(to: directory.appendingPathComponent("contact-\(start/15).jpg"))
}
