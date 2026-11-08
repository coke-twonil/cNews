import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decode only an orientation-corrected, bounded thumbnail, never the full camera frame.
/// Call on a worker task; the returned JPEG carries no original location metadata.
enum PhotoPreparation {
    static let maxDimension = 1280
    static let maxBytes = 512 * 1024
    static func prepare(_ data: Data) throws -> ReplyPhoto {
        try autoreleasepool {
            guard data.count <= 100 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw PhotoError.invalid }
            for quality in [0.75, 0.6, 0.45, 0.3] {
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw PhotoError.invalid }
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw PhotoError.invalid }
                if output.length <= maxBytes { return ReplyPhoto(data: output as Data, mime: "image/jpeg") }
            }
            throw PhotoError.tooLarge
        }
    }
    static func forSending(_ photo: ReplyPhoto) throws -> ReplyPhoto {
        if photo.mime == "image/jpeg", photo.data.count <= maxBytes,
           let source = CGImageSourceCreateWithData(photo.data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
           max(width, height) <= maxDimension, (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1 { return photo }
        var resized = try prepare(photo.data); resized.id = photo.id; return resized
    }
    static func thumbnail(_ data: Data) -> Data? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 240] as CFDictionary) else { return nil }
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            return CGImageDestinationFinalize(destination) ? result as Data : nil
        }
    }
    enum PhotoError: LocalizedError {
        case invalid, tooLarge
        var errorDescription: String? { self == .invalid ? "相片無法讀取，請揀另一張相再試。" : "相片縮細後仍然太大，請揀另一張相。" }
    }
}
