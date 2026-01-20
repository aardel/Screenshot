import AppKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

enum ImageEditorTool: String, CaseIterable, Identifiable {
    case pen
    case highlighter
    case line
    case arrow
    case rectangle
    case ellipse
    case text
    case blur
    case crop
    case loupe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Circle"
        case .text: return "Text"
        case .blur: return "Blur"
        case .crop: return "Crop"
        case .loupe: return "Loupe"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil"
        case .highlighter: return "highlighter"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .blur: return "drop"
        case .crop: return "crop"
        case .loupe: return "magnifyingglass.circle"
        }
    }
}

enum ImageAnnotationType {
    case pen(points: [CGPoint])
    case highlighter(points: [CGPoint])
    case line(start: CGPoint, end: CGPoint)
    case arrow(start: CGPoint, end: CGPoint)
    case rectangle(rect: CGRect)
    case ellipse(rect: CGRect)
    case text(point: CGPoint, text: String)
    case blur(rect: CGRect)
    case loupe(center: CGPoint, radius: CGFloat, zoom: CGFloat, target: CGPoint)
}

struct ImageAnnotation: Identifiable {
    let id = UUID()
    let type: ImageAnnotationType
    let color: NSColor
    let lineWidth: CGFloat
}

@MainActor
final class ImageEditorState: ObservableObject {
    @Published var tool: ImageEditorTool = .pen
    @Published var color: NSColor = .systemBlue
    @Published var lineWidth: CGFloat = 4
    @Published var textValue: String = "Text"
    @Published var annotations: [ImageAnnotation] = []
    @Published var draftAnnotation: ImageAnnotation?
    @Published var cropRect: CGRect?
    @Published var notes: String = ""

    private(set) var baseImage: NSImage?
    private(set) var imageSize: CGSize = .zero

    func load(image: NSImage, notes: String) {
        baseImage = image
        imageSize = image.size
        annotations = []
        draftAnnotation = nil
        cropRect = nil
        self.notes = notes
    }

    func reset() {
        annotations = []
        draftAnnotation = nil
        cropRect = nil
    }

    func applyDraft() {
        if let draft = draftAnnotation {
            if case .pen(let points) = draft.type {
                let smoothed = smoothPoints(points)
                let normalized = normalizeFreehand(points: smoothed)
                let updated = ImageAnnotation(type: normalized, color: draft.color, lineWidth: draft.lineWidth)
                annotations.append(updated)
            } else if case .highlighter(let points) = draft.type {
                let smoothed = smoothPoints(points)
                let updated = ImageAnnotation(type: .highlighter(points: smoothed), color: draft.color, lineWidth: draft.lineWidth)
                annotations.append(updated)
            } else {
                annotations.append(draft)
            }
        }
        draftAnnotation = nil
    }

    func renderImage() -> NSImage? {
        guard let base = baseImage else { return nil }
        var workingImage = base

        if let crop = cropRect {
            workingImage = cropImage(base: workingImage, rect: crop)
        }

        let finalImage = NSImage(size: workingImage.size)
        finalImage.lockFocus()
        workingImage.draw(at: .zero, from: CGRect(origin: .zero, size: workingImage.size), operation: .sourceOver, fraction: 1.0)

        for annotation in annotations {
            draw(annotation: annotation, on: finalImage.size, baseImage: workingImage)
        }
        finalImage.unlockFocus()
        return finalImage
    }

    private func cropImage(base: NSImage, rect: CGRect) -> NSImage {
        let cropRect = rect.standardized
        let target = NSImage(size: cropRect.size)
        target.lockFocus()
        base.draw(at: .zero, from: cropRect, operation: .sourceOver, fraction: 1.0)
        target.unlockFocus()
        return target
    }

