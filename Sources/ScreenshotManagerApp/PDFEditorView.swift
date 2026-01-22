import SwiftUI
import PDFKit
import AppKit
import Combine

// MARK: - PDF Editor View

struct PDFEditorView: View {
    let initialItems: [ScreenshotItem]
    @Binding var isPresented: Bool
    @EnvironmentObject var organization: OrganizationModel

    @StateObject private var viewModel: PDFEditorViewModel
    
    init(items: [ScreenshotItem], isPresented: Binding<Bool>) {
        self.initialItems = items
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: PDFEditorViewModel(items: items))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            topToolbar
            
            Divider()
            
            HStack(spacing: 0) {
                // Left sidebar - Pages
                pagesSidebar
                    .frame(width: 150)
                
                Divider()
                
                // Main canvas area
                canvasArea
                
                Divider()
                
                // Right sidebar - Tools & Properties
                toolsSidebar
                    .frame(width: 200)
            }
        }
        .frame(minWidth: 1400, minHeight: 900)
        .frame(idealWidth: 1600, idealHeight: 1000)
        .background(
            KeyEventHandlerView { event in
                // Handle Delete key (backspace) and Forward Delete
                if event.keyCode == 51 || event.keyCode == 117 {
                    viewModel.deleteSelected()
                    return true
                }
                return false
            }
        )
    }

    // MARK: - Top Toolbar
    
    private var topToolbar: some View {
        HStack(spacing: 12) {
            Text("PDF Editor")
                .font(.headline)
                .frame(minWidth: 100, alignment: .leading)
            
            Divider().frame(height: 20)
            
            // Selection tool (first, separate)
            toolButton(.select)
            
            Divider().frame(height: 20)
            
            // Drawing tools group
            toolButton(.pen)
            toolButton(.arrow)
            toolButton(.rectangle)
            toolButton(.circle)
            
            Divider().frame(height: 20)
            
            // Text and highlight tools
            toolButton(.text)
            toolButton(.highlight)
            
            Divider().frame(height: 20)
            
            // Color picker
            HStack(spacing: 4) {
                ForEach([NSColor.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .black], id: \.self) { color in
                    Circle()
                        .fill(Color(color))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(viewModel.selectedColor == color ? Color.white : Color.clear, lineWidth: 2))
                        .onTapGesture { viewModel.selectedColor = color }
                }
            }
            
            Divider().frame(height: 20)
            
            // Line width
            HStack(spacing: 8) {
                Text("Size")
                    .font(.caption)
                    .frame(width: 35, alignment: .trailing)
                Slider(value: $viewModel.lineWidth, in: 1...10)
                    .frame(width: 100)
            }
            
            Spacer(minLength: 0)
            
            // Delete selected button (when something is selected)
            if viewModel.selectedAnnotationIndex != nil || viewModel.selectedElementIndex != nil {
                Button {
                    viewModel.deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .toolbarButtonStyle()
                .help("Delete selection")
            }
            
            Divider().frame(height: 20)
            
            // Zoom
            HStack(spacing: 4) {
                Button { viewModel.zoom = max(0.5, viewModel.zoom - 0.25) } label: { 
                    Image(systemName: "minus.magnifyingglass")
                }
                .toolbarButtonStyle()
                
                Text("\(Int(viewModel.zoom * 100))%")
                    .frame(width: 45)
                    .font(.caption)
                
                Button { viewModel.zoom = min(2.0, viewModel.zoom + 0.25) } label: { 
                    Image(systemName: "plus.magnifyingglass")
                }
                .toolbarButtonStyle()
            }
            
            Divider().frame(height: 20)
            
            // Undo/Redo
            HStack(spacing: 4) {
                Button { viewModel.undo() } label: { 
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)
                .toolbarButtonStyle()
                .help("Undo (Cmd+Z)")
                .keyboardShortcut("z", modifiers: .command)
                
                Button { viewModel.redo() } label: { 
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)
                .toolbarButtonStyle()
                .help("Redo (Cmd+Shift+Z)")
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            
            Divider().frame(height: 20)
            
            Button("Cancel") { 
                isPresented = false
                // Close the window
                if let window = NSApp.windows.first(where: { $0.title == "PDF Editor" }) {
                    window.close()
                }
            }
            .actionButtonStyle()
            
            Button("Export PDF") { viewModel.exportPDF() }
                .actionButtonStyle(isProminent: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 50)
        .background(.ultraThinMaterial)
    }
    
    private func toolButton(_ tool: PDFTool) -> some View {
        Button {
            viewModel.selectedTool = tool
            // Clear selection when switching tools
            if tool != .select {
                viewModel.selectedAnnotationIndex = nil
                viewModel.selectedElementIndex = nil
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tool.icon)
                    .font(.system(size: 16))
                Text(tool.rawValue)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: 65, height: 50)
        }
        .toolbarButtonStyle()
        .background(viewModel.selectedTool == tool ? Color.accentColor : Color.clear)
        .foregroundColor(viewModel.selectedTool == tool ? .white : .primary)
        .cornerRadius(6)
        .help(tool.rawValue)
    }
    
    // MARK: - Pages Sidebar
    
    private var pagesSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pages")
                    .font(.caption.bold())
                Spacer()
                Button { viewModel.addNewPage() } label: {
                    Image(systemName: "plus")
                }
                .toolbarButtonStyle()
            }
            .padding(8)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(viewModel.document.pages.enumerated()), id: \.element.id) { index, page in
                        pageThumbnail(page: page, index: index)
                    }
                }
                .padding(8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func pageThumbnail(page: PDFPageModel, index: Int) -> some View {
        let thumbnailScale: CGFloat = 0.15  // Scale factor for thumbnail
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842

        return VStack(spacing: 4) {
            ZStack {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: pageWidth * thumbnailScale, height: pageHeight * thumbnailScale)
                    .shadow(radius: 2)

                // Mini canvas preview showing all content
                if !page.elements.isEmpty || !page.annotations.isEmpty {
                    Canvas { context, size in
                        let scale = thumbnailScale

                        // Draw elements (screenshots)
                        for element in page.elements {
                            if case .screenshot(let url) = element.type,
                               let nsImage = NSImage(contentsOf: url) {
                                let scaledFrame = CGRect(
                                    x: element.frame.origin.x * scale,
                                    y: element.frame.origin.y * scale,
                                    width: element.frame.width * scale,
                                    height: element.frame.height * scale
                                )
                                let image = Image(nsImage: nsImage)
                                context.draw(image, in: scaledFrame)
                            }
                        }

                        // Draw annotations
                        for annotation in page.annotations {
                            let color = Color(annotation.color)
                            let lineWidth = max(annotation.lineWidth * scale, 0.5)

                            switch annotation.type {
                            case .freehand(let points):
                                if points.count > 1 {
                                    var path = Path()
                                    path.move(to: CGPoint(x: points[0].x * scale, y: points[0].y * scale))
                                    for point in points.dropFirst() {
                                        path.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale))
                                    }
                                    context.stroke(path, with: .color(color), lineWidth: lineWidth)
                                }

                            case .arrow(let start, let end):
                                let scaledStart = CGPoint(x: start.x * scale, y: start.y * scale)
                                let scaledEnd = CGPoint(x: end.x * scale, y: end.y * scale)
                                var path = Path()
                                path.move(to: scaledStart)
                                path.addLine(to: scaledEnd)
                                context.stroke(path, with: .color(color), lineWidth: lineWidth)

                            case .rectangle(let rect):
                                let scaledRect = CGRect(
                                    x: rect.origin.x * scale,
                                    y: rect.origin.y * scale,
                                    width: rect.width * scale,
                                    height: rect.height * scale
                                )
                                context.stroke(Path(scaledRect), with: .color(color), lineWidth: lineWidth)

                            case .circle(let rect):
                                let scaledRect = CGRect(
                                    x: rect.origin.x * scale,
                                    y: rect.origin.y * scale,
                                    width: rect.width * scale,
                                    height: rect.height * scale
                                )
                                context.stroke(Path(ellipseIn: scaledRect), with: .color(color), lineWidth: lineWidth)

                            case .highlight(let rect):
                                let scaledRect = CGRect(
                                    x: rect.origin.x * scale,
                                    y: rect.origin.y * scale,
                                    width: rect.width * scale,
                                    height: rect.height * scale
                                )
                                context.fill(Path(scaledRect), with: .color(color.opacity(0.3)))

                            case .text(let text, let position):
                                let scaledPos = CGPoint(x: position.x * scale, y: position.y * scale)
                                context.draw(Text(text).font(.system(size: 3)).foregroundColor(color), at: scaledPos)
                            }
                        }
                    }
                    .frame(width: pageWidth * thumbnailScale, height: pageHeight * thumbnailScale)
                    .clipped()
                } else {
                    Text("Empty")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(viewModel.currentPageIndex == index ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .onTapGesture { viewModel.currentPageIndex = index }

            Text("Page \(index + 1)")
                .font(.caption2)
        }
        .contextMenu {
            Button("Delete Page", role: .destructive) {
                viewModel.deletePage(at: index)
            }
        }
    }
    
    // MARK: - Canvas Area
    
    private var canvasArea: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    // A4 page background
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 595 * viewModel.zoom, height: 842 * viewModel.zoom)
                        .shadow(color: .black.opacity(0.2), radius: 10)
                    
                    // Page content
                    if viewModel.document.pages.indices.contains(viewModel.currentPageIndex) {
                        PageCanvasView(
                            viewModel: viewModel
                        )
                        .frame(width: 595 * viewModel.zoom, height: 842 * viewModel.zoom)
                    }
                }
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        }
    }
    
    // MARK: - Tools Sidebar
    
    private var toolsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Screenshots to place
            Text("Screenshots")
                .font(.caption.bold())
                .padding(.horizontal)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(initialItems) { item in
                        screenshotTile(item: item)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 200)
            
            Divider()
            
            // Properties
            Text("Properties")
                .font(.caption.bold())
                .padding(.horizontal)
            
            if viewModel.selectedTool == .text {
                VStack(alignment: .leading, spacing: 8) {
                    FocusableTextField(text: $viewModel.textInput, placeholder: "Enter text...")
                        .padding(.horizontal)
                    
                    HStack {
                        Text("Font Size")
                            .font(.caption)
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $viewModel.fontSize, in: 8...72, step: 1)
                            .frame(width: 120)
                        Text("\(Int(viewModel.fontSize))")
                            .font(.caption)
                            .frame(width: 30, alignment: .trailing)
                    }
                    .padding(.horizontal)
                }
            }
            
            // Show text editing controls when a text annotation is selected
            if let selectedIndex = viewModel.selectedAnnotationIndex,
               viewModel.currentPage.annotations.indices.contains(selectedIndex),
               case .text(let text, _) = viewModel.currentPage.annotations[selectedIndex].type {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edit Text")
                        .font(.caption.bold())
                        .padding(.horizontal)
                    
                    FocusableTextField(text: Binding(
                        get: { text },
                        set: { newValue in
                            viewModel.updateTextAnnotation(at: selectedIndex, text: newValue)
                        }
                    ), placeholder: "Text")
                    .padding(.horizontal)
                    
                    HStack {
                        Text("Font Size")
                            .font(.caption)
                            .frame(width: 60, alignment: .leading)
                        Slider(value: Binding(
                            get: { viewModel.currentPage.annotations[selectedIndex].lineWidth },
                            set: { newValue in
                                viewModel.updateTextAnnotationFontSize(at: selectedIndex, size: newValue)
                            }
                        ), in: 8...72, step: 1)
                        .frame(width: 120)
                        Text("\(Int(viewModel.currentPage.annotations[selectedIndex].lineWidth))")
                            .font(.caption)
                            .frame(width: 30, alignment: .trailing)
                    }
                    .padding(.horizontal)
                }
            }
            
            Spacer()
        }
        .padding(.top, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func screenshotTile(item: ScreenshotItem) -> some View {
        VStack(spacing: 4) {
            if let image = NSImage(contentsOf: item.url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)
                    .cornerRadius(4)
                    .shadow(radius: 2)
            }
            Text(item.filename)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .help("Drag to canvas to add")
    }
}

