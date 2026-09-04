import Combine
import Foundation

/// All user settings. Each property is stored under its own UserDefaults key so
/// that adding a new setting never invalidates the ones already saved.
final class Preferences: ObservableObject {
    private let store = UserDefaults.standard

    // MARK: Sources

    @Published var enabledSources: Set<SourceKind> {
        didSet { store.set(enabledSources.map(\.rawValue), forKey: Key.enabledSources) }
    }

    // MARK: Schedule

    /// Seconds between automatic changes. 0 disables the timer.
    @Published var intervalSeconds: Int {
        didSet { store.set(intervalSeconds, forKey: Key.intervalSeconds) }
    }

    @Published var changeOnLaunch: Bool {
        didSet { store.set(changeOnLaunch, forKey: Key.changeOnLaunch) }
    }

    @Published var changeOnWake: Bool {
        didSet { store.set(changeOnWake, forKey: Key.changeOnWake) }
    }

    @Published var pauseOnBattery: Bool {
        didSet { store.set(pauseOnBattery, forKey: Key.pauseOnBattery) }
    }

    // MARK: Display

    @Published var applyToAllScreens: Bool {
        didSet { store.set(applyToAllScreens, forKey: Key.applyToAllScreens) }
    }

    @Published var scaling: ScalingMode {
        didSet { store.set(scaling.rawValue, forKey: Key.scaling) }
    }

    @Published var minWidth: Int {
        didSet { store.set(minWidth, forKey: Key.minWidth) }
    }

    @Published var minHeight: Int {
        didSet { store.set(minHeight, forKey: Key.minHeight) }
    }

    // MARK: Wallhaven

    @Published var wallhavenQuery: String {
        didSet { store.set(wallhavenQuery, forKey: Key.wallhavenQuery) }
    }

    @Published var wallhavenGeneral: Bool {
        didSet { store.set(wallhavenGeneral, forKey: Key.wallhavenGeneral) }
    }

    @Published var wallhavenAnime: Bool {
        didSet { store.set(wallhavenAnime, forKey: Key.wallhavenAnime) }
    }

    @Published var wallhavenPeople: Bool {
        didSet { store.set(wallhavenPeople, forKey: Key.wallhavenPeople) }
    }

    @Published var wallhavenRatios: String {
        didSet { store.set(wallhavenRatios, forKey: Key.wallhavenRatios) }
    }

    @Published var wallhavenAPIKey: String {
        didSet { store.set(wallhavenAPIKey, forKey: Key.wallhavenAPIKey) }
    }

    // MARK: Reddit

    @Published var redditSubreddits: [String] {
        didSet { store.set(redditSubreddits, forKey: Key.redditSubreddits) }
    }

    @Published var redditTimeframe: String {
        didSet { store.set(redditTimeframe, forKey: Key.redditTimeframe) }
    }

    // MARK: Wikimedia

    @Published var wikimediaCategory: String {
        didSet { store.set(wikimediaCategory, forKey: Key.wikimediaCategory) }
    }

    // MARK: Unsplash

    @Published var unsplashAccessKey: String {
        didSet { store.set(unsplashAccessKey, forKey: Key.unsplashAccessKey) }
    }

    @Published var unsplashQuery: String {
        didSet { store.set(unsplashQuery, forKey: Key.unsplashQuery) }
    }

    // MARK: NASA

    @Published var nasaAPIKey: String {
        didSet { store.set(nasaAPIKey, forKey: Key.nasaAPIKey) }
    }

    // MARK: Custom URLs

    @Published var customURLs: [String] {
        didSet { store.set(customURLs, forKey: Key.customURLs) }
    }

    // MARK: Bing

    @Published var bingMarket: String {
        didSet { store.set(bingMarket, forKey: Key.bingMarket) }
    }

    // MARK: General

