// MARK: - Smart Folder Rule Builder
// SmartFolderRuleBuilder.swift
// Professional rule builder UI for creating and editing smart folders

import SwiftUI

// MARK: - Rule Builder State

/// Represents editable state for a single rule row
struct EditableRule: Identifiable {
    let id = UUID()
    var category: SmartFolderRuleCategory = .date
    var ruleType: RuleType = .dateWithinLast
    
    // Value fields for different rule types
    var stringValue: String = ""
    var intValue: Int = 7
    var int64Value: Int64 = 1_000_000 // 1MB default
    var boolValue: Bool = true
    var dateValue: Date = Date()
    var endDateValue: Date = Date()
    var selectedTags: [String] = []
    var selectedCollectionID: UUID? = nil
    
    enum RuleType: String, CaseIterable, Identifiable {
        // Date rules
        case dateToday = "Created today"
        case dateThisWeek = "Created this week"
        case dateThisMonth = "Created this month"
        case dateThisYear = "Created this year"
        case dateWithinLast = "Within last N days"
        case dateOlderThan = "Older than N days"
        case dateRange = "Between dates"
        
        // Tag rules
        case hasTag = "Has tag"
        case hasAnyTag = "Has any of tags"
        case hasAllTags = "Has all tags"
        case hasNoTags = "Has no tags"
        
        // Status rules
        case isFavorite = "Is favorite"
        case isNotFavorite = "Is not favorite"
        
        // File type rules
        case isImage = "Is image"
        case isVideo = "Is video"
        case fileExtension = "Has extension"
        
        // Size rules
        case sizeGreaterThan = "Larger than"
        case sizeLessThan = "Smaller than"
        
        // Filename rules
        case filenameContains = "Filename contains"
        case filenameStartsWith = "Filename starts with"
        case filenameEndsWith = "Filename ends with"
        case filenameMatches = "Filename matches regex"
        
        // Notes rules
        case hasNotes = "Has notes"
        case hasNoNotes = "Has no notes"
        case notesContain = "Notes contain"
        case hasCustomName = "Has custom name"
        case hasNoCustomName = "Has no custom name"
        
        // Collection rules
        case inCollection = "In collection"
        case inAnyCollection = "In any collection"
        case notInCollection = "Not in any collection"
        
        var id: String { rawValue }
        
        var category: SmartFolderRuleCategory {
            switch self {
            case .dateToday, .dateThisWeek, .dateThisMonth, .dateThisYear, .dateWithinLast, .dateOlderThan, .dateRange:
                return .date
            case .hasTag, .hasAnyTag, .hasAllTags, .hasNoTags:
                return .tag
            case .isFavorite, .isNotFavorite:
                return .status
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
            }
        }
        
        var needsInput: Bool {
            switch self {
            case .dateToday, .dateThisWeek, .dateThisMonth, .dateThisYear, .hasNoTags,
                 .isFavorite, .isNotFavorite, .isImage, .isVideo, .hasNotes, .hasNoNotes,
                 .hasCustomName, .hasNoCustomName, .inAnyCollection, .notInCollection:
                return false
            default:
                return true
            }
        }
        
        static func rulesForCategory(_ category: SmartFolderRuleCategory) -> [RuleType] {
            allCases.filter { $0.category == category }
        }
    }
    
    /// Convert to SmartFolderRule
    func toRule() -> SmartFolderRule {
        switch ruleType {
        case .dateToday: return .dateToday
        case .dateThisWeek: return .dateThisWeek
        case .dateThisMonth: return .dateThisMonth
        case .dateThisYear: return .dateThisYear
        case .dateWithinLast: return .dateWithinLast(days: intValue)
        case .dateOlderThan: return .dateOlderThan(days: intValue)
        case .dateRange: return .dateRange(start: dateValue, end: endDateValue)
        case .hasTag: return .hasTag(selectedTags.first ?? stringValue)
        case .hasAnyTag: return .hasAnyTag(selectedTags.isEmpty ? [stringValue] : selectedTags)
        case .hasAllTags: return .hasAllTags(selectedTags.isEmpty ? [stringValue] : selectedTags)
        case .hasNoTags: return .hasNoTags
        case .isFavorite: return .isFavorite
        case .isNotFavorite: return .isNotFavorite
        case .isImage: return .isImage
        case .isVideo: return .isVideo
        case .fileExtension: return .fileExtension(stringValue)
        case .sizeGreaterThan: return .sizeGreaterThan(bytes: int64Value)
        case .sizeLessThan: return .sizeLessThan(bytes: int64Value)
        case .filenameContains: return .filenameContains(stringValue)
        case .filenameStartsWith: return .filenameStartsWith(stringValue)
        case .filenameEndsWith: return .filenameEndsWith(stringValue)
        case .filenameMatches: return .filenameMatches(stringValue)
        case .hasNotes: return .hasNotes
        case .hasNoNotes: return .hasNoNotes
        case .notesContain: return .notesContain(stringValue)
        case .hasCustomName: return .hasCustomName
        case .hasNoCustomName: return .hasNoCustomName
        case .inCollection: 
            return selectedCollectionID.map { .inCollection($0) } ?? .inAnyCollection
        case .inAnyCollection: return .inAnyCollection
        case .notInCollection: return .notInCollection
        }
    }
    