// MARK: - View Model

@MainActor
class PDFEditorViewModel: ObservableObject {
    @Published var document: PDFDocumentModel
    @Published var currentPageIndex: Int = 0
    @Published var selectedTool: PDFTool = .select
    @Published var selectedColor: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 3
    @Published var textInput: String = ""
    @Published var fontSize: CGFloat = 18
    @Published var zoom: CGFloat = 1.0
    
    // Drawing state
    @Published var dragStart: CGPoint?
    @Published var currentDragPoints: [CGPoint] = []
    @Published var selectedElementIndex: Int?
    @Published var selectedAnnotationIndex: Int?
    @Published var annotationDragOffset: CGSize = .zero
    @Published var elementDragOffset: CGSize = .zero
    @Published var activeResizeHandle: ResizeHandle?
    @Published var resizeStartFrame: CGRect?
    @Published var hasDragged: Bool = false // Track if a drag actually occurred

    // Annotation resize state
    @Published var activeAnnotationResizeHandle: ResizeHandle?
    @Published var annotationResizeStartRect: CGRect?

    // Undo/Redo State
    @Published private var undoStack: [PDFDocumentModel] = []
    @Published private var redoStack: [PDFDocumentModel] = []
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    let initialItems: [ScreenshotItem]

    // Subscription to forward nested ObservableObject changes
    private var documentSubscription: AnyCancellable?

    init(items: [ScreenshotItem]) {
        self.initialItems = items
        self.document = PDFDocumentModel(items: items)
        
        // Forward changes from nested document to this viewModel
        // This ensures SwiftUI updates when document.pages changes
        documentSubscription = document.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
    
    // MARK: - Undo/Redo Logic
    
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        
        // Push current state to redo
        redoStack.append(document.copy())
        
        // Restore previous
        document = previous
    }
    
    func redo() {
        guard let next = redoStack.popLast() else { return }
        
        // Push current to undo
        undoStack.append(document.copy())
        
        // Restore next
        document = next
    }
    
    func registerUndo() {
        undoStack.append(document.copy())
        redoStack.removeAll()
    }
    
    var currentPage: PDFPageModel {
        get {
            guard document.pages.indices.contains(currentPageIndex) else {
                return PDFPageModel()
            }
            return document.pages[currentPageIndex]
        }
        set {
            guard document.pages.indices.contains(currentPageIndex) else { return }
            document.pages[currentPageIndex] = newValue
        }
    }
    
    func addNewPage() {
        registerUndo()
        document.pages.append(PDFPageModel())
        currentPageIndex = document.pages.count - 1
    }
    
    func deletePage(at index: Int) {
        guard document.pages.count > 1 else { return }
        registerUndo()
        document.pages.remove(at: index)
        if currentPageIndex >= document.pages.count {
            currentPageIndex = document.pages.count - 1
        }
    }
    
    func addAnnotation(_ annotation: PDFAnnotationModel) {
        registerUndo()
        var page = currentPage
        page.annotations.append(annotation)
        currentPage = page
    }
    
    func addElement(_ element: PDFElementModel) {
        registerUndo()
        var page = currentPage
        page.elements.append(element)
        currentPage = page
    }
    
