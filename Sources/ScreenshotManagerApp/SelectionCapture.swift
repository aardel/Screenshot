import AppKit
import CoreGraphics
import Foundation

final class SelectionCapture: NSObject {
    private var overlayWindows: [SelectionWindow] = []
    private var completion: ((NSImage?) -> Void)?
    private var eventMonitor: Any?
    private var isInteractive = false
    private var activeWindow: SelectionWindow?

    deinit {
        // Ensure cleanup if object is deallocated before finish() is called
        cleanup()
    }

    private func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        for w in overlayWindows {
            w.orderOut(nil)
        }
        overlayWindows.removeAll()
        activeWindow = nil
    }

    private func restoreCursor() {
        NSCursor.unhide()
        NSCursor.arrow.set()
    }

    func start(interactive: Bool = false, completion: @escaping (NSImage?) -> Void) {
        self.completion = completion
        self.isInteractive = interactive
        self.activeWindow = nil

        // Monitor for ESC key to cancel, Enter to confirm (in interactive mode)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                self?.finish(with: nil, from: nil)
            } else if event.keyCode == 36 && self?.isInteractive == true { // Enter key
                self?.confirmInteractiveCapture()
            }
        }

        // Activate app first
        NSApp.activate(ignoringOtherApps: true)

        // Create a window for each screen
        for (index, screen) in NSScreen.screens.enumerated() {
            let window = SelectionWindow(screen: screen, interactive: interactive)
            window.selectionEnded = { [weak self] rect, sourceWindow in
                self?.finish(with: rect, from: sourceWindow)
            }
            // When selection starts on this window, disable others
            window.selectionStarted = { [weak self] startedWindow in
                self?.handleSelectionStarted(on: startedWindow)
            }
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.orderFrontRegardless()
            overlayWindows.append(window)

            // Make the first window key
            if index == 0 {
                window.makeKey()
            }
        }
    }

    private func handleSelectionStarted(on window: SelectionWindow) {
        // Once selection starts on one screen, disable others
        activeWindow = window
        for w in overlayWindows where w !== window {
            w.disableSelection()
        }
    }

    private func confirmInteractiveCapture() {
        // Find the window with an active selection
        for window in overlayWindows {
            if let rect = window.currentSelection, !rect.isEmpty {
                finish(with: rect, from: window)
                return
            }
        }
    }

    private func finish(with rect: CGRect?, from window: NSWindow?) {
        // Clean up event monitor and windows
        cleanup()

        // Don't hide app windows - we'll exclude them from capture instead
        guard let rect = rect, !rect.isEmpty, let window = window else {
            // Ensure cursor is visible if selection was cancelled or invalid
            restoreCursor()
            completion?(nil)
            return
        }

        // Convert view coordinates to global screen coordinates
        let globalRect = CGRect(
            x: window.frame.origin.x + rect.origin.x,
            y: window.frame.origin.y + rect.origin.y,
            width: rect.width,
            height: rect.height
        )

        // Capture after a short delay to ensure overlay windows are fully gone
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Convert NS coords (origin bottom-left) to CG coords (origin top-left)
            let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
            let cgRect = CGRect(
                x: globalRect.origin.x,
                y: primaryScreenHeight - globalRect.maxY,
                width: globalRect.width,
                height: globalRect.height
            )

            // Capture normally - app windows will only appear if they're actually visible on top
            // macOS window compositing handles this automatically
            guard let cgImage = CGWindowListCreateImage(
                cgRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            ) else {
                // Ensure cursor is visible even if capture failed
                self.restoreCursor()
                self.completion?(nil)
                return
            }
            // Ensure cursor is visible after capture
            self.restoreCursor()
            // Record successful capture to help with permission detection
            Task { @MainActor in
                PermissionChecker.recordSuccessfulCapture()
            }
            self.completion?(NSImage(cgImage: cgImage, size: .zero))
        }
    }
}

final class SelectionWindow: NSWindow {
    var selectionEnded: ((CGRect?, NSWindow?) -> Void)?
    var selectionStarted: ((SelectionWindow) -> Void)?
    private let selectionView: SelectionView

    var currentSelection: CGRect? {
        selectionView.currentRect
    }

    init(screen: NSScreen, interactive: Bool = false) {
        selectionView = SelectionView(frame: .zero, interactive: interactive)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.05)
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = selectionView
        selectionView.selectionEnded = { [weak self] rect in
            self?.selectionEnded?(rect, self)
        }
        selectionView.selectionDidStart = { [weak self] in
            guard let self = self else { return }
            self.selectionStarted?(self)
        }
    }

    func disableSelection() {
        selectionView.isDisabled = true
        ignoresMouseEvents = true
        // Dim the overlay to show it's inactive
        backgroundColor = NSColor.black.withAlphaComponent(0.3)
    }

    override func makeKey() {
        super.makeKey()
        makeFirstResponder(selectionView)
    }

    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(selectionView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            selectionEnded?(nil, nil)
        } else if event.keyCode == 36 { // Enter
            selectionEnded?(selectionView.currentRect, self)
        } else {
            super.keyDown(with: event)
        }
    }
}

