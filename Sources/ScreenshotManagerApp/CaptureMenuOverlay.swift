import AppKit
import ScreenCaptureKit

enum CaptureMenuAction {
    case fullScreen
    case frontWindow
    case selection
    case interactive
    case recordScreen
    case recordWindow
    case cancel
}

final class CaptureMenuOverlay: NSObject {
    private var overlayWindow: CaptureMenuWindow?
    private var eventMonitor: Any?
    private var completion: ((CaptureMenuAction) -> Void)?

    func show(completion: @escaping (CaptureMenuAction) -> Void) {
        self.completion = completion

        // Monitor for ESC key to cancel
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                self?.dismiss(with: .cancel)
            }
        }

        // Create overlay window on main screen
        guard let screen = NSScreen.main else {
            // No screen available, notify caller
            completion(.cancel)
            return
        }
        let window = CaptureMenuWindow(screen: screen)
        window.actionSelected = { [weak self] action in
            self?.dismiss(with: action)
        }
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window

        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismiss(with action: CaptureMenuAction) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        overlayWindow?.orderOut(nil)
        overlayWindow = nil

        completion?(action)
    }
}

final class CaptureMenuWindow: NSWindow {
    var actionSelected: ((CaptureMenuAction) -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.7)
        ignoresMouseEvents = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let menuView = CaptureMenuView(frame: .zero)
        menuView.actionSelected = { [weak self] action in
            self?.actionSelected?(action)
        }
        contentView = menuView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            actionSelected?(.cancel)
        } else {
            super.keyDown(with: event)
        }
    }
}

final class CaptureMenuView: NSView {
    var actionSelected: ((CaptureMenuAction) -> Void)?

    private var buttons: [CaptureButton] = []
    private var hoveredButton: CaptureButton?

    private let menuItems: [(action: CaptureMenuAction, icon: String, title: String, shortcut: String)] = [
        (.fullScreen, "rectangle.inset.filled", "Full Screen", "⌃⌥⌘3"),
        (.frontWindow, "macwindow", "Window", "⌃⌥⌘4"),
        (.selection, "rectangle.dashed", "Selection", "⌃⌥⌘5"),
        (.interactive, "rectangle.and.hand.point.up.left", "Interactive", "⌃⌥⌘6"),
        (.recordScreen, "record.circle", "Record Screen", ""),
        (.recordWindow, "menubar.dock.rectangle", "Record Window", ""),
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupButtons() {
        for item in menuItems {
            let button = CaptureButton(
                action: item.action,
                iconName: item.icon,
                title: item.title,
                shortcut: item.shortcut
            )
            button.target = self
            button.action = #selector(buttonClicked(_:))
            buttons.append(button)
            addSubview(button)
        }
    }

    override func layout() {
        super.layout()

        let buttonWidth: CGFloat = 100
        let buttonHeight: CGFloat = 90
        let spacing: CGFloat = 15
        let totalWidth = CGFloat(buttons.count) * buttonWidth + CGFloat(buttons.count - 1) * spacing
        let startX = (bounds.width - totalWidth) / 2
        let bottomY: CGFloat = 120  // Position from bottom of screen (above Dock)

        for (index, button) in buttons.enumerated() {
            let x = startX + CGFloat(index) * (buttonWidth + spacing)
            button.frame = CGRect(x: x, y: bottomY, width: buttonWidth, height: buttonHeight)
        }
    }

    @objc private func buttonClicked(_ sender: CaptureButton) {
        actionSelected?(sender.captureAction)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw title (above buttons at bottom)
        let title = "Screenshot & Recording"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleRect = CGRect(
            x: (bounds.width - titleSize.width) / 2,
            y: 220,  // Above buttons
            width: titleSize.width,
            height: titleSize.height
        )
        title.draw(in: titleRect, withAttributes: titleAttributes)

        // Draw hint (below buttons at bottom)
        let hint = "Click an option or press ESC to cancel"
        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7)
        ]
        let hintSize = hint.size(withAttributes: hintAttributes)
        let hintRect = CGRect(
            x: (bounds.width - hintSize.width) / 2,
            y: 100,  // Below buttons
            width: hintSize.width,
            height: hintSize.height
        )
        hint.draw(in: hintRect, withAttributes: hintAttributes)
    }
}

final class CaptureButton: NSView {
    let captureAction: CaptureMenuAction
    private let iconName: String
    private let title: String
    private let shortcut: String
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    var target: AnyObject?
    var action: Selector?

    init(action: CaptureMenuAction, iconName: String, title: String, shortcut: String) {
        self.captureAction = action
        self.iconName = iconName
        self.title = title
        self.shortcut = shortcut
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        if let target = target, let action = action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Background
        let bgColor = isHovered
            ? NSColor.white.withAlphaComponent(0.2)
            : NSColor.white.withAlphaComponent(0.1)
        bgColor.setFill()
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        bgPath.fill()

        // Border on hover
        if isHovered {
            NSColor.white.withAlphaComponent(0.3).setStroke()
            bgPath.lineWidth = 2
            bgPath.stroke()
        }

        // Icon
        let iconSize: CGFloat = 32
        let iconRect = CGRect(
            x: (bounds.width - iconSize) / 2,
            y: bounds.height - 45,
            width: iconSize,
            height: iconSize
        )

        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
            let configuredImage = image.withSymbolConfiguration(config)
            configuredImage?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)

            // Tint to white
            NSColor.white.set()
            iconRect.fill(using: .sourceAtop)
        }

        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleRect = CGRect(
            x: (bounds.width - titleSize.width) / 2,
            y: 20,
            width: titleSize.width,
            height: titleSize.height
        )
        title.draw(in: titleRect, withAttributes: titleAttributes)

        // Shortcut
        if !shortcut.isEmpty {
            let shortcutAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.6)
            ]
            let shortcutSize = shortcut.size(withAttributes: shortcutAttributes)
            let shortcutRect = CGRect(
                x: (bounds.width - shortcutSize.width) / 2,
                y: 6,
                width: shortcutSize.width,
                height: shortcutSize.height
            )
            shortcut.draw(in: shortcutRect, withAttributes: shortcutAttributes)
        }
    }
}