    func updateElement(at index: Int, frame: CGRect) {
        guard currentPage.elements.indices.contains(index) else { return }
        // Note: For continuous dragging, we usually registerUndo at start of drag, not every frame.
        // But for this simple setter, we assume it's a discrete change or managed by caller.
        // For dragging, caller should registerUndo on drag start.
        var page = currentPage
        page.elements[index].frame = frame
        currentPage = page
    }
    
    func moveElement(at index: Int, offset: CGSize) {
        guard currentPage.elements.indices.contains(index) else { return }
        var page = currentPage
        let currentFrame = page.elements[index].frame
        page.elements[index].frame = CGRect(
            x: currentFrame.origin.x + offset.width,
            y: currentFrame.origin.y + offset.height,
            width: currentFrame.width,
            height: currentFrame.height
        )
        currentPage = page
    }
    
    func hitTestElement(at point: CGPoint) -> Int? {
        let zoom = self.zoom
        for (index, element) in currentPage.elements.enumerated().reversed() {
            let scaledFrame = CGRect(
                x: element.frame.origin.x * zoom,
                y: element.frame.origin.y * zoom,
                width: element.frame.width * zoom,
                height: element.frame.height * zoom
            )
            if scaledFrame.contains(point) {
                return index
            }
        }
        return nil
    }
    
    func updateAnnotation(at index: Int, offset: CGSize) {
        guard currentPage.annotations.indices.contains(index) else { return }
        var page = currentPage
        var annotation = page.annotations[index]
        
        switch annotation.type {
        case .freehand(let points):
            annotation.type = .freehand(points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) })
        case .arrow(let start, let end):
            annotation.type = .arrow(
                start: CGPoint(x: start.x + offset.width, y: start.y + offset.height),
                end: CGPoint(x: end.x + offset.width, y: end.y + offset.height)
            )
        case .rectangle(let rect):
            annotation.type = .rectangle(CGRect(
                x: rect.origin.x + offset.width,
                y: rect.origin.y + offset.height,
                width: rect.width,
                height: rect.height
            ))
        case .circle(let rect):
            annotation.type = .circle(CGRect(
                x: rect.origin.x + offset.width,
                y: rect.origin.y + offset.height,
                width: rect.width,
                height: rect.height
            ))
        case .highlight(let rect):
            annotation.type = .highlight(CGRect(
                x: rect.origin.x + offset.width,
                y: rect.origin.y + offset.height,
                width: rect.width,
                height: rect.height
            ))
        case .text(let text, let position):
            annotation.type = .text(text, position: CGPoint(
                x: position.x + offset.width,
                y: position.y + offset.height
            ))
        }
        
        page.annotations[index] = annotation
        currentPage = page
    }
    
    func deleteSelected() {
        if let index = selectedAnnotationIndex {
            registerUndo()
            var page = currentPage
            page.annotations.remove(at: index)
            currentPage = page
            selectedAnnotationIndex = nil
        } else if let index = selectedElementIndex {
            registerUndo()
            var page = currentPage
            page.elements.remove(at: index)
            currentPage = page
            selectedElementIndex = nil
        }
    }

    /// Returns the bounding rect for resizable annotations (rectangle, circle, highlight, arrow)
    func getAnnotationRect(at index: Int) -> CGRect? {
        guard currentPage.annotations.indices.contains(index) else { return nil }
        let annotation = currentPage.annotations[index]

        switch annotation.type {
        case .rectangle(let rect), .circle(let rect), .highlight(let rect):
            return rect
        case .arrow(let start, let end):
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case .freehand, .text:
            return nil  // Not resizable
        }
    }

    /// Check if an annotation type supports resizing
    func annotationSupportsResize(at index: Int) -> Bool {
        guard currentPage.annotations.indices.contains(index) else { return false }
        let annotation = currentPage.annotations[index]
        switch annotation.type {
        case .rectangle, .circle, .highlight, .arrow:
            return true
        case .freehand, .text:
            return false
        }
    }

    /// Resize an annotation to a new bounding rect
    func updateTextAnnotation(at index: Int, text: String) {
        guard currentPage.annotations.indices.contains(index) else { return }
        var page = currentPage
        var annotation = page.annotations[index]
        
        if case .text(_, let position) = annotation.type {
            annotation.type = .text(text, position: position)
            page.annotations[index] = annotation
            currentPage = page
        }
    }
    
    func updateTextAnnotationFontSize(at index: Int, size: CGFloat) {
        guard currentPage.annotations.indices.contains(index) else { return }
        var page = currentPage
        page.annotations[index].lineWidth = size
        currentPage = page
    }
    
    func resizeAnnotation(at index: Int, to newRect: CGRect) {
        guard currentPage.annotations.indices.contains(index) else { return }
        var page = currentPage
        var annotation = page.annotations[index]

        switch annotation.type {
        case .rectangle:
            annotation.type = .rectangle(newRect)
        case .circle:
            annotation.type = .circle(newRect)
        case .highlight:
            annotation.type = .highlight(newRect)
        case .arrow(let start, let end):
            // For arrow, we need to map the new rect back to start/end points
            // Determine which corner was start and which was end based on original positions
            let wasStartLeft = start.x <= end.x
            let wasStartTop = start.y <= end.y

            let newStart = CGPoint(
                x: wasStartLeft ? newRect.minX : newRect.maxX,
                y: wasStartTop ? newRect.minY : newRect.maxY
            )
            let newEnd = CGPoint(
                x: wasStartLeft ? newRect.maxX : newRect.minX,
                y: wasStartTop ? newRect.maxY : newRect.minY
            )
            annotation.type = .arrow(start: newStart, end: newEnd)
        case .freehand, .text:
            return  // Not resizable
        }

        page.annotations[index] = annotation
        currentPage = page
    }

    func hitTestResizeHandle(at point: CGPoint, for elementIndex: Int) -> ResizeHandle? {
        guard currentPage.elements.indices.contains(elementIndex) else { return nil }
        let element = currentPage.elements[elementIndex]
        let scaledFrame = CGRect(
            x: element.frame.origin.x * zoom,
            y: element.frame.origin.y * zoom,
            width: element.frame.width * zoom,
            height: element.frame.height * zoom
        )
        
        let handleSize: CGFloat = 12
        let handles: [(ResizeHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: scaledFrame.minX, y: scaledFrame.minY)),
            (.top, CGPoint(x: scaledFrame.midX, y: scaledFrame.minY)),
            (.topRight, CGPoint(x: scaledFrame.maxX, y: scaledFrame.minY)),
            (.left, CGPoint(x: scaledFrame.minX, y: scaledFrame.midY)),
            (.right, CGPoint(x: scaledFrame.maxX, y: scaledFrame.midY)),
            (.bottomLeft, CGPoint(x: scaledFrame.minX, y: scaledFrame.maxY)),
            (.bottom, CGPoint(x: scaledFrame.midX, y: scaledFrame.maxY)),
            (.bottomRight, CGPoint(x: scaledFrame.maxX, y: scaledFrame.maxY))
        ]
        
        for (handle, position) in handles {
            if point.distance(to: position) <= handleSize {
                return handle
            }
        }
        return nil
    }
    
    func hitTestAnnotation(at point: CGPoint) -> Int? {
        let zoom = self.zoom
        for (index, annotation) in currentPage.annotations.enumerated().reversed() {
            switch annotation.type {
            case .freehand(let points):
                if points.count > 1 {
                    // Check if point is near any line segment
                    for i in 0..<(points.count - 1) {
                        let p1 = CGPoint(x: points[i].x * zoom, y: points[i].y * zoom)
                        let p2 = CGPoint(x: points[i + 1].x * zoom, y: points[i + 1].y * zoom)
                        if point.distanceToLine(start: p1, end: p2) < 10 {
                            return index
                        }
                    }
                }
            case .arrow(let start, let end):
                let scaledStart = CGPoint(x: start.x * zoom, y: start.y * zoom)
                let scaledEnd = CGPoint(x: end.x * zoom, y: end.y * zoom)
                if point.distanceToLine(start: scaledStart, end: scaledEnd) < 10 {
                    return index
                }
            case .rectangle(let rect):
                let scaledRect = CGRect(
                    x: rect.origin.x * zoom,
                    y: rect.origin.y * zoom,
                    width: rect.width * zoom,
                    height: rect.height * zoom
                )
                if scaledRect.contains(point) {
                    return index
                }
            case .circle(let rect):
                let scaledRect = CGRect(
                    x: rect.origin.x * zoom,
                    y: rect.origin.y * zoom,
                    width: rect.width * zoom,
                    height: rect.height * zoom
                )
                let center = CGPoint(x: scaledRect.midX, y: scaledRect.midY)
                let radius = max(scaledRect.width, scaledRect.height) / 2
                if point.distance(to: center) <= radius {
                    return index
                }
            case .highlight(let rect):
                let scaledRect = CGRect(
                    x: rect.origin.x * zoom,
                    y: rect.origin.y * zoom,
                    width: rect.width * zoom,
                    height: rect.height * zoom
                )
                if scaledRect.contains(point) {
                    return index
                }
            case .text(let text, let position):
                let scaledPos = CGPoint(x: position.x * zoom, y: position.y * zoom)
                // Approximate text bounds
                let textSize = text.size(withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
                let textRect = CGRect(
                    x: scaledPos.x,
                    y: scaledPos.y - textSize.height,
                    width: textSize.width,
                    height: textSize.height
                )
                if textRect.contains(point) {
                    return index
                }
            }
        }
        return nil
    }
    
    private func createPath(from points: [CGPoint], zoom: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x * zoom, y: first.y * zoom))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * zoom, y: point.y * zoom))
        }
        return path
    }
    
    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Screenshots Documentation.pdf"
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        let pdfDocument = PDFDocument()
        
        for page in document.pages {
            if let pdfPage = renderPageToPDF(page) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }
        }
        
        if pdfDocument.pageCount > 0 {
            pdfDocument.write(to: url)
            NSWorkspace.shared.open(url)
        }
    }
    
    private func renderPageToPDF(_ page: PDFPageModel) -> PDFPage? {
        let pageSize = CGSize(width: 595, height: 842)
        let renderer = ImageRenderer(content: PageRenderView(page: page, size: pageSize))
        renderer.scale = 3.0
        
        if let nsImage = renderer.nsImage {
            return PDFPage(image: nsImage)
        }
        return nil
    }
}

