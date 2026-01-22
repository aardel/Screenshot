import SwiftUI

@main
struct ScreenshotManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var settings = SettingsModel()
    @StateObject private var organization = OrganizationModel()
    @StateObject private var library: ScreenshotLibrary

    // Menu-bar actions need access to the library instance.
    @MainActor static var sharedLibrary: ScreenshotLibrary?
    @MainActor static var sharedSettings: SettingsModel?

    init() {
        let settings = SettingsModel()
        let organization = OrganizationModel()
        _settings = StateObject(wrappedValue: settings)
        _organization = StateObject(wrappedValue: organization)
        _library = StateObject(wrappedValue: ScreenshotLibrary(settings: settings, organization: organization))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(organization)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    ScreenshotManagerApp.sharedLibrary = library
                    ScreenshotManagerApp.sharedSettings = settings
                    
                    // Check permissions before starting
                    await ScreenshotManagerApp.checkAndRequestPermissions()
                    
                    // Initialize default screenshot folder on first launch
                    ScreenshotFolderManager.initializeOnFirstLaunch(settings: settings)
                    
                    library.start()
                    // Ensure cursor is visible and window is key
                    DispatchQueue.main.async {
                        NSCursor.unhide()
                        NSApp.activate(ignoringOtherApps: true)
                        if let window = NSApp.windows.first(where: { $0.isVisible && !($0 is SelectionWindow) && !($0 is CaptureMenuWindow) }) {
                            window.makeKey()
                            // Don't call makeMain() - it's set automatically when window becomes key
                        }
                    }
                }
        }
        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(width: 520)
        }
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("Copy Latest Screenshot") {
                    if let latest = library.latest() {
                        ClipboardActions.copyImage(from: latest.url)
                    }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .textEditing) {
                Button("Select All") {
                    library.selectAll()
                }
                .keyboardShortcut("a", modifiers: [.command])
                Button("Deselect All") {
                    library.deselectAll()
                }
                .keyboardShortcut("d", modifiers: [.command])
                Button("Delete Selected") {
                    library.batchDelete(library.selectedItems())
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(library.selectedItems().isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button("Next Selected") {
                    library.navigateToNextSelected()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(library.selectedIDs.count <= 1)
                
                Button("Previous Selected") {
                    library.navigateToPreviousSelected()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(library.selectedIDs.count <= 1)
            }
        }
    }
    
    @MainActor
    static func checkAndRequestPermissions() async {
        // If user previously chose to skip, don't bother them again
        if PermissionChecker.shouldSkipPermissionCheck {
            return
        }

        let hasScreen = PermissionChecker.hasScreenRecordingPermission()
        let hasAccessibility = PermissionChecker.hasAccessibilityPermission()

        // If permissions look good, we're done
        if hasScreen && hasAccessibility {
            return
        }

        // Request missing permissions - this triggers macOS native dialogs
        await PermissionChecker.requestMissingPermissions()
    }
}