enum SelectionState {
    case idle
    case selecting
    case adjusting
}

enum DragHandle {
    case none
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
    case move
}

final class SelectionView: NSView {
    var selectionEnded: ((CGRect?) -> Void)?
    var selectionDidStart: (() -> Void)?
    var isDisabled: Bool = false

    private var startPoint: CGPoint?
    private(set) var currentRect: CGRect?
    private var mouseLocation: CGPoint = .zero
    private var state: SelectionState = .idle
    private var activeHandle: DragHandle = .none
    private var dragStartRect: CGRect?
    private var dragStartPoint: CGPoint?
    private let isInteractive: Bool
    private let handleSize: CGFloat = 10
    private var hasNotifiedStart: Bool = false

    init(frame frameRect: NSRect, interactive: Bool = false) {
        self.isInteractive = interactive
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            selectionEnded?(nil)
        } else if event.keyCode == 36 && state == .adjusting { // Enter in adjusting mode
            selectionEnded?(currentRect)
        } else {
            super.keyDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            let mouseInScreen = NSEvent.mouseLocation
            let mouseInWindow = window.convertPoint(fromScreen: mouseInScreen)
            mouseLocation = convert(mouseInWindow, from: nil)
            needsDisplay = true

            // Delay cursor hiding to ensure window is fully ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard self?.window != nil else { return }
                NSCursor.hide()
                self?.needsDisplay = true
            }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            NSCursor.unhide()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        mouseLocation = convert(event.locationInWindow, from: nil)

        if state == .adjusting {
            updateCursorForHandle(handleAt(mouseLocation))
        }

        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if state != .adjusting {
            NSCursor.hide()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.unhide()
    }