// MARK: - Page Canvas View

struct PageCanvasView: View {
    @ObservedObject var viewModel: PDFEditorViewModel
    
    var body: some View {
        ZStack {
            // Background
            Color.white
            
            // Elements (screenshots, text boxes)
            // Render in reverse order so earlier elements appear on top for easier selection
            ForEach(Array(viewModel.currentPage.elements.enumerated().reversed()), id: \.element.id) { index, element in
                elementView(element: element, index: index)
            }
            
            // Annotations
            ForEach(Array(viewModel.currentPage.annotations.enumerated()), id: \.element.id) { index, annotation in
                annotationView(for: annotation, index: index)
            }
            
            // Live drawing preview
            if let dragStart = viewModel.dragStart, !viewModel.currentDragPoints.isEmpty {
                Canvas { context, size in
                    drawPreview(in: &context, start: dragStart)
                }
                .allowsHitTesting(false)
                .id("preview-\(viewModel.currentDragPoints.count)") // Force redraw on point count change
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Skip if resize handle is active (it handles its own gesture)
                    if viewModel.activeResizeHandle != nil || viewModel.activeAnnotationResizeHandle != nil {
                        return
                    }
                    if viewModel.selectedTool == .select {
                        // For select tool, check if it's a tap (minimal movement)
                        if abs(value.translation.width) < 2 && abs(value.translation.height) < 2 {
                            // It's a tap, don't drag yet
                            return
                        }
                        handleSelectDrag(value)
                    } else {
                        handleDrag(value)
                    }
                }
                .onEnded { value in
                    // Skip if resize handle is active
                    if viewModel.activeResizeHandle != nil || viewModel.activeAnnotationResizeHandle != nil {
                        return
                    }
                    if viewModel.selectedTool == .select {
                        // Check if it was a tap (minimal movement)
                        if abs(value.translation.width) < 2 && abs(value.translation.height) < 2 {
                            // It's a tap - select at location
                            handleSelectTap(at: value.location)
                        } else {
                            // It was a drag
                            handleSelectDragEnd(value)
                        }
                    } else {
                        handleDragEnd(value)
                    }
                    // Reset drag flag
                    viewModel.hasDragged = false
                }
        )
        .onDrop(of: [.url], isTargeted: nil) { providers, location in
            handleDrop(providers: providers, at: location)
        }
    }
    
    @ViewBuilder
    private func elementView(element: PDFElementModel, index: Int) -> some View {
        // Read directly from viewModel for real-time updates during resize
        let currentElement = viewModel.currentPage.elements.indices.contains(index)
            ? viewModel.currentPage.elements[index]
            : element

        let scaledFrame = CGRect(
            x: currentElement.frame.origin.x * viewModel.zoom,
            y: currentElement.frame.origin.y * viewModel.zoom,
            width: currentElement.frame.width * viewModel.zoom,
            height: currentElement.frame.height * viewModel.zoom
        )
        let isSelected = viewModel.selectedElementIndex == index

        ZStack {
            Group {
                switch currentElement.type {
                case .screenshot(let url):
                    if let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: scaledFrame.width, height: scaledFrame.height)
                            .shadow(radius: 2)
                    }
                case .textBox(let text):
                    Text(text)
                        .padding(8)
                        .background(Color.white)
                        .border(Color.gray, width: 1)
                }
            }
            .position(x: scaledFrame.midX, y: scaledFrame.midY)
            .allowsHitTesting(false) // Element content doesn't need hit testing - main canvas handles selection

            // Selection indicator
            if isSelected {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: scaledFrame.width + 4, height: scaledFrame.height + 4)
                    .position(x: scaledFrame.midX, y: scaledFrame.midY)
                    .allowsHitTesting(false) // Selection indicator is visual only

