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
    /// Sets the wallpaper on every target screen.
    ///
    /// With several displays, macOS only reliably refreshes the screens when the
    /// focused one (where the menu bar panel is open) is set last and each screen
    /// gets its own file path; handing all screens the same URL lets the wallpaper
    /// agent treat them as one linked choice and skip the unfocused display.
    static func apply(fileURL: URL, prefs: Preferences) async throws {
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: prefs.scaling.imageScaling.rawValue),
            .allowClipping: NSNumber(value: prefs.scaling.allowsClipping),
        ]
        let focused = NSScreen.main
        let targets = prefs.applyToAllScreens ? NSScreen.screens : [focused].compactMap { $0 }
        let ordered = targets.filter { $0 != focused } + targets.filter { $0 == focused }

        var appliedNames = Set<String>()
        for (index, screen) in ordered.enumerated() {
            let screenFile = try screenCopy(of: fileURL, for: screen)
            try NSWorkspace.shared.setDesktopImageURL(screenFile, for: screen, options: options)
            appliedNames.insert(screenFile.lastPathComponent)
            if index < ordered.count - 1 {
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        pruneScreenCopies(keeping: appliedNames, for: ordered)
    }

    /// A per-display clone of the image (APFS clone, so no extra disk space).
    private static func screenCopy(of fileURL: URL, for screen: NSScreen) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: FileLocations.screensDirectory, withIntermediateDirectories: true)
        let destination = FileLocations.screensDirectory
            .appendingPathComponent("\(displayID(of: screen))-\(fileURL.lastPathComponent)")
        if !fm.fileExists(atPath: destination.path) {
            try fm.copyItem(at: fileURL, to: destination)
        }
        return destination
    }

    /// Drops the previous per-display copies once the new ones are in place.
    private static func pruneScreenCopies(keeping names: Set<String>, for screens: [NSScreen]) {
        let fm = FileManager.default
        let prefixes = screens.map { "\(displayID(of: $0))-" }
        guard let files = try? fm.contentsOfDirectory(at: FileLocations.screensDirectory,
                                                      includingPropertiesForKeys: nil) else { return }
        for url in files {
            let name = url.lastPathComponent
            if !names.contains(name), prefixes.contains(where: name.hasPrefix) {
                try? fm.removeItem(at: url)
            }
        }
    }

    private static func displayID(of screen: NSScreen) -> UInt32 {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
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
