import AppKit
import CryptoKit
import Foundation

/// Downloads images into the app's cache and validates that they are usable.
enum Downloader {
    static func download(_ image: RemoteImage, prefs: Preferences) async throws -> URL {
        FileLocations.ensureDirectories()
        let data = try await Net.data(from: image.imageURL)

        guard let rep = NSBitmapImageRep(data: data) else { throw WallShiftError.notAnImage }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width >= prefs.minWidth, height >= prefs.minHeight else {
            throw WallShiftError.tooSmall(width: width, height: height)
        }

        let ext = fileExtension(for: image.imageURL, data: data)
        let name = "\(sha1(image.imageURL.absoluteString)).\(ext)"
        let destination = FileLocations.wallpapersDirectory.appendingPathComponent(name)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func fileExtension(for url: URL, data: Data) -> String {
        // Trust the magic bytes over the URL, since many APIs serve extension-less paths.
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.count > 12, Array(data[8..<12]) == Array("WEBP".utf8) { return "webp" }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "jpg" : ext
    }

    private static func sha1(_ string: String) -> String {
        Insecure.SHA1.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Applies a local image file to the desktop and keeps the cache tidy.
enum WallpaperManager {
    static func apply(fileURL: URL, prefs: Preferences) throws {
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: prefs.scaling.imageScaling.rawValue),
            .allowClipping: NSNumber(value: prefs.scaling.allowsClipping),
        ]
        let screens = prefs.applyToAllScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        for screen in screens {
            try NSWorkspace.shared.setDesktopImageURL(fileURL, for: screen, options: options)
        }
    }

    /// Deletes the oldest cached files once the cache passes the configured budget.
    static func pruneCache(limitMB: Int, keeping protectedNames: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: FileLocations.wallpapersDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        let entries = files.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else { return nil }
            return (url, date, size)
        }.sorted { $0.1 > $1.1 }

        var total = 0
        let limit = max(limitMB, 50) * 1_048_576
        for (url, _, size) in entries {
            total += size
            if total > limit, !protectedNames.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }
    }

    static func cacheSizeBytes() -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: FileLocations.wallpapersDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    static func clearCache(keeping protectedNames: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: FileLocations.wallpapersDirectory,
                                                      includingPropertiesForKeys: nil) else { return }
        for url in files where !protectedNames.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }
}