                // Resize handles - read from viewModel for real-time updates
                // These have highPriorityGesture and need hit testing
                resizeHandles(for: index)
            }
        }
        // Element view itself allows hit testing so resize handles can work
        // But element content is non-hit-testable so it doesn't block main canvas selection
    }
    
    @ViewBuilder
    private func resizeHandles(for index: Int) -> some View {
        // Read from viewModel for real-time updates during resize
        if viewModel.currentPage.elements.indices.contains(index) {
            let element = viewModel.currentPage.elements[index]
            let frame = CGRect(
                x: element.frame.origin.x * viewModel.zoom,
                y: element.frame.origin.y * viewModel.zoom,
                width: element.frame.width * viewModel.zoom,
                height: element.frame.height * viewModel.zoom
            )
            let handleSize: CGFloat = 10
            let hitAreaSize: CGFloat = 24  // Larger hit area for easier clicking
            let handles: [(ResizeHandle, CGPoint)] = [
                (.topLeft, CGPoint(x: frame.minX, y: frame.minY)),
                (.top, CGPoint(x: frame.midX, y: frame.minY)),
                (.topRight, CGPoint(x: frame.maxX, y: frame.minY)),
                (.left, CGPoint(x: frame.minX, y: frame.midY)),
                (.right, CGPoint(x: frame.maxX, y: frame.midY)),
                (.bottomLeft, CGPoint(x: frame.minX, y: frame.maxY)),
                (.bottom, CGPoint(x: frame.midX, y: frame.maxY)),
                (.bottomRight, CGPoint(x: frame.maxX, y: frame.maxY))
            ]

            ForEach(handles, id: \.0.rawValue) { handle, position in
                ZStack {
                    // Invisible larger hit area
                    Circle()
                        .fill(Color.clear)
                        .frame(width: hitAreaSize, height: hitAreaSize)

                    // Visible handle
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: handleSize, height: handleSize)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                }
                .contentShape(Circle().size(width: hitAreaSize, height: hitAreaSize))
                .position(position)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleResize(value, handle: handle)
                        }
                        .onEnded { _ in
                            viewModel.activeResizeHandle = nil
                            viewModel.resizeStartFrame = nil
                        }
                )
            }
        }
    }
    
    private func handleResize(_ value: DragGesture.Value, handle: ResizeHandle) {
        guard let elementIndex = viewModel.selectedElementIndex,
              viewModel.currentPage.elements.indices.contains(elementIndex) else {
            return
        }
        
        let element = viewModel.currentPage.elements[elementIndex]
        
        if viewModel.activeResizeHandle == nil {
            viewModel.registerUndo()
            viewModel.activeResizeHandle = handle
            viewModel.resizeStartFrame = element.frame
        }
        
        guard let startFrame = viewModel.resizeStartFrame,
              let elementIndex = viewModel.selectedElementIndex else { return }
        
        let zoom = viewModel.zoom
        let deltaX = (value.location.x - value.startLocation.x) / zoom
        let deltaY = (value.location.y - value.startLocation.y) / zoom
        
        var newFrame = startFrame
        let minSize: CGFloat = 50
        
        switch handle {
        case .topLeft:
            newFrame.origin.x = startFrame.origin.x + deltaX
            newFrame.origin.y = startFrame.origin.y + deltaY
            newFrame.size.width = startFrame.width - deltaX
            newFrame.size.height = startFrame.height - deltaY
        case .top:
            newFrame.origin.y = startFrame.origin.y + deltaY
            newFrame.size.height = startFrame.height - deltaY
        case .topRight:
            newFrame.origin.y = startFrame.origin.y + deltaY
            newFrame.size.width = startFrame.width + deltaX
            newFrame.size.height = startFrame.height - deltaY
        case .left:
            newFrame.origin.x = startFrame.origin.x + deltaX
            newFrame.size.width = startFrame.width - deltaX
        case .right:
            newFrame.size.width = startFrame.width + deltaX
        case .bottomLeft:
            newFrame.origin.x = startFrame.origin.x + deltaX
            newFrame.size.width = startFrame.width - deltaX
            newFrame.size.height = startFrame.height + deltaY
        case .bottom:
            newFrame.size.height = startFrame.height + deltaY
        case .bottomRight:
            newFrame.size.width = startFrame.width + deltaX
            newFrame.size.height = startFrame.height + deltaY
        }
        
        if newFrame.width >= minSize && newFrame.height >= minSize {
            viewModel.updateElement(at: elementIndex, frame: newFrame)
        }
    }
    
    @ViewBuilder
    private func annotationView(for annotation: PDFAnnotationModel, index: Int) -> some View {
        // Read directly from viewModel for real-time updates during resize
        let currentAnnotation = viewModel.currentPage.annotations.indices.contains(index)
            ? viewModel.currentPage.annotations[index]
            : annotation

        let color = Color(currentAnnotation.color)
        let zoom = viewModel.zoom
        let isSelected = viewModel.selectedAnnotationIndex == index

        // Draw annotations directly without wrapper positioning
        // All annotations use absolute canvas coordinates
        ZStack {
            switch currentAnnotation.type {
            case .freehand(let points):
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x * zoom, y: points[0].y * zoom))
                        for point in points.dropFirst() {
                            path.addLine(to: CGPoint(x: point.x * zoom, y: point.y * zoom))
                        }
                    }
                    .stroke(color, lineWidth: currentAnnotation.lineWidth)
                }

            case .arrow(let start, let end):
                let scaledStart = CGPoint(x: start.x * zoom, y: start.y * zoom)
                let scaledEnd = CGPoint(x: end.x * zoom, y: end.y * zoom)
                let angle = atan2(scaledEnd.y - scaledStart.y, scaledEnd.x - scaledStart.x)
                let arrowLength = 14 + currentAnnotation.lineWidth * 1.5
                let arrowAngle: CGFloat = .pi / 7

                // Stop line at base of arrowhead
                let lineEnd = CGPoint(
                    x: scaledEnd.x - arrowLength * 0.7 * cos(angle),
                    y: scaledEnd.y - arrowLength * 0.7 * sin(angle)
                )

                // Draw line
                Path { path in
                    path.move(to: scaledStart)
                    path.addLine(to: lineEnd)
                }
                .stroke(color, lineWidth: currentAnnotation.lineWidth)

                // Draw filled arrowhead
                Path { path in
                    let p1 = CGPoint(
                        x: scaledEnd.x - arrowLength * cos(angle - arrowAngle),
                        y: scaledEnd.y - arrowLength * sin(angle - arrowAngle)
                    )
                    let p2 = CGPoint(
                        x: scaledEnd.x - arrowLength * cos(angle + arrowAngle),
                        y: scaledEnd.y - arrowLength * sin(angle + arrowAngle)
                    )
                    path.move(to: scaledEnd)
                    path.addLine(to: p1)
                    path.addLine(to: p2)
                    path.closeSubpath()
                }
                .fill(color)

            case .rectangle(let rect):
                let scaledRect = CGRect(
                    x: rect.origin.x * zoom,
                    y: rect.origin.y * zoom,
                    width: rect.width * zoom,
                    height: rect.height * zoom
                )
                Path(scaledRect)
                    .stroke(color, lineWidth: currentAnnotation.lineWidth)

            case .circle(let rect):
                let scaledRect = CGRect(
                    x: rect.origin.x * zoom,
                    y: rect.origin.y * zoom,
                    width: rect.width * zoom,
                    height: rect.height * zoom
                )
                Path(ellipseIn: scaledRect)
                    .stroke(color, lineWidth: currentAnnotation.lineWidth)

            case .highlight(let rect):
                let scaledRect = CGRect(
                    x: rect.origin.x * zoom,
                    y: rect.origin.y * zoom,
                    width: rect.width * zoom,
                    height: rect.height * zoom
                )
                Path(scaledRect)
                    .fill(color.opacity(0.3))

            case .text(let text, let position):
                let scaledPos = CGPoint(x: position.x * zoom, y: position.y * zoom)
                Text(text)
                    .font(.system(size: currentAnnotation.lineWidth))
                    .foregroundColor(color)
                    .position(scaledPos)
            }

            // Selection indicator and resize handles
            if isSelected {
                selectionIndicator(for: currentAnnotation)
                    .allowsHitTesting(false)

                // Show resize handles for resizable annotation types
                if viewModel.annotationSupportsResize(at: index) {
                    annotationResizeHandles(for: index)
                }
            }
        }
        // No frame/position wrapper - annotations draw at absolute coordinates
        // Hit testing is handled by the parent canvas gesture
    }

    @ViewBuilder
    private func annotationResizeHandles(for index: Int) -> some View {
        // Read from viewModel for real-time updates
        if viewModel.currentPage.annotations.indices.contains(index) {
            let annotation = viewModel.currentPage.annotations[index]
            let zoom = viewModel.zoom
            let bounds = annotationBounds(annotation, zoom: zoom)
            let handleSize: CGFloat = 10
            let hitAreaSize: CGFloat = 24

            let handles: [(ResizeHandle, CGPoint)] = [
                (.topLeft, CGPoint(x: bounds.minX, y: bounds.minY)),
                (.top, CGPoint(x: bounds.midX, y: bounds.minY)),
                (.topRight, CGPoint(x: bounds.maxX, y: bounds.minY)),
                (.left, CGPoint(x: bounds.minX, y: bounds.midY)),
                (.right, CGPoint(x: bounds.maxX, y: bounds.midY)),
                (.bottomLeft, CGPoint(x: bounds.minX, y: bounds.maxY)),
                (.bottom, CGPoint(x: bounds.midX, y: bounds.maxY)),
                (.bottomRight, CGPoint(x: bounds.maxX, y: bounds.maxY))
            ]

            ForEach(handles, id: \.0.rawValue) { handle, position in
                ZStack {
                    // Invisible larger hit area
                    Circle()
                        .fill(Color.clear)
                        .frame(width: hitAreaSize, height: hitAreaSize)

                    // Visible handle
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: handleSize, height: handleSize)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                }
                .contentShape(Circle().size(width: hitAreaSize, height: hitAreaSize))
                .position(position)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleAnnotationResize(value, handle: handle, annotationIndex: index)
                        }
                        .onEnded { _ in
                            viewModel.activeAnnotationResizeHandle = nil
                            viewModel.annotationResizeStartRect = nil
                        }
                )
            }
        }
    }

    private func handleAnnotationResize(_ value: DragGesture.Value, handle: ResizeHandle, annotationIndex: Int) {
        guard viewModel.currentPage.annotations.indices.contains(annotationIndex),
              let currentRect = viewModel.getAnnotationRect(at: annotationIndex) else {
            return
        }

        if viewModel.activeAnnotationResizeHandle == nil {
            viewModel.registerUndo()
            viewModel.activeAnnotationResizeHandle = handle
            viewModel.annotationResizeStartRect = currentRect
        }

        guard let startRect = viewModel.annotationResizeStartRect else { return }

        let zoom = viewModel.zoom
        let deltaX = (value.location.x - value.startLocation.x) / zoom
        let deltaY = (value.location.y - value.startLocation.y) / zoom

        var newRect = startRect
        let minSize: CGFloat = 10

        switch handle {
        case .topLeft:
            newRect.origin.x = startRect.origin.x + deltaX
            newRect.origin.y = startRect.origin.y + deltaY
            newRect.size.width = startRect.width - deltaX
            newRect.size.height = startRect.height - deltaY
        case .top:
            newRect.origin.y = startRect.origin.y + deltaY
            newRect.size.height = startRect.height - deltaY
        case .topRight:
            newRect.origin.y = startRect.origin.y + deltaY
            newRect.size.width = startRect.width + deltaX
            newRect.size.height = startRect.height - deltaY
        case .left:
            newRect.origin.x = startRect.origin.x + deltaX
            newRect.size.width = startRect.width - deltaX
        case .right:
            newRect.size.width = startRect.width + deltaX
        case .bottomLeft:
            newRect.origin.x = startRect.origin.x + deltaX
            newRect.size.width = startRect.width - deltaX
            newRect.size.height = startRect.height + deltaY
        case .bottom:
            newRect.size.height = startRect.height + deltaY
        case .bottomRight:
            newRect.size.width = startRect.width + deltaX
            newRect.size.height = startRect.height + deltaY
        }

        if newRect.width >= minSize && newRect.height >= minSize {
            viewModel.resizeAnnotation(at: annotationIndex, to: newRect)
        }
    }
    
    @ViewBuilder
    private func selectionIndicator(for annotation: PDFAnnotationModel) -> some View {
        let zoom = viewModel.zoom
        let bounds = annotationBounds(annotation, zoom: zoom)
        
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: bounds.width + 8, height: bounds.height + 8)
            .position(x: bounds.midX, y: bounds.midY)
    }
    
    private func annotationBounds(_ annotation: PDFAnnotationModel, zoom: CGFloat) -> CGRect {
        switch annotation.type {
        case .freehand(let points):
            guard !points.isEmpty else { return .zero }
            let scaledPoints = points.map { CGPoint(x: $0.x * zoom, y: $0.y * zoom) }
            let minX = scaledPoints.map(\.x).min() ?? 0
            let maxX = scaledPoints.map(\.x).max() ?? 0
            let minY = scaledPoints.map(\.y).min() ?? 0
            let maxY = scaledPoints.map(\.y).max() ?? 0
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .arrow(let start, let end):
            let scaledStart = CGPoint(x: start.x * zoom, y: start.y * zoom)
            let scaledEnd = CGPoint(x: end.x * zoom, y: end.y * zoom)
            return CGRect(
                x: min(scaledStart.x, scaledEnd.x) - 5,
                y: min(scaledStart.y, scaledEnd.y) - 5,
                width: abs(scaledEnd.x - scaledStart.x) + 10,
                height: abs(scaledEnd.y - scaledStart.y) + 10
            )
        case .rectangle(let rect), .circle(let rect), .highlight(let rect):
            return CGRect(
                x: rect.origin.x * zoom,
                y: rect.origin.y * zoom,
                width: rect.width * zoom,
                height: rect.height * zoom
            )
        case .text(let text, let position):
            let textSize = text.size(withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
            let scaledPos = CGPoint(x: position.x * zoom, y: position.y * zoom)
            return CGRect(
                x: scaledPos.x,
                y: scaledPos.y - textSize.height,
                width: textSize.width,
                height: textSize.height
            )
        }
    }
    
    private func drawPreview(in context: inout GraphicsContext, start: CGPoint) {
        guard !viewModel.currentDragPoints.isEmpty else { return }
        let color = Color(viewModel.selectedColor)
        
        switch viewModel.selectedTool {
        case .pen:
            if viewModel.currentDragPoints.count > 1 {
                var path = Path()
                path.move(to: viewModel.currentDragPoints[0])
                for point in viewModel.currentDragPoints.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(path, with: .color(color), lineWidth: viewModel.lineWidth)
            }
            
        case .arrow:
            if let end = viewModel.currentDragPoints.last {
                let angle = atan2(end.y - start.y, end.x - start.x)
                let arrowLength = 14 + viewModel.lineWidth * 1.5
                let arrowAngle: CGFloat = .pi / 7
                
                // Stop line at base of arrowhead
                let lineEnd = CGPoint(
                    x: end.x - arrowLength * 0.7 * cos(angle),
                    y: end.y - arrowLength * 0.7 * sin(angle)
                )
                
                var path = Path()
                path.move(to: start)
                path.addLine(to: lineEnd)
                context.stroke(path, with: .color(color), lineWidth: viewModel.lineWidth)
                
                // Draw filled arrowhead
                var head = Path()
                let p1 = CGPoint(
                    x: end.x - arrowLength * cos(angle - arrowAngle),
                    y: end.y - arrowLength * sin(angle - arrowAngle)
                )
                let p2 = CGPoint(
                    x: end.x - arrowLength * cos(angle + arrowAngle),
                    y: end.y - arrowLength * sin(angle + arrowAngle)
                )
                head.move(to: end)
                head.addLine(to: p1)
                head.addLine(to: p2)
                head.closeSubpath()
                context.fill(head, with: .color(color))
            }
            
        case .rectangle:
            if let end = viewModel.currentDragPoints.last {
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                context.stroke(Path(rect), with: .color(color), lineWidth: viewModel.lineWidth)
            }
            
        case .circle:
            if let end = viewModel.currentDragPoints.last {
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: viewModel.lineWidth)
            }
            
        case .highlight:
            if let end = viewModel.currentDragPoints.last {
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                context.fill(Path(rect), with: .color(color.opacity(0.3)))
            }
            
        default:
            break
        }
    }
    
    private func handleDrag(_ value: DragGesture.Value) {
        guard viewModel.selectedTool != .select else { return }
        
        if viewModel.dragStart == nil {
            viewModel.dragStart = value.startLocation
            viewModel.currentDragPoints = []
            viewModel.hasDragged = false
        }
        
        // Mark that we've actually dragged (moved more than a tiny amount)
        let dragDistance = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
        if dragDistance > 2 {
            viewModel.hasDragged = true
        }
        
        // Add current location - limit to reasonable number for performance
        if viewModel.currentDragPoints.count < 1000 {
            viewModel.currentDragPoints.append(value.location)
        }
    }
    
    private func handleDragEnd(_ value: DragGesture.Value) {
        guard viewModel.selectedTool != .select,
              let start = viewModel.dragStart else {
            viewModel.dragStart = nil
            viewModel.currentDragPoints = []
            return
        }
        
        // Clamp coordinates to page bounds (595 x 842 at 1x zoom)
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let maxX = pageWidth * viewModel.zoom
        let maxY = pageHeight * viewModel.zoom
        
        let clampedStart = CGPoint(
            x: max(0, min(start.x, maxX)),
            y: max(0, min(start.y, maxY))
        )
        let clampedEnd = CGPoint(
            x: max(0, min(value.location.x, maxX)),
            y: max(0, min(value.location.y, maxY))
        )
        
        let unzoomedStart = CGPoint(x: clampedStart.x / viewModel.zoom, y: clampedStart.y / viewModel.zoom)
        let unzoomedEnd = CGPoint(x: clampedEnd.x / viewModel.zoom, y: clampedEnd.y / viewModel.zoom)
        
        let annotation: PDFAnnotationModel?
        
        switch viewModel.selectedTool {
        case .pen:
            let pageWidth: CGFloat = 595
            let pageHeight: CGFloat = 842
            let maxX = pageWidth * viewModel.zoom
            let maxY = pageHeight * viewModel.zoom
            let unzoomedPoints = viewModel.currentDragPoints.map { point in
                let clamped = CGPoint(
                    x: max(0, min(point.x, maxX)),
                    y: max(0, min(point.y, maxY))
                )
                return CGPoint(x: clamped.x / viewModel.zoom, y: clamped.y / viewModel.zoom)
            }
            annotation = PDFAnnotationModel(type: .freehand(unzoomedPoints), color: viewModel.selectedColor, lineWidth: viewModel.lineWidth)
            
        case .arrow:
            annotation = PDFAnnotationModel(type: .arrow(start: unzoomedStart, end: unzoomedEnd), color: viewModel.selectedColor, lineWidth: viewModel.lineWidth)
            
        case .rectangle:
            let rect = CGRect(
                x: min(unzoomedStart.x, unzoomedEnd.x),
                y: min(unzoomedStart.y, unzoomedEnd.y),
                width: abs(unzoomedEnd.x - unzoomedStart.x),
                height: abs(unzoomedEnd.y - unzoomedStart.y)
            )
            annotation = PDFAnnotationModel(type: .rectangle(rect), color: viewModel.selectedColor, lineWidth: viewModel.lineWidth)
            
        case .circle:
            let rect = CGRect(
                x: min(unzoomedStart.x, unzoomedEnd.x),
                y: min(unzoomedStart.y, unzoomedEnd.y),
                width: abs(unzoomedEnd.x - unzoomedStart.x),
                height: abs(unzoomedEnd.y - unzoomedStart.y)
            )
            annotation = PDFAnnotationModel(type: .circle(rect), color: viewModel.selectedColor, lineWidth: viewModel.lineWidth)
            
        case .highlight:
            let rect = CGRect(
                x: min(unzoomedStart.x, unzoomedEnd.x),
                y: min(unzoomedStart.y, unzoomedEnd.y),
                width: abs(unzoomedEnd.x - unzoomedStart.x),
                height: abs(unzoomedEnd.y - unzoomedStart.y)
            )
            annotation = PDFAnnotationModel(type: .highlight(rect), color: viewModel.selectedColor, lineWidth: viewModel.lineWidth)
            
        default:
            annotation = nil
        }
        
        if let annotation = annotation {
            viewModel.addAnnotation(annotation)
        }
        
        // Clear drag state
        viewModel.dragStart = nil
        viewModel.currentDragPoints = []
        viewModel.hasDragged = false
    }
    
    private func handleTap(at location: CGPoint) {
        if viewModel.selectedTool == .text && !viewModel.textInput.isEmpty {
            let unzoomedPos = CGPoint(x: location.x / viewModel.zoom, y: location.y / viewModel.zoom)
            let annotation = PDFAnnotationModel(
                type: .text(viewModel.textInput, position: unzoomedPos),
                color: viewModel.selectedColor,
                lineWidth: viewModel.fontSize // Use fontSize for text annotations
            )
            viewModel.addAnnotation(annotation)
            viewModel.textInput = ""
        }
    }
    
    private func handleSelectTap(at location: CGPoint) {
        // Convert location to canvas coordinates
        // The location is in window coordinates, we need canvas coordinates
        // For now, use the location directly as it should be relative to the canvas
        let canvasLocation = location
        
        // Try to select annotation first (they're drawn on top)
        if let index = viewModel.hitTestAnnotation(at: canvasLocation) {
            viewModel.selectedAnnotationIndex = index
            viewModel.selectedElementIndex = nil
            return
        }
        
        // Try to select element
        if let index = viewModel.hitTestElement(at: canvasLocation) {
            viewModel.selectedAnnotationIndex = nil
            viewModel.selectedElementIndex = index
            return
        }
        
        // Deselect all if clicking on empty space
        viewModel.selectedAnnotationIndex = nil
        viewModel.selectedElementIndex = nil
    }
    
    private func handleSelectDrag(_ value: DragGesture.Value) {
        // Don't drag if we're resizing
        if viewModel.activeResizeHandle != nil {
            return
        }

        // Initialize drag on first event - store the start position
        if viewModel.dragStart == nil {
            // Register Undo if we have something selected to move
            if viewModel.selectedAnnotationIndex != nil || viewModel.selectedElementIndex != nil {
                 viewModel.registerUndo()
            }
            viewModel.dragStart = value.startLocation
            return // Don't move on first event, just initialize
        }

        // Use translation directly - it's already the delta from startLocation
        // Convert from zoomed view coordinates to unzoomed storage coordinates
        let delta = CGSize(
            width: value.translation.width / viewModel.zoom,
            height: value.translation.height / viewModel.zoom
        )

        // Move selected annotation - apply delta relative to original position
        if let index = viewModel.selectedAnnotationIndex {
            // First, reset to original position (undo previous drag)
            let previousOffset = viewModel.annotationDragOffset
            if previousOffset != .zero {
                viewModel.updateAnnotation(at: index, offset: CGSize(width: -previousOffset.width, height: -previousOffset.height))
            }
            // Then apply new total offset
            viewModel.updateAnnotation(at: index, offset: delta)
            viewModel.annotationDragOffset = delta
        }
        // Move selected element - apply delta relative to original position
        else if let index = viewModel.selectedElementIndex {
            // First, reset to original position (undo previous drag)
            let previousOffset = viewModel.elementDragOffset
            if previousOffset != .zero {
                viewModel.moveElement(at: index, offset: CGSize(width: -previousOffset.width, height: -previousOffset.height))
            }
            // Then apply new total offset
            viewModel.moveElement(at: index, offset: delta)
            viewModel.elementDragOffset = delta
        }
    }
    
    private func handleSelectDragEnd(_ value: DragGesture.Value) {
        viewModel.dragStart = nil
        viewModel.annotationDragOffset = .zero
        viewModel.elementDragOffset = .zero
    }
    
    private func handleDrop(providers: [NSItemProvider], at location: CGPoint) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadObject(ofClass: NSURL.self) { url, error in
            guard let url = url as? URL else { return }
            guard let image = NSImage(contentsOf: url) else { return }
            
            let imageSize = image.size
            let aspectRatio = imageSize.width / imageSize.height
            let defaultHeight: CGFloat = 200
            let defaultWidth = defaultHeight * aspectRatio
            
            Task { @MainActor in
                let zoom = viewModel.zoom
                let unzoomedX = location.x / zoom
                let unzoomedY = location.y / zoom
                
                let element = PDFElementModel(
                    type: .screenshot(url),
                    frame: CGRect(
                        x: unzoomedX - defaultWidth / 2,
                        y: unzoomedY - defaultHeight / 2,
                        width: defaultWidth,
                        height: defaultHeight
                    )
                )
                viewModel.addElement(element)
            }
        }
        
        return true
    }
}

