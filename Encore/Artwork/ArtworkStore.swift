import UIKit
import CryptoKit
import ImageIO
import AVFoundation

/// Static artwork on disk, deduplicated by content hash.
enum ArtworkStore {
    /// Normalizes any image data to a ≤1400px JPEG, stores it, and returns its ID.
    static func save(_ data: Data) -> String? {
        guard let jpeg = normalizedJPEG(from: data) else { return nil }
        let id = SHA256.hash(data: jpeg).prefix(12).map { String(format: "%02x", $0) }.joined()
        let url = url(for: id)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? jpeg.write(to: url, options: .atomic)
        }
        return id
    }

    static func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return save(data)
    }

    static func url(for id: String) -> URL { Paths.artwork.appendingPathComponent(id + ".jpg") }

    static func data(for id: String) -> Data? { try? Data(contentsOf: url(for: id)) }

    static func normalizedJPEG(from data: Data, maxPixel: Int = 1400) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions(maxPixel)) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.88)
    }

    /// Downsampled image straight from disk (cheap on memory).
    static func thumbnail(id: String, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url(for: id) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions(maxPixel)) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func thumbnailOptions(_ maxPixel: Int) -> CFDictionary {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
    }

    /// First frame of a video or GIF, used as static artwork for animated covers.
    static func firstFrame(of url: URL) async -> UIImage? {
        if url.pathExtension.lowercased() == "gif" {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return UIImage(cgImage: cg)
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1400, height: 1400)
        guard let frame = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: frame.image)
    }
}

/// In-memory cache of decoded thumbnails.
final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.countLimit = 400 }

    func cached(id: String, maxPixel: Int) -> UIImage? {
        cache.object(forKey: "\(id)@\(maxPixel)" as NSString)
    }

    func image(id: String, maxPixel: Int) async -> UIImage? {
        let key = "\(id)@\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .userInitiated) {
            ArtworkStore.thumbnail(id: id, maxPixel: maxPixel)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