    /// Create from existing SmartFolderRule
    static func from(_ rule: SmartFolderRule) -> EditableRule {
        var editable = EditableRule()
        editable.category = rule.category
        
        switch rule {
        case .dateToday:
            editable.ruleType = .dateToday
        case .dateThisWeek:
            editable.ruleType = .dateThisWeek
        case .dateThisMonth:
            editable.ruleType = .dateThisMonth
        case .dateThisYear:
            editable.ruleType = .dateThisYear
        case .dateWithinLast(let days):
            editable.ruleType = .dateWithinLast
            editable.intValue = days
        case .dateOlderThan(let days):
            editable.ruleType = .dateOlderThan
            editable.intValue = days
        case .dateRange(let start, let end):
            editable.ruleType = .dateRange
            editable.dateValue = start
            editable.endDateValue = end
        case .hasTag(let tag):
            editable.ruleType = .hasTag
            editable.selectedTags = [tag]
        case .hasAnyTag(let tags):
            editable.ruleType = .hasAnyTag
            editable.selectedTags = tags
        case .hasAllTags(let tags):
            editable.ruleType = .hasAllTags
            editable.selectedTags = tags
        case .hasNoTags:
            editable.ruleType = .hasNoTags
        case .isFavorite:
            editable.ruleType = .isFavorite
        case .isNotFavorite:
            editable.ruleType = .isNotFavorite
        case .isImage:
            editable.ruleType = .isImage
        case .isVideo:
            editable.ruleType = .isVideo
        case .fileExtension(let ext):
            editable.ruleType = .fileExtension
            editable.stringValue = ext
        case .sizeGreaterThan(let bytes):
            editable.ruleType = .sizeGreaterThan
            editable.int64Value = bytes
        case .sizeLessThan(let bytes):
            editable.ruleType = .sizeLessThan
            editable.int64Value = bytes
        case .filenameContains(let text):
            editable.ruleType = .filenameContains
            editable.stringValue = text
        case .filenameStartsWith(let text):
            editable.ruleType = .filenameStartsWith
            editable.stringValue = text
        case .filenameEndsWith(let text):
            editable.ruleType = .filenameEndsWith
            editable.stringValue = text
        case .filenameMatches(let pattern):
            editable.ruleType = .filenameMatches
            editable.stringValue = pattern
        case .hasNotes:
            editable.ruleType = .hasNotes
        case .hasNoNotes:
            editable.ruleType = .hasNoNotes
        case .notesContain(let text):
            editable.ruleType = .notesContain
            editable.stringValue = text
        case .hasCustomName:
            editable.ruleType = .hasCustomName
        case .hasNoCustomName:
            editable.ruleType = .hasNoCustomName
        case .inCollection(let uuid):
            editable.ruleType = .inCollection
            editable.selectedCollectionID = uuid
        case .inAnyCollection:
            editable.ruleType = .inAnyCollection
        case .notInCollection:
            editable.ruleType = .notInCollection
        case .appName:
            editable.ruleType = .isFavorite
        }
        
        return editable
    }
}

// MARK: - Smart Folder Rule Row

