import AppKit
import ImageIO
import SwiftUI

/// The panel shown when the menu bar icon is clicked.
struct MenuPanel: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var prefs: Preferences

    @State private var now = Date()
    /// Which screen's image the caption and the save/open buttons refer to.
    @State private var selectedScreen = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            preview
            countdown
            Divider()
            actions
            Divider()
            quickInterval
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onReceive(ticker) { now = $0 }
    }

    private var header: some View {
        HStack {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(.tint)
            Text("WallShift")
                .font(.headline)
            Spacer()
            if state.isWorking {
                ProgressView().controlSize(.small)
            }
        }
    }

    /// The image shown on each screen, in `NSScreen.screens` order.
    private var screenImages: [WallpaperRecord] {
        guard let current = state.current else { return [] }
        guard state.usesPerScreenImages, current.images.count > 1 else { return [current] }
        let images = current.images
        return NSScreen.screens.indices.map { images[$0 % images.count] }
    }

    /// The image the caption and buttons act on.
    private var selectedImage: WallpaperRecord? {
        let images = screenImages
        guard !images.isEmpty else { return nil }
        return images[min(selectedScreen, images.count - 1)]
    }

    @ViewBuilder
    private var preview: some View {
        let images = screenImages
        if let selected = selectedImage {
            VStack(alignment: .leading, spacing: 6) {
                if images.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            screenThumbnail(image, index: index, isSelected: index == selectedScreen)
                        }
                    }
                } else {
                    thumbnail(for: selected, height: 110)
                }
                Text(selected.title ?? selected.source.displayName)
                    .font(.caption)
                    .lineLimit(2)
                Text([selected.source.displayName, selected.credit]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(height: 110)
                .overlay(Text("Henüz duvar kağıdı değiştirilmedi")
                    .font(.caption)
                    .foregroundStyle(.secondary))
        }
    }

    private func screenThumbnail(_ image: WallpaperRecord, index: Int, isSelected: Bool) -> some View {
        let screens = NSScreen.screens
        let name = index < screens.count ? screens[index].localizedName : "Ekran \(index + 1)"
        return Button {
            selectedScreen = index
        } label: {
            VStack(spacing: 3) {
                thumbnail(for: image, height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help(image.title ?? image.source.displayName)
    }

    @ViewBuilder
    private func thumbnail(for image: WallpaperRecord, height: CGFloat) -> some View {
        if let nsImage = Thumbnails.image(for: image.localURL) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(height: height)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if let error = state.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        } else if let next = state.nextChangeDate, prefs.intervalSeconds > 0 {
            Label(nextChangeText(next), systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Label("Otomatik değişim kapalı", systemImage: "pause.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func nextChangeText(_ next: Date) -> String {
        let remaining = Int(next.timeIntervalSince(now))
        if remaining <= 0 { return "Birazdan değişecek…" }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if hours > 0 { return "Sonraki değişime \(hours) sa \(minutes) dk" }
        if minutes > 0 { return "Sonraki değişime \(minutes) dk \(seconds) sn" }
        return "Sonraki değişime \(seconds) sn"
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                Task { await state.changeWallpaper() }
            } label: {
                Label("Şimdi değiştir", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("r")
            .disabled(state.isWorking)

            HStack(spacing: 8) {
                Button {
                    state.showPrevious()
                } label: {
                    Label("Önceki", systemImage: "chevron.left").frame(maxWidth: .infinity)
                }
                .disabled(!state.canGoBack)

                Button {
                    state.showNextInHistory()
                } label: {
                    Label("Sonraki", systemImage: "chevron.right").frame(maxWidth: .infinity)
                }
                .disabled(!state.canGoForward)
            }

            HStack(spacing: 8) {
                Button {
                    state.saveCurrentAs(selectedImage)
                } label: {
                    Label("Kaydet…", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                .disabled(state.current == nil)

                Button {
                    state.openSourcePage(selectedImage)
                } label: {
                    Label("Kaynağı aç", systemImage: "safari").frame(maxWidth: .infinity)
                }
                .disabled(state.current?.pageURL == nil && state.current?.remoteURL == nil)
            }
        }
    }

    private var quickInterval: some View {
        HStack {
            Text("Periyot")
                .font(.caption)
            Spacer()
            Picker("", selection: $prefs.intervalSeconds) {
                ForEach(IntervalOption.all) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
    }

    private var footer: some View {
        HStack {
            Button("Ayarlar…") {
                openSettings()
            }
            Spacer()
            Button("Çıkış") {
                NSApplication.shared.terminate(nil)
            }
        }
        .font(.callout)
    }

    private func openSettings() {
        state.requestSettings()
    }
}

/// Downscaled, cached previews for the menu panel.
enum Thumbnails {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(for url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
