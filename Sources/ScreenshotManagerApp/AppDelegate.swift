import AppKit
import Foundation
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private let selectionCapture = SelectionCapture()
    private let captureMenuOverlay = CaptureMenuOverlay()
    private var screenRecorder: ScreenRecorder?
    private var windowPicker: WindowPicker?
    private weak var copyAfterCaptureMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Screenshot Manager")
        item.menu = buildMenu()
        statusItem = item

        setupHotkeys()
        
        // Ensure cursor is visible when app launches
        NSCursor.unhide()
        
        // Monitor for app activation to restore cursor after permission dialogs
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Restore cursor when app becomes active (e.g., after permission dialogs)
            NSCursor.unhide()
            NSCursor.arrow.set()
            // Make sure main window is key
            if let window = NSApp.windows.first(where: { $0.isVisible && !($0 is SelectionWindow) && !($0 is CaptureMenuWindow) && !($0 is RecordingIndicatorWindow) && !($0 is WindowBorderOverlay) }) {
                window.makeKey()
                // Don't call makeMain() - it's set automatically when window becomes key
            }
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Open Library", action: #selector(openLibrary), keyEquivalent: "o"))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Copy Latest Screenshot", action: #selector(copyLatest), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Reveal Latest in Finder", action: #selector(revealLatest), keyEquivalent: "r"))

        let copyAfterItem = NSMenuItem(title: "Copy After Capture", action: #selector(toggleCopyAfterCapture), keyEquivalent: "")
        copyAfterItem.state = (ScreenshotManagerApp.sharedSettings?.copyToClipboardAfterCapture ?? true) ? .on : .off
        menu.addItem(copyAfterItem)
        copyAfterCaptureMenuItem = copyAfterItem

        menu.addItem(.separator())

        let captureModifiers: NSEvent.ModifierFlags = [.control, .option, .command]

        let fullItem = NSMenuItem(title: "Capture Full Screen (App)", action: #selector(captureFullScreen), keyEquivalent: "3")
        fullItem.keyEquivalentModifierMask = captureModifiers
        menu.addItem(fullItem)

        let windowItem = NSMenuItem(title: "Capture Front Window (App)", action: #selector(captureFrontWindow), keyEquivalent: "4")
        windowItem.keyEquivalentModifierMask = captureModifiers
        menu.addItem(windowItem)

        let selectionItem = NSMenuItem(title: "Capture Selection (App)", action: #selector(captureSelection), keyEquivalent: "5")
        selectionItem.keyEquivalentModifierMask = captureModifiers
        menu.addItem(selectionItem)

        let interactiveItem = NSMenuItem(title: "Interactive Capture (App)", action: #selector(captureInteractive), keyEquivalent: "6")
        interactiveItem.keyEquivalentModifierMask = captureModifiers
        menu.addItem(interactiveItem)

        let menuItem = NSMenuItem(title: "Capture Menu (App)", action: #selector(showCaptureMenu), keyEquivalent: "7")
        menuItem.keyEquivalentModifierMask = captureModifiers
        menu.addItem(menuItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Record Screen", action: #selector(recordScreen), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Record Window", action: #selector(recordWindow), keyEquivalent: ""))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func openLibrary() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func copyLatest() {
        guard let library = ScreenshotManagerApp.sharedLibrary,
              let latest = library.latest() else { return }
        ClipboardActions.copyImage(from: latest.url)
    }

    @objc private func revealLatest() {
        guard let library = ScreenshotManagerApp.sharedLibrary,
              let latest = library.latest() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([latest.url])
    }

    @objc private func captureFullScreen() {
        guard let image = ScreenshotCapture.captureFullScreen(),
              let library = ScreenshotManagerApp.sharedLibrary else {
            // Restore cursor and focus even if capture failed
            restoreCursorAndFocus()
            return
        }
        if let url = library.saveCapturedImage(image) {
            copyIfEnabled(url: url)
        }
        restoreCursorAndFocus()
    }

    @objc private func captureFrontWindow() {
        guard let library = ScreenshotManagerApp.sharedLibrary else { return }

        // Use window picker to let user select a window
        windowPicker = WindowPicker()
        windowPicker?.start { [weak self] image in
            self?.windowPicker = nil
            guard let image else {
                self?.restoreCursorAndFocus()
                return
            }
            if let url = library.saveCapturedImage(image) {
                self?.copyIfEnabled(url: url)
            }
            self?.restoreCursorAndFocus()
        }
    }

    @objc private func captureSelection() {
        guard let library = ScreenshotManagerApp.sharedLibrary else { return }
        selectionCapture.start(interactive: false) { [weak self] image in
            guard let image else {
                self?.restoreCursorAndFocus()
                return
            }
            if let url = library.saveCapturedImage(image) {
                self?.copyIfEnabled(url: url)
            }
            self?.restoreCursorAndFocus()
        }
    }

    @objc private func captureInteractive() {
        guard let library = ScreenshotManagerApp.sharedLibrary else { return }
        selectionCapture.start(interactive: true) { [weak self] image in
            guard let image else {
                self?.restoreCursorAndFocus()
                return
            }
            if let url = library.saveCapturedImage(image) {
                self?.copyIfEnabled(url: url)
            }
            self?.restoreCursorAndFocus()
        }
    }

    @objc private func toggleCopyAfterCapture() {
        guard let settings = ScreenshotManagerApp.sharedSettings else { return }
        settings.copyToClipboardAfterCapture.toggle()
        copyAfterCaptureMenuItem?.state = settings.copyToClipboardAfterCapture ? .on : .off
    }

    private func copyIfEnabled(url: URL) {
        guard ScreenshotManagerApp.sharedSettings?.copyToClipboardAfterCapture ?? true else { return }
        ClipboardActions.copyImage(from: url)
    }
    
    private func restoreCursorAndFocus() {
        // Restore cursor visibility
        NSCursor.unhide()
        NSCursor.arrow.set()
        
        // Restore app focus and make window key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.isVisible && !($0 is SelectionWindow) && !($0 is CaptureMenuWindow) && !($0 is RecordingIndicatorWindow) && !($0 is WindowBorderOverlay) }) {
                window.makeKey()
            }
        }
    }

    @objc private func showCaptureMenu() {
        captureMenuOverlay.show { [weak self] action in
            self?.handleCaptureMenuAction(action)
        }
    }

    private func handleCaptureMenuAction(_ action: CaptureMenuAction) {
        switch action {
        case .fullScreen:
            captureFullScreen()
        case .frontWindow:
            captureFrontWindow()
        case .selection:
            captureSelection()
        case .interactive:
            captureInteractive()
        case .recordScreen:
            recordScreen()
        case .recordWindow:
            recordWindow()
        case .cancel:
            break
        }
    }

    @objc private func recordScreen() {
        if screenRecorder == nil {
            screenRecorder = ScreenRecorder()
            screenRecorder?.onRecordingFinished = { [weak self] url in
                self?.screenRecorder = nil
                if let url = url {
                    // Notify user recording is saved
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        Task {
            await screenRecorder?.startRecordingScreen()
        }
    }

    @objc private func recordWindow() {
        if screenRecorder == nil {
            screenRecorder = ScreenRecorder()
            screenRecorder?.onRecordingFinished = { [weak self] url in
                self?.screenRecorder = nil
                if let url = url {
                    // Notify user recording is saved
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        Task {
            await screenRecorder?.startRecordingWindow()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setupHotkeys() {
        let manager = HotkeyManager()
        let cmd: UInt32 = UInt32(cmdKey)
        let opt: UInt32 = UInt32(optionKey)
        let ctrl: UInt32 = UInt32(controlKey)
        // ctrl + option + cmd + 3
        manager.register(id: 1, keyCode: 20, modifiers: ctrl | opt | cmd) { [weak self] in
            self?.captureFullScreen()
        }
        // ctrl + option + cmd + 4
        manager.register(id: 2, keyCode: 21, modifiers: ctrl | opt | cmd) { [weak self] in
            self?.captureFrontWindow()
        }
        // ctrl + option + cmd + 5 for selection
        manager.register(id: 3, keyCode: 23, modifiers: ctrl | opt | cmd) { [weak self] in
            self?.captureSelection()
        }
        // ctrl + option + cmd + 6 for interactive capture
        manager.register(id: 4, keyCode: 22, modifiers: ctrl | opt | cmd) { [weak self] in
            self?.captureInteractive()
        }
        // ctrl + option + cmd + 7 for capture menu
        manager.register(id: 5, keyCode: 26, modifiers: ctrl | opt | cmd) { [weak self] in
            self?.showCaptureMenu()
        }
        hotkeyManager = manager
    }
}

