import AppKit
import Foundation

@MainActor
final class ScreenshotLibrary: ObservableObject {
    @Published private(set) var items: [ScreenshotItem] = []
    @Published var selectedID: ScreenshotItem.ID?
    @Published var selectedIDs: Set<ScreenshotItem.ID> = []
    @Published private(set) var contentHashes: [URL: String] = [:]
    @Published private(set) var perceptualHashes: [URL: UInt64] = [:]
    @Published private(set) var showDuplicatesOnly: Bool = false
    @Published private(set) var showNearDuplicatesOnly: Bool = false
    @Published private(set) var showSelectedOnly: Bool = false

    private var watcher: DirectoryWatcher?

    private let fileManager = FileManager.default
    private let settings: SettingsModel
    private let organization: OrganizationModel
    private var hashTask: Task<Void, Never>?
    private var perceptualHashTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    
    @Published var activeCollectionID: UUID?
    @Published var activeSmartFolderID: UUID?
    @Published var activeTagFilter: String?
    @Published var showFavoritesOnly: Bool = false
    @Published var searchQuery: String = ""

    init(settings: SettingsModel, organization: OrganizationModel) {
        self.settings = settings
        self.organization = organization
    }

    var watchedFolder: URL {
        if let bookmark = settings.watchedFolderBookmark,
           let url = BookmarkResolver.resolveFolder(from: bookmark) {
            return url
        }
        // Default: Desktop
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    func start() {
        reload()
        watcher = DirectoryWatcher(url: watchedFolder) { [weak self] in
            // Debounce reloads: cancel any pending reload and schedule a new one after a short delay
            // This helps handle macOS screenshot preview windows that keep files locked
            Task { @MainActor [weak self] in
                self?.reloadTask?.cancel()
                self?.reloadTask = Task {
                    // Wait a bit for macOS screenshot preview to finish writing/unlocking
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    if !Task.isCancelled {
                        self?.reload()
                    }
                }
            }
        }
        watcher?.start()
        
        // Listen for recording completion notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RecordingComplete"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Recording is complete and file is ready - reload immediately
            Task { @MainActor in
                ErrorLogger.shared.debug("Recording complete notification received, reloading library")
                self?.reload()
            }
        }
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        hashTask?.cancel()
        hashTask = nil
        perceptualHashTask?.cancel()
        perceptualHashTask = nil
        reloadTask?.cancel()
        reloadTask = nil
    }

    func reload() {
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: watchedFolder,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            ErrorLogger.shared.logFileOperation(
                "List directory contents",
                path: watchedFolder.path,
                error: error,
                showToUser: false
            )
            items = []
            selectedID = nil
            return
        }

        let candidates: [ScreenshotItem] = urls.compactMap { url in
            // Check if file is readable (not locked by macOS screenshot preview)
            guard fileManager.isReadableFile(atPath: url.path) else { return nil }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            let item = ScreenshotItem(id: url, url: url, createdAt: createdAt)
            guard item.isMediaFile else { return nil }
            return item
        }
        .sorted { $0.createdAt > $1.createdAt }

        let filtered = applyDateFilter(to: candidates)
        let searchFiltered = applySearchFilter(to: filtered)
        let deduped = showDuplicatesOnly ? filterDuplicates(in: searchFiltered) : searchFiltered
        let nearDeduped = showNearDuplicatesOnly ? filterNearDuplicates(in: deduped) : deduped
        let selectedFiltered = showSelectedOnly ? filterSelected(in: nearDeduped) : nearDeduped
        let favoritesFiltered = showFavoritesOnly ? filterFavorites(in: selectedFiltered) : selectedFiltered
        let collectionFiltered = applyCollectionFilter(to: favoritesFiltered)
        let smartFolderFiltered = applySmartFolderFilter(to: collectionFiltered)
        let tagFiltered = applyTagFilter(to: smartFolderFiltered)
        let sorted = organization.sortItems(tagFiltered)
        items = sorted
        if selectedID == nil, let first = candidates.first {
            selectedID = first.id
        } else if let selectedID, !candidates.contains(where: { $0.id == selectedID }) {
            self.selectedID = candidates.first?.id
        }

