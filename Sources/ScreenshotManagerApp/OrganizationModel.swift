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

// MARK: - Smart Folder Match Mode

enum SmartFolderMatchMode: String, Codable, CaseIterable {
    case all = "all"   // AND: Must match ALL rules
    case any = "any"   // OR: Must match ANY rule
    
    var label: String {
        switch self {
        case .all: return "All rules (AND)"
        case .any: return "Any rule (OR)"
        }
    }
}

struct SmartFolder: Codable, Identifiable {
    let id: UUID
    var name: String
    var rules: [SmartFolderRule]
    var matchMode: SmartFolderMatchMode
    var icon: String?
    var createdAt: Date
    
    init(id: UUID = UUID(), name: String, rules: [SmartFolderRule] = [], matchMode: SmartFolderMatchMode = .all, icon: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.rules = rules
        self.matchMode = matchMode
        self.icon = icon
        self.createdAt = createdAt
    }
    
    // Migration: provide default for older saved data without matchMode
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        rules = try container.decode([SmartFolderRule].self, forKey: .rules)
        matchMode = try container.decodeIfPresent(SmartFolderMatchMode.self, forKey: .matchMode) ?? .all
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

// MARK: - Smart Folder Rule Categories

enum SmartFolderRuleCategory: String, CaseIterable, Identifiable {
    case date = "Date"
    case tag = "Tag"
    case status = "Status"
    case fileType = "File Type"
    case size = "Size"
    case filename = "Filename"
    case notes = "Notes"
    case collection = "Collection"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .date: return "calendar"
        case .tag: return "tag"
        case .status: return "star"
        case .fileType: return "doc"
        case .size: return "externaldrive"
        case .filename: return "textformat"
        case .notes: return "note.text"
        case .collection: return "folder"
        }
    }
}

enum SmartFolderRule: Codable, Identifiable, Hashable {
    // --- Tag Rules ---
    case hasTag(String)
    case hasAnyTag([String])           // Match ANY of these tags
    case hasAllTags([String])          // Must have ALL tags
    case hasNoTags                     // No tags assigned
    
    // --- Favorite/Status ---
    case isFavorite
    case isNotFavorite
    
    // --- Date Rules ---
    case dateRange(start: Date, end: Date)
    case dateWithinLast(days: Int)     // Last N days
    case dateOlderThan(days: Int)      // Older than N days
    case dateToday
    case dateThisWeek
    case dateThisMonth
    case dateThisYear
    
    // --- File Type Rules ---
    case isImage
    case isVideo
    case fileExtension(String)         // Specific extension (png, jpg, etc.)
    
    // --- Size Rules ---
    case sizeGreaterThan(bytes: Int64)
    case sizeLessThan(bytes: Int64)
    
    // --- Name/Content Rules ---
    case filenameContains(String)      // Filename contains text
    case filenameStartsWith(String)
    case filenameEndsWith(String)
    case filenameMatches(String)       // Regex pattern
    
    // --- Notes/Metadata ---
    case hasNotes
    case hasNoNotes
    case notesContain(String)
    case hasCustomName
    case hasNoCustomName
    
    // --- Collection Rules ---
    case inCollection(UUID)
    case inAnyCollection               // Belongs to any collection
    case notInCollection               // Not in any collection
    
    // --- App/Source ---
    case appName(String)
    
    // MARK: - Identifiable
    
