import AppKit
import Combine
import Foundation
import IOKit.ps
import ServiceManagement

/// Orchestrates fetching, downloading, applying and scheduling.
@MainActor
final class AppState: ObservableObject {
    let prefs = Preferences()

    @Published private(set) var current: WallpaperRecord?
    @Published private(set) var history: [WallpaperRecord] = []
    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?
    @Published private(set) var nextChangeDate: Date?
    /// Bumped whenever the settings window should come to front.
    @Published private(set) var settingsToken = 0

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// Position in `history` while stepping back and forth with the menu commands.
    @Published private var historyIndex = 0
    private var recentIdentities: [String] = []
    private var lastKnownInterval: Int
    private var lastKnownPerScreen: Bool

    init() {
        Self.handleCommandLineOnlyFlags()
        let initialPrefs = Preferences()
        lastKnownInterval = initialPrefs.intervalSeconds
        lastKnownPerScreen = initialPrefs.differentImagePerScreen
        FileLocations.ensureDirectories()
        loadHistory()
        current = history.first
        nextChangeDate = prefs.nextChangeDate

        // Settings changes reschedule the timer and refresh the login item.
        prefs.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.syncLoginItem()
                let intervalChanged = self.prefs.intervalSeconds != self.lastKnownInterval
                self.lastKnownInterval = self.prefs.intervalSeconds
                self.rescheduleTimer(resetCycle: intervalChanged)
                // Mirror or split the current set right away when the mode flips.
                if self.prefs.differentImagePerScreen != self.lastKnownPerScreen {
                    self.lastKnownPerScreen = self.prefs.differentImagePerScreen
                    self.reapplyCurrent()
                }
            }
            .store(in: &cancellables)

        rescheduleTimer(resetCycle: nextChangeDate == nil)
        observeSystemEvents()