        kickOffHashing(for: candidates)
        kickOffPerceptualHashing(for: candidates)
    }

    func latest() -> ScreenshotItem? {
        items.first
    }

    private func applyDateFilter(to items: [ScreenshotItem]) -> [ScreenshotItem] {
        let now = Date()
        switch settings.dateFilter {
        case .all:
            return items
        case .last1h:
            let cutoff = now.addingTimeInterval(-1 * 60 * 60)
            return items.filter { $0.createdAt >= cutoff }
        case .last6h:
            let cutoff = now.addingTimeInterval(-6 * 60 * 60)
            return items.filter { $0.createdAt >= cutoff }
        case .last12h:
            let cutoff = now.addingTimeInterval(-12 * 60 * 60)
            return items.filter { $0.createdAt >= cutoff }
        case .last24h:
            let cutoff = now.addingTimeInterval(-24 * 60 * 60)
            return items.filter { $0.createdAt >= cutoff }
        case .last3d:
            let cutoff = now.addingTimeInterval(-3 * 24 * 60 * 60)
            return items.filter { $0.createdAt >= cutoff }
        case .last7d:
            let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
            return items.filter { $0.createdAt >= cutoff }
        }
    }

    func setShowDuplicatesOnly(_ on: Bool) {
        showDuplicatesOnly = on
        reload()
    }

    func setShowNearDuplicatesOnly(_ on: Bool) {
        showNearDuplicatesOnly = on
        reload()
    }

    func setShowSelectedOnly(_ on: Bool) {
        showSelectedOnly = on
        reload()
    }

    func isDuplicate(_ item: ScreenshotItem) -> Bool {
        guard let h = contentHashes[item.url] else { return false }
        let count = contentHashes.values.filter { $0 == h }.count
        return count > 1
    }

    func isNearDuplicate(_ item: ScreenshotItem) -> Bool {
        guard let ph = perceptualHashes[item.url] else { return false }
        // Check if any other item has a similar perceptual hash
        for (otherURL, otherPH) in perceptualHashes {
            if otherURL != item.url {
                let distance = PerceptualHasher.hammingDistance(ph, otherPH)
                if distance <= PerceptualHasher.nearDuplicateThreshold {
                    return true
                }
            }
        }
        return false
    }

    func nearDuplicateGroup(for item: ScreenshotItem) -> [ScreenshotItem] {
        guard let ph = perceptualHashes[item.url] else { return [] }
        var group: [ScreenshotItem] = [item]
        for (otherURL, otherPH) in perceptualHashes {
            if otherURL != item.url {
                let distance = PerceptualHasher.hammingDistance(ph, otherPH)
                if distance <= PerceptualHasher.nearDuplicateThreshold {
                    if let otherItem = items.first(where: { $0.url == otherURL }) {
                        group.append(otherItem)
                    }
                }
            }
        }
        return group.sorted { $0.createdAt > $1.createdAt }
    }

    func duplicateGroup(for item: ScreenshotItem) -> [ScreenshotItem] {
        guard let h = contentHashes[item.url] else { return [] }
        return items.filter { contentHashes[$0.url] == h }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func selectedItems() -> [ScreenshotItem] {
        // Return selected items in the same order as they appear in items
        items.filter { selectedIDs.contains($0.id) }
    }

    func selectedItemsOrdered() -> [ScreenshotItem] {
        // Return selected items sorted by creation date (newest first)
        selectedItems().sorted { $0.createdAt > $1.createdAt }
    }

    func currentSelectedIndex() -> Int? {
        guard let selectedID = selectedID,
              let ordered = selectedItemsOrdered().firstIndex(where: { $0.id == selectedID }) else {
            return nil
        }
        return ordered
    }

    func navigateToNextSelected() {
        let ordered = selectedItemsOrdered()
        guard !ordered.isEmpty else { return }
        
        if let currentIndex = currentSelectedIndex() {
            let nextIndex = (currentIndex + 1) % ordered.count
            selectedID = ordered[nextIndex].id
        } else if let first = ordered.first {
            selectedID = first.id
        }
    }

    func navigateToPreviousSelected() {
        let ordered = selectedItemsOrdered()
        guard !ordered.isEmpty else { return }
        
        if let currentIndex = currentSelectedIndex() {
            let prevIndex = currentIndex == 0 ? ordered.count - 1 : currentIndex - 1
            selectedID = ordered[prevIndex].id
        } else if let first = ordered.first {
            selectedID = first.id
        }
    }

    func saveCapturedImage(_ image: NSImage) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }

        let filename = "Capture-\(Int(Date().timeIntervalSince1970)).png"
        let url = watchedFolder.appendingPathComponent(filename)
        do {
            try pngData.write(to: url)
            reload()
            return url
        } catch {
            return nil
        }
    }

    func selectAll() {
        selectedIDs = Set(items.map(\.id))
    }

    func deselectAll() {
        selectedIDs.removeAll()
        if showSelectedOnly {
            showSelectedOnly = false
            reload()
        }
    }

    func toggleSelection(_ id: ScreenshotItem.ID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            // If we're showing selected only and just deselected the last item, turn off filter
            if showSelectedOnly && selectedIDs.isEmpty {
                showSelectedOnly = false
                reload()
            }
        } else {
            selectedIDs.insert(id)
        }
    }

    func batchDelete(_ itemsToDelete: [ScreenshotItem]) {
        let fileManager = FileManager.default
        var failedCount = 0
        for item in itemsToDelete {
            do {
                try fileManager.removeItem(at: item.url)
                selectedIDs.remove(item.id)
                contentHashes.removeValue(forKey: item.url)
                perceptualHashes.removeValue(forKey: item.url)
            } catch {
                failedCount += 1
                ErrorLogger.shared.logFileOperation(
                    "Delete file",
                    path: item.url.lastPathComponent,
                    error: error,
                    showToUser: false
                )
            }
        }
        
        if failedCount > 0 {
            Task { @MainActor in
                ErrorLogger.shared.error(
                    "Failed to delete \(failedCount) of \(itemsToDelete.count) items",
                    showToUser: true
                )
            }
        }
        
        reload()
    }

    func batchCopy(_ itemsToCopy: [ScreenshotItem]) {
        // Copy all selected images to clipboard (as files)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let urls = itemsToCopy.map(\.url)
        pasteboard.writeObjects(urls as [NSPasteboardWriting])
    }

    func keepBest(from items: [ScreenshotItem]) -> ScreenshotItem? {
        guard !items.isEmpty else { return nil }
        if items.count == 1 { return items.first }

        // Strategy: prefer highest resolution, then newest, then largest file size
        var best = items.first!
        var bestScore: (width: Int, height: Int, date: Date, size: Int64) = (0, 0, .distantPast, 0)

        for item in items {
            let attrs = try? fileManager.attributesOfItem(atPath: item.url.path)
            let size = (attrs?[.size] as? Int64) ?? 0

            // Try to get image dimensions
            var width = 0, height = 0
            if let image = NSImage(contentsOf: item.url),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                width = cgImage.width
                height = cgImage.height
            }

            let score = (width: width, height: height, date: item.createdAt, size: size)
            let pixelCount = score.width * score.height
            let bestPixelCount = bestScore.width * bestScore.height

            if pixelCount > bestPixelCount ||
               (pixelCount == bestPixelCount && score.date > bestScore.date) ||
               (pixelCount == bestPixelCount && score.date == bestScore.date && score.size > bestScore.size) {
                best = item
                bestScore = score
            }
        }

        return best
    }

    func keepBestFromSelected() {
        let selected = selectedItems()
        guard !selected.isEmpty else { return }

        // Group selected items by duplicate/near-duplicate groups
        var groups: [[ScreenshotItem]] = []
        var processed = Set<URL>()

        for item in selected {
            if processed.contains(item.url) { continue }

            // Check for exact duplicates first
            let dupGroup = duplicateGroup(for: item)
            let relevantDups = dupGroup.filter { selectedIDs.contains($0.id) }
            if relevantDups.count > 1 {
                groups.append(relevantDups)
                processed.formUnion(relevantDups.map(\.url))
                continue
            }

            // Check for near-duplicates
            let nearGroup = nearDuplicateGroup(for: item)
            let relevantNear = nearGroup.filter { selectedIDs.contains($0.id) }
            if relevantNear.count > 1 {
                groups.append(relevantNear)
                processed.formUnion(relevantNear.map(\.url))
                continue
            }

            // Standalone item
            groups.append([item])
            processed.insert(item.url)
        }

        // For each group, keep the best and delete the rest
        var toDelete: [ScreenshotItem] = []
        for group in groups {
            guard let best = keepBest(from: group) else { continue }
            let others = group.filter { $0.id != best.id }
            toDelete.append(contentsOf: others)
        }

        if !toDelete.isEmpty {
            batchDelete(toDelete)
        }
    }

    private func filterDuplicates(in items: [ScreenshotItem]) -> [ScreenshotItem] {
        // Only include items with a hash that appears more than once.
        // Items without a hash yet are excluded until hashing finishes.
        var counts: [String: Int] = [:]
        for (_, h) in contentHashes {
            counts[h, default: 0] += 1
        }
        return items.filter { item in
            guard let h = contentHashes[item.url] else { return false }
            return (counts[h] ?? 0) > 1
        }
    }

    private func filterNearDuplicates(in items: [ScreenshotItem]) -> [ScreenshotItem] {
        // Only include items that have at least one near-duplicate.
        // Items without a perceptual hash yet are excluded until hashing finishes.
        return items.filter { item in
            isNearDuplicate(item)
        }
    }

    private func filterSelected(in items: [ScreenshotItem]) -> [ScreenshotItem] {
        // Only include items that are in the selectedIDs set.
        return items.filter { selectedIDs.contains($0.id) }
    }
    
    private func applyCollectionFilter(to items: [ScreenshotItem]) -> [ScreenshotItem] {
        guard let collectionID = activeCollectionID else { return items }
        return items.filter { organization.metadata(for: $0).collectionID == collectionID }
    }
    
    private func applySmartFolderFilter(to items: [ScreenshotItem]) -> [ScreenshotItem] {
        guard let smartFolderID = activeSmartFolderID,
              let folder = organization.smartFolders.first(where: { $0.id == smartFolderID }) else {
            return items
        }
        return items.filter { organization.matchesSmartFolder($0, folder: folder) }
    }
    
    private func applyTagFilter(to items: [ScreenshotItem]) -> [ScreenshotItem] {
        guard let tag = activeTagFilter else { return items }
        return items.filter { organization.tags(for: $0).contains(tag) }
    }
    
    private func filterFavorites(in items: [ScreenshotItem]) -> [ScreenshotItem] {
        return items.filter { organization.isFavorite($0) }
    }
    
    private func applySearchFilter(to items: [ScreenshotItem]) -> [ScreenshotItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        
        let lowercasedQuery = query.lowercased()
        return items.filter { item in
            // Search in filename
            if item.filename.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            // Search in tags
            let tags = organization.tags(for: item)
            if tags.contains(where: { $0.lowercased().contains(lowercasedQuery) }) {
                return true
            }
            
            // Search in notes
            if let notes = organization.metadata(for: item).notes,
               notes.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            return false
        }
    }
    
    func setActiveCollection(_ collectionID: UUID?) {
        activeCollectionID = collectionID
        activeSmartFolderID = nil
        activeTagFilter = nil
        reload()
    }
    
    func setActiveSmartFolder(_ folderID: UUID?) {
        activeSmartFolderID = folderID
        activeCollectionID = nil
        activeTagFilter = nil
        reload()
    }
    
    func setActiveTag(_ tag: String?) {
        activeTagFilter = tag
        activeCollectionID = nil
        activeSmartFolderID = nil
        reload()
    }
    
    func clearFilters() {
        activeCollectionID = nil
        activeSmartFolderID = nil
        activeTagFilter = nil
        showFavoritesOnly = false
        reload()
    }
    
    func setShowFavoritesOnly(_ value: Bool) {
        showFavoritesOnly = value
        if value {
            activeCollectionID = nil
            activeSmartFolderID = nil
            activeTagFilter = nil
        }
        reload()
    }

    private func kickOffHashing(for items: [ScreenshotItem]) {
        let urlsToHash = items
            .map(\.url)
            .filter { contentHashes[$0] == nil }

        guard !urlsToHash.isEmpty else { return }

        // Cancel any existing hashing run and start a new one.
        hashTask?.cancel()
        hashTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            var newlyComputed: [URL: String] = [:]
            newlyComputed.reserveCapacity(urlsToHash.count)

            for url in urlsToHash {
                if Task.isCancelled { return }
                do {
                    let h = try FileHasher.sha256Hex(of: url)
                    newlyComputed[url] = h
                } catch {
                    // Ignore hashing failures for now.
                }
            }

            if Task.isCancelled { return }

            let snapshot = newlyComputed

            await MainActor.run {
                for (url, h) in snapshot {
                    self.contentHashes[url] = h
                }
                if self.showDuplicatesOnly || self.showNearDuplicatesOnly {
                    self.reload()
                }
            }
        }
    }

    private func kickOffPerceptualHashing(for items: [ScreenshotItem]) {
        let urlsToHash = items
            .map(\.url)
            .filter { perceptualHashes[$0] == nil }

        guard !urlsToHash.isEmpty else { return }

        // Cancel any existing perceptual hashing run and start a new one.
        perceptualHashTask?.cancel()
        perceptualHashTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            var newlyComputed: [URL: UInt64] = [:]
            newlyComputed.reserveCapacity(urlsToHash.count)

            for url in urlsToHash {
                if Task.isCancelled { return }
                if let ph = PerceptualHasher.dHash(for: url) {
                    newlyComputed[url] = ph
                }
            }

            if Task.isCancelled { return }

            let snapshot = newlyComputed

            await MainActor.run {
                for (url, ph) in snapshot {
                    self.perceptualHashes[url] = ph
                }
                if self.showNearDuplicatesOnly {
                    self.reload()
                }
            }
        }
    }
}

