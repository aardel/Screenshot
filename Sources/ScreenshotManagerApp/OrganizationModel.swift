import Foundation
import AppKit

// MARK: - Organization Data Models

struct ScreenshotMetadata: Codable, Identifiable {
    let id: URL // ScreenshotItem.id
    var tags: Set<String>
    var isFavorite: Bool
    var collectionID: UUID?
    var customName: String?
    var notes: String?
    var createdAt: Date
    
    init(id: URL, tags: Set<String> = [], isFavorite: Bool = false, collectionID: UUID? = nil, customName: String? = nil, notes: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.tags = tags
        self.isFavorite = isFavorite
        self.collectionID = collectionID
        self.customName = customName
        self.notes = notes
        self.createdAt = createdAt
    }
}

private struct MetadataExport: Codable {
    let metadata: [String: ScreenshotMetadata]
    let collections: [Collection]
    let smartFolders: [SmartFolder]
}

struct Collection: Codable, Identifiable {
    let id: UUID
    var name: String
    var color: String // Hex color
    var createdAt: Date
    var screenshotIDs: Set<URL>
    
    init(id: UUID = UUID(), name: String, color: String = "#007AFF", createdAt: Date = Date(), screenshotIDs: Set<URL> = []) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.screenshotIDs = screenshotIDs
    }
}

struct SmartFolder: Codable, Identifiable {
    let id: UUID
    var name: String
    var rules: [SmartFolderRule]
    var createdAt: Date
    
    init(id: UUID = UUID(), name: String, rules: [SmartFolderRule] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.rules = rules
        self.createdAt = createdAt
    }
}

enum SmartFolderRule: Codable {
    case hasTag(String)
    case isFavorite
    case dateRange(start: Date, end: Date)
    case appName(String)
    case hasNotes
    case inCollection(UUID)
}

enum SortOption: String, CaseIterable, Identifiable {
    case dateNewest = "date_newest"
    case dateOldest = "date_oldest"
    case nameAscending = "name_asc"
    case nameDescending = "name_desc"
    case sizeLargest = "size_largest"
    case sizeSmallest = "size_smallest"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .dateNewest: return "Date (Newest First)"
        case .dateOldest: return "Date (Oldest First)"
        case .nameAscending: return "Name (A-Z)"
        case .nameDescending: return "Name (Z-A)"
        case .sizeLargest: return "Size (Largest First)"
        case .sizeSmallest: return "Size (Smallest First)"
        case .custom: return "Custom Order"
        }
    }
}

// MARK: - Organization Manager

@MainActor
final class OrganizationModel: ObservableObject {
    @Published private(set) var metadata: [URL: ScreenshotMetadata] = [:]
    @Published private(set) var collections: [Collection] = []
    @Published private(set) var smartFolders: [SmartFolder] = []
    @Published var sortOption: SortOption = .dateNewest
    
    private let metadataURL: URL
    private let collectionsURL: URL
    private let smartFoldersURL: URL
    
    init() {
        // Get Application Support directory - this should always succeed on macOS
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // This is a critical error - Application Support should always exist on macOS
            // If we can't access it, something is seriously wrong
            fatalError("Could not access Application Support directory. This indicates a serious system issue. Please check system permissions and disk space.")
        }
        
        let appFolder = appSupport.appendingPathComponent("ScreenshotManager", isDirectory: true)

        // Create app support directory if needed
        do {
            try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        } catch {
            // Log the error but try to continue - reads might still work
            Task { @MainActor in
                ErrorLogger.shared.logFileOperation(
                    "Create app support directory",
                    path: appFolder.path,
                    error: error,
                    showToUser: true
                )
            }
        }

        metadataURL = appFolder.appendingPathComponent("metadata.json")
        collectionsURL = appFolder.appendingPathComponent("collections.json")
        smartFoldersURL = appFolder.appendingPathComponent("smartFolders.json")

