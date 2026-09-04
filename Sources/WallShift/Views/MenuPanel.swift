import AppKit
import SwiftUI

/// The panel shown when the menu bar icon is clicked.
struct MenuPanel: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var prefs: Preferences

    @State private var now = Date()
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

    @ViewBuilder
    private var preview: some View {
        if let current = state.current, let image = NSImage(contentsOf: current.localURL) {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(current.title ?? current.source.displayName)
                    .font(.caption)
                    .lineLimit(2)
                Text([current.source.displayName, current.credit]
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
                    state.saveCurrentAs()
                } label: {
                    Label("Kaydet…", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                .disabled(state.current == nil)

                Button {
                    state.openSourcePage()
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