    @Published var launchAtLogin: Bool {
        didSet { store.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @Published var keepHistoryCount: Int {
        didSet { store.set(keepHistoryCount, forKey: Key.keepHistoryCount) }
    }

    @Published var cacheLimitMB: Int {
        didSet { store.set(cacheLimitMB, forKey: Key.cacheLimitMB) }
    }

    /// Timestamp of the next scheduled change; kept so a restart resumes the cycle.
    var nextChangeDate: Date? {
        get { store.object(forKey: Key.nextChangeDate) as? Date }
        set { store.set(newValue, forKey: Key.nextChangeDate) }
    }

    init() {
        let d = UserDefaults.standard
        let rawSources = d.stringArray(forKey: Key.enabledSources) ?? [SourceKind.bing.rawValue]
        enabledSources = Set(rawSources.compactMap(SourceKind.init(rawValue:)))
        intervalSeconds = d.object(forKey: Key.intervalSeconds) as? Int ?? 3600
        changeOnLaunch = d.object(forKey: Key.changeOnLaunch) as? Bool ?? false
        changeOnWake = d.object(forKey: Key.changeOnWake) as? Bool ?? true
        pauseOnBattery = d.object(forKey: Key.pauseOnBattery) as? Bool ?? false
        applyToAllScreens = d.object(forKey: Key.applyToAllScreens) as? Bool ?? true
        scaling = ScalingMode(rawValue: d.string(forKey: Key.scaling) ?? "") ?? .fill
        minWidth = d.object(forKey: Key.minWidth) as? Int ?? 1920
        minHeight = d.object(forKey: Key.minHeight) as? Int ?? 1080
        wallhavenQuery = d.string(forKey: Key.wallhavenQuery) ?? "landscape"
        wallhavenGeneral = d.object(forKey: Key.wallhavenGeneral) as? Bool ?? true
        wallhavenAnime = d.object(forKey: Key.wallhavenAnime) as? Bool ?? false
        wallhavenPeople = d.object(forKey: Key.wallhavenPeople) as? Bool ?? false
        wallhavenRatios = d.string(forKey: Key.wallhavenRatios) ?? "16x9"
        wallhavenAPIKey = d.string(forKey: Key.wallhavenAPIKey) ?? ""
        redditSubreddits = d.stringArray(forKey: Key.redditSubreddits) ?? ["wallpapers", "EarthPorn"]
        redditTimeframe = d.string(forKey: Key.redditTimeframe) ?? "week"
        wikimediaCategory = d.string(forKey: Key.wikimediaCategory) ?? "Featured pictures on Wikimedia Commons"
        unsplashAccessKey = d.string(forKey: Key.unsplashAccessKey) ?? ""
        unsplashQuery = d.string(forKey: Key.unsplashQuery) ?? "nature"
        nasaAPIKey = d.string(forKey: Key.nasaAPIKey) ?? "DEMO_KEY"
        customURLs = d.stringArray(forKey: Key.customURLs) ?? []
        bingMarket = d.string(forKey: Key.bingMarket) ?? "en-US"
        launchAtLogin = d.object(forKey: Key.launchAtLogin) as? Bool ?? false
        keepHistoryCount = d.object(forKey: Key.keepHistoryCount) as? Int ?? 30
        cacheLimitMB = d.object(forKey: Key.cacheLimitMB) as? Int ?? 500
    }

    var intervalLabel: String {
        IntervalOption.all.first { $0.seconds == intervalSeconds }?.label
            ?? "\(intervalSeconds / 60) dakikada bir"
    }

    private enum Key {
        static let enabledSources = "enabledSources"
        static let intervalSeconds = "intervalSeconds"
        static let changeOnLaunch = "changeOnLaunch"
        static let changeOnWake = "changeOnWake"
        static let pauseOnBattery = "pauseOnBattery"
        static let applyToAllScreens = "applyToAllScreens"
        static let scaling = "scaling"
        static let minWidth = "minWidth"
        static let minHeight = "minHeight"
        static let wallhavenQuery = "wallhavenQuery"
        static let wallhavenGeneral = "wallhavenGeneral"
        static let wallhavenAnime = "wallhavenAnime"
        static let wallhavenPeople = "wallhavenPeople"
        static let wallhavenRatios = "wallhavenRatios"
        static let wallhavenAPIKey = "wallhavenAPIKey"
        static let redditSubreddits = "redditSubreddits"
        static let redditTimeframe = "redditTimeframe"
        static let wikimediaCategory = "wikimediaCategory"
        static let unsplashAccessKey = "unsplashAccessKey"
        static let unsplashQuery = "unsplashQuery"
        static let nasaAPIKey = "nasaAPIKey"
        static let customURLs = "customURLs"
        static let bingMarket = "bingMarket"
        static let launchAtLogin = "launchAtLogin"
        static let keepHistoryCount = "keepHistoryCount"
        static let cacheLimitMB = "cacheLimitMB"
        static let nextChangeDate = "nextChangeDate"
    }
}
