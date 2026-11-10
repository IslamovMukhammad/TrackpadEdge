import AppKit
import SwiftUI

@main
struct TrackpadEdgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("TrackpadEdge", systemImage: "rectangle.portrait.lefthalf.inset.filled") {
            MenuBarContent()
        }
    }
}

/// The menu bar menu.
private struct MenuBarContent: View {
    var body: some View {
        @Bindable var settings = AppSettings.shared
        Toggle("Trackpad Edges", isOn: $settings.enabled)
        Toggle("Swap Left and Right", isOn: $settings.swapEdges)
        Divider()
        Button("Settings…") { SettingsWindow.shared.show() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit TrackpadEdge") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppState.isRunningTests else { return }
        let state = AppState.shared
        state.start()
        if Demo.isOn {
            Demo.run()
            return
        }
        // Opened by the user (not at login), or still missing permission → show settings.
        if !launchedAsLoginItem || !state.isTrusted {
            SettingsWindow.shared.show()
        }
    }

    /// Double-clicking the app while it runs opens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.shutdown()
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

/// The settings window is managed by hand so it can be reopened from anywhere (menu bar, Finder).
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private(set) var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingView(rootView: SettingsView()
                .environment(AppState.shared)
                .environment(AppSettings.shared))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "TrackpadEdge"
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