    private func draw(annotation: ImageAnnotation, on size: CGSize, baseImage: NSImage) {
        switch annotation.type {
        case .pen(let points):
            strokePath(points: points, color: annotation.color, lineWidth: annotation.lineWidth, alpha: 1.0)
        case .highlighter(let points):
            strokePath(points: points, color: annotation.color, lineWidth: annotation.lineWidth * 2, alpha: 0.35)
        case .line(let start, let end):
            strokeLine(start: start, end: end, color: annotation.color, lineWidth: annotation.lineWidth)
        case .arrow(let start, let end):
            strokeArrow(start: start, end: end, color: annotation.color, lineWidth: annotation.lineWidth)
        case .rectangle(let rect):
            strokeRect(rect: rect, color: annotation.color, lineWidth: annotation.lineWidth)
        case .ellipse(let rect):
            strokeEllipse(rect: rect, color: annotation.color, lineWidth: annotation.lineWidth)
        case .text(let point, let text):
            drawText(text: text, at: point, color: annotation.color)
        case .blur(let rect):
            applyBlur(rect: rect, baseImage: baseImage)
        case .loupe(let center, let radius, let zoom, let target):
            drawLoupe(center: target, radius: radius, zoom: zoom, baseImage: baseImage)
        }
    }

    private func strokePath(points: [CGPoint], color: NSColor, lineWidth: CGFloat, alpha: CGFloat) {
        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.lineWidth = lineWidth
        path.move(to: points[0])
        for p in points.dropFirst() {
            path.line(to: p)
        }
        color.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private func strokeLine(start: CGPoint, end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)
        color.setStroke()
        path.stroke()
    }