struct SmartFolderRuleRow: View {
    @Binding var rule: EditableRule
    let allTags: [String]
    let collections: [Collection]
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Category picker
            Picker("", selection: $rule.category) {
                ForEach(SmartFolderRuleCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .tag(category)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            .onChange(of: rule.category) { newCategory in
                // Reset rule type to first of new category
                rule.ruleType = EditableRule.RuleType.rulesForCategory(newCategory).first ?? .dateToday
            }
            
            // Rule type picker
            Picker("", selection: $rule.ruleType) {
                ForEach(EditableRule.RuleType.rulesForCategory(rule.category)) { ruleType in
                    Text(ruleType.rawValue).tag(ruleType)
                }
            }
            .labelsHidden()
            .frame(minWidth: 150)
            
            // Value input based on rule type
            ruleValueInput
            
            Spacer()
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove rule")
        }
        .padding(10)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var ruleValueInput: some View {
        switch rule.ruleType {
        // Days input
        case .dateWithinLast, .dateOlderThan:
            HStack(spacing: 4) {
                TextField("", value: $rule.intValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("days")
                    .foregroundColor(.secondary)
            }
            
        // Date range picker
        case .dateRange:
            HStack(spacing: 8) {
                DatePicker("", selection: $rule.dateValue, displayedComponents: .date)
                    .labelsHidden()
                Text("to")
                    .foregroundColor(.secondary)
                DatePicker("", selection: $rule.endDateValue, displayedComponents: .date)
                    .labelsHidden()
            }
            
        // Single tag picker
        case .hasTag:
            Picker("", selection: Binding(
                get: { rule.selectedTags.first ?? "" },
                set: { rule.selectedTags = [$0] }
            )) {
                Text("Select tag").tag("")
                ForEach(allTags, id: \.self) { tag in
                    Text(tag).tag(tag)
                }
            }
            .labelsHidden()
            .frame(minWidth: 120)
            
        // Multi-tag picker
        case .hasAnyTag, .hasAllTags:
            MultiTagPicker(selectedTags: $rule.selectedTags, allTags: allTags)
            
        // File extension input
        case .fileExtension:
            HStack(spacing: 4) {
                Text(".")
                    .foregroundColor(.secondary)
                TextField("png", text: $rule.stringValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            
        // Size input
        case .sizeGreaterThan, .sizeLessThan:
            SizeInputView(bytes: $rule.int64Value)
            
        // Text input
        case .filenameContains, .filenameStartsWith, .filenameEndsWith, .notesContain:
            TextField("Enter text...", text: $rule.stringValue)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, maxWidth: 200)
            
        // Regex input
        case .filenameMatches:
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundColor(.secondary)
                TextField("Pattern", text: $rule.stringValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 100, maxWidth: 200)
            }
            
        // Collection picker
        case .inCollection:
            Picker("", selection: $rule.selectedCollectionID) {
                Text("Select collection").tag(nil as UUID?)
                ForEach(collections) { collection in
                    HStack {
                        Circle()
                            .fill(Color(hex: collection.color))
                            .frame(width: 8, height: 8)
                        Text(collection.name)
                    }
                    .tag(collection.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(minWidth: 150)
            
        // No additional input needed
        default:
            EmptyView()
        }
    }
}

// MARK: - Multi Tag Picker

struct MultiTagPicker: View {
    @Binding var selectedTags: [String]
    let allTags: [String]
    @State private var showPopover = false
    
    var body: some View {
        Button(action: { showPopover.toggle() }) {
            HStack {
                if selectedTags.isEmpty {
                    Text("Select tags...")
                        .foregroundColor(.secondary)
                } else {
                    Text(selectedTags.joined(separator: ", "))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Tags")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                if allTags.isEmpty {
                    Text("No tags available")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(allTags, id: \.self) { tag in
                                HStack {
                                    Image(systemName: selectedTags.contains(tag) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selectedTags.contains(tag) ? .accentColor : .secondary)
                                    Text(tag)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedTags.contains(tag) {
                                        selectedTags.removeAll { $0 == tag }
                                    } else {
                                        selectedTags.append(tag)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                
                HStack {
                    Button("Clear") {
                        selectedTags = []
                    }
                    .disabled(selectedTags.isEmpty)
                    
                    Spacer()
                    
                    Button("Done") {
                        showPopover = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 250)
        }
    }
}

// MARK: - Size Input View

struct SizeInputView: View {
    @Binding var bytes: Int64
    @State private var displayValue: Double = 1.0
    @State private var unit: SizeUnit = .mb
    
    enum SizeUnit: String, CaseIterable {
        case kb = "KB"
        case mb = "MB"
        case gb = "GB"
        
        var multiplier: Int64 {
            switch self {
            case .kb: return 1_024
            case .mb: return 1_024 * 1_024
            case .gb: return 1_024 * 1_024 * 1_024
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: $displayValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .onChange(of: displayValue) { _ in updateBytes() }
            
            Picker("", selection: $unit) {
                ForEach(SizeUnit.allCases, id: \.self) { u in
                    Text(u.rawValue).tag(u)
                }
            }
            .labelsHidden()
            .frame(width: 60)
            .onChange(of: unit) { _ in updateBytes() }
        }
        .onAppear {
            // Initialize display from bytes
            if bytes >= SizeUnit.gb.multiplier {
                displayValue = Double(bytes) / Double(SizeUnit.gb.multiplier)
                unit = .gb
            } else if bytes >= SizeUnit.mb.multiplier {
                displayValue = Double(bytes) / Double(SizeUnit.mb.multiplier)
                unit = .mb
            } else {
                displayValue = Double(bytes) / Double(SizeUnit.kb.multiplier)
                unit = .kb
            }
        }
    }
    
    private func updateBytes() {
        bytes = Int64(displayValue * Double(unit.multiplier))
    }
}

// MARK: - Icon Picker

struct IconPicker: View {
    @Binding var selectedIcon: String?
    @State private var showPopover = false
    
    let icons = [
        "folder.smart", "folder.fill", "star.fill", "heart.fill", "tag.fill",
        "photo", "video.fill", "doc.fill", "calendar", "clock.fill",
        "mappin.circle.fill", "flag.fill", "bookmark.fill", "paperclip",
        "tray.full.fill", "archivebox.fill", "trash.fill", "eye.fill",
        "camera.fill", "mic.fill", "wand.and.stars", "sparkles"
    ]
    
    var body: some View {
        Button(action: { showPopover.toggle() }) {
            HStack {
                Image(systemName: selectedIcon ?? "folder.smart")
                    .font(.title2)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover) {
            VStack(alignment: .leading) {
                Text("Choose Icon")
                    .font(.headline)
                    .padding(.bottom, 8)
                
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 5), spacing: 8) {
                    ForEach(icons, id: \.self) { icon in
                        Button(action: {
                            selectedIcon = icon
                            showPopover = false
                        }) {
                            Image(systemName: icon)
                                .font(.title2)
                                .frame(width: 36, height: 36)
                                .background(selectedIcon == icon ? Color.accentColor.opacity(0.3) : Color.clear)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .frame(width: 250)
        }
    }
}

// MARK: - Smart Folder Rule Builder View

struct SmartFolderRuleBuilder: View {
    @ObservedObject var organization: OrganizationModel
    @Binding var isPresented: Bool
    let existingFolder: SmartFolder?
    let items: [ScreenshotItem] // For live preview
    
    @State private var name: String = ""
    @State private var matchMode: SmartFolderMatchMode = .all
    @State private var icon: String? = nil
    @State private var rules: [EditableRule] = []
    @FocusState private var isNameFocused: Bool
    
    init(organization: OrganizationModel, isPresented: Binding<Bool>, existingFolder: SmartFolder? = nil, items: [ScreenshotItem] = []) {
        self.organization = organization
        self._isPresented = isPresented
        self.existingFolder = existingFolder
        self.items = items
        
        // Initialize state from existing folder
        if let folder = existingFolder {
            _name = State(initialValue: folder.name)
            _matchMode = State(initialValue: folder.matchMode)
            _icon = State(initialValue: folder.icon)
            _rules = State(initialValue: folder.rules.map { EditableRule.from($0) })
        }
    }
    
    private var isEditing: Bool { existingFolder != nil }
    
    private var previewFolder: SmartFolder {
        SmartFolder(
            name: name,
            rules: rules.map { $0.toRule() },
            matchMode: matchMode,
            icon: icon
        )
    }
    
    private var matchingCount: Int {
        organization.countMatchingItems(items, folder: previewFolder)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Smart Folder" : "New Smart Folder")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name and Icon row
                    HStack(spacing: 16) {
                        IconPicker(selectedIcon: $icon)
                        
                        TextField("Folder Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($isNameFocused)
                    }
                    
                    Divider()
                    
                    // Match mode toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Match Mode")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $matchMode) {
                            ForEach(SmartFolderMatchMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    Divider()
                    
                    // Rules section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Rules")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            if !rules.isEmpty {
                                Text("\(rules.count) rule\(rules.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        
                        if rules.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                    Text("No rules added")
                                        .foregroundColor(.secondary)
                                    Text("Add rules to filter screenshots")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 20)
                                Spacer()
                            }
                        } else {
                            ForEach($rules) { $rule in
                                SmartFolderRuleRow(
                                    rule: $rule,
                                    allTags: organization.allTags(),
                                    collections: organization.collections,
                                    onDelete: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            rules.removeAll { $0.id == rule.id }
                                        }
                                    }
                                )
                            }
                        }
                        
                        Button(action: addRule) {
                            Label("Add Rule", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Preview section
                    if !items.isEmpty {
                        Divider()
                        
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.secondary)
                            Text("Preview:")
                                .foregroundColor(.secondary)
                            Text("\(matchingCount) screenshot\(matchingCount == 1 ? "" : "s") match\(matchingCount == 1 ? "es" : "")")
                                .fontWeight(.medium)
                                .foregroundColor(matchingCount > 0 ? .primary : .secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button(isEditing ? "Save" : "Create") {
                    saveFolder()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .keyboardShortcut(.return)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
        .frame(width: 600, height: 550)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFocused = true
            }
        }
    }
    
    private func addRule() {
        withAnimation(.easeInOut(duration: 0.2)) {
            rules.append(EditableRule())
        }
    }
    
    private func saveFolder() {
        let smartRules = rules.map { $0.toRule() }
        
        if let existing = existingFolder {
            organization.updateSmartFolder(
                existing,
                name: name,
                rules: smartRules,
                matchMode: matchMode,
                icon: icon
            )
        } else {
            _ = organization.createSmartFolder(
                name: name,
                rules: smartRules,
                matchMode: matchMode,
                icon: icon
            )
        }
        
        isPresented = false
    }
}
