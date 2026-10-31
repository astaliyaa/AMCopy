import SwiftUI
import UIKit

/// Pulls colors out of artwork for Now Playing's animated mesh background and tinted cards.
enum ColorExtractor {
    static let fallbackMesh: [Color] = Array(repeating: Color(white: 0.22), count: 9)

    /// 3×3 grid of colors sampled from the artwork, in row order from the top-left.
    static func meshColors(artworkID: String?) async -> [Color] {
        guard let artworkID else { return fallbackMesh }
        return await Task.detached(priority: .utility) {
            guard let pixels = sample(artworkID: artworkID, size: 3) else { return fallbackMesh }
            return pixels.map { adjust($0, maxBrightness: 0.72, saturationBoost: 1.15) }
        }.value
    }

    /// Average color, darkened enough for white text.
    static func averageColor(artworkID: String?) async -> Color {
        guard let artworkID else { return Color(white: 0.3) }
        return await Task.detached(priority: .utility) {
            guard let pixel = sample(artworkID: artworkID, size: 1)?.first else { return Color(white: 0.3) }
            return adjust(pixel, maxBrightness: 0.55, saturationBoost: 1.1)
        }.value
    }

    private static func sample(artworkID: String, size: Int) -> [UIColor]? {
        guard let cg = ArtworkStore.thumbnail(id: artworkID, maxPixel: 64)?.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        return stride(from: 0, to: pixels.count, by: 4).map { i in
            UIColor(
                red: CGFloat(pixels[i]) / 255,
                green: CGFloat(pixels[i + 1]) / 255,
                blue: CGFloat(pixels[i + 2]) / 255,
                alpha: 1
            )
        }
    }

    private static func adjust(_ color: UIColor, maxBrightness: CGFloat, saturationBoost: CGFloat) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let adjusted = UIColor(
            hue: h,
            saturation: min(1, s * saturationBoost),
            brightness: min(b, maxBrightness) * 0.9 + 0.04,
            alpha: 1
        )
        return Color(uiColor: adjusted)
    }
}
