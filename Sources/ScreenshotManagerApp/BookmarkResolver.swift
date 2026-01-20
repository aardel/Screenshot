import Foundation

enum BookmarkResolver {
    /// Resolves a security-scoped bookmark and starts accessing the resource.
    /// The caller is responsible for calling `stopAccessingSecurityScopedResource()` when done.
    static func resolveFolder(from bookmark: Data) -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // Start accessing the security-scoped resource
            // Caller must call url.stopAccessingSecurityScopedResource() when done
            if !url.startAccessingSecurityScopedResource() {
                print("Warning: Failed to start accessing security-scoped resource for \(url.path)")
            }

            return url
        } catch {
            print("Error resolving bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    /// Stops accessing a security-scoped resource.
    static func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

