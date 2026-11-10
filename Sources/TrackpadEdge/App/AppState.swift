import AppKit
import ApplicationServices
import Observation
import ServiceManagement

/// App-wide state: the trackpad listener, Accessibility, launch at login.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    private(set) var isTrusted = AXIsProcessTrusted()
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?
    /// False if MultitouchSupport can't be loaded on this macOS.
    let trackpadAvailable = TrackpadEdgeControl.shared.isAvailable

    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var started = false

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func start() {
        guard !started, !Self.isRunningTests else { return }
        started = true
        let settings = AppSettings.shared
        settings.onEnabled = { TrackpadEdgeControl.shared.setEnabled($0) }
        if !Demo.isOn { TrackpadEdgeControl.shared.setEnabled(settings.enabled) }
        if !trackpadAvailable { NSLog("[TrackpadEdge] MultitouchSupport not found: the trackpad edges are off") }
        if !isTrusted { startPolling() }
    }

    func shutdown() {
        guard started else { return }
        TrackpadEdgeControl.shared.setEnabled(false)
    }

    // MARK: - Accessibility
    // Needed to hold back scrolling while you control (event tap) and to notice typing.

    func requestPermission() {
        if !AccessibilityPermission.requestIfNeeded() { AccessibilityPermission.openSystemSettings() }
        startPolling()
    }

    /// Polls only while permission is missing; stops for good once it's granted.
    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let state = AppState.shared
                guard AXIsProcessTrusted() else { return }
                state.isTrusted = true
                state.pollTimer?.invalidate()
                state.pollTimer = nil
                // The key monitor added before the grant stays deaf: start the listener again.
                if AppSettings.shared.enabled, !Demo.isOn {
                    TrackpadEdgeControl.shared.setEnabled(false)
                    TrackpadEdgeControl.shared.setEnabled(true)
                }
            }
        }
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
