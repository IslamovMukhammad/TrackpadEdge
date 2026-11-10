import ApplicationServices
import AppKit

/// TrackpadEdge needs Accessibility for two things: the event tap that holds back scrolling and
/// trackpad gestures while you control volume or brightness, and the global key monitor that
/// ignores the trackpad for 0.6 s after you type. Reading the trackpad itself needs no permission.
enum AccessibilityPermission {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system's own "would like to control this computer" prompt,
    /// which drops the app straight into System Settings ▸ Accessibility.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
