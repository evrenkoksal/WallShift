import AppKit
import SwiftUI

enum SettingsWindow {
    static let id = "wallshift-settings"
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var prefs: Preferences

    var body: some View {
        TabView {
            SourcesTab(prefs: prefs)
                .tabItem { Label("Kaynaklar", systemImage: "globe") }
            ScheduleTab(prefs: prefs)
                .tabItem { Label("Zamanlama", systemImage: "clock") }
            DisplayTab(prefs: prefs)
                .tabItem { Label("Görünüm", systemImage: "display") }
            GeneralTab(prefs: prefs)
                .tabItem { Label("Genel", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 470)
    }
}

// MARK: - Sources

private struct SourcesTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Duvar kağıtlarının çekileceği siteleri seçin. Birden fazla site seçerseniz görseller hepsinden karıştırılarak gelir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(SourceKind.allCases) { kind in
                    sourceBox(kind)
                }
            }
            .padding(16)
        }
    }

    private func sourceBox(_ kind: SourceKind) -> some View {
        let isOn = Binding(
            get: { prefs.enabledSources.contains(kind) },
            set: { on in
                if on { prefs.enabledSources.insert(kind) } else { prefs.enabledSources.remove(kind) }
            }
        )
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: isOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.displayName).fontWeight(.medium)
                        Text(kind.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if isOn.wrappedValue {
                    Divider()
                    details(for: kind)
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func details(for kind: SourceKind) -> some View {
        switch kind {
        case .bing:
            LabeledContent("Bölge") {
                Picker("", selection: $prefs.bingMarket) {
                    Text("Türkiye").tag("tr-TR")
                    Text("ABD").tag("en-US")
                    Text("Birleşik Krallık").tag("en-GB")
                    Text("Almanya").tag("de-DE")
                    Text("Japonya").tag("ja-JP")
                }
                .labelsHidden()
            }
        case .wallhaven:
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Arama") {
                    TextField("örn. mountains, minimal, city", text: $prefs.wallhavenQuery)
                }
                LabeledContent("Oran") {
                    TextField("örn. 16x9 (boş bırakılabilir)", text: $prefs.wallhavenRatios)
                }
                HStack(spacing: 12) {
                    Toggle("Genel", isOn: $prefs.wallhavenGeneral)
                    Toggle("Anime", isOn: $prefs.wallhavenAnime)
                    Toggle("İnsan", isOn: $prefs.wallhavenPeople)
                }
                LabeledContent("API anahtarı") {
                    SecureField("isteğe bağlı", text: $prefs.wallhavenAPIKey)
                }
                Text("Yalnızca SFW içerik çekilir.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        case .reddit:
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Subreddit'ler") {
                    TextField("virgülle ayırın", text: Binding(
                        get: { prefs.redditSubreddits.joined(separator: ", ") },
                        set: { prefs.redditSubreddits = $0.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty } }
                    ))
                }
                LabeledContent("Dönem") {
                    Picker("", selection: $prefs.redditTimeframe) {
                        Text("Bugün").tag("day")
                        Text("Bu hafta").tag("week")
                        Text("Bu ay").tag("month")
                        Text("Bu yıl").tag("year")
                        Text("Tüm zamanlar").tag("all")
                    }
                    .labelsHidden()
                }
            }
        case .wikimedia:
            LabeledContent("Koleksiyon") {
                Picker("", selection: $prefs.wikimediaCategory) {
                    Text("Öne çıkan görseller").tag("Featured pictures on Wikimedia Commons")
                    Text("Kaliteli görseller").tag("Quality images")
                    Text("Değerli görseller").tag("Valued images")
                }
                .labelsHidden()
            }
        case .unsplash:
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Access Key") {
                    SecureField("unsplash.com/developers", text: $prefs.unsplashAccessKey)
                }
                LabeledContent("Arama") {
                    TextField("örn. nature, architecture", text: $prefs.unsplashQuery)
                }
            }
        case .nasa:
            LabeledContent("API anahtarı") {
                TextField("DEMO_KEY", text: $prefs.nasaAPIKey)
            }
        case .picsum:
            Text("Ek ayar gerekmez.")
                .font(.caption).foregroundStyle(.secondary)
        case .custom:
            VStack(alignment: .leading, spacing: 6) {
                Text("Her satıra bir doğrudan görsel bağlantısı yazın.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { prefs.customURLs.joined(separator: "\n") },
                    set: { prefs.customURLs = $0.split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty } }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(height: 80)
                .border(.separator)
            }
        }
    }
}

// MARK: - Schedule

private struct ScheduleTab: View {
    @ObservedObject var prefs: Preferences
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                Picker("Değişim periyodu", selection: $prefs.intervalSeconds) {
                    ForEach(IntervalOption.all) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                if let next = state.nextChangeDate, prefs.intervalSeconds > 0 {
                    LabeledContent("Sonraki değişim", value: next.formatted(date: .omitted, time: .shortened))
                }
            }
            Section {
                Toggle("Uygulama açılışında değiştir", isOn: $prefs.changeOnLaunch)
                Toggle("Uykudan uyanınca kaçırılan değişimi yap", isOn: $prefs.changeOnWake)
                Toggle("Pil ile çalışırken duraklat", isOn: $prefs.pauseOnBattery)
            }
            Section {
                Button("Şimdi değiştir") {
                    Task { await state.changeWallpaper() }
                }
                .disabled(state.isWorking)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Display

private struct DisplayTab: View {
    @ObservedObject var prefs: Preferences
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Tüm ekranlara uygula", isOn: $prefs.applyToAllScreens)
                Picker("Yerleşim", selection: $prefs.scaling) {
                    ForEach(ScalingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
            Section("En küçük çözünürlük") {
                LabeledContent("Genişlik") {
                    TextField("", value: $prefs.minWidth, format: .number)
                        .frame(width: 90)
                }
                LabeledContent("Yükseklik") {
                    TextField("", value: $prefs.minHeight, format: .number)
                        .frame(width: 90)
                }
                Text("Bu boyutun altındaki görseller atlanır. Ekranınız \(mainScreenDescription).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Geçerli görseli yeniden uygula") { state.reapplyCurrent() }
                    .disabled(state.current == nil)
            }
        }
        .formStyle(.grouped)
    }

    private var mainScreenDescription: String {
        guard let screen = NSScreen.main else { return "bilinmiyor" }
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        return "\(Int(size.width * scale))×\(Int(size.height * scale)) piksel"
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var prefs: Preferences
    @EnvironmentObject var state: AppState
    @State private var cacheSize = ""

    var body: some View {
        Form {
            Section {
                Toggle("Girişte otomatik başlat", isOn: $prefs.launchAtLogin)
            }
            Section("Geçmiş ve önbellek") {
                Stepper("Geçmişte tutulacak görsel: \(prefs.keepHistoryCount)",
                        value: $prefs.keepHistoryCount, in: 5...200, step: 5)
                Stepper("Önbellek sınırı: \(prefs.cacheLimitMB) MB",
                        value: $prefs.cacheLimitMB, in: 50...5000, step: 50)
                LabeledContent("Şu anki önbellek", value: cacheSize)
                HStack {
                    Button("Klasörü aç") {
                        NSWorkspace.shared.open(FileLocations.wallpapersDirectory)
                    }
                    Button("Önbelleği temizle") {
                        state.clearCache()
                        cacheSize = state.cacheSizeDescription()
                    }
                }
            }
            Section {
                LabeledContent("Sürüm", value: "1.0")
                Text("Görseller \(FileLocations.wallpapersDirectory.path) altında saklanır.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { cacheSize = state.cacheSizeDescription() }
    }
}