    var id: String {
        switch self {
        case .hasTag(let tag): return "hasTag-\(tag)"
        case .hasAnyTag(let tags): return "hasAnyTag-\(tags.joined(separator: ","))"
        case .hasAllTags(let tags): return "hasAllTags-\(tags.joined(separator: ","))"
        case .hasNoTags: return "hasNoTags"
        case .isFavorite: return "isFavorite"
        case .isNotFavorite: return "isNotFavorite"
        case .dateRange(let start, let end): return "dateRange-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
        case .dateWithinLast(let days): return "dateWithinLast-\(days)"
        case .dateOlderThan(let days): return "dateOlderThan-\(days)"
        case .dateToday: return "dateToday"
        case .dateThisWeek: return "dateThisWeek"
        case .dateThisMonth: return "dateThisMonth"
        case .dateThisYear: return "dateThisYear"
        case .isImage: return "isImage"
        case .isVideo: return "isVideo"
        case .fileExtension(let ext): return "fileExtension-\(ext)"
        case .sizeGreaterThan(let bytes): return "sizeGreaterThan-\(bytes)"
        case .sizeLessThan(let bytes): return "sizeLessThan-\(bytes)"
        case .filenameContains(let text): return "filenameContains-\(text)"
        case .filenameStartsWith(let text): return "filenameStartsWith-\(text)"
        case .filenameEndsWith(let text): return "filenameEndsWith-\(text)"
        case .filenameMatches(let pattern): return "filenameMatches-\(pattern)"
        case .hasNotes: return "hasNotes"
        case .hasNoNotes: return "hasNoNotes"
        case .notesContain(let text): return "notesContain-\(text)"
        case .hasCustomName: return "hasCustomName"
        case .hasNoCustomName: return "hasNoCustomName"
        case .inCollection(let uuid): return "inCollection-\(uuid.uuidString)"
        case .inAnyCollection: return "inAnyCollection"
        case .notInCollection: return "notInCollection"
        case .appName(let name): return "appName-\(name)"
        }
    }
    
    // MARK: - Category
    
    var category: SmartFolderRuleCategory {
        switch self {
        case .hasTag, .hasAnyTag, .hasAllTags, .hasNoTags:
            return .tag
        case .isFavorite, .isNotFavorite:
            return .status
        case .dateRange, .dateWithinLast, .dateOlderThan, .dateToday, .dateThisWeek, .dateThisMonth, .dateThisYear:
            return .date
        case .isImage, .isVideo, .fileExtension:
            return .fileType
        case .sizeGreaterThan, .sizeLessThan:
            return .size
        case .filenameContains, .filenameStartsWith, .filenameEndsWith, .filenameMatches:
            return .filename
        case .hasNotes, .hasNoNotes, .notesContain, .hasCustomName, .hasNoCustomName:
            return .notes
        case .inCollection, .inAnyCollection, .notInCollection:
            return .collection
        case .appName:
            return .status
        }
    }
    
    // MARK: - Display
    
