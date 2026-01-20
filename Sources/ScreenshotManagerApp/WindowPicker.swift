import AppKit
import CoreGraphics
import Foundation

/// Window picker that lets user click to select a window for capture
final class WindowPicker {
    private var overlayWindows: [WindowPickerOverlay] = []
    private var highlightWindow: WindowHighlightOverlay?
    private var completion: ((NSImage?) -> Void)?
    private var hoveredWindowID: CGWindowID?
    private var eventMonitor: Any?

    func start(completion: @escaping (NSImage?) -> Void) {
        self.completion = completion

        // Create overlay on each screen
        for screen in NSScreen.screens {
            let overlay = WindowPickerOverlay(screen: screen)
            overlay.onMouseMoved = { [weak self] point in
                self?.handleMouseMoved(to: point)
            }
            overlay.onMouseClicked = { [weak self] point in
                self?.handleMouseClicked(at: point)
            }
            overlay.makeKeyAndOrderFront(nil)
            overlayWindows.append(overlay)
        }

        // Monitor for ESC key
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.finish(with: nil)
                return nil
            }
            return event
        }

        // Activate app to receive events
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleMouseMoved(to point: NSPoint) {
        // Ensure point is on a screen
        guard NSScreen.screens.contains(where: { NSPointInRect(point, $0.frame) }) else { return }

        // Find window under cursor
        let windowID = windowUnderPoint(point)

        if windowID != hoveredWindowID {
            hoveredWindowID = windowID
            updateHighlight()
        }
    }

    private func handleMouseClicked(at point: NSPoint) {
        guard let windowID = hoveredWindowID else {
            finish(with: nil)
            return
        }

        // Capture the selected window
        captureWindow(windowID: windowID)
    }

    private func windowUnderPoint(_ point: NSPoint) -> CGWindowID? {
        // Get all on-screen windows
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Convert NSPoint to CGPoint (flip Y coordinate for CG)
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = CGPoint(x: point.x, y: screenHeight - point.y)

        for windowInfo in windowList {
            // Skip our own overlay windows
            guard let windowLayer = windowInfo[kCGWindowLayer as String] as? Int,
                  windowLayer == 0 else { continue } // Only normal windows

            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else { continue }

            let windowFrame = CGRect(x: x, y: y, width: width, height: height)

            if windowFrame.contains(cgPoint) {
                if let windowNumber = windowInfo[kCGWindowNumber as String] as? Int {
                    // Skip our own windows
                    let isOurWindow = overlayWindows.contains { Int($0.windowNumber) == windowNumber } ||
                                      (highlightWindow != nil && Int(highlightWindow!.windowNumber) == windowNumber)
                    if !isOurWindow {
                        return CGWindowID(windowNumber)
                    }
                }
            }
        }

        return nil
    }

    private func updateHighlight() {
        // Remove existing highlight
        highlightWindow?.orderOut(nil)
        highlightWindow = nil

        guard let windowID = hoveredWindowID else { return }

        // Get window frame
        guard let windowFrame = frameForWindow(windowID) else { return }

        // Convert CG coordinates to NS coordinates
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsFrame = CGRect(
            x: windowFrame.origin.x,
            y: screenHeight - windowFrame.origin.y - windowFrame.height,
            width: windowFrame.width,
            height: windowFrame.height
        )

        // Create highlight window
        highlightWindow = WindowHighlightOverlay(frame: nsFrame)
        highlightWindow?.orderFront(nil)
    }

    private func frameForWindow(_ windowID: CGWindowID) -> CGRect? {
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let windowList = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]],
              let windowInfo = windowList.first,
              let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"],
              let y = boundsDict["Y"],
              let width = boundsDict["Width"],
              let height = boundsDict["Height"] else {
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func captureWindow(windowID: CGWindowID) {
        // Clean up overlays first
        cleanup()

        // Small delay to let overlays disappear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let bounds = CGRect.null
            let imageOption: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]

            guard let cgImage = CGWindowListCreateImage(bounds, .optionIncludingWindow, windowID, imageOption) else {
                self?.completion?(nil)
                return
            }

            // Record successful capture
            Task { @MainActor in
                PermissionChecker.recordSuccessfulCapture()
            }

            self?.completion?(NSImage(cgImage: cgImage, size: .zero))
        }
    }

    private func finish(with image: NSImage?) {
        cleanup()
        completion?(image)
    }

    private func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        highlightWindow?.orderOut(nil)
        highlightWindow = nil

        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    deinit {
        cleanup()
    }
}

// Overlay window for picking
final class WindowPickerOverlay: NSWindow {
    var onMouseMoved: ((NSPoint) -> Void)?
    var onMouseClicked: ((NSPoint) -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.3)
        ignoresMouseEvents = false
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = WindowPickerView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.onMouseMoved = { [weak self] point in
            // Convert to screen coordinates
            let screenPoint = NSPoint(x: screen.frame.origin.x + point.x, y: screen.frame.origin.y + point.y)
            self?.onMouseMoved?(screenPoint)
        }
        view.onMouseClicked = { [weak self] point in
            let screenPoint = NSPoint(x: screen.frame.origin.x + point.x, y: screen.frame.origin.y + point.y)
            self?.onMouseClicked?(screenPoint)
        }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class WindowPickerView: NSView {
    var onMouseMoved: ((NSPoint) -> Void)?
    var onMouseClicked: ((NSPoint) -> Void)?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTracking()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTracking() {
        let options: NSTrackingArea.Options = [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        setupTracking()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseMoved?(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseClicked?(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw instructions
        let text = "Click on a window to capture it. Press ESC to cancel."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - size.height - 60,
            width: size.width,
            height: size.height
        )

        // Background pill
        let bgRect = rect.insetBy(dx: -16, dy: -8)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 12, yRadius: 12).fill()

        text.draw(in: rect, withAttributes: attributes)
    }
}

// Highlight overlay for selected window
final class WindowHighlightOverlay: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let borderView = WindowHighlightView(frame: CGRect(origin: .zero, size: frame.size))
        contentView = borderView
    }

    override var canBecomeKey: Bool { false }
}

final class WindowHighlightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw white dotted border
        let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        borderPath.lineWidth = 4

        // Dashed line pattern
        let dashPattern: [CGFloat] = [10, 6]
        borderPath.setLineDash(dashPattern, count: 2, phase: 0)

        // Draw black outline first for contrast
        NSColor.black.setStroke()
        borderPath.lineWidth = 6
        borderPath.stroke()

        // Draw white border on top
        NSColor.white.setStroke()
        borderPath.lineWidth = 4
        borderPath.stroke()
    }
}
