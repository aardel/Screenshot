import SwiftUI
import AppKit

// MARK: - Batch Collection Picker Sheet

struct BatchCollectionPickerSheet: View {
    let items: [ScreenshotItem]
    @Binding var isPresented: Bool
    @EnvironmentObject var organization: OrganizationModel
    
    @State private var selectedCollectionID: UUID?
    @State private var createNew: Bool = false
    @State private var newCollectionName: String = ""
    @State private var newCollectionColor: Color = .blue
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add \(items.count) Screenshots to Collection")
                .font(.headline)
            
            if organization.collections.isEmpty && !createNew {
                VStack {
                    Image(systemName: "folder")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Collections")
                        .font(.headline)
                    Text("Create a new collection to organize your screenshots")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 150)
            } else if !createNew {
                List(selection: $selectedCollectionID) {
                    ForEach(organization.collections) { collection in
                        HStack {
                            Circle()
                                .fill(Color(hex: collection.color))
                                .frame(width: 12, height: 12)
                            Text(collection.name)
                            Spacer()
                            Text("\(collection.screenshotIDs.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(collection.id)
                    }
                }
                .frame(height: 200)
                .listStyle(.bordered)
            }
            
            if createNew {
                HStack {
                    TextField("Collection Name", text: $newCollectionName)
                        .textFieldStyle(.roundedBorder)
                    
                    ColorPicker("", selection: $newCollectionColor)
                        .labelsHidden()
                        .frame(width: 30)
                }
                .padding(.horizontal)
            }
            
            Toggle("Create new collection", isOn: $createNew)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                
                Spacer()
                
                Button(createNew ? "Create & Add" : "Add to Collection") {
                    if createNew {
                        guard !newCollectionName.isEmpty else { return }
                        let newCollection = organization.createCollection(
                            name: newCollectionName,
                            color: newCollectionColor.hexString
                        )
                        addItemsToCollection(newCollection.id)
                    } else if let collectionID = selectedCollectionID {
                        addItemsToCollection(collectionID)
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(createNew ? newCollectionName.isEmpty : selectedCollectionID == nil)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    private func addItemsToCollection(_ collectionID: UUID) {
        for item in items {
            organization.addToCollection(item, collectionID: collectionID)
        }
    }
}

// MARK: - Batch Tag Editor Sheet

struct BatchTagEditorSheet: View {
    let items: [ScreenshotItem]
    @Binding var isPresented: Bool
    @EnvironmentObject var organization: OrganizationModel
    
    @State private var newTag: String = ""
    @State private var selectedExistingTags: Set<String> = []
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add Tags to \(items.count) Screenshots")
                .font(.headline)
            
            // Existing tags
            let existingTags = organization.allTags()
            if !existingTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Existing Tags")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(existingTags, id: \.self) { tag in
                            Button {
                                if selectedExistingTags.contains(tag) {
                                    selectedExistingTags.remove(tag)
                                } else {
                                    selectedExistingTags.insert(tag)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if selectedExistingTags.contains(tag) {
                                        Image(systemName: "checkmark")
                                            .font(.caption2)
                                    }
                                    Text(tag)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(selectedExistingTags.contains(tag) ? Color.accentColor : Color.secondary.opacity(0.2))
                                .foregroundColor(selectedExistingTags.contains(tag) ? .white : .primary)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            Divider()
            
            // New tag input
            HStack {
                TextField("Add new tag...", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addNewTag()
                    }
                
                Button("Add") {
                    addNewTag()
                }
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            
            if !selectedExistingTags.isEmpty {
                Text("Selected: \(selectedExistingTags.sorted().joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                
                Spacer()
                
                Button("Apply Tags") {
                    applyTags()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedExistingTags.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
    
    private func addNewTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        selectedExistingTags.insert(tag)
        newTag = ""
    }
    
    private func applyTags() {
        for item in items {
            for tag in selectedExistingTags {
                organization.addTag(tag, to: item)
            }
        }
    }
}

// MARK: - Flow Layout Helper

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        
        for (index, placement) in result.placements.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + placement.y), proposal: .unspecified)
        }
    }
    
    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, placements: [CGPoint]) {
        var placements: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        
        let containerWidth = proposal.width ?? .infinity
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            placements.append(CGPoint(x: currentX, y: currentY))
            
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }
        
        return (CGSize(width: maxWidth, height: currentY + lineHeight), placements)
    }
}

// MARK: - Color Extensions

extension Color {
    var hexString: String {
        guard let components = NSColor(self).cgColor.components else { return "#007AFF" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
