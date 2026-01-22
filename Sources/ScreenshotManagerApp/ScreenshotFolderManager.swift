import Foundation
import AppKit

/// Manages screenshot folder configuration and macOS system integration
enum ScreenshotFolderManager {
    
    /// Default screenshot folder path
    static var defaultFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("Screenshots")
    }
    
    /// Creates the default screenshot folder if it doesn't exist
    @discardableResult
    static func createDefaultFolderIfNeeded() -> URL {
        let url = defaultFolderURL
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                ErrorLogger.shared.debug("Created default screenshot folder: \(url.path)")
            } catch {
                ErrorLogger.shared.log(error, context: "Failed to create default screenshot folder", showToUser: false)
            }
        }
        return url
    }
    
    /// Gets the current macOS system screenshot location
    static func getSystemScreenshotLocation() -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "com.apple.screencapture", "location"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                return output
            }
        } catch {
            ErrorLogger.shared.debug("Could not read system screenshot location: \(error)")
        }
        
        return nil
    }
    
    /// Sets the macOS system screenshot location
    static func setSystemScreenshotLocation(_ path: String) {
        // Set the location
        let setTask = Process()
        setTask.launchPath = "/usr/bin/defaults"
        setTask.arguments = ["write", "com.apple.screencapture", "location", path]
        setTask.standardOutput = FileHandle.nullDevice
        setTask.standardError = FileHandle.nullDevice
        
        do {
            try setTask.run()
            setTask.waitUntilExit()
            ErrorLogger.shared.debug("Set system screenshot location to: \(path)")
            
            // Restart SystemUIServer to apply changes
            restartSystemUIServer()
        } catch {
            ErrorLogger.shared.log(error, context: "Failed to set system screenshot location", showToUser: true)
        }
    }
    
    /// Restarts SystemUIServer to apply screenshot location changes
    private static func restartSystemUIServer() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["SystemUIServer"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            ErrorLogger.shared.debug("Restarted SystemUIServer")
        } catch {
            ErrorLogger.shared.debug("Could not restart SystemUIServer: \(error)")
        }
    }
    
    /// Initializes the default folder on first app launch and syncs to system
    @MainActor
    static func initializeOnFirstLaunch(settings: SettingsModel) {
        // Check if we've already initialized
        if settings.hasInitializedScreenshotFolder {
            return
        }
        
        // Create the default folder
        let defaultURL = createDefaultFolderIfNeeded()
        
        // Create security-scoped bookmark for the default folder
        do {
            let bookmark = try defaultURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            settings.watchedFolderBookmark = bookmark
            
            // Set macOS system screenshot location
            setSystemScreenshotLocation(defaultURL.path)
            
            // Mark as initialized
            settings.hasInitializedScreenshotFolder = true
            
            ErrorLogger.shared.debug("Initialized default screenshot folder: \(defaultURL.path)")
        } catch {
            ErrorLogger.shared.log(error, context: "Failed to initialize screenshot folder", showToUser: false)
        }
    }
    
    /// Updates both app and system screenshot location
    @MainActor
    static func setScreenshotFolder(_ url: URL, settings: SettingsModel) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            settings.watchedFolderBookmark = bookmark
            
            // Sync to macOS system
            setSystemScreenshotLocation(url.path)
        } catch {
            ErrorLogger.shared.log(error, context: "Failed to set screenshot folder", showToUser: true)
        }
    }
}