// MARK: - CGPoint Extensions

extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        let dx = x - point.x
        let dy = y - point.y
        return sqrt(dx * dx + dy * dy)
    }
    
    func distanceToLine(start: CGPoint, end: CGPoint) -> CGFloat {
        let A = x - start.x
        let B = y - start.y
        let C = end.x - start.x
        let D = end.y - start.y
        
        let dot = A * C + B * D
        let lenSq = C * C + D * D
        var param: CGFloat = -1
        if lenSq != 0 {
            param = dot / lenSq
        }
        
        var xx: CGFloat
        var yy: CGFloat
        
        if param < 0 {
            xx = start.x
            yy = start.y
        } else if param > 1 {
            xx = end.x
            yy = end.y
        } else {
            xx = start.x + param * C
            yy = start.y + param * D
        }
        
        let dx = x - xx
        let dy = y - yy
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Resize Handle

enum ResizeHandle: String, CaseIterable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight
}

// MARK: - Data Models

enum PDFTool: String, CaseIterable, Identifiable {
    case select = "Select"
    case pen = "Pen"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case circle = "Circle"
    case text = "Text"
    case highlight = "Highlight"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .pen: return "pencil"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        }
    }
}

class PDFDocumentModel: ObservableObject {
    @Published var pages: [PDFPageModel]
    
