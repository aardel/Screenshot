import AppKit
import AVKit
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: ScreenshotLibrary
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var organization: OrganizationModel
    @State private var showDeleteConfirmation = false
    @State private var showBatchCollectionPicker = false
    @State private var showBatchTagEditor = false
    @State private var showPDFEditor = false
    
    var body: some View {
        NavigationSplitView {
            OrganizationSidebar()
                .environmentObject(library)
                .environmentObject(organization)
                .frame(minWidth: 200)
        } content: {
            TimelineGridView()
                .environmentObject(library)
                .environmentObject(organization)
        } detail: {
            DetailPane(showPDFEditor: $showPDFEditor)
                .environmentObject(organization)
        }
        .navigationTitle("Library")
        .onAppear {
            // Ensure cursor is visible when view appears
            NSCursor.unhide()
            NSCursor.arrow.set()
            // Make window key
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.isVisible && !($0 is SelectionWindow) && !($0 is CaptureMenuWindow) && !($0 is RecordingIndicatorWindow) && !($0 is WindowBorderOverlay) }) {
                    window.makeKey()
                    // Don't call makeMain() - it's set automatically when window becomes key
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Restore cursor when app becomes active (e.g., after permission dialogs)
            DispatchQueue.main.async {
                NSCursor.unhide()
                NSCursor.arrow.set()
                // Make sure main window is key
                if let window = NSApp.windows.first(where: { $0.isVisible && !($0 is SelectionWindow) && !($0 is CaptureMenuWindow) }) {
                    window.makeKey()
                    // Don't call makeMain() - it's set automatically when window becomes key
                }
            }
        }
        .toolbar {
            // MARK: - Search Field
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Search...", text: $library.searchQuery)
                        .textFieldStyle(.plain)
                        .frame(width: 180)
                    if !library.searchQuery.isEmpty {
                        Button(action: { library.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .controlSize(.small)
                .frame(height: 26)
            }

            // MARK: - Date Filter
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 0) {
                    Picker("Date", selection: Binding<SettingsModel.DateFilter?>(
                        get: { settings.dateFilter },
                        set: { newValue in
                            if let val = newValue {
                                settings.dateFilter = val
                            }
                        }
                    )) {
                        Text("All").tag(SettingsModel.DateFilter.all as SettingsModel.DateFilter?)
                        Text("24h").tag(SettingsModel.DateFilter.last24h as SettingsModel.DateFilter?)
                        Text("7d").tag(SettingsModel.DateFilter.last7d as SettingsModel.DateFilter?)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .padding(.trailing, 6)

                    Menu {
                        ForEach(SettingsModel.DateFilter.allCases) { f in
                            Button(f.label) { settings.dateFilter = f }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                    .padding(.trailing, 6)
                }
            }

            // MARK: - Duplicates Filter
            ToolbarItem(placement: .automatic) {
                Picker("", selection: Binding(
                    get: {
                        if library.showDuplicatesOnly { return 1 }
                        if library.showNearDuplicatesOnly { return 2 }
                        return 0
                    },
                    set: { value in
                        library.setShowDuplicatesOnly(value == 1)
                        library.setShowNearDuplicatesOnly(value == 2)
                    }
                )) {
                    Text("All").tag(0)
                    Text("Duplicates").tag(1)
                    Text("Near Dupes").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .padding(.horizontal, 4)
            }
            
            // MARK: - Utility Actions
            ToolbarItem(placement: .automatic) {
                let multiple = library.selectedIDs.count > 1
                
                Picker("Utility", selection: Binding<String?>(
                    get: { nil },
                    set: { value in
                        guard let value else { return }
                        switch value {
                        case "refresh":
                            library.reload()
                        case "best":
                            library.keepBestFromSelected()
                        case "batch":
                            showBatchCollectionPicker = true
                        default:
                            break
                        }
                    }
                )) {
                    Label("Refresh", systemImage: "arrow.clockwise").tag("refresh" as String?)
                    if multiple {
                        Label("Best", systemImage: "wand.and.stars").tag("best" as String?)
                        Label("Batch", systemImage: "ellipsis.circle").tag("batch" as String?)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: multiple ? 120 : 40)
            }

            // MARK: - Selection Status
            ToolbarItem(placement: .automatic) {
                if !library.selectedIDs.isEmpty {
                    StatusPill(text: "\(library.selectedIDs.count) selected")
                }
            }
        }
        .onChange(of: settings.dateFilter) { _ in
            library.reload()
        }
        .onChange(of: library.searchQuery) { _ in
            library.reload()
        }
        .onDeleteCommand {
            deleteSelected()
        }
        // Hidden buttons for keyboard shortcuts
        .background(
            VStack {
                Button("") { library.selectAll() }.keyboardShortcut("a", modifiers: .command).hidden()
                Button("") { library.deselectAll() }.keyboardShortcut("d", modifiers: .command).hidden()
                Button("") { library.deselectAll() }.keyboardShortcut(.escape, modifiers: []).hidden()
                Button("") { toggleFavoriteForSelected() }.keyboardShortcut("f", modifiers: .command).hidden()
                Button("") { quickLookSelected() }.keyboardShortcut(.space, modifiers: []).hidden()
            }
        )
        .sheet(isPresented: $showBatchCollectionPicker) {
            BatchCollectionPickerSheet(items: library.selectedItems(), isPresented: $showBatchCollectionPicker)
                .environmentObject(organization)
        }
        .sheet(isPresented: $showBatchTagEditor) {
            BatchTagEditorSheet(items: library.selectedItems(), isPresented: $showBatchTagEditor)
                .environmentObject(organization)
        }
        .onChange(of: showPDFEditor) { newValue in
            if newValue {
                showPDFEditorWindow(items: library.selectedItems())
            }
        }
    }

    private var selectedItem: ScreenshotItem? {
        guard let id = library.selectedID else { return nil }
        return library.items.first(where: { $0.id == id })
    }

    private func deleteSelected() {
        let selected = library.selectedItems()
        guard !selected.isEmpty else { return }
        library.batchDelete(selected)
    }
    
    private func toggleFavoriteForSelected() {
        let selected = library.selectedItems()
        guard !selected.isEmpty else { return }
        organization.batchToggleFavorites(selected)
        library.reload()
    }
    
    private func quickLookSelected() {
        guard let item = selectedItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
    
    private func exportSelectedScreenshots() {
        let selected = library.selectedItems()
        guard !selected.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Export Screenshots"
        panel.message = "Choose a folder to export \(selected.count) screenshots"

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        var successCount = 0
        var failedItems: [String] = []

        for item in selected {
            let destination = folder.appendingPathComponent(item.filename)
            do {
                // If file already exists, create unique name
                var finalDestination = destination
                var counter = 1
                while FileManager.default.fileExists(atPath: finalDestination.path) {
                    let name = destination.deletingPathExtension().lastPathComponent
                    let ext = destination.pathExtension
                    finalDestination = folder.appendingPathComponent("\(name)_\(counter).\(ext)")
                    counter += 1
                }
                try FileManager.default.copyItem(at: item.url, to: finalDestination)
                successCount += 1
            } catch {
                failedItems.append(item.filename)
                print("Export failed for \(item.filename): \(error.localizedDescription)")
            }
        }

        if !failedItems.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Export Partially Complete"
            alert.informativeText = "Exported \(successCount) of \(selected.count) screenshots.\n\nFailed items:\n\(failedItems.prefix(5).joined(separator: "\n"))\(failedItems.count > 5 ? "\n...and \(failedItems.count - 5) more" : "")"
            alert.alertStyle = .warning
            alert.runModal()
        }

        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
    
    private func showPDFEditorWindow(items: [ScreenshotItem]) {
        let contentView = PDFEditorView(items: items, isPresented: $showPDFEditor)
            .environmentObject(organization)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        
        let screenFrame = NSScreen.main?.frame ?? .zero
        let windowRect = NSRect(
            x: screenFrame.midX - 800,
            y: screenFrame.midY - 500,
            width: 1600,
            height: 1000
        )
        
        let window = PDFEditorWindowClass(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "PDF Editor"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.level = .floating  // Keep above main window to prevent focus stealing
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true

        // Minimize the main window so it doesn't compete for focus
        if let mainWindow = NSApp.windows.first(where: { $0.title != "PDF Editor" && $0.isVisible && $0.canBecomeMain }) {
            mainWindow.miniaturize(nil)
        }

        // Make window key, main, and visible so it properly receives focus
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSApp.activate(ignoringOtherApps: true)

        window.onClose = {
            showPDFEditor = false
            // Restore the main window when PDF editor closes
            for win in NSApp.windows where win.isMiniaturized && win.title != "PDF Editor" {
                win.deminiaturize(nil)
            }
        }
    }
}

private struct TimelineGridView: View {
    @EnvironmentObject var library: ScreenshotLibrary
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var organization: OrganizationModel
    @State private var showTagEditorForItem: ScreenshotItem?
    @State private var showCollectionPickerForItem: ScreenshotItem?
    
    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: settings.thumbnailSize.minWidth, maximum: settings.thumbnailSize.maxWidth), spacing: 12, alignment: .top)
        ]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                // Thumbnail Size Control
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                                .foregroundStyle(.secondary)
                            Text("Thumbnail Size")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Picker("", selection: $settings.thumbnailSize) {
                            ForEach(SettingsModel.ThumbnailSize.allCases) { size in
                                Text(size.label).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                }
                
                // Show Selected Only filter
                if !library.selectedIDs.isEmpty {
                    Section {
                        HStack {
                            Button(action: {
                                library.setShowSelectedOnly(!library.showSelectedOnly)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: library.showSelectedOnly ? "checkmark.circle.fill" : "circle")
                                    Text("Show Selected Only (\(library.selectedIDs.count))")
                                        .font(.subheadline)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                    }
                }
                
                ForEach(sections, id: \.day) { section in
                    Section {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(section.items) { item in
                                ScreenshotCard(
                                    item: item,
                                    isSelected: item.id == library.selectedID,
                                    isMultiSelected: library.selectedIDs.contains(item.id),
                                    isDuplicate: library.isDuplicate(item),
                                    isNearDuplicate: library.isNearDuplicate(item),
                                    organization: organization
                                )
                                    .onTapGesture {
                                        handleTap(item: item)
                                    }
                                    .onDrag {
                                        let provider = NSItemProvider(object: item.url as NSURL)
                                        return provider
                                    }
                                    .contextMenu {
                                        Button("Select") {
                                            library.toggleSelection(item.id)
                                        }
                                        Divider()
                                        Button("Copy Image") { ClipboardActions.copyImage(from: item.url) }
                                        Button("Print") { PrintActions.printImage(at: item.url) }
                                        Divider()
                                        Button("Share") {
                                            ShareActions.share(items: [item.url])
                                        }
                                        Divider()
                                        // Organization options
                                        Button(action: {
                                            let selectedItems = library.selectedItems()
                                            if selectedItems.count > 1 && selectedItems.contains(where: { $0.id == item.id }) {
                                                organization.batchToggleFavorites(selectedItems)
                                            } else {
                                                organization.toggleFavorite(item)
                                            }
                                            library.reload()
                                        }) {
                                            favoritesButtonLabel(for: item)
                                        }
                                        Button("Edit Tags...") {
                                            showTagEditorForItem = item
                                        }
                                        Menu("Add to Collection") {
                                            if organization.collections.isEmpty {
                                                Text("No collections")
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                ForEach(organization.collections) { collection in
                                                    Button(action: {
                                                        if organization.collection(for: item)?.id == collection.id {
                                                            organization.removeFromCollection(item, collectionID: collection.id)
                                                        } else {
                                                            organization.addToCollection(item, collectionID: collection.id)
                                                        }
                                                        library.reload()
                                                    }) {
                                                        HStack {
                                                            Circle()
                                                                .fill(Color(hex: collection.color))
                                                                .frame(width: 8, height: 8)
                                                            Text(collection.name)
                                                            if organization.collection(for: item)?.id == collection.id {
                                                                Spacer()
                                                                Image(systemName: "checkmark")
                                                                    .foregroundColor(.accentColor)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Divider()
                                        Button("Copy File Path") { ClipboardActions.copyFilePath(item.url) }
                                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            library.batchDelete([item])
                                            if library.selectedID == item.id {
                                                library.selectedID = library.items.first?.id
                                            }
                                        }
                                        if library.isDuplicate(item) || library.isNearDuplicate(item) {
                                            Divider()
                                            Button("Select Group") {
                                                selectGroup(for: item)
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 12)
                    } header: {
                        HStack {
                            Text(section.title)
                                .font(.headline)
                            Spacer()
                            Text("\(section.items.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if library.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No screenshots found")
                        .font(.headline)
                    Text("Take a screenshot, or choose a watched folder in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private struct DaySection {
        let day: Date
        let title: String
        let items: [ScreenshotItem]
    }

    private var sections: [DaySection] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: library.items) { item in
            cal.startOfDay(for: item.createdAt)
        }
        return groups
            .map { (day, items) in
                DaySection(
                    day: day,
                    title: day.formatted(date: .abbreviated, time: .omitted),
                    items: items.sorted { $0.createdAt > $1.createdAt }
                )
            }
            .sorted { $0.day > $1.day }
    }

    private func handleTap(item: ScreenshotItem) {
        // Check for modifier keys
        let event = NSApp.currentEvent
        let isCommandPressed = event?.modifierFlags.contains(.command) == true
        let isShiftPressed = event?.modifierFlags.contains(.shift) == true

        if isCommandPressed {
            // Cmd+click: toggle selection (macOS Finder behavior)
            library.toggleSelection(item.id)
            library.selectedID = item.id
        } else if isShiftPressed {
            // Shift+click: range selection (macOS Finder behavior)
            // Keep existing selections and add range
            if let currentID = library.selectedID,
               let currentIndex = library.items.firstIndex(where: { $0.id == currentID }),
               let clickedIndex = library.items.firstIndex(where: { $0.id == item.id }) {
                let start = min(currentIndex, clickedIndex)
                let end = max(currentIndex, clickedIndex)
                for i in start...end {
                    library.selectedIDs.insert(library.items[i].id)
                }
            } else {
                // If no current selection, just select this item
                library.selectedIDs = [item.id]
            }
            library.selectedID = item.id
        } else {
            // Regular click: clear all selections and select only this item (macOS Finder behavior)
            library.selectedIDs = [item.id]
            library.selectedID = item.id
        }
    }

    private func favoritesButtonLabel(for item: ScreenshotItem) -> some View {
        let selectedItems = library.selectedItems()
        let isMultiSelect = selectedItems.count > 1 && selectedItems.contains(where: { $0.id == item.id })
        
        if isMultiSelect {
            let allFavorited = selectedItems.allSatisfy { organization.isFavorite($0) }
            let labelText = allFavorited ? "Remove from Favorites (\(selectedItems.count))" : "Add to Favorites (\(selectedItems.count))"
            let iconName = allFavorited ? "star.fill" : "star"
            return Label(labelText, systemImage: iconName)
        } else {
            let labelText = organization.isFavorite(item) ? "Remove from Favorites" : "Add to Favorites"
            let iconName = organization.isFavorite(item) ? "star.fill" : "star"
            return Label(labelText, systemImage: iconName)
        }
    }

    private func selectGroup(for item: ScreenshotItem) {
        // Select all items in the duplicate or near-duplicate group
        let dupGroup = library.duplicateGroup(for: item)
        if dupGroup.count > 1 {
            library.selectedIDs.formUnion(dupGroup.map(\.id))
            library.selectedID = item.id
            return
        }
        let nearGroup = library.nearDuplicateGroup(for: item)
        if nearGroup.count > 1 {
            library.selectedIDs.formUnion(nearGroup.map(\.id))
            library.selectedID = item.id
        }
    }
}

private struct ScreenshotCard: View {
    let item: ScreenshotItem
    let isSelected: Bool
    let isMultiSelected: Bool
    let isDuplicate: Bool
    let isNearDuplicate: Bool
    @ObservedObject var organization: OrganizationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ThumbnailView(item: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(height: 160)
                    .clipped()
                
                // Badges overlay - positioned absolutely
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if isDuplicate {
                            Badge(text: "DUP", color: .red)
                        }
                        if isNearDuplicate {
                            Badge(text: "NEAR", color: .orange)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
                .allowsHitTesting(false)
                
                // Organization indicators overlay - positioned at top-right
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Spacer()
                        if organization.isFavorite(item) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.yellow)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                .transition(.scale.combined( with: .opacity))
                        }
                        if !organization.tags(for: item).isEmpty {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                .transition(.scale.combined(with: .opacity))
                        }
                        if let collectionID = organization.collections.first(where: { $0.screenshotIDs.contains(item.id) })?.id,
                           let collection = organization.collections.first(where: { $0.id == collectionID }) {
                            Circle()
                                .fill(Color(hex: collection.color))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    Spacer()
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: organization.isFavorite(item))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: organization.tags(for: item).count)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)
                .allowsHitTesting(false)
                
                // Selection checkmark overlay - positioned absolutely
                if isMultiSelected {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 24, height: 24)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(10)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 160)
            .clipped()
            .overlay(
                // Classic selection border
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected || isMultiSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 3 : 2)
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isMultiSelected ? Color.accentColor : (isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.22)),
                    lineWidth: isMultiSelected ? 2 : (isSelected ? 1.5 : 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.4), lineWidth: 1)
            )
    }
}

private struct DetailPane: View {
// Copy the content and replace the existing DetailPane struct


    @Binding var showPDFEditor: Bool
    @EnvironmentObject var library: ScreenshotLibrary
    @EnvironmentObject var organization: OrganizationModel
    @State private var showDeleteConfirmation = false
    @State private var showTagEditor = false
    @State private var showCollectionPicker = false
    @State private var isEditingImage = false
    @StateObject private var editorState = ImageEditorState()

    private var selectedItemsOrdered: [ScreenshotItem] {
        library.selectedItemsOrdered()
    }

    private var currentIndex: Int? {
        library.currentSelectedIndex()
    }

    private var hasMultipleSelections: Bool {
        library.selectedIDs.count > 1
    }

    var body: some View {
        if let item = selectedItem {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.filename)
                                .font(.headline)
                                .textSelection(.enabled)
                            if library.isDuplicate(item) {
                                Badge(text: "DUP", color: .red)
                            }
                            if library.isNearDuplicate(item) {
                                Badge(text: "NEAR", color: .orange)
                            }
                            if organization.isFavorite(item) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                        }
                        Text(item.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if hasMultipleSelections, let index = currentIndex {
                            Text("\(index + 1) of \(selectedItemsOrdered.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if library.isNearDuplicate(item) {
                            let group = library.nearDuplicateGroup(for: item)
                            if group.count > 1 {
                                Text("\(group.count) similar screenshots")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        // Navigation buttons for multiple selections
                        if hasMultipleSelections {
                            Button(action: { library.navigateToPreviousSelected() }) {
                                Image(systemName: "chevron.left")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .help("Previous (←)")
                            
                            Divider().frame(height: 22)
                            
                            Button(action: { library.navigateToNextSelected() }) {
                                Image(systemName: "chevron.right")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .help("Next (→)")
                            
                            Divider().frame(height: 22)
                        }
                        
                        // Favorite button
                        Button(action: {
                            organization.toggleFavorite(item)
                            library.reload()
                        }) {
                            Image(systemName: organization.isFavorite(item) ? "star.fill" : "star")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .foregroundColor(organization.isFavorite(item) ? .yellow : .primary)
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Favorite")
                        
                        if !item.isVideo {
                            Divider().frame(height: 22)
                            
                            Button(isEditingImage ? "Done" : "Edit") {
                                toggleEditor(for: item)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundColor(isEditingImage ? .green : .accentColor)
                        }

                        Divider().frame(height: 22)
                        
                        // Share menu
                        Menu {
                            let messagingServices = ShareActions.availableMessagingServices(for: hasMultipleSelections ? selectedItemsOrdered.map(\.url) : [item.url])
                            if !messagingServices.isEmpty {
                                ForEach(messagingServices, id: \.name) { serviceInfo in
                                    Button(serviceInfo.name) {
                                        serviceInfo.service.perform(withItems: hasMultipleSelections ? selectedItemsOrdered.map(\.url) : [item.url])
                                    }
                                }
                                Divider()
                            }
                            Button("More...") {
                                let items = hasMultipleSelections ? selectedItemsOrdered.map(\.url) : [item.url]
                                if let window = NSApp.keyWindow, let contentView = window.contentView {
                                    let sharingPicker = NSSharingServicePicker(items: items)
                                    sharingPicker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                                }
                            }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .menuStyle(.borderlessButton)
                        .controlSize(.small)
                        
                        Divider().frame(height: 22)
                        
                        // More menu
                        Menu {
                            Button(action: { organization.toggleFavorite(item); library.reload() }) {
                                Text(organization.isFavorite(item) ? "Remove from Favorites" : "Add to Favorites")
                            }
                            Button("Edit Tags...") {
                                showTagEditor = true
                            }
                            Button("Add to Collection...") {
                                showCollectionPicker = true
                            }
                            Divider()
                            Button("Copy File Path") { ClipboardActions.copyFilePath(item.url) }
                            Button("Copy File URL") { ClipboardActions.copyFileURL(item.url) }
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            Divider()
                            Button("Create PDF...") {
                                showPDFEditor = true
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                showDeleteConfirmation = true
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .menuStyle(.borderlessButton)
                        .controlSize(.small)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .controlSize(.small)
                }
                .padding(12)

                Divider()
                
                // Organization controls panel
                VStack(alignment: .leading, spacing: 12) {
                    // Tags section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Tags")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(action: { showTagEditor = true }) {
                                Image(systemName: "plus.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Add Tag")
                        }
                        
                        if organization.tags(for: item).isEmpty {
                            Text("No tags")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .italic()
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(organization.tags(for: item)), id: \.self) { tag in
                                        TagBadge(tag: tag, onRemove: {
                                            organization.removeTag(tag, from: item)
                                            library.reload()
                                        })
                                    }
                                }
                            }
                        }
                    }
                    
                    // Collection section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Collection")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(action: { showCollectionPicker = true }) {
                                Image(systemName: organization.collection(for: item) != nil ? "pencil.circle" : "plus.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(organization.collection(for: item) != nil ? "Change Collection" : "Add to Collection")
                        }
                        
                        if let collection = organization.collection(for: item) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: collection.color))
                                    .frame(width: 10, height: 10)
                                Text(collection.name)
                                    .font(.caption)
                                Button(action: {
                                    organization.removeFromCollection(item, collectionID: collection.id)
                                    library.reload()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        } else {
                            Text("No collection")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .italic()
                        }
                    }

                    // Notes section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { organization.metadata(for: item).notes ?? "" },
                            set: { newValue in
                                organization.updateMetadata(item, notes: newValue)
                            }
                        ))
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

                Divider()

                GeometryReader { proxy in
                    if isEditingImage, !item.isVideo {
                        ImageEditorView(
                            editor: editorState,
                            imageURL: item.url,
                            onSave: { editedImage, notes in
                                saveEditedImage(editedImage, for: item)
                                organization.updateMetadata(item, notes: notes)
                                library.reload()
                                isEditingImage = false
                            },
                            onCancel: {
                                isEditingImage = false
                            }
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .padding(12)
                    } else {
                        MediaView(item: item)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .padding(12)
                            .contextMenu {
                                if item.isVideo {
                                    Button("Open in QuickTime") {
                                        NSWorkspace.shared.open(item.url)
                                    }
                                } else {
                                    Button("Copy Image") { ClipboardActions.copyImage(from: item.url) }
                                    Button("Print") { PrintActions.printImage(at: item.url) }
                                }
                                Button("Share") {
                                    ShareActions.share(items: hasMultipleSelections ? selectedItemsOrdered.map(\.url) : [item.url])
                                }
                                Divider()
                                Button(action: { organization.toggleFavorite(item); library.reload() }) {
                                    Text(organization.isFavorite(item) ? "Remove from Favorites" : "Add to Favorites")
                                }
                                Button("Edit Tags...") {
                                    showTagEditor = true
                                }
                                Button("Add to Collection...") {
                                    showCollectionPicker = true
                                }
                                Divider()
                                Button("Copy File Path") { ClipboardActions.copyFilePath(item.url) }
                                Button("Copy File URL") { ClipboardActions.copyFileURL(item.url) }
                                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    showDeleteConfirmation = true
                                }
                            }
                    }
                }

                // Thumbnail strip for multiple selections
                if hasMultipleSelections {
                    Divider()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedItemsOrdered) { selectedItem in
                                ThumbnailStripItem(
                                    item: selectedItem,
                                    isSelected: selectedItem.id == library.selectedID,
                                    onTap: {
                                        library.selectedID = selectedItem.id
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 80)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                }
            }
            .confirmationDialog(
                "Delete screenshot?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    library.batchDelete([item])
                    // Clear selection if we deleted the selected item
                    if library.selectedID == item.id {
                        library.selectedID = library.items.first?.id
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $showTagEditor) {
                if let item = selectedItem {
                    TagEditorView(item: item, organization: organization, isPresented: $showTagEditor) {
                        library.reload()
                    }
                    .background(WindowActivator())
                }
            }
            .sheet(isPresented: $showCollectionPicker) {
                if let item = selectedItem {
                    CollectionPickerView(item: item, organization: organization, isPresented: $showCollectionPicker) {
                        library.reload()
                    }
                    .background(WindowActivator())
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("No screenshots found")
                    .font(.headline)
                Text("Take a screenshot, or change the watched folder (coming next).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func toggleEditor(for item: ScreenshotItem) {
        if isEditingImage {
            isEditingImage = false
            return
        }
        guard let image = NSImage(contentsOf: item.url) else { return }
        let notes = organization.metadata(for: item).notes ?? ""
        editorState.load(image: image, notes: notes)
        isEditingImage = true
    }

    private func saveEditedImage(_ image: NSImage, for item: ScreenshotItem) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        try? pngData.write(to: item.url)
    }

    private var selectedItem: ScreenshotItem? {
        guard let id = library.selectedID else { return nil }
        return library.items.first(where: { $0.id == id })
    }
}


private struct ThumbnailView: View {
    let item: ScreenshotItem
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                if let image {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        // Video indicator badge
                        if item.isVideo {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                                .padding(6)
                        }
                    }
                } else {
                    Image(systemName: item.isVideo ? "video" : "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: item.url) {
            // Reset image when URL changes
            image = nil
            let currentURL = item.url

            // Generate thumbnail on background thread for both images and videos to avoid blocking UI
            Task.detached(priority: .userInitiated) {
                let thumbnail: NSImage?
                if item.isVideo {
                    thumbnail = await Thumbnailer.thumbnail(for: currentURL, maxPixelSize: 256)
                } else {
                    // Use sync thumbnailer off the main thread to avoid UI jank
                    thumbnail = Thumbnailer.thumbnailSync(for: currentURL, maxPixelSize: 256)
                }
                await MainActor.run {
                    // Guard against races if the item changed while we were generating
                    if currentURL == item.url {
                        image = thumbnail
                    }
                }
            }
        }
    }
}

private struct MediaView: View {
    let item: ScreenshotItem
    @State private var image: NSImage?
    
    var body: some View {
        Group {
            if item.isVideo {
                VideoPlayerView(url: item.url)
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.url) {
            if !item.isVideo {
                // Reset image when URL changes
                image = nil
                image = NSImage(contentsOf: item.url)
            }
        }
    }
}

private struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = AVPlayer(url: url)
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Update player if URL changes (compare by URL to avoid unnecessary recreation)
        let currentAssetURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url
        if currentAssetURL != url {
            nsView.player = AVPlayer(url: url)
        }
    }
}

private struct ThumbnailStripItem: View {
    let item: ScreenshotItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ThumbnailView(item: item)
                    .frame(width: 60, height: 60)
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                Text(item.filename)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 60)
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
        .help(item.filename)
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
    }
}

// SwiftUI wrapper for share button with messaging app shortcuts
struct ShareButtonView: View {
    let items: [URL]
    @State private var showShareMenu = false
    
    var body: some View {
        Menu {
            // Quick actions for messaging apps
            let messagingServices = ShareActions.availableMessagingServices(for: items)
            
            if !messagingServices.isEmpty {
                ForEach(messagingServices, id: \.name) { serviceInfo in
                    Button(serviceInfo.name) {
                        serviceInfo.service.perform(withItems: items)
                    }
                }
                Divider()
            }
            
            // Show Messages if available and not already listed
            let alreadyHasMessages = messagingServices.contains { $0.name.lowercased().contains("message") }
            if !alreadyHasMessages, NSSharingService(named: .composeMessage) != nil {
                Button("Messages") {
                    ShareActions.shareToMessages(items: items)
                }
                Divider()
            }
            
            // Show full share sheet
            Button("More...") {
                showShareSheet()
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .labelStyle(.iconOnly)
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .help("Share")
    }
    
    private func showShareSheet() {
        guard !items.isEmpty else { return }
        
        // Find the key window to show the share picker
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView else { return }
        
        let sharingPicker = NSSharingServicePicker(items: items)
        
        // Show from current mouse location or center of window
        let mouseLocation = NSEvent.mouseLocation
        let windowLocation = window.convertPoint(fromScreen: mouseLocation)
        let rect = NSRect(x: windowLocation.x, y: windowLocation.y, width: 1, height: 1)
        
        sharingPicker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
    }
}

// MARK: - Organization Sidebar

private struct OrganizationSidebar: View {
    @EnvironmentObject var library: ScreenshotLibrary
    @EnvironmentObject var organization: OrganizationModel
    @State private var showNewCollection = false
    @State private var showNewSmartFolder = false
    @State private var newCollectionName = ""
    @State private var newSmartFolderName = ""
    @State private var sidebarSelection: String? = "all"
    @State private var editingCollection: Collection?
    @State private var editingTag: String?
    @State private var editingSmartFolder: SmartFolder?
    @State private var deletingCollection: Collection?
    @State private var deletingTag: String?
    @State private var deletingSmartFolder: SmartFolder?
    
    private var showDeleteCollection: Binding<Bool> {
        Binding(
            get: { deletingCollection != nil },
            set: { if !$0 { deletingCollection = nil } }
        )
    }
    
    private var showDeleteTag: Binding<Bool> {
        Binding(
            get: { deletingTag != nil },
            set: { if !$0 { deletingTag = nil } }
        )
    }
    
    private var showDeleteSmartFolder: Binding<Bool> {
        Binding(
            get: { deletingSmartFolder != nil },
            set: { if !$0 { deletingSmartFolder = nil } }
        )
    }
    
    var body: some View {
        List(selection: $sidebarSelection) {
            // All Screenshots
            Section {
                NavigationLink(value: "all") {
                    HStack {
                        Label("All Screenshots", systemImage: "photo.on.rectangle")
                        Spacer()
                        Text("\(library.items.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag("all")
                
                NavigationLink(value: "favorites") {
                    HStack {
                        Label("Favorites", systemImage: "star.fill")
                        Spacer()
                        Text("\(library.items.filter { organization.isFavorite($0) }.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag("favorites")
            }
            
            // Collections
            Section("Collections") {
                ForEach(organization.collections) { collection in
                    NavigationLink(value: "collection-\(collection.id.uuidString)") {
                        HStack {
                            Circle()
                                .fill(Color(hex: collection.color))
                                .frame(width: 8, height: 8)
                            Text(collection.name)
                            Spacer()
                            Text("\(collection.screenshotIDs.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag("collection-\(collection.id.uuidString)")
                    .contextMenu {
                        Button("Edit Collection...") {
                            editingCollection = collection
                        }
                        Button("Delete Collection", role: .destructive) {
                            deletingCollection = collection
                        }
                    }
                }
                
                Button(action: { showNewCollection = true }) {
                    Label("New Collection", systemImage: "plus.circle")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            
            // Smart Folders
            Section("Smart Folders") {
                ForEach(organization.smartFolders) { folder in
                    NavigationLink(value: "smart-\(folder.id.uuidString)") {
                        HStack {
                            Label(folder.name, systemImage: "folder.smart")
                            Spacer()
                            Text("\(library.items.filter { organization.matchesSmartFolder($0, folder: folder) }.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag("smart-\(folder.id.uuidString)")
                    .contextMenu {
                        Button("Edit Smart Folder...") {
                            editingSmartFolder = folder
                        }
                        Button("Delete Smart Folder", role: .destructive) {
                            deletingSmartFolder = folder
                        }
                    }
                }
                
                Button(action: { showNewSmartFolder = true }) {
                    Label("New Smart Folder", systemImage: "plus.circle")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            
            // Tags
            Section("Tags") {
                ForEach(organization.allTags(), id: \.self) { tag in
                    NavigationLink(value: "tag-\(tag)") {
                        HStack {
                            Label(tag, systemImage: "tag")
                            Spacer()
                            Text("\(organization.itemsWithTag(tag))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag("tag-\(tag)")
                    .contextMenu {
                        Button("Rename Tag...") {
                            editingTag = tag
                        }
                        Button("Delete Tag", role: .destructive) {
                            deletingTag = tag
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Organize")
        .onChange(of: sidebarSelection) { newValue in
            handleSidebarSelection(newValue)
        }
        .sheet(isPresented: $showNewCollection) {
            NewCollectionView(organization: organization, isPresented: $showNewCollection)
        }
        .sheet(isPresented: $showNewSmartFolder) {
            NewSmartFolderView(organization: organization, isPresented: $showNewSmartFolder)
                .background(WindowActivator())
        }
        .sheet(item: $editingCollection) { collection in
            EditCollectionView(collection: collection, organization: organization, isPresented: Binding(
                get: { editingCollection != nil },
                set: { if !$0 { editingCollection = nil } }
            ))
            .background(WindowActivator())
        }
        .sheet(item: Binding(
            get: { editingTag.map { TagWrapper(tag: $0) } },
            set: { editingTag = $0?.tag }
        )) { wrapper in
            EditTagView(tag: wrapper.tag, organization: organization, isPresented: Binding(
                get: { editingTag != nil },
                set: { if !$0 { editingTag = nil } }
            ))
            .background(WindowActivator())
        }
        .sheet(item: $editingSmartFolder) { folder in
            EditSmartFolderView(folder: folder, organization: organization, isPresented: Binding(
                get: { editingSmartFolder != nil },
                set: { if !$0 { editingSmartFolder = nil } }
            ))
            .background(WindowActivator())
        }
        .confirmationDialog(
            "Delete Collection?",
            isPresented: showDeleteCollection,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let collection = deletingCollection {
                    organization.deleteCollection(collection)
                    library.reload()
                    deletingCollection = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let collection = deletingCollection {
                Text("This will remove the collection from all \(collection.screenshotIDs.count) screenshots. This action cannot be undone.")
            }
        }
        .confirmationDialog(
            "Delete Tag?",
            isPresented: showDeleteTag,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let tag = deletingTag {
                    organization.deleteTag(tag)
                    library.reload()
                    deletingTag = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let tag = deletingTag {
                Text("This will remove the tag '\(tag)' from all \(organization.itemsWithTag(tag)) screenshots. This action cannot be undone.")
            }
        }
        .confirmationDialog(
            "Delete Smart Folder?",
            isPresented: showDeleteSmartFolder,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let folder = deletingSmartFolder {
                    organization.deleteSmartFolder(folder)
                    library.reload()
                    deletingSmartFolder = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    private func handleSidebarSelection(_ selection: String?) {
        guard let selection = selection else {
            library.clearFilters()
            sidebarSelection = "all"
            return
        }
        
        if selection == "all" {
            library.clearFilters()
        } else if selection == "favorites" {
            library.setShowFavoritesOnly(true)
        } else if selection.hasPrefix("collection-") {
            let uuidString = String(selection.dropFirst("collection-".count))
            if let uuid = UUID(uuidString: uuidString) {
                library.setActiveCollection(uuid)
            }
        } else if selection.hasPrefix("smart-") {
            let uuidString = String(selection.dropFirst("smart-".count))
            if let uuid = UUID(uuidString: uuidString) {
                library.setActiveSmartFolder(uuid)
            }
        } else if selection.hasPrefix("tag-") {
            let tag = String(selection.dropFirst("tag-".count))
            library.setActiveTag(tag)
        }
    }
}

// MARK: - New Collection View

private struct NewCollectionView: View {
    @ObservedObject var organization: OrganizationModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var color = "#007AFF"
    
    let colors = ["#007AFF", "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#5AC8FA", "#AF52DE", "#FF2D55"]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New Collection")
                .font(.headline)
            
            TextField("Collection Name", text: $name)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Text("Color:")
                ForEach(colors, id: \.self) { hexColor in
                    Button(action: { color = hexColor }) {
                        Circle()
                            .fill(Color(hex: hexColor))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: color == hexColor ? 3 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Button("Create") {
                    _ = organization.createCollection(name: name, color: color)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - New Smart Folder View

private struct NewSmartFolderView: View {
    @ObservedObject var organization: OrganizationModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var selectedTag: String?
    @State private var isFavorite = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New Smart Folder")
                .font(.headline)
            
            TextField("Folder Name", text: $name)
                .textFieldStyle(.roundedBorder)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Rules:")
                
                Picker("Tag", selection: $selectedTag) {
                    Text("None").tag(nil as String?)
                    ForEach(organization.allTags(), id: \.self) { tag in
                        Text(tag).tag(tag as String?)
                    }
                }
                
                Toggle("Is Favorite", isOn: $isFavorite)
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Button("Create") {
                    var rules: [SmartFolderRule] = []
                    if let tag = selectedTag {
                        rules.append(.hasTag(tag))
                    }
                    if isFavorite {
                        rules.append(.isFavorite)
                    }
                    _ = organization.createSmartFolder(name: name, rules: rules)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Tag Components

private struct TagBadge: View {
    let tag: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption2)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct TagEditorView: View {
    let item: ScreenshotItem
    @ObservedObject var organization: OrganizationModel
    @Binding var isPresented: Bool
    let onUpdate: () -> Void
    @State private var newTagName = ""
    @State private var allTags: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Tags")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Tags:")
                    .font(.subheadline)
                if organization.tags(for: item).isEmpty {
                    Text("No tags")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(organization.tags(for: item)), id: \.self) { tag in
                                TagBadge(tag: tag, onRemove: {
                                    organization.removeTag(tag, from: item)
                                    onUpdate()
                                })
                            }
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Tag:")
                    .font(.subheadline)
                HStack {
                    TextField("Tag name", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        if !newTagName.isEmpty {
                            organization.addTag(newTagName, to: item)
                            newTagName = ""
                            onUpdate()
                        }
                    }
                    .disabled(newTagName.isEmpty)
                }
                
                if !allTags.isEmpty {
                    Text("Or select:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(allTags.filter { !organization.tags(for: item).contains($0) }, id: \.self) { tag in
                                Button(tag) {
                                    organization.addTag(tag, to: item)
                                    onUpdate()
                                }
                                .buttonStyle(PlainButtonStyle())
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            
            Button("Done") {
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 450)
        .onAppear {
            allTags = organization.allTags()
        }
    }
}

private struct CollectionPickerView: View {
    let item: ScreenshotItem
    @ObservedObject var organization: OrganizationModel
    @Binding var isPresented: Bool
    let onUpdate: () -> Void
    @State private var selectedCollectionID: UUID?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add to Collection")
                .font(.headline)
            
            if organization.collections.isEmpty {
                VStack(spacing: 12) {
                    Text("No collections yet")
                        .foregroundStyle(.secondary)
                    Text("Create a collection from the sidebar first")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                List(selection: $selectedCollectionID) {
                    ForEach(organization.collections) { collection in
                        HStack {
                            Circle()
                                .fill(Color(hex: collection.color))
                                .frame(width: 12, height: 12)
                            Text(collection.name)
                            Spacer()
                            if organization.collection(for: item)?.id == collection.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .tag(collection.id)
                    }
                    
                    Divider()
                    
                    Button("Remove from Collection") {
                        if let currentCollection = organization.collection(for: item) {
                            organization.removeFromCollection(item, collectionID: currentCollection.id)
                            onUpdate()
                            isPresented = false
                        }
                    }
                    .disabled(organization.collection(for: item) == nil)
                }
                .frame(height: 200)
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Button("Add") {
                    if let collectionID = selectedCollectionID {
                        organization.addToCollection(item, collectionID: collectionID)
                        onUpdate()
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCollectionID == nil)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            selectedCollectionID = organization.collection(for: item)?.id
        }
    }
}

// MARK: - Edit Views

private struct TagWrapper: Identifiable {
    let id = UUID()
    let tag: String
}

private struct EditTagView: View {
    let tag: String
    @ObservedObject var organization: OrganizationModel
    @Binding var isPresented: Bool
    @State private var newTagName: String
    @FocusState private var isTextFieldFocused: Bool
    
    init(tag: String, organization: OrganizationModel, isPresented: Binding<Bool>) {
        self.tag = tag
        self.organization = organization
        self._isPresented = isPresented
        self._newTagName = State(initialValue: tag)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Tag")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Current tag: \(tag)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Used by \(organization.itemsWithTag(tag)) screenshots")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            TextField("New tag name", text: $newTagName)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextFieldFocused = true
                    }
                }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Button("Rename") {
                    guard !newTagName.isEmpty, newTagName != tag else { return }
                    organization.renameTag(from: tag, to: newTagName)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTagName.isEmpty || newTagName == tag)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

private struct EditCollectionView: View {
    let collection: Collection
    @ObservedObject var organization: OrganizationModel
    @Binding var isPresented: Bool
    @State private var name: String
    @State private var color: String
    @FocusState private var isTextFieldFocused: Bool
    
    let colors = ["#007AFF", "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#5AC8FA", "#AF52DE", "#FF2D55"]
    
    init(collection: Collection, organization: OrganizationModel, isPresented: Binding<Bool>) {
        self.collection = collection
        self.organization = organization
        self._isPresented = isPresented
        self._name = State(initialValue: collection.name)
        self._color = State(initialValue: collection.color)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Collection")
                .font(.headline)
            
            TextField("Collection Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextFieldFocused = true
                    }
                }
            
            HStack {
                Text("Color:")
                ForEach(colors, id: \.self) { hexColor in
                    Button(action: { color = hexColor }) {
                        Circle()
                            .fill(Color(hex: hexColor))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: color == hexColor ? 3 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text("\(collection.screenshotIDs.count) screenshots")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Button("Save") {
                    guard !name.isEmpty else { return }
                    organization.updateCollection(collection, name: name, color: color)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

private struct EditSmartFolderView: View {
    let folder: SmartFolder
    @ObservedObject var organization: OrganizationModel
    @Binding var isPresented: Bool
    @State private var name: String
    @State private var selectedTag: String?
    @State private var isFavorite = false
    @FocusState private var isTextFieldFocused: Bool
    
    init(folder: SmartFolder, organization: OrganizationModel, isPresented: Binding<Bool>) {
        self.folder = folder
        self.organization = organization
        self._isPresented = isPresented
        self._name = State(initialValue: folder.name)
        
        // Extract current rules
        var tag: String? = nil
        var favorite = false
        for rule in folder.rules {
            if case .hasTag(let t) = rule {
                tag = t
            } else if case .isFavorite = rule {
                favorite = true
            }
        }
        self._selectedTag = State(initialValue: tag)
        self._isFavorite = State(initialValue: favorite)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Smart Folder")
                .font(.headline)
            
            TextField("Folder Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextFieldFocused = true
                    }
                }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Rules:")
                
                Picker("Tag", selection: $selectedTag) {
                    Text("None").tag(nil as String?)
                    ForEach(organization.allTags(), id: \.self) { tag in
                        Text(tag).tag(tag as String?)
                    }
                }
                
                Toggle("Is Favorite", isOn: $isFavorite)
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Button("Save") {
                    guard !name.isEmpty else { return }
                    var rules: [SmartFolderRule] = []
                    if let tag = selectedTag {
                        rules.append(.hasTag(tag))
                    }
                    if isFavorite {
                        rules.append(.isFavorite)
                    }
                    organization.updateSmartFolder(folder, name: name, rules: rules)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Window Activator Helper

private struct WindowActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows {
                if window.isSheet || window.isModalPanel {
                    window.makeKey()
                    window.orderFrontRegardless()
                }
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - PDF Editor Window

final class PDFEditorWindowClass: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        onClose?()
        super.close()
    }

    // Allow this window to become main so it can properly receive focus
    override var canBecomeMain: Bool {
        return true
    }

    // Allow it to become key for input
    override var canBecomeKey: Bool {
        return true
    }
}


