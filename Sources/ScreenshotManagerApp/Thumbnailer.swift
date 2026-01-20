import AppKit
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Thumbnailer {
    static func thumbnail(for url: URL, maxPixelSize: Int = 512) async -> NSImage? {
        // Check if it's a video file
        let item = ScreenshotItem(id: url, url: url, createdAt: Date())
        if item.isVideo {
            return await thumbnailForVideo(url: url, maxPixelSize: maxPixelSize)
        } else {
            return thumbnailForImage(url: url, maxPixelSize: maxPixelSize)
        }
    }

    /// Synchronous version for backwards compatibility
    static func thumbnailSync(for url: URL, maxPixelSize: Int = 512) -> NSImage? {
        let item = ScreenshotItem(id: url, url: url, createdAt: Date())
        if item.isVideo {
            return thumbnailForVideoSync(url: url, maxPixelSize: maxPixelSize)
        } else {
            return thumbnailForImage(url: url, maxPixelSize: maxPixelSize)
        }
    }
    
    private static func thumbnailForImage(url: URL, maxPixelSize: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgThumb, size: .zero)
    }
    
    private static func thumbnailForVideo(url: URL, maxPixelSize: Int) async -> NSImage? {
        // Check if file exists and is readable
        guard FileManager.default.fileExists(atPath: url.path),
              FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }

        // Wait for file to be fully written (especially important for just-recorded videos)
        // Check file size stability to ensure it's fully written
        var lastSize: Int64 = 0
        var stableCount = 0
        for attempt in 0..<10 {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                if size == lastSize && size > 0 {
                    stableCount += 1
                    if stableCount >= 3 {
                        // File size is stable, wait a bit more for file system to finalize
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second
                        break
                    }
                } else {
                    stableCount = 0
                }
                lastSize = size
            }
            // Longer wait for newly created files
            let waitTime = attempt < 3 ? 300_000_000 : 200_000_000 // 0.3s first 3 attempts, then 0.2s
            try? await Task.sleep(nanoseconds: UInt64(waitTime))
        }

        // Create asset and wait until tracks are available (file ready)
        var asset: AVURLAsset?
        var tracksReady = false
        for attempt in 0..<6 {
            let candidate = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            do {
                let tracks = try await candidate.load(.tracks)
                if !tracks.isEmpty {
                    asset = candidate
                    tracksReady = true
                    break
                }
            } catch {
                if attempt == 5 {
                    print("Failed to load video tracks after \(attempt + 1) attempts: \(error.localizedDescription)")
                    return nil
                }
            }
            // Wait before retry
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6 second
        }
        
        guard tracksReady, let asset else {
            print("Video tracks not ready yet: \(url.lastPathComponent)")
            return nil
        }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: CGFloat(maxPixelSize), height: CGFloat(maxPixelSize))
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 1.0, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)

        // Get video duration using modern async API
        let durationSeconds: Double
        do {
            let duration = try await asset.load(.duration)
            durationSeconds = CMTimeGetSeconds(duration)
        } catch {
            print("Failed to load video duration: \(error.localizedDescription)")
            durationSeconds = 0
        }

        // Pick a thumbnail time based on video duration
        let thumbnailTime: CMTime
        if durationSeconds <= 0 || durationSeconds.isNaN {
            // Invalid duration, try time zero
            thumbnailTime = .zero
        } else if durationSeconds < 0.5 {
            // Very short video, use middle point
            thumbnailTime = CMTime(seconds: durationSeconds * 0.5, preferredTimescale: 600)
        } else if durationSeconds < 1.0 {
            // Short video, use 0.25 seconds or middle
            thumbnailTime = CMTime(seconds: min(0.25, durationSeconds * 0.5), preferredTimescale: 600)
        } else {
            // Normal video, use 0.5 seconds
            thumbnailTime = CMTime(seconds: 0.5, preferredTimescale: 600)
        }

        do {
            let cgImage = try imageGenerator.copyCGImage(at: thumbnailTime, actualTime: nil)
            return NSImage(cgImage: cgImage, size: .zero)
        } catch {
            // Fallback: try at time zero
            do {
                let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
                return NSImage(cgImage: cgImage, size: .zero)
            } catch {
                print("Failed to generate video thumbnail for \(url.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// Synchronous version for backwards compatibility (uses deprecated API)
    private static func thumbnailForVideoSync(url: URL, maxPixelSize: Int) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }

        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: CGFloat(maxPixelSize), height: CGFloat(maxPixelSize))
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 1.0, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)

        // Try at 0.5 seconds first, then fallback to zero
        let times: [CMTime] = [
            CMTime(seconds: 0.5, preferredTimescale: 600),
            .zero
        ]

        for time in times {
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                return NSImage(cgImage: cgImage, size: .zero)
            } catch {
                continue
            }
        }

        print("Failed to generate video thumbnail for \(url.lastPathComponent)")
        return nil
    }
}

