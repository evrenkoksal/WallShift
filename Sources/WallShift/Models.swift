import AppKit
import Foundation

/// A wallpaper website the app can pull images from.
enum SourceKind: String, Codable, CaseIterable, Identifiable {
    case bing
    case wallhaven
    case reddit
    case wikimedia
    case unsplash
    case nasa
    case picsum
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bing: return "Bing — Günün Görseli"
        case .wallhaven: return "Wallhaven"
        case .reddit: return "Reddit"
        case .wikimedia: return "Wikimedia Commons"
        case .unsplash: return "Unsplash"
        case .nasa: return "NASA APOD"
        case .picsum: return "Lorem Picsum"
        case .custom: return "Özel URL listesi"
        }
    }

    var subtitle: String {
        switch self {
        case .bing: return "Son 8 günün Bing arkaplanları, UHD"
        case .wallhaven: return "Arama sorgusuna göre rastgele duvar kağıdı"
        case .reddit: return "Seçtiğiniz subreddit'lerin en beğenilenleri"
        case .wikimedia: return "Öne çıkan yüksek çözünürlüklü görseller, anahtar gerekmez"
        case .unsplash: return "API anahtarı gerekir"
        case .nasa: return "Günün astronomi fotoğrafı"
        case .picsum: return "Rastgele fotoğraf, anahtar gerekmez"
        case .custom: return "Kendi eklediğiniz doğrudan görsel bağlantıları"
        }
    }

    /// Sources that cannot work at all without user-supplied credentials.
    var requiresAPIKey: Bool { self == .unsplash }
}

/// How the image is laid out on the desktop.
enum ScalingMode: String, Codable, CaseIterable, Identifiable {
    case fill
    case fit
    case stretch
    case center

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fill: return "Ekranı doldur (kırp)"
        case .fit: return "Ekrana sığdır"
        case .stretch: return "Ekrana yay"
        case .center: return "Ortala"
        }
    }

    var imageScaling: NSImageScaling {
        switch self {
        case .fill, .fit: return .scaleProportionallyUpOrDown
        case .stretch: return .scaleAxesIndependently
        case .center: return .scaleNone
        }
    }

    var allowsClipping: Bool {
        switch self {
        case .fill, .stretch: return true
        case .fit, .center: return false
        }
    }
}

/// A candidate image discovered on a remote source, before download.
struct RemoteImage: Hashable {
    let imageURL: URL
    let source: SourceKind
    let title: String?
    /// Human-facing page the image came from, for "kaynağı aç".
    let pageURL: URL?
    /// Photographer / poster, when the API tells us.
    let credit: String?

    var identity: String { imageURL.absoluteString }
}

/// A wallpaper that has actually been downloaded and applied.
struct WallpaperRecord: Codable, Identifiable, Hashable {
    var id: String
    var source: SourceKind
    var title: String?
    var credit: String?
    var remoteURL: URL
    var pageURL: URL?
    var fileName: String
    var appliedAt: Date

    var localURL: URL { FileLocations.wallpapersDirectory.appendingPathComponent(fileName) }
}

/// Preset change intervals offered in the UI. `0` means "sadece elle".
struct IntervalOption: Identifiable, Hashable {
    let seconds: Int
    let label: String
    var id: Int { seconds }

    static let all: [IntervalOption] = [
        .init(seconds: 0, label: "Sadece elle değiştir"),
        .init(seconds: 60, label: "1 dakikada bir"),
        .init(seconds: 5 * 60, label: "5 dakikada bir"),
        .init(seconds: 15 * 60, label: "15 dakikada bir"),
        .init(seconds: 30 * 60, label: "30 dakikada bir"),
        .init(seconds: 60 * 60, label: "Saatte bir"),
        .init(seconds: 3 * 60 * 60, label: "3 saatte bir"),
        .init(seconds: 6 * 60 * 60, label: "6 saatte bir"),
        .init(seconds: 12 * 60 * 60, label: "12 saatte bir"),
        .init(seconds: 24 * 60 * 60, label: "Günde bir"),
    ]
}

enum FileLocations {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("WallShift", isDirectory: true)
    }

    static var wallpapersDirectory: URL {
        supportDirectory.appendingPathComponent("Wallpapers", isDirectory: true)
    }

    /// Per-display copies of the applied image; see `WallpaperManager.apply`.
    static var screensDirectory: URL {
        supportDirectory.appendingPathComponent("Screens", isDirectory: true)
    }

    static var historyFile: URL {
        supportDirectory.appendingPathComponent("history.json")
    }

    static func ensureDirectories() {
        try? FileManager.default.createDirectory(at: wallpapersDirectory, withIntermediateDirectories: true)
    }
}

enum WallShiftError: LocalizedError {
    case noSourcesEnabled
    case noImagesFound
    case notAnImage
    case tooSmall(width: Int, height: Int)
    case sourceFailed(SourceKind, String)
    case allSourcesFailed(String)
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .noSourcesEnabled:
            return "Hiç kaynak seçili değil. Ayarlar → Kaynaklar bölümünden en az bir site seçin."
        case .noImagesFound:
            return "Seçili kaynaklardan uygun görsel bulunamadı."
        case .notAnImage:
            return "İndirilen dosya geçerli bir görsel değil."
        case let .tooSmall(w, h):
            return "Görsel çok küçük (\(w)×\(h))."
        case let .sourceFailed(kind, message):
            return "\(kind.displayName): \(message)"
        case let .allSourcesFailed(message):
            return "Hiçbir kaynaktan görsel alınamadı — \(message)"
        case let .badResponse(code):
            return "Sunucu \(code) döndürdü."
        }
    }
}
