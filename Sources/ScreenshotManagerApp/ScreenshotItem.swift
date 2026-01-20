import AppKit
import Foundation
import UniformTypeIdentifiers

struct ScreenshotItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    let createdAt: Date

    var filename: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }

    var isLikelyScreenshotImage: Bool {
        guard let type = UTType(filenameExtension: fileExtension) else { return false }
        return type.conforms(to: .image)
    }
    
    var isVideo: Bool {
        guard let type = UTType(filenameExtension: fileExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }
    
    var isMediaFile: Bool {
        return isLikelyScreenshotImage || isVideo
    }
}

