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

        // Create dispatch source - if this fails, we need to clean up the FD
        guard let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib, .extend, .link, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        ) as? DispatchSourceFileSystemObject else {
            // Failed to create source - clean up FD
            close(fd)
            fd = -1
            ErrorLogger.shared.warning("Failed to create file system event source for: \(url.path)")
            return
        }

        src.setEventHandler { [weak self] in
            self?.onChange()
        }

        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fd != -1 {
                close(self.fd)
                self.fd = -1
            }
        }

        source = src
        src.resume()
    }

    deinit {
        // Ensure cleanup if object is deallocated before stop() is called
        stop()
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}

