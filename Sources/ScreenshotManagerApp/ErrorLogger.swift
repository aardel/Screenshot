import Foundation
import os.log

/// Centralized error logging and user notification system
/// Thread-safe and can be called from any context
final class ErrorLogger {
    static let shared = ErrorLogger()
    
    private let logger = Logger(subsystem: "com.screenshotmanager", category: "app")
    
    /// Callback for showing user-facing error alerts (called on main thread)
    var onError: (@MainActor (String, String) -> Void)?
    
    private init() {}
    
    // MARK: - Logging Methods
    
    /// Log an error with optional user notification
    func log(_ error: Error, context: String, showToUser: Bool = false, file: String = #file, line: Int = #line) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        logger.error("[\(filename):\(line)] \(context): \(error.localizedDescription)")
        
        if showToUser, let onError {
            let title = "Error: \(context)"
            let message = error.localizedDescription
            Task { @MainActor in
                onError(title, message)
            }
        }
    }
    
    /// Log a message with error level
    func error(_ message: String, showToUser: Bool = false, file: String = #file, line: Int = #line) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        logger.error("[\(filename):\(line)] \(message)")
        
        if showToUser, let onError {
            Task { @MainActor in
                onError("Error", message)
            }
        }
    }
    
    /// Log a warning message
    func warning(_ message: String, file: String = #file, line: Int = #line) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        logger.warning("[\(filename):\(line)] \(message)")
    }
    
    /// Log an info message
    func info(_ message: String, file: String = #file, line: Int = #line) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        logger.info("[\(filename):\(line)] \(message)")
    }
    
    /// Log a debug message
    func debug(_ message: String, file: String = #file, line: Int = #line) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        logger.debug("[\(filename):\(line)] \(message)")
    }
    
    // MARK: - Convenience Methods
    
    /// Log file operation failure
    func logFileOperation(_ operation: String, path: String, error: Error, showToUser: Bool = false) {
        let message = "\(operation) failed for \(path): \(error.localizedDescription)"
        logger.error("\(message)")
        
        if showToUser, let onError {
            let userMessage = "\(operation) failed: \(error.localizedDescription)"
            Task { @MainActor in
                onError("File Operation Error", userMessage)
            }
        }
    }
    
    /// Log metadata operation failure
    func logMetadataOperation(_ operation: String, error: Error?, showToUser: Bool = true) {
        if let error = error {
            logger.error("\(operation): \(error.localizedDescription)")
            if showToUser, let onError {
                Task { @MainActor in
                    onError("Metadata Error", "\(operation): \(error.localizedDescription)")
                }
            }
        } else {
            logger.error("\(operation): Unknown error")
            if showToUser, let onError {
                Task { @MainActor in
                    onError("Metadata Error", operation)
                }
            }
        }
    }
    
    /// Log capture failure
    func logCapture(_ type: String, error: Error?, showToUser: Bool = true) {
        if let error = error {
            logger.error("Screenshot capture (\(type)) failed: \(error.localizedDescription)")
            if showToUser, let onError {
                Task { @MainActor in
                    onError("Capture Failed", "Could not capture \(type): \(error.localizedDescription)")
                }
            }
        } else {
            logger.error("Screenshot capture (\(type)) failed")
            if showToUser, let onError {
                Task { @MainActor in
                    onError("Capture Failed", "Could not capture \(type)")
                }
            }
        }
    }
}

// MARK: - Global Convenience

/// Global logging function for quick access
func logError(_ error: Error, context: String, showToUser: Bool = false, file: String = #file, line: Int = #line) {
    Task { @MainActor in
        ErrorLogger.shared.log(error, context: context, showToUser: showToUser, file: file, line: line)
    }
}