    private func strokeArrow(start: CGPoint, end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        strokeLine(start: start, end: end, color: color, lineWidth: lineWidth)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 12 + lineWidth
        let arrowAngle: CGFloat = .pi / 6
        let p1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: end)
        path.line(to: p1)
        path.move(to: end)
        path.line(to: p2)
        color.setStroke()
        path.stroke()
    }

    private func strokeRect(rect: CGRect, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath(rect: rect.standardized)
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }

    private func strokeEllipse(rect: CGRect, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath(ovalIn: rect.standardized)
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }

    private func drawText(text: String, at point: CGPoint, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: color
        ]
        let nsText = NSString(string: text)
        nsText.draw(at: point, withAttributes: attrs)
    }

    private func applyBlur(rect: CGRect, baseImage: NSImage) {
        guard let cgImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let ciImage = CIImage(cgImage: cgImage)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = ciImage
        blur.radius = 8
        guard let blurred = blur.outputImage else { return }
        let context = CIContext(options: nil)
        guard let blurredCG = context.createCGImage(blurred, from: ciImage.extent) else { return }

        let targetRect = rect.standardized
        let cropped = NSImage(cgImage: blurredCG, size: baseImage.size)
        cropped.draw(at: CGPoint.zero, from: targetRect, operation: .sourceOver, fraction: 1.0)
    }

    private func drawLoupe(center: CGPoint, radius: CGFloat, zoom: CGFloat, baseImage: NSImage) {
        let diameter = radius * 2
        let sourceRect = CGRect(
            x: center.x - radius / zoom,
            y: center.y - radius / zoom,
            width: diameter / zoom,
            height: diameter / zoom
        )
        let destRect = CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)

        let clipPath = NSBezierPath(ovalIn: destRect)
        clipPath.addClip()
        baseImage.draw(in: destRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)

        NSColor.white.setStroke()
        clipPath.lineWidth = 3
        clipPath.stroke()
    }

    private func smoothPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result: [CGPoint] = [points.first!]
        let window = 3
        for i in 1..<(points.count - 1) {
            let start = max(0, i - window)
            let end = min(points.count - 1, i + window)
            var sumX: CGFloat = 0
            var sumY: CGFloat = 0
            var count: CGFloat = 0
            for j in start...end {
                sumX += points[j].x
                sumY += points[j].y
                count += 1
            }
            result.append(CGPoint(x: sumX / count, y: sumY / count))
        }
        result.append(points.last!)
        return result
    }

    private func normalizeFreehand(points: [CGPoint]) -> ImageAnnotationType {
        guard let first = points.first, let last = points.last else {
            return .pen(points: points)
        }

        let bounds = points.reduce(CGRect(x: first.x, y: first.y, width: 1, height: 1)) { rect, point in
            rect.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        let width = bounds.width
        let height = bounds.height
        let diagonal = hypot(width, height)
        let startEnd = hypot(last.x - first.x, last.y - first.y)

        // Check for line
        let lineError = maxDistanceToLine(points: points, start: first, end: last)
        if diagonal > 0, lineError < max(6, diagonal * 0.03) {
            return .line(start: first, end: last)
        }

        // Check for closed shape
        if startEnd < max(10, diagonal * 0.15) {
            let aspect = width / max(height, 1)
            let isEllipse = aspect > 0.6 && aspect < 1.6 && isCircular(points: points, bounds: bounds)
            if isEllipse {
                return .ellipse(rect: bounds)
            }
            let rectScore = pointsNearRectangleEdges(points: points, bounds: bounds)
            if rectScore > 0.7 {
                return .rectangle(rect: bounds)
            }
        }

        return .pen(points: points)
    }

    private func maxDistanceToLine(points: [CGPoint], start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let denom = max(1, hypot(dx, dy))
        var maxDist: CGFloat = 0
        for p in points {
            let dist = abs(dy * p.x - dx * p.y + end.x * start.y - end.y * start.x) / denom
            maxDist = max(maxDist, dist)
        }
        return maxDist
    }

    private func isCircular(points: [CGPoint], bounds: CGRect) -> Bool {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(bounds.width, bounds.height) * 0.5
        guard radius > 1 else { return false }
        var variance: CGFloat = 0
        for p in points {
            let dist = hypot(p.x - center.x, p.y - center.y)
            variance += abs(dist - radius)
        }
        let avg = variance / CGFloat(points.count)
        return avg < radius * 0.15
    }

    private func pointsNearRectangleEdges(points: [CGPoint], bounds: CGRect) -> CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 0 }
        let threshold: CGFloat = 8
        var hits: CGFloat = 0
        for p in points {
            let left = abs(p.x - bounds.minX) < threshold
            let right = abs(p.x - bounds.maxX) < threshold
            let top = abs(p.y - bounds.minY) < threshold
            let bottom = abs(p.y - bounds.maxY) < threshold
            if left || right || top || bottom {
                hits += 1
            }
        }
        return hits / CGFloat(points.count)
    }
}

struct ImageEditorView: View {
    @ObservedObject var editor: ImageEditorState
    let imageURL: URL
    let onSave: (NSImage, String) -> Void
    let onCancel: () -> Void

