import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    @State private var lastPickedFolder: URL?

    var body: some View {
        Form {
            Section("Watched Folder") {
                HStack(alignment: .center) {
                    Text(currentFolderLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)

                    Spacer()

                    Button("Choose…") { chooseFolder() }
                }
            }

            Section("Filters") {
                Picker("Date range", selection: $settings.dateFilter) {
                    ForEach(SettingsModel.DateFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Capture") {
                Toggle("Copy to clipboard after capture", isOn: $settings.copyToClipboardAfterCapture)
            }

            Section {
                Text("Local-first. No uploads. (Sharing features are future opt-in.)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Screen Recording:")
                        Spacer()
                        Text(PermissionChecker.hasScreenRecordingPermission() ? "Granted" : "Not Granted")
                            .foregroundColor(PermissionChecker.hasScreenRecordingPermission() ? .green : .red)
                    }
                    HStack {
                        Text("Accessibility:")
                        Spacer()
                        Text(PermissionChecker.hasAccessibilityPermission() ? "Granted" : "Not Granted")
                            .foregroundColor(PermissionChecker.hasAccessibilityPermission() ? .green : .red)
                    }

                    Divider()

                    HStack {
                        Button("Request Permissions") {
                            Task {
                                await PermissionChecker.requestMissingPermissions()
                            }
                        }

                        Button("Open Screen Recording Settings") {
                            PermissionChecker.openSystemSettings(for: .screenRecording)
                        }
                        .buttonStyle(.link)
                    }

                    Text("If permissions don't work after an app update, remove the old entry in System Settings and re-add it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            Section("Capture & macOS Shortcuts") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("App hotkeys (active when app is running):")
                        .font(.subheadline.weight(.semibold))
                    Text("• Ctrl + Opt + Cmd + 3 → Capture full screen (into library)")
                    Text("• Ctrl + Opt + Cmd + 4 → Capture front window (into library)")
                        .padding(.bottom, 8)

                    Text("To route Apple screenshots into this library:")
                        .font(.subheadline.weight(.semibold))
                    Text("1) System Settings → Keyboard → Keyboard Shortcuts → Screenshots → disable default shortcuts (Cmd+Shift+3/4/5).")
                    Text("2) (Optional) Point Apple screenshots to this folder:\n   defaults write com.apple.screencapture location \"\(currentFolderLabel)\" && killall SystemUIServer")
                        .textSelection(.enabled)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .padding(16)
    }

    private var currentFolderLabel: String {
        if let bookmark = settings.watchedFolderBookmark,
           let url = BookmarkResolver.resolveFolder(from: bookmark) {
            return url.path
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").path
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch this folder"
        panel.directoryURL = lastPickedFolder ?? FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url {
            lastPickedFolder = url
            do {
                let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                settings.watchedFolderBookmark = data
            } catch {
                // Ignore for now; we'll add user-visible error later.
            }
        }
    }
}

