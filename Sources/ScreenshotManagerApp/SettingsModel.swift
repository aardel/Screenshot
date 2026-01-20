import Foundation

@MainActor
final class SettingsModel: ObservableObject {
    @Published var watchedFolderBookmark: Data? {
        didSet { save() }
    }

    @Published var dateFilter: DateFilter = .all {
        didSet { save() }
    }
    
    @Published var thumbnailSize: ThumbnailSize = .medium {
        didSet { save() }
    }

    @Published var copyToClipboardAfterCapture: Bool = true {
        didSet { save() }
    }
    
    enum ThumbnailSize: Int, CaseIterable, Identifiable {
        case small = 0
        case medium = 1
        case large = 2
        
        var id: Int { rawValue }
        
        var label: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
        
        var minWidth: CGFloat {
            switch self {
            case .small: return 160
            case .medium: return 220
            case .large: return 300
            }
        }
        
        var maxWidth: CGFloat {
            switch self {
            case .small: return 200
            case .medium: return 340
            case .large: return 480
            }
        }
    }

    enum DateFilter: String, CaseIterable, Identifiable {
        case all
        case last1h
        case last6h
        case last12h
        case last24h
        case last3d
        case last7d

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .last1h: return "Last 1 hour"
            case .last6h: return "Last 6 hours"
            case .last12h: return "Last 12 hours"
            case .last24h: return "Last 24 hours"
            case .last3d: return "Last 3 days"
            case .last7d: return "Last 7 days"
            }
        }
    }

    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    private func load() {
        watchedFolderBookmark = defaults.data(forKey: "watchedFolderBookmark")
        if let raw = defaults.string(forKey: "dateFilter"), let f = DateFilter(rawValue: raw) {
            dateFilter = f
        }
        if let raw = defaults.object(forKey: "thumbnailSize") as? Int,
           let size = ThumbnailSize(rawValue: raw) {
            thumbnailSize = size
        }
        if defaults.object(forKey: "copyToClipboardAfterCapture") != nil {
            copyToClipboardAfterCapture = defaults.bool(forKey: "copyToClipboardAfterCapture")
        }
    }

    private func save() {
        defaults.set(watchedFolderBookmark, forKey: "watchedFolderBookmark")
        defaults.set(dateFilter.rawValue, forKey: "dateFilter")
        defaults.set(thumbnailSize.rawValue, forKey: "thumbnailSize")
        defaults.set(copyToClipboardAfterCapture, forKey: "copyToClipboardAfterCapture")
    }
}