    var displayLabel: String {
        switch self {
        case .hasTag(let tag): return "Has tag: \(tag)"
        case .hasAnyTag(let tags): return "Has any tag: \(tags.joined(separator: ", "))"
        case .hasAllTags(let tags): return "Has all tags: \(tags.joined(separator: ", "))"
        case .hasNoTags: return "Has no tags"
        case .isFavorite: return "Is favorite"
        case .isNotFavorite: return "Is not favorite"
        case .dateRange(let start, let end): 
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return "Date between \(formatter.string(from: start)) and \(formatter.string(from: end))"
        case .dateWithinLast(let days): return "Within last \(days) days"
        case .dateOlderThan(let days): return "Older than \(days) days"
        case .dateToday: return "Created today"
        case .dateThisWeek: return "Created this week"
        case .dateThisMonth: return "Created this month"
        case .dateThisYear: return "Created this year"
        case .isImage: return "Is image"
        case .isVideo: return "Is video"
        case .fileExtension(let ext): return "Extension: .\(ext)"
        case .sizeGreaterThan(let bytes): return "Larger than \(formatBytes(bytes))"
        case .sizeLessThan(let bytes): return "Smaller than \(formatBytes(bytes))"
        case .filenameContains(let text): return "Filename contains: \(text)"
        case .filenameStartsWith(let text): return "Filename starts with: \(text)"
        case .filenameEndsWith(let text): return "Filename ends with: \(text)"
        case .filenameMatches(let pattern): return "Filename matches: \(pattern)"
        case .hasNotes: return "Has notes"
        case .hasNoNotes: return "Has no notes"
        case .notesContain(let text): return "Notes contain: \(text)"
        case .hasCustomName: return "Has custom name"
        case .hasNoCustomName: return "Has no custom name"
        case .inCollection(let uuid): return "In collection: \(uuid.uuidString.prefix(8))..."
        case .inAnyCollection: return "In any collection"
        case .notInCollection: return "Not in any collection"
        case .appName(let name): return "App: \(name)"
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
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
    
    // Debounce tasks
    private var metadataSaveTask: Task<Void, Never>?
    private var collectionsSaveTask: Task<Void, Never>?
    private var smartFoldersSaveTask: Task<Void, Never>?
    
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
            
            // Normalize imported keys: support both absolute URL strings and file system paths
            for (keyString, value) in export.metadata {
                let urlKey: URL?
                if let candidate = URL(string: keyString), candidate.scheme != nil {
                    // Likely an absolute URL string (e.g., file://)
                    urlKey = candidate
                } else {
                    // Treat as a file system path
                    urlKey = URL(fileURLWithPath: keyString)
                }
                if let urlKey {
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
    
    func createSmartFolder(name: String, rules: [SmartFolderRule], matchMode: SmartFolderMatchMode = .all, icon: String? = nil) -> SmartFolder {
        let folder = SmartFolder(name: name, rules: rules, matchMode: matchMode, icon: icon)
        smartFolders.append(folder)
        saveSmartFolders()
        return folder
    }
    
    func updateSmartFolder(_ folder: SmartFolder, name: String? = nil, rules: [SmartFolderRule]? = nil, matchMode: SmartFolderMatchMode? = nil, icon: String? = nil) {
        guard let index = smartFolders.firstIndex(where: { $0.id == folder.id }) else { return }
        if let name = name {
            smartFolders[index].name = name
        }
        if let rules = rules {
            smartFolders[index].rules = rules
        }
        if let matchMode = matchMode {
            smartFolders[index].matchMode = matchMode
        }
        if let icon = icon {
            smartFolders[index].icon = icon
        }
        saveSmartFolders()
    }
    
    func deleteSmartFolder(_ folder: SmartFolder) {
        smartFolders.removeAll { $0.id == folder.id }
        saveSmartFolders()
    }
    
    func matchesSmartFolder(_ item: ScreenshotItem, folder: SmartFolder) -> Bool {
        guard !folder.rules.isEmpty else { return true }
        
        let results = folder.rules.map { matchesRule(item, rule: $0) }
        
        switch folder.matchMode {
        case .all:
            return results.allSatisfy { $0 }
        case .any:
            return results.contains { $0 }
        }
    }
    
    private func matchesRule(_ item: ScreenshotItem, rule: SmartFolderRule) -> Bool {
        let meta = metadata(for: item)
        let itemTags = tags(for: item)
        
        switch rule {
        // --- Tag Rules ---
        case .hasTag(let tag):
            return itemTags.contains(tag)
        case .hasAnyTag(let requiredTags):
            return !itemTags.isDisjoint(with: Set(requiredTags))
        case .hasAllTags(let requiredTags):
            return Set(requiredTags).isSubset(of: itemTags)
        case .hasNoTags:
            return itemTags.isEmpty
            
        // --- Favorite/Status ---
        case .isFavorite:
            return isFavorite(item)
        case .isNotFavorite:
            return !isFavorite(item)
            
        // --- Date Rules ---
        case .dateRange(let start, let end):
            return item.createdAt >= start && item.createdAt <= end
        case .dateWithinLast(let days):
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            return item.createdAt >= cutoff
        case .dateOlderThan(let days):
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            return item.createdAt < cutoff
        case .dateToday:
            return Calendar.current.isDateInToday(item.createdAt)
        case .dateThisWeek:
            return Calendar.current.isDate(item.createdAt, equalTo: Date(), toGranularity: .weekOfYear)
        case .dateThisMonth:
            return Calendar.current.isDate(item.createdAt, equalTo: Date(), toGranularity: .month)
        case .dateThisYear:
            return Calendar.current.isDate(item.createdAt, equalTo: Date(), toGranularity: .year)
            
        // --- File Type Rules ---
        case .isImage:
            return item.isLikelyScreenshotImage
        case .isVideo:
            return item.isVideo
        case .fileExtension(let ext):
            return item.fileExtension.lowercased() == ext.lowercased()
            
        // --- Size Rules ---
        case .sizeGreaterThan(let bytes):
            guard let size = fileSize(for: item) else { return false }
            return size > bytes
        case .sizeLessThan(let bytes):
            guard let size = fileSize(for: item) else { return false }
            return size < bytes
            
        // --- Name/Content Rules ---
        case .filenameContains(let text):
            return item.filename.localizedCaseInsensitiveContains(text)
        case .filenameStartsWith(let text):
            return item.filename.lowercased().hasPrefix(text.lowercased())
        case .filenameEndsWith(let text):
            // Remove extension first for proper matching
            let nameWithoutExt = (item.filename as NSString).deletingPathExtension
            return nameWithoutExt.lowercased().hasSuffix(text.lowercased())
        case .filenameMatches(let pattern):
            return matchesRegex(item.filename, pattern: pattern)
            
        // --- Notes/Metadata ---
        case .hasNotes:
            return !(meta.notes?.isEmpty ?? true)
        case .hasNoNotes:
            return meta.notes?.isEmpty ?? true
        case .notesContain(let text):
            return meta.notes?.localizedCaseInsensitiveContains(text) ?? false
        case .hasCustomName:
            return !(meta.customName?.isEmpty ?? true)
        case .hasNoCustomName:
            return meta.customName?.isEmpty ?? true
            
        // --- Collection Rules ---
        case .inCollection(let collectionID):
            return meta.collectionID == collectionID
        case .inAnyCollection:
            return meta.collectionID != nil
        case .notInCollection:
            return meta.collectionID == nil
            
        // --- App/Source ---
        case .appName(_):
            // Would need to detect app name from screenshot - not implemented yet
            return true
        }
    }
    
    private func fileSize(for item: ScreenshotItem) -> Int64? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: item.url.path)
            return attrs[.size] as? Int64
        } catch {
            return nil
        }
    }
    
    private func matchesRegex(_ text: String, pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        } catch {
            return false
        }
    }
    