    @State private var dragStart: CGPoint?
    @State private var dragPoints: [CGPoint] = []
    @State private var activeLoupeID: UUID?
    @State private var loupeDragOffset: CGPoint = .zero
    @State private var loupeZoom: CGFloat = 2.8

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                editorToolbar
                    .padding(8)
                    .background(.ultraThinMaterial)
                GeometryReader { imageProxy in
                    ZStack {
                        if let image = editor.baseImage {
                            let imageRect = aspectFitRect(imageSize: image.size, in: imageProxy.size)
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: imageProxy.size.width, height: imageProxy.size.height)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                .overlay(
                                    Canvas { context, size in
                                        for annotation in editor.annotations {
                                            draw(annotation: annotation, in: context, imageRect: imageRect)
                                        }
                                        if let draft = editor.draftAnnotation {
                                            draw(annotation: draft, in: context, imageRect: imageRect)
                                        }
                                        if let crop = editor.cropRect {
                                            let rect = mapImageRectToView(crop, imageRect: imageRect)
                                            let path = Path(rect)
                                            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
                                        }
                                    }
                                )
                                .overlay(loupeOverlay(imageRect: imageRect).allowsHitTesting(false))
                                .contentShape(Rectangle())
                                .gesture(dragGesture(imageRect: imageRect))
                        } else {
                            ProgressView()
                        }
                    }
                }
            }
        }
    }

    private var editorToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(ImageEditorTool.allCases) { tool in
                    Button {
                        editor.tool = tool
                    } label: {
                        Image(systemName: tool.systemImage)
                            .foregroundColor(editor.tool == tool ? .white : .primary)
                            .padding(6)
                            .background(editor.tool == tool ? Color.accentColor : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .help(tool.label)
                }
            }
            HStack(spacing: 12) {
                ColorPicker("", selection: Binding(get: {
                    Color(editor.color)
                }, set: { newValue in
                    editor.color = NSColor(newValue)
                }))
                .labelsHidden()

                Slider(value: $editor.lineWidth, in: 2...12)
                    .frame(width: 120)
                    .help("Line Width")

                if editor.tool == .text {
                    TextField("Text", text: $editor.textValue)
                        .frame(width: 180)
                }
                if editor.tool == .loupe {
                    Text("Zoom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $loupeZoom, in: 2.0...5.0, step: 0.1)
                        .frame(width: 140)
                        .help("Loupe Zoom")
                }

                Spacer()

                Button("Reset") { editor.reset() }
                Button("Cancel") { onCancel() }
                Button("Save") {
                    guard let rendered = editor.renderImage() else { return }
                    onSave(rendered, editor.notes)
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Text("Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $editor.notes)
                    .frame(height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func dragGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let viewPoint = value.location
                
                // If we're already dragging a loupe, continue dragging it (don't re-check hit test)
                if let activeID = activeLoupeID {
                    let imagePoint = mapViewPointToImage(viewPoint, imageRect: imageRect)
                    let newCenter = CGPoint(x: imagePoint.x + loupeDragOffset.x, y: imagePoint.y + loupeDragOffset.y)
                    updateLoupeCenter(id: activeID, newCenter: newCenter)
                    return
                }
                
                // Only check hit-test on initial press (when dragStart is nil)
                if dragStart == nil {
                    // Check if we're clicking on an existing loupe (regardless of current tool)
                    if let hit = hitTestLoupe(viewPoint: viewPoint, imageRect: imageRect) {
                        // Starting to drag an existing loupe
                        activeLoupeID = hit.id
                        let imagePoint = mapViewPointToImage(viewPoint, imageRect: imageRect)
                        // Calculate offset from click point to loupe center
                        loupeDragOffset = CGPoint(x: hit.center.x - imagePoint.x, y: hit.center.y - imagePoint.y)
                        dragStart = imagePoint
                        return
                    }
                }
                
                guard imageRect.contains(viewPoint) else { return }
                let imagePoint = mapViewPointToImage(viewPoint, imageRect: imageRect)

                switch editor.tool {
                case .pen, .highlighter:
                    if dragStart == nil {
                        dragStart = imagePoint
                        dragPoints = [imagePoint]
                    } else {
                        dragPoints.append(imagePoint)
                    }
                    let annotationType: ImageAnnotationType = editor.tool == .pen
                    ? .pen(points: dragPoints)
                    : .highlighter(points: dragPoints)
                    editor.draftAnnotation = ImageAnnotation(type: annotationType, color: editor.color, lineWidth: editor.lineWidth)
                case .line, .arrow, .rectangle, .ellipse, .blur, .crop:
                    if dragStart == nil {
                        dragStart = imagePoint
                    }
                    guard let start = dragStart else { return }
                    let rect = CGRect(x: start.x, y: start.y, width: imagePoint.x - start.x, height: imagePoint.y - start.y).standardized
                    switch editor.tool {
                    case .line:
                        editor.draftAnnotation = ImageAnnotation(type: .line(start: start, end: imagePoint), color: editor.color, lineWidth: editor.lineWidth)
                    case .arrow:
                        editor.draftAnnotation = ImageAnnotation(type: .arrow(start: start, end: imagePoint), color: editor.color, lineWidth: editor.lineWidth)
                    case .rectangle:
                        editor.draftAnnotation = ImageAnnotation(type: .rectangle(rect: rect), color: editor.color, lineWidth: editor.lineWidth)
                    case .ellipse:
                        editor.draftAnnotation = ImageAnnotation(type: .ellipse(rect: rect), color: editor.color, lineWidth: editor.lineWidth)
                    case .blur:
                        editor.draftAnnotation = ImageAnnotation(type: .blur(rect: rect), color: editor.color, lineWidth: editor.lineWidth)
                    case .crop:
                        editor.cropRect = rect
                    default:
                        break
                    }
                case .loupe:
                    if dragStart == nil {
                        // First click sets the target (what we're zooming into)
                        dragStart = imagePoint
                        // Start with loupe centered on target
                        editor.draftAnnotation = ImageAnnotation(type: .loupe(center: imagePoint, radius: 50, zoom: loupeZoom, target: imagePoint), color: editor.color, lineWidth: editor.lineWidth)
                    } else if let start = dragStart {
                        // Dragging sets the radius and keeps the loupe centered on the drag point
                        // but target stays at the initial click point
                        let radius = max(abs(imagePoint.x - start.x), abs(imagePoint.y - start.y))
                        editor.draftAnnotation = ImageAnnotation(type: .loupe(center: imagePoint, radius: max(radius, 30), zoom: loupeZoom, target: start), color: editor.color, lineWidth: editor.lineWidth)
                    }
                case .text:
                    if dragStart == nil {
                        dragStart = imagePoint
                        editor.draftAnnotation = ImageAnnotation(type: .text(point: imagePoint, text: editor.textValue), color: editor.color, lineWidth: editor.lineWidth)
                    }
                }
            }
            .onEnded { _ in
                if editor.tool == .crop {
                    // Keep crop rect but don't add as annotation
                } else {
                    editor.applyDraft()
                }
                dragStart = nil
                dragPoints = []
                activeLoupeID = nil
            }
    }

    private func draw(annotation: ImageAnnotation, in context: GraphicsContext, imageRect: CGRect) {
        switch annotation.type {
        case .pen(let points):
            let path = pathFromPoints(points, imageRect: imageRect)
            context.stroke(path, with: .color(Color(annotation.color)), lineWidth: annotation.lineWidth)
        case .highlighter(let points):
            let path = pathFromPoints(points, imageRect: imageRect)
            context.stroke(path, with: .color(Color(annotation.color).opacity(0.35)), lineWidth: annotation.lineWidth * 2)
        case .line(let start, let end):
            context.stroke(Path { p in
                p.move(to: mapImagePointToView(start, imageRect: imageRect))
                p.addLine(to: mapImagePointToView(end, imageRect: imageRect))
            }, with: .color(Color(annotation.color)), lineWidth: annotation.lineWidth)
        case .arrow(let start, let end):
            let startPoint = mapImagePointToView(start, imageRect: imageRect)
            let endPoint = mapImagePointToView(end, imageRect: imageRect)
            let path = arrowPath(start: startPoint, end: endPoint, lineWidth: annotation.lineWidth)
            context.stroke(path, with: .color(Color(annotation.color)), lineWidth: annotation.lineWidth)
        case .rectangle(let rect):
            let viewRect = mapImageRectToView(rect, imageRect: imageRect)
            context.stroke(Path(viewRect), with: .color(Color(annotation.color)), lineWidth: annotation.lineWidth)
        case .ellipse(let rect):
            let viewRect = mapImageRectToView(rect, imageRect: imageRect)
            context.stroke(Path(ellipseIn: viewRect), with: .color(Color(annotation.color)), lineWidth: annotation.lineWidth)
        case .text(let point, let text):
            let viewPoint = mapImagePointToView(point, imageRect: imageRect)
            context.draw(Text(text).font(.system(size: 18, weight: .medium)).foregroundColor(Color(annotation.color)), at: viewPoint, anchor: .topLeading)
        case .blur(let rect):
            let viewRect = mapImageRectToView(rect, imageRect: imageRect)
            context.fill(Path(viewRect), with: .color(Color.gray.opacity(0.2)))
        case .loupe(let center, let radius, _, let target):
            let centerPoint = mapImagePointToView(center, imageRect: imageRect)
            let targetPoint = mapImagePointToView(target, imageRect: imageRect)
            let viewRadius = radius * imageRect.width / (editor.imageSize.width == 0 ? 1 : editor.imageSize.width)
            let rect = CGRect(x: centerPoint.x - viewRadius, y: centerPoint.y - viewRadius, width: viewRadius * 2, height: viewRadius * 2)
            
            // Draw loupe circle
            context.stroke(Path(ellipseIn: rect), with: .color(.accentColor), lineWidth: 3)
            
            // Only draw arrow if loupe has been moved away from target
            let distance = hypot(centerPoint.x - targetPoint.x, centerPoint.y - targetPoint.y)
            if distance > viewRadius + 10 { // Only show arrow if moved beyond the loupe radius
                let edgePoint = circleEdgePoint(center: centerPoint, radius: viewRadius, toward: targetPoint)
                let arrow = arrowPath(start: edgePoint, end: targetPoint, lineWidth: 2)
                context.stroke(arrow, with: .color(.accentColor), lineWidth: 2)
            }
        }
    }

    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        let imageAspect = imageSize.width / max(imageSize.height, 1)
        let containerAspect = container.width / max(container.height, 1)
        if imageAspect > containerAspect {
            let width = container.width
            let height = width / imageAspect
            return CGRect(x: 0, y: (container.height - height) / 2, width: width, height: height)
        } else {
            let height = container.height
            let width = height * imageAspect
            return CGRect(x: (container.width - width) / 2, y: 0, width: width, height: height)
        }
    }

    private func mapViewPointToImage(_ point: CGPoint, imageRect: CGRect) -> CGPoint {
        let x = (point.x - imageRect.minX) / imageRect.width * editor.imageSize.width
        let yFromTop = (point.y - imageRect.minY) / imageRect.height * editor.imageSize.height
        let y = editor.imageSize.height - yFromTop
        return CGPoint(x: x, y: y)
    }

    private func mapImagePointToView(_ point: CGPoint, imageRect: CGRect) -> CGPoint {
        let x = imageRect.minX + (point.x / max(editor.imageSize.width, 1)) * imageRect.width
        let yFromTop = (editor.imageSize.height - point.y) / max(editor.imageSize.height, 1) * imageRect.height
        let y = imageRect.minY + yFromTop
        return CGPoint(x: x, y: y)
    }

    private func mapImageRectToView(_ rect: CGRect, imageRect: CGRect) -> CGRect {
        let origin = mapImagePointToView(CGPoint(x: rect.minX, y: rect.maxY), imageRect: imageRect)
        let size = CGSize(
            width: rect.width / max(editor.imageSize.width, 1) * imageRect.width,
            height: rect.height / max(editor.imageSize.height, 1) * imageRect.height
        )
        return CGRect(origin: origin, size: size)
    }

    private func pathFromPoints(_ points: [CGPoint], imageRect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: mapImagePointToView(first, imageRect: imageRect))
        for p in points.dropFirst() {
            path.addLine(to: mapImagePointToView(p, imageRect: imageRect))
        }
        return path
    }

    private func arrowPath(start: CGPoint, end: CGPoint, lineWidth: CGFloat) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength = 12 + lineWidth
        let arrowAngle: CGFloat = .pi / 6
        let p1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        path.move(to: end)
        path.addLine(to: p1)
        path.move(to: end)
        path.addLine(to: p2)
        return path
    }

    private func circleEdgePoint(center: CGPoint, radius: CGFloat, toward target: CGPoint) -> CGPoint {
        let angle = atan2(target.y - center.y, target.x - center.x)
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    @ViewBuilder
    private func loupeOverlay(imageRect: CGRect) -> some View {
        if let image = editor.baseImage {
            ForEach(loupeItems(), id: \.id) { item in
                let centerView = mapImagePointToView(item.center, imageRect: imageRect)
                let viewRadius = item.radius * imageRect.width / (editor.imageSize.width == 0 ? 1 : editor.imageSize.width)
                LoupePreviewView(
                    image: image,
                    targetImage: item.target,
                    radius: viewRadius,
                    zoom: item.zoom
                )
                .frame(width: viewRadius * 2, height: viewRadius * 2)
                .position(centerView)
            }
        }
    }

    private func loupeItems() -> [(id: UUID, center: CGPoint, radius: CGFloat, zoom: CGFloat, target: CGPoint)] {
        var items: [(UUID, CGPoint, CGFloat, CGFloat, CGPoint)] = []
        for annotation in editor.annotations {
            if case .loupe(let center, let radius, let zoom, let target) = annotation.type {
                items.append((annotation.id, center, radius, zoom, target))
            }
        }
        if let draft = editor.draftAnnotation, case .loupe(let center, let radius, let zoom, let target) = draft.type {
            items.append((draft.id, center, radius, zoom, target))
        }
        return items
    }

    private func hitTestLoupe(viewPoint: CGPoint, imageRect: CGRect) -> (id: UUID, center: CGPoint, radius: CGFloat)? {
        for annotation in editor.annotations {
            if case .loupe(let center, let radius, _, _) = annotation.type {
                let centerView = mapImagePointToView(center, imageRect: imageRect)
                let viewRadius = radius * imageRect.width / (editor.imageSize.width == 0 ? 1 : editor.imageSize.width)
                let dist = hypot(viewPoint.x - centerView.x, viewPoint.y - centerView.y)
                if dist <= viewRadius {
                    return (annotation.id, center, radius)
                }
            }
        }
        return nil
    }

    private func updateLoupeCenter(id: UUID, newCenter: CGPoint) {
        guard let index = editor.annotations.firstIndex(where: { $0.id == id }) else { return }
        let annotation = editor.annotations[index]
        if case .loupe(_, let radius, let zoom, let target) = annotation.type {
            let updated = ImageAnnotation(type: .loupe(center: newCenter, radius: radius, zoom: zoom, target: target), color: annotation.color, lineWidth: annotation.lineWidth)
            editor.annotations[index] = updated
        }
    }
}

private struct LoupePreviewView: NSViewRepresentable {
    let image: NSImage
    let targetImage: CGPoint
    let radius: CGFloat
    let zoom: CGFloat

    func makeNSView(context: Context) -> LoupeNSView {
        let view = LoupeNSView()
        view.image = image
        view.targetImage = targetImage
        view.radius = radius
        view.zoom = zoom
        return view
    }

    func updateNSView(_ nsView: LoupeNSView, context: Context) {
        nsView.image = image
        nsView.targetImage = targetImage
        nsView.radius = radius
        nsView.zoom = zoom
        nsView.needsDisplay = true
    }
}

private final class LoupeNSView: NSView {
    var image: NSImage?
    var targetImage: CGPoint = .zero
    var radius: CGFloat = 40
    var zoom: CGFloat = 2.8

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }

        let diameter = radius * 2
        let destRect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let sourceRect = CGRect(
            x: targetImage.x - radius / zoom,
            y: targetImage.y - radius / zoom,
            width: diameter / zoom,
            height: diameter / zoom
        )

        let clipPath = NSBezierPath(ovalIn: destRect)
        clipPath.addClip()
        image.draw(in: destRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)

        NSColor.white.setStroke()
        clipPath.lineWidth = 3
        clipPath.stroke()
    }
}
