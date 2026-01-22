import Foundation

final class DirectoryWatcher {
    private let url: URL
    private let onChange: () -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        
        // Open file descriptor
        fd = open(url.path, O_EVTONLY)
        guard fd != -1 else {
            ErrorLogger.shared.warning("Failed to open directory for watching: \(url.path)")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib, .extend, .link, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )

        src.setEventHandler { [weak self] in
            self?.onChange()
        }

        src.setCancelHandler { [weak self] in
            // Capture fd locally to avoid self reference issues in async cancel handler if possible,
            // but we need self to access the property. However, we can just close the captured fd value?
            // No, the fd is in the closure capture if we capture it.
            // But standard pattern is to use self.
            guard let self = self else { return }
            
            // Only close if it's still open
            if self.fd != -1 {
                close(self.fd)
                self.fd = -1
            }
        }

        source = src
        src.resume()
    }

    deinit {
        // Stop the source if it exists
        if let source = source {
            source.cancel()
            // We can't rely on the async cancel handler in deinit
            // Close fd immediately here if it's open, but we have to be careful about race with cancel handler.
            // Actually, simply cancelling is the contract. The handler keeps 'self' alive? No it captures weak self.
            // If self is deallocating, the handler guard let self = self else { return } will fail.
            // So we MUST close fd here if self is dying.
            if fd != -1 {
                close(fd)
                // Set to -1 so cancel handler (if it runs and somehow gets self) sees it closed,
                // but self is dying so it won't be seen.
                //fd = -1 // Cannot assign to property in deinit? Actually we can.
            }
        }
    }

    func stop() {
        if let src = source {
            src.cancel()
            source = nil
            // The cancel handler will run async and close the fd.
            // But to be deterministic, we should perhaps close it?
            // If we close it here, the cancel handler might double close (bad).
            // Let the cancel handler do it, OR do it here and unset handlers.
        }
    }
}

