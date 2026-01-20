import AppKit
import Foundation

enum PerceptualHasher {
    /// Computes a dHash (difference hash) for an image.
    /// Returns a 64-bit hash as a UInt64, or nil if the image can't be processed.
    /// Images with Hamming distance <= threshold are considered similar.
    static func dHash(for url: URL) -> UInt64? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return dHash(for: cgImage)
    }

    static func dHash(for cgImage: CGImage) -> UInt64? {
        // Resize to 9x8 (we compare horizontally, so 9 columns gives 8 differences)
        let width = 9
        let height = 8

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        // Build hash by comparing adjacent pixels horizontally
        var hash: UInt64 = 0
        var bitPosition: UInt64 = 0

        for row in 0..<height {
            let rowStart = row * width
            for col in 0..<(width - 1) {
                let leftPixel = pixelData[rowStart + col]
                let rightPixel = pixelData[rowStart + col + 1]
                if leftPixel > rightPixel {
                    hash |= (1 << bitPosition)
                }
                bitPosition += 1
            }
        }

        return hash
    }

    /// Computes Hamming distance between two dHash values.
    /// Returns a value from 0 (identical) to 64 (completely different).
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        let xor = a ^ b
        return xor.nonzeroBitCount
    }

    /// Threshold for considering two images as near-duplicates.
    /// Lower = stricter (fewer matches). Higher = more lenient (more matches).
    /// Default 5 means images with <= 5 bit differences are considered similar.
    static let nearDuplicateThreshold = 5
}
