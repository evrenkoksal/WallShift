import AppKit
import SwiftUI

@main
struct WallShiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(prefs: state.prefs)
                .environmentObject(state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)

        Window("WallShift Ayarları", id: SettingsWindow.id) {
            SettingsView(prefs: state.prefs)
                .environmentObject(state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// The menu bar icon; also the place where settings-window requests are handled,
/// since this view is alive for the whole app lifetime.
private struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: state.isWorking ? "arrow.triangle.2.circlepath" : "photo.on.rectangle.angled")
            .onChange(of: state.settingsToken) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: SettingsWindow.id)
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no main window on launch.
        NSApp.setActivationPolicy(.accessory)
    }
}