        load()
    }
    
    // MARK: - Metadata Management
    
    func metadata(for item: ScreenshotItem) -> ScreenshotMetadata {
        if let existing = metadata[item.id] {
            return existing
        }
        let new = ScreenshotMetadata(id: item.id, createdAt: item.createdAt)
        metadata[item.id] = new
        return new
    }
    
    func updateMetadata(_ item: ScreenshotItem, tags: Set<String>? = nil, isFavorite: Bool? = nil, collectionID: UUID? = nil, customName: String? = nil, notes: String? = nil) {
        var meta = metadata(for: item)
        if let tags = tags { meta.tags = tags }
        if let isFavorite = isFavorite { meta.isFavorite = isFavorite }
        if let collectionID = collectionID { meta.collectionID = collectionID }
        if let customName = customName { meta.customName = customName }
        if let notes = notes { meta.notes = notes }
        metadata[item.id] = meta
        saveMetadata()
    }
    
    func addTag(_ tag: String, to item: ScreenshotItem) {
        var meta = metadata(for: item)
        meta.tags.insert(tag)
        metadata[item.id] = meta
        saveMetadata()
    }
    
    func removeTag(_ tag: String, from item: ScreenshotItem) {
        var meta = metadata(for: item)
        meta.tags.remove(tag)
        metadata[item.id] = meta
        saveMetadata()
    }
    
    func toggleFavorite(_ item: ScreenshotItem) {
        var meta = metadata(for: item)
        meta.isFavorite.toggle()
        metadata[item.id] = meta
        saveMetadata()
    }
    
    func batchToggleFavorites(_ items: [ScreenshotItem]) {
        guard !items.isEmpty else { return }
        
        // Determine if we should set all to favorite or unfavorite
        // Check current state
        let anyNotFavorite = items.contains { !isFavorite($0) }
        
        // If any are not favorites, favorite all; otherwise unfavorite all
        for item in items {
            var meta = metadata(for: item)
            meta.isFavorite = anyNotFavorite
            metadata[item.id] = meta
        }
        saveMetadata()
    }
    
    // MARK: - Export/Import
    
    func exportMetadata() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "screenshot-metadata-\(Date().ISO8601Format()).json"
        panel.title = "Export Metadata"
        
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        
        do {
            let export = MetadataExport(
                metadata: metadata.mapKeys { $0.absoluteString }, // Convert URL keys to String for Codable
                collections: collections,
                smartFolders: smartFolders
            )
            let data = try JSONEncoder().encode(export)
            try data.write(to: url)
            return url
        } catch {
            ErrorLogger.shared.log(error, context: "Failed to export metadata")
            return nil
        }
    }
    
    func importMetadata() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.title = "Import Metadata"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        
        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }
        
        do {
            let data = try Data(contentsOf: url)
            let export = try JSONDecoder().decode(MetadataExport.self, from: data)
            
            // Merge imported data with existing
            for (keyString, value) in export.metadata {
                if let urlKey = URL(string: keyString) {
                    metadata[urlKey] = value
                }
            }
            
            for newCollection in export.collections {
                if !collections.contains(where: { $0.id == newCollection.id }) {
                    collections.append(newCollection)
                }
            }
            
            for newSmartFolder in export.smartFolders {
                if !smartFolders.contains(where: { $0.id == newSmartFolder.id }) {
                    smartFolders.append(newSmartFolder)
                }
            }
            
            saveMetadata()
            saveCollections()
            saveSmartFolders()
            return true
        } catch {
            ErrorLogger.shared.log(error, context: "Failed to import metadata")
            return false
        }
    }
    
    func isFavorite(_ item: ScreenshotItem) -> Bool {
        metadata(for: item).isFavorite
    }
    
    func tags(for item: ScreenshotItem) -> Set<String> {
        metadata(for: item).tags
    }
    
    func allTags() -> [String] {
        Set(metadata.values.flatMap { $0.tags }).sorted()
    }
    
    // Rename a tag across all items
    func renameTag(from oldTag: String, to newTag: String) {
        guard oldTag != newTag, !newTag.isEmpty else { return }
        for (id, var meta) in metadata {
            if meta.tags.contains(oldTag) {
                meta.tags.remove(oldTag)
                meta.tags.insert(newTag)
                metadata[id] = meta
            }
        }
        saveMetadata()
    }
    
    // Delete a tag from all items
    func deleteTag(_ tag: String) {
        for (id, var meta) in metadata {
            meta.tags.remove(tag)
            metadata[id] = meta
        }
        saveMetadata()
    }
    
    // Get count of items with a tag
    func itemsWithTag(_ tag: String) -> Int {
        metadata.values.filter { $0.tags.contains(tag) }.count
    }
    
    // MARK: - Collections Management
    
    func createCollection(name: String, color: String = "#007AFF") -> Collection {
        let collection = Collection(name: name, color: color)
        collections.append(collection)
        saveCollections()
        return collection
    }
    
    func updateCollection(_ collection: Collection, name: String? = nil, color: String? = nil) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        if let name = name {
            collections[index].name = name
        }
        if let color = color {
            collections[index].color = color
        }
        saveCollections()
    }
    
    func deleteCollection(_ collection: Collection) {
        collections.removeAll { $0.id == collection.id }
        // Remove collection reference from metadata
        for (id, var meta) in metadata {
            if meta.collectionID == collection.id {
                meta.collectionID = nil
                metadata[id] = meta
            }
        }
        saveCollections()
        saveMetadata()
    }
    
    func addToCollection(_ item: ScreenshotItem, collectionID: UUID) {
        updateMetadata(item, collectionID: collectionID)
        if let index = collections.firstIndex(where: { $0.id == collectionID }) {
            collections[index].screenshotIDs.insert(item.id)
            saveCollections()
        }
    }
    
    func removeFromCollection(_ item: ScreenshotItem, collectionID: UUID) {
        updateMetadata(item, collectionID: nil)
        if let index = collections.firstIndex(where: { $0.id == collectionID }) {
            collections[index].screenshotIDs.remove(item.id)
            saveCollections()
        }
    }
    
    func collection(for item: ScreenshotItem) -> Collection? {
        guard let meta = metadata[item.id],
              let collectionID = meta.collectionID else { return nil }
        return collections.first { $0.id == collectionID }
    }
    
    // MARK: - Smart Folders Management
    
    func createSmartFolder(name: String, rules: [SmartFolderRule]) -> SmartFolder {
        let folder = SmartFolder(name: name, rules: rules)
        smartFolders.append(folder)
        saveSmartFolders()
        return folder
    }
    
    func updateSmartFolder(_ folder: SmartFolder, name: String? = nil, rules: [SmartFolderRule]? = nil) {
        guard let index = smartFolders.firstIndex(where: { $0.id == folder.id }) else { return }
        if let name = name {
            smartFolders[index].name = name
        }
        if let rules = rules {
            smartFolders[index].rules = rules
        }
        saveSmartFolders()
    }
    
    func deleteSmartFolder(_ folder: SmartFolder) {
        smartFolders.removeAll { $0.id == folder.id }
        saveSmartFolders()
    }
    
    func matchesSmartFolder(_ item: ScreenshotItem, folder: SmartFolder) -> Bool {
        for rule in folder.rules {
            switch rule {
            case .hasTag(let tag):
                if !tags(for: item).contains(tag) { return false }
            case .isFavorite:
                if !isFavorite(item) { return false }
            case .dateRange(let start, let end):
                if item.createdAt < start || item.createdAt > end { return false }
            case .appName(_):
                // Would need to detect app name from screenshot
                break
            case .hasNotes:
                if metadata(for: item).notes?.isEmpty != false { return false }
            case .inCollection(let collectionID):
                if metadata(for: item).collectionID != collectionID { return false }
            }
        }
        return true
    }
    
    // MARK: - Sorting
    
    func sortItems(_ items: [ScreenshotItem]) -> [ScreenshotItem] {
        switch sortOption {
        case .dateNewest:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .dateOldest:
            return items.sorted { $0.createdAt < $1.createdAt }
        case .nameAscending:
            return items.sorted { (item1: ScreenshotItem, item2: ScreenshotItem) -> Bool in
                let name1 = item1.metadata(self).customName ?? item1.filename
                let name2 = item2.metadata(self).customName ?? item2.filename
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }
        case .nameDescending:
            return items.sorted { (item1: ScreenshotItem, item2: ScreenshotItem) -> Bool in
                let name1 = item1.metadata(self).customName ?? item1.filename
                let name2 = item2.metadata(self).customName ?? item2.filename
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedDescending
            }
        case .sizeLargest:
            // Pre-compute file sizes to avoid O(n·log n) filesystem calls during sort
            let sizeCache = items.reduce(into: [URL: Int64]()) { cache, item in
                cache[item.url] = (try? FileManager.default.attributesOfItem(atPath: item.url.path)[.size] as? Int64) ?? 0
            }
            return items.sorted { (item1: ScreenshotItem, item2: ScreenshotItem) -> Bool in
                let size1 = sizeCache[item1.url] ?? 0
                let size2 = sizeCache[item2.url] ?? 0
                return size1 > size2
            }
        case .sizeSmallest:
            // Pre-compute file sizes to avoid O(n·log n) filesystem calls during sort
            let sizeCache = items.reduce(into: [URL: Int64]()) { cache, item in
                cache[item.url] = (try? FileManager.default.attributesOfItem(atPath: item.url.path)[.size] as? Int64) ?? 0
            }
            return items.sorted { (item1: ScreenshotItem, item2: ScreenshotItem) -> Bool in
                let size1 = sizeCache[item1.url] ?? 0
                let size2 = sizeCache[item2.url] ?? 0
                return size1 < size2
            }
        case .custom:
            // Custom order would require storing order preference
            return items
        }
    }
    
    // MARK: - Persistence
    
    private func load() {
        loadMetadata()
        loadCollections()
        loadSmartFolders()
        
        // Load sort option from UserDefaults
        if let raw = UserDefaults.standard.string(forKey: "sortOption"),
           let option = SortOption(rawValue: raw) {
            sortOption = option
        }
    }
    
    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([String: ScreenshotMetadata].self, from: data) else {
            metadata = [:]
            return
        }
        metadata = decoded.mapKeys { URL(fileURLWithPath: $0) }
    }
    
    private func saveMetadata() {
        let encoded = metadata.mapKeys { $0.path }
        do {
            let data = try JSONEncoder().encode(encoded)
            try data.write(to: metadataURL, options: .atomic)
            ErrorLogger.shared.debug("Metadata saved successfully")
        } catch {
            ErrorLogger.shared.logMetadataOperation(
                "Failed to save metadata",
                error: error,
                showToUser: true
            )
        }
    }
    
    private func loadCollections() {
        guard let data = try? Data(contentsOf: collectionsURL),
              let decoded = try? JSONDecoder().decode([Collection].self, from: data) else {
            collections = []
            return
        }
        collections = decoded
    }
    
    private func saveCollections() {
        do {
            let data = try JSONEncoder().encode(collections)
            try data.write(to: collectionsURL, options: .atomic)
            ErrorLogger.shared.debug("Collections saved successfully")
        } catch {
            ErrorLogger.shared.logMetadataOperation(
                "Failed to save collections",
                error: error,
                showToUser: true
            )
        }
    }
    
    private func loadSmartFolders() {
        guard let data = try? Data(contentsOf: smartFoldersURL),
              let decoded = try? JSONDecoder().decode([SmartFolder].self, from: data) else {
            smartFolders = []
            return
        }
        smartFolders = decoded
    }
    
    private func saveSmartFolders() {
        do {
            let data = try JSONEncoder().encode(smartFolders)
            try data.write(to: smartFoldersURL, options: .atomic)
            ErrorLogger.shared.debug("Smart folders saved successfully")
        } catch {
            ErrorLogger.shared.logMetadataOperation(
                "Failed to save smart folders",
                error: error,
                showToUser: true
            )
        }
    }
    
    func saveSortOption() {
        UserDefaults.standard.set(sortOption.rawValue, forKey: "sortOption")
    }
}

// MARK: - Extensions

extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        Dictionary<T, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}

extension ScreenshotItem {
    @MainActor
    func metadata(_ organization: OrganizationModel) -> ScreenshotMetadata {
        organization.metadata(for: self)
    }
}