        // `--change-now` lets Shortcuts, cron or the Terminal trigger a change:
        // open -a WallShift --args --change-now
        let forcedChange = CommandLine.arguments.contains("--change-now")
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.requestSettings()
            }
        }
        if prefs.changeOnLaunch || forcedChange {
            Task { await changeWallpaper() }
        } else if let next = nextChangeDate, next <= Date(), prefs.intervalSeconds > 0 {
            Task { await changeWallpaper() }
        }
    }

    // MARK: - Main action

    func changeWallpaper() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let pool = try await fetchPool()
            guard !pool.isEmpty else { throw WallShiftError.noImagesFound }

            // Prefer images we have not shown recently, but never give up entirely.
            let fresh = pool.filter { !recentIdentities.contains($0.identity) }
            var queue = (fresh.isEmpty ? pool : fresh).shuffled()

            // One image per screen in per-screen mode, otherwise a single image.
            let needed = usesPerScreenImages ? NSScreen.screens.count : 1
            var downloaded: [(RemoteImage, URL)] = []
            var lastFailure: Error?
            while downloaded.count < needed, let candidate = queue.popLast() {
                do {
                    let file = try await Downloader.download(candidate, prefs: prefs)
                    downloaded.append((candidate, file))
                } catch {
                    lastFailure = error
                    continue // Try the next candidate; a single dead link is not fatal.
                }
            }
            guard !downloaded.isEmpty else { throw lastFailure ?? WallShiftError.noImagesFound }

            // If the pool ran short, the remaining screens reuse images cyclically.
            try await WallpaperManager.apply(files: downloaded.map(\.1), prefs: prefs)
            record(downloaded)
            lastError = nil
            scheduleNext(resetCycle: true)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            scheduleNext(resetCycle: true)
        }
    }

    /// Fetches from every enabled source in parallel; partial failures are tolerated.
    private func fetchPool() async throws -> [RemoteImage] {
        let kinds = Array(prefs.enabledSources)
        guard !kinds.isEmpty else { throw WallShiftError.noSourcesEnabled }

        let prefs = self.prefs
        var collected: [RemoteImage] = []
        var failures: [String] = []

        await withTaskGroup(of: Result<[RemoteImage], Error>.self) { group in
            for kind in kinds {
                group.addTask {
                    do {
                        return .success(try await SourceRegistry.provider(for: kind)
                            .fetchCandidates(prefs: prefs))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case let .success(images): collected.append(contentsOf: images)
                case let .failure(error):
                    failures.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            }
        }

        if collected.isEmpty, !failures.isEmpty {
            throw WallShiftError.allSourcesFailed(failures.joined(separator: " · "))
        }
        if !failures.isEmpty { lastError = failures.joined(separator: " · ") }
        return collected
    }

    /// True when each display should get its own picture.
    var usesPerScreenImages: Bool {
        prefs.differentImagePerScreen && prefs.applyToAllScreens && NSScreen.screens.count > 1
    }

    private func record(_ items: [(RemoteImage, URL)]) {
        let now = Date()
        let records = items.map { image, file in
            WallpaperRecord(
                id: UUID().uuidString,
                source: image.source,
                title: image.title,
                credit: image.credit,
                remoteURL: image.imageURL,
                pageURL: image.pageURL,
                fileName: file.lastPathComponent,
                appliedAt: now
            )
        }
        var entry = records[0]
        if records.count > 1 { entry.companions = Array(records.dropFirst()) }
        current = entry
        history.insert(entry, at: 0)
        history = Array(history.prefix(max(prefs.keepHistoryCount, 5)))
        historyIndex = 0
        recentIdentities.append(contentsOf: items.map { $0.0.identity })
        recentIdentities = Array(recentIdentities.suffix(300))
        saveHistory()
        WallpaperManager.pruneCache(limitMB: prefs.cacheLimitMB, keeping: protectedFileNames())
    }

    // MARK: - History navigation

    func showPrevious() {
        guard historyIndex + 1 < history.count else { return }
        historyIndex += 1
        Task { await applyFromHistory() }
    }

    func showNextInHistory() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        Task { await applyFromHistory() }
    }

    var canGoBack: Bool { historyIndex + 1 < history.count }
    var canGoForward: Bool { historyIndex > 0 }

    private func applyFromHistory() async {
        let entry = history[historyIndex]
        guard FileManager.default.fileExists(atPath: entry.localURL.path) else {
            lastError = "Bu görselin yerel kopyası silinmiş."
            return
        }
        do {
            try await WallpaperManager.apply(files: files(for: entry), prefs: prefs)
            current = entry
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Re-applies the current image(s), e.g. after a display is connected.
    func reapplyCurrent() {
        guard let current, FileManager.default.fileExists(atPath: current.localURL.path) else { return }
        let prefs = self.prefs
        let files = files(for: current)
        Task { try? await WallpaperManager.apply(files: files, prefs: prefs) }
    }

    /// Local files to apply for a history entry under the current mode.
    private func files(for entry: WallpaperRecord) -> [URL] {
        guard usesPerScreenImages else { return [entry.localURL] }
        let existing = entry.images.map(\.localURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return existing.isEmpty ? [entry.localURL] : existing
    }

    // MARK: - Scheduling

    func rescheduleTimer(resetCycle: Bool) {
        timer?.invalidate()
        timer = nil
        guard prefs.intervalSeconds > 0 else {
            nextChangeDate = nil
            prefs.nextChangeDate = nil
            return
        }
        if resetCycle || nextChangeDate == nil {
            scheduleNext(resetCycle: true)
        } else {
            armTimer()
        }
    }

    private func scheduleNext(resetCycle: Bool) {
        guard prefs.intervalSeconds > 0 else {
            nextChangeDate = nil
            prefs.nextChangeDate = nil
            timer?.invalidate()
            return
        }
        if resetCycle || nextChangeDate == nil || nextChangeDate! <= Date() {
            nextChangeDate = Date().addingTimeInterval(TimeInterval(prefs.intervalSeconds))
            prefs.nextChangeDate = nextChangeDate
        }
        armTimer()
    }

    private func armTimer() {
        timer?.invalidate()
        guard let next = nextChangeDate else { return }
        let delay = max(next.timeIntervalSinceNow, 1)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.timerFired() }
        }
        timer.tolerance = min(delay * 0.1, 30)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func timerFired() async {
        if prefs.pauseOnBattery, Self.isOnBattery() {
            // Skip this round but keep the cycle going.
            nextChangeDate = Date().addingTimeInterval(TimeInterval(prefs.intervalSeconds))
            prefs.nextChangeDate = nextChangeDate
            armTimer()
            return
        }
        await changeWallpaper()
    }

    static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if let state = description[kIOPSPowerSourceStateKey] as? String {
                return state == kIOPSBatteryPowerValue
            }
        }
        return false
    }

    // MARK: - System events

    private func observeSystemEvents() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reapplyCurrent()
                guard self.prefs.changeOnWake, self.prefs.intervalSeconds > 0 else { return }
                if let next = self.nextChangeDate, next <= Date() {
                    await self.changeWallpaper()
                } else {
                    self.armTimer()
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapplyCurrent() }
        }
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = try? Data(contentsOf: FileLocations.historyFile),
              let decoded = try? JSONDecoder().decode([WallpaperRecord].self, from: data) else { return }
        history = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: FileLocations.historyFile, options: .atomic)
    }

    private func protectedFileNames() -> Set<String> {
        Set(history.prefix(10).flatMap(\.allFileNames))
    }

    // MARK: - Utilities exposed to the UI

    func revealCurrentInFinder() {
        guard let current else { return }
        NSWorkspace.shared.activateFileViewerSelecting(current.images.map(\.localURL))
    }

    /// Opens the page of `image`, or of the current primary image.
    func openSourcePage(_ image: WallpaperRecord? = nil) {
        let target = image ?? current
        guard let url = target?.pageURL ?? target?.remoteURL else { return }
        NSWorkspace.shared.open(url)
    }

    func saveCurrentAs(_ image: WallpaperRecord? = nil) {
        guard let current = image ?? current else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = current.fileName
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let destination = panel.url {
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: current.localURL, to: destination)
        }
    }

    func clearCache() {
        WallpaperManager.clearCache(keeping: Set(current?.allFileNames ?? []))
    }

    func cacheSizeDescription() -> String {
        ByteCountFormatter.string(fromByteCount: Int64(WallpaperManager.cacheSizeBytes()), countStyle: .file)
    }

    /// Headless flags handled before the UI matters:
    ///   --login-item=on|off   toggle the Login Item registration
    ///   --print-status        print the Login Item status and exit
    private static func handleCommandLineOnlyFlags() {
        var shouldExit = false
        for argument in CommandLine.arguments {
            if argument.hasPrefix("--login-item=") {
                let wantsOn = argument.hasSuffix("on")
                do {
                    if wantsOn {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    print("login-item \(wantsOn ? "on" : "off"): ok")
                } catch {
                    print("login-item \(wantsOn ? "on" : "off"): FAILED — \(error.localizedDescription)")
                }
                shouldExit = true
            }
            if argument == "--print-status" {
                let status = SMAppService.mainApp.status
                let name: String
                switch status {
                case .enabled: name = "enabled"
                case .requiresApproval: name = "requiresApproval"
                case .notRegistered: name = "notRegistered"
                case .notFound: name = "notFound"
                @unknown default: name = "unknown(\(status.rawValue))"
                }
                print("login item status: \(name)")
                print("bundle: \(Bundle.main.bundlePath)")
                shouldExit = true
            }
        }
        if shouldExit { exit(0) }
    }

    func requestSettings() {
        settingsToken += 1
    }

    // MARK: - Login item

    func syncLoginItem() {
        let service = SMAppService.mainApp
        do {
            if prefs.launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            lastError = "Girişte başlatma ayarlanamadı: \(error.localizedDescription)"
        }
    }
}