    /// Get the count of items matching a smart folder's rules (for preview)
    func countMatchingItems(_ items: [ScreenshotItem], folder: SmartFolder) -> Int {
        items.filter { matchesSmartFolder($0, folder: folder) }.count
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
    
    /// Load metadata keys as absolute URL strings for consistency.
    /// Fallback to file paths if string is not a valid URL.
    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([String: ScreenshotMetadata].self, from: data) else {
            metadata = [:]
            return
        }
        // Keys are stored as absolute URL strings (e.g., file://...) for consistency
        var rebuilt: [URL: ScreenshotMetadata] = [:]
        for (key, value) in decoded {
            if let url = URL(string: key) {
                rebuilt[url] = value
            } else {
                // Fallback: treat as file path if string isn't a valid URL
                rebuilt[URL(fileURLWithPath: key)] = value
            }
        }
        metadata = rebuilt
    }
    
    /// Save metadata keys as absolute URL strings for consistency across save/load/export/import
    private func saveMetadata() {
        metadataSaveTask?.cancel()
        metadataSaveTask = Task {
            // Debounce: wait 0.5s before saving
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            
            // Persist keys as absolute URL strings for consistency across save/load/export/import
            let encoded: [String: ScreenshotMetadata] = metadata.reduce(into: [:]) { dict, pair in
                dict[pair.key.absoluteString] = pair.value
            }
            
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
        collectionsSaveTask?.cancel()
        collectionsSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            
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
        smartFoldersSaveTask?.cancel()
        smartFoldersSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            
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
