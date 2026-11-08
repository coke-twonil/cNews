import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
func check(_ value: @autoclosure () -> Bool, _ label: String) { guard value() else { fatalError(label) }; print("PASS \(label)") }
let data = try autoreleasepool { () throws -> Data in
    let context = CGContext(data: nil, width: 6000, height: 4000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 6000, height: 4000))
    let bytes = NSMutableData()
    let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: 6, kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 22.3]] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("fixture") }
    return bytes as Data
}
let prepared = try PhotoPreparation.prepare(data)
let source = CGImageSourceCreateWithData(prepared.data as CFData, nil)!
let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
let width = properties[kCGImagePropertyPixelWidth] as! Int, height = properties[kCGImagePropertyPixelHeight] as! Int
check(max(width, height) <= 1280, "24 MP input downsampled to bounded dimensions")
check(height > width, "Camera EXIF orientation applied")
check(prepared.mime == "image/jpeg" && prepared.data.count <= PhotoPreparation.maxBytes, "JPEG attachment remains within 512 KB")
check(properties[kCGImagePropertyGPSDictionary] == nil, "Source GPS metadata not copied")
let thumb = PhotoPreparation.thumbnail(prepared.data)!
let thumbSource = CGImageSourceCreateWithData(thumb as CFData, nil)!
let thumbProperties = CGImageSourceCopyPropertiesAtIndex(thumbSource, 0, nil)! as NSDictionary
check(max(thumbProperties[kCGImagePropertyPixelWidth] as! Int, thumbProperties[kCGImagePropertyPixelHeight] as! Int) <= 240, "Composer preview uses small thumbnail")
do { _ = try PhotoPreparation.prepare(Data("invalid photo".utf8)); fatalError("invalid accepted") } catch { print("PASS malformed image produces recoverable error") }

let ready = try PhotoPreparation.forSending(prepared)
check(ready.id == prepared.id && ready.data == prepared.data, "Already compressed photo is not recompressed on retry")
let legacyPhoto = ReplyPhoto(data: data, mime: "image/jpeg")
let smaller = try PhotoPreparation.forSending(legacyPhoto)
check(smaller.id == legacyPhoto.id && smaller.data.count <= PhotoPreparation.maxBytes, "Old large draft photo is compressed before send without losing attachment identity")