    init(items: [ScreenshotItem]) {
        self.pages = [PDFPageModel()]
    }
    
    init(pages: [PDFPageModel]) {
        self.pages = pages
    }
    
    func copy() -> PDFDocumentModel {
        return PDFDocumentModel(pages: self.pages)
    }
}

struct PDFPageModel: Identifiable {
    let id = UUID()
    var elements: [PDFElementModel] = []
    var annotations: [PDFAnnotationModel] = []
}

struct PDFElementModel: Identifiable {
    let id = UUID()
    var type: PDFElementType
    var frame: CGRect
}

enum PDFElementType {
    case screenshot(URL)
    case textBox(String)
}

struct PDFAnnotationModel: Identifiable {
    let id = UUID()
    var type: PDFAnnotationType
    var color: NSColor
    var lineWidth: CGFloat
}

enum PDFAnnotationType {
    case freehand([CGPoint])
    case arrow(start: CGPoint, end: CGPoint)
    case rectangle(CGRect)
    case circle(CGRect)
    case text(String, position: CGPoint)
    case highlight(CGRect)
}

// MARK: - Page Render View (for PDF export)

struct PageRenderView: View {
    let page: PDFPageModel
    let size: CGSize
    
    var body: some View {
        ZStack {
            Color.white
            
            // Elements
            ForEach(page.elements) { element in
                switch element.type {
                case .screenshot(let url):
                    if let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: element.frame.width, height: element.frame.height)
                            .position(x: element.frame.midX, y: element.frame.midY)
                    }
                case .textBox(let text):
                    Text(text)
                        .position(x: element.frame.midX, y: element.frame.midY)
                }
            }
            