    override func mouseDown(with event: NSEvent) {
        // Ignore if this view is disabled (another screen has the active selection)
        guard !isDisabled else { return }

        let location = convert(event.locationInWindow, from: nil)
        mouseLocation = location

        if state == .adjusting {
            // In adjusting mode, only allow adjusting the existing selection
            // Check if clicking on a handle or inside the selection
            activeHandle = handleAt(location)
            if activeHandle != .none {
                dragStartRect = currentRect
                dragStartPoint = location
            } else if let rect = currentRect, rect.contains(location) {
                activeHandle = .move
                dragStartRect = currentRect
                dragStartPoint = location
            }
            // If clicking outside, do nothing - don't start a new selection
        } else {
            // Starting fresh selection (from idle state)
            // Ensure cursor is hidden when starting selection
            NSCursor.hide()
            state = .selecting
            startPoint = location
            currentRect = CGRect(origin: location, size: .zero)

            // Notify that selection started (only once)
            if !hasNotifiedStart {
                hasNotifiedStart = true
                selectionDidStart?()
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        mouseLocation = location

        if state == .adjusting && activeHandle != .none {
            guard let startRect = dragStartRect, let startPoint = dragStartPoint else { return }
            let delta = CGPoint(x: location.x - startPoint.x, y: location.y - startPoint.y)
            currentRect = adjustedRect(startRect, handle: activeHandle, delta: delta)
        } else if state == .selecting {
            guard let start = startPoint else { return }
            currentRect = CGRect(x: min(start.x, location.x),
                                 y: min(start.y, location.y),
                                 width: abs(location.x - start.x),
                                 height: abs(location.y - start.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if state == .selecting {
            if isInteractive {
                // Transition to adjusting mode
                state = .adjusting
                NSCursor.unhide()
                NSCursor.arrow.set()
            } else {
                // Finish immediately
                selectionEnded?(currentRect)
            }
        } else if state == .adjusting {
            activeHandle = .none
            dragStartRect = nil
            dragStartPoint = nil
        }
        needsDisplay = true
    }

    private func handleAt(_ point: CGPoint) -> DragHandle {
        guard let rect = currentRect else { return .none }

        let handles: [(DragHandle, CGRect)] = [
            (.topLeft, handleRect(at: CGPoint(x: rect.minX, y: rect.maxY))),
            (.topRight, handleRect(at: CGPoint(x: rect.maxX, y: rect.maxY))),
            (.bottomLeft, handleRect(at: CGPoint(x: rect.minX, y: rect.minY))),
            (.bottomRight, handleRect(at: CGPoint(x: rect.maxX, y: rect.minY))),
            (.top, handleRect(at: CGPoint(x: rect.midX, y: rect.maxY))),
            (.bottom, handleRect(at: CGPoint(x: rect.midX, y: rect.minY))),
            (.left, handleRect(at: CGPoint(x: rect.minX, y: rect.midY))),
            (.right, handleRect(at: CGPoint(x: rect.maxX, y: rect.midY))),
        ]

        for (handle, handleRect) in handles {
            if handleRect.contains(point) {
                return handle
            }
        }
        return .none
    }

    private func handleRect(at center: CGPoint) -> CGRect {
        CGRect(x: center.x - handleSize/2, y: center.y - handleSize/2, width: handleSize, height: handleSize)
    }

    private func adjustedRect(_ rect: CGRect, handle: DragHandle, delta: CGPoint) -> CGRect {
        var newRect = rect

        switch handle {
        case .move:
            newRect.origin.x += delta.x
            newRect.origin.y += delta.y
        case .topLeft:
            newRect.origin.x += delta.x
            newRect.size.width -= delta.x
            newRect.size.height += delta.y
        case .topRight:
            newRect.size.width += delta.x
            newRect.size.height += delta.y
        case .bottomLeft:
            newRect.origin.x += delta.x
            newRect.origin.y += delta.y
            newRect.size.width -= delta.x
            newRect.size.height -= delta.y
        case .bottomRight:
            newRect.origin.y += delta.y
            newRect.size.width += delta.x
            newRect.size.height -= delta.y
        case .top:
            newRect.size.height += delta.y
        case .bottom:
            newRect.origin.y += delta.y
            newRect.size.height -= delta.y
        case .left:
            newRect.origin.x += delta.x
            newRect.size.width -= delta.x
        case .right:
            newRect.size.width += delta.x
        case .none:
            break
        }

        // Ensure minimum size
        if newRect.width < 10 { newRect.size.width = 10 }
        if newRect.height < 10 { newRect.size.height = 10 }

        return newRect
    }

    private func updateCursorForHandle(_ handle: DragHandle) {
        switch handle {
        case .topLeft, .bottomRight:
            NSCursor.crosshair.set()
        case .topRight, .bottomLeft:
            NSCursor.crosshair.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .move:
            NSCursor.openHand.set()
        case .none:
            if let rect = currentRect, rect.contains(mouseLocation) {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.1).setFill()
        dirtyRect.fill()

        if let rect = currentRect {
            NSColor.systemBlue.setStroke()
            NSColor.systemBlue.withAlphaComponent(0.15).setFill()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()
            path.fill()

            // Draw handles in adjusting mode
            if state == .adjusting {
                drawHandles(for: rect)
                drawInstructions(for: rect)
            }
        }

        // Draw crosshair only when not in adjusting mode
        if state != .adjusting {
            drawCrosshair(at: mouseLocation)
        }
    }

    private func drawHandles(for rect: CGRect) {
        let handlePositions = [
            CGPoint(x: rect.minX, y: rect.maxY),  // topLeft
            CGPoint(x: rect.maxX, y: rect.maxY),  // topRight
            CGPoint(x: rect.minX, y: rect.minY),  // bottomLeft
            CGPoint(x: rect.maxX, y: rect.minY),  // bottomRight
            CGPoint(x: rect.midX, y: rect.maxY),  // top
            CGPoint(x: rect.midX, y: rect.minY),  // bottom
            CGPoint(x: rect.minX, y: rect.midY),  // left
            CGPoint(x: rect.maxX, y: rect.midY),  // right
        ]

        for pos in handlePositions {
            let handleRect = self.handleRect(at: pos)
            NSColor.white.setFill()
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(ovalIn: handleRect)
            path.fill()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawInstructions(for rect: CGRect) {
        let text = "Drag handles to adjust • Enter to capture • ESC to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)

        // Position below the selection
        var textRect = CGRect(
            x: rect.midX - size.width/2,
            y: rect.minY - size.height - 15,
            width: size.width,
            height: size.height
        )

        // If too close to bottom, put it above
        if textRect.minY < 20 {
            textRect.origin.y = rect.maxY + 10
        }

        // Draw background pill
        let bgRect = textRect.insetBy(dx: -10, dy: -5)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 10, yRadius: 10).fill()

        text.draw(in: textRect, withAttributes: attributes)
    }

    private func drawCrosshair(at point: CGPoint) {
        let size: CGFloat = 20
        let lineWidth: CGFloat = 2.0

        // Draw black outline FIRST (thicker, acts as shadow/outline)
        NSColor.black.setStroke()

        let hOutline = NSBezierPath()
        hOutline.move(to: CGPoint(x: point.x - size, y: point.y))
        hOutline.line(to: CGPoint(x: point.x + size, y: point.y))
        hOutline.lineWidth = lineWidth + 2
        hOutline.stroke()

        let vOutline = NSBezierPath()
        vOutline.move(to: CGPoint(x: point.x, y: point.y - size))
        vOutline.line(to: CGPoint(x: point.x, y: point.y + size))
        vOutline.lineWidth = lineWidth + 2
        vOutline.stroke()

        // Draw white lines ON TOP (thinner, visible against black outline)
        NSColor.white.setStroke()

        let hPath = NSBezierPath()
        hPath.move(to: CGPoint(x: point.x - size, y: point.y))
        hPath.line(to: CGPoint(x: point.x + size, y: point.y))
        hPath.lineWidth = lineWidth
        hPath.stroke()

        let vPath = NSBezierPath()
        vPath.move(to: CGPoint(x: point.x, y: point.y - size))
        vPath.line(to: CGPoint(x: point.x, y: point.y + size))
        vPath.lineWidth = lineWidth
        vPath.stroke()
    }
}