            // Annotations
            Canvas { context, _ in
                for annotation in page.annotations {
                    let color = Color(annotation.color)
                    
                    switch annotation.type {
                    case .freehand(let points):
                        if points.count > 1 {
                            var path = Path()
                            path.move(to: points[0])
                            for point in points.dropFirst() {
                                path.addLine(to: point)
                            }
                            context.stroke(path, with: .color(color), lineWidth: annotation.lineWidth)
                        }
                        
                    case .arrow(let start, let end):
                        let angle = atan2(end.y - start.y, end.x - start.x)
                        let arrowLength = 14 + annotation.lineWidth * 1.5
                        let arrowAngle: CGFloat = .pi / 7
                        
                        // Stop line at base of arrowhead
                        let lineEnd = CGPoint(
                            x: end.x - arrowLength * 0.7 * cos(angle),
                            y: end.y - arrowLength * 0.7 * sin(angle)
                        )
                        
                        var path = Path()
                        path.move(to: start)
                        path.addLine(to: lineEnd)
                        context.stroke(path, with: .color(color), lineWidth: annotation.lineWidth)
                        
                        var head = Path()
                        let p1 = CGPoint(
                            x: end.x - arrowLength * cos(angle - arrowAngle),
                            y: end.y - arrowLength * sin(angle - arrowAngle)
                        )
                        let p2 = CGPoint(
                            x: end.x - arrowLength * cos(angle + arrowAngle),
                            y: end.y - arrowLength * sin(angle + arrowAngle)
                        )
                        head.move(to: end)
                        head.addLine(to: p1)
                        head.addLine(to: p2)
                        head.closeSubpath()
                        context.fill(head, with: .color(color))
                        
                    case .rectangle(let rect):
                        context.stroke(Path(rect), with: .color(color), lineWidth: annotation.lineWidth)
                        
                    case .circle(let rect):
                        context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: annotation.lineWidth)
                        
                    case .highlight(let rect):
                        context.fill(Path(rect), with: .color(color.opacity(0.3)))
                        
                    case .text(let text, let position):
                        // Use lineWidth as font size for text annotations
                        let fontSize = annotation.lineWidth * size.width / 595
                        context.draw(Text(text).font(.system(size: fontSize)).foregroundColor(color), at: position)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Focusable Text Field

/// A TextField that properly receives keyboard focus
struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> ClickableTextField {
        let textField = ClickableTextField()
        textField.placeholderString = placeholder
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: 13)
        textField.delegate = context.coordinator
        textField.focusRingType = .exterior
        return textField
    }

    func updateNSView(_ nsView: ClickableTextField, context: Context) {
        // Only update if the text actually changed (avoid infinite loops)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder

        // Set up binding
        context.coordinator.textBinding = $text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var textBinding: Binding<String>?

        init(text: Binding<String>) {
            self.textBinding = text
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                textBinding?.wrappedValue = textField.stringValue
            }
        }
    }

    /// Custom NSTextField that properly handles click-to-focus
    class ClickableTextField: NSTextField {
        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            // Make sure we become first responder when clicked
            if let window = self.window {
                window.makeFirstResponder(self)
            }
            super.mouseDown(with: event)
        }

        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            // Select all text when becoming first responder for easier editing
            if result {
                self.currentEditor()?.selectAll(nil)
            }
            return result
        }
    }
}

// MARK: - Key Event Handler

/// A view that captures keyboard events for the PDF editor
struct KeyEventHandlerView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }

    class KeyCaptureView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            // Don't handle key events if a text field is focused
            if let firstResponder = self.window?.firstResponder,
               firstResponder is NSTextView || firstResponder is NSTextField {
                super.keyDown(with: event)
                return
            }

            if let handler = onKeyDown, handler(event) {
                return  // Event was handled
            }
            super.keyDown(with: event)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Only become first responder if no text field is currently focused
            DispatchQueue.main.async {
                guard let window = self.window else { return }
                let firstResponder = window.firstResponder
                // Don't steal focus from text fields or text views
                if !(firstResponder is NSTextView) && !(firstResponder is NSTextField) {
                    window.makeFirstResponder(self)
                }
            }
        }
    }
}
