import AppKit

/// Demo mode for README screenshots. It never reads the trackpad and never touches the real
/// volume or brightness; settings go to a throwaway store, not yours.
///
///     TRACKPADEDGE_DEMO=hud:5             build/TrackpadEdge.app/Contents/MacOS/TrackpadEdge   # variant 5, volume 62 %
///     TRACKPADEDGE_DEMO=hud:3:brightness  …   # variant 3, brightness 48 %
///     TRACKPADEDGE_DEMO=settings          …   # the settings window
///
/// Add `TRACKPADEDGE_DEMO_NOTCH=185` to lay the indicators out as on a Mac with a notch that wide
/// (the backdrop then draws the notch for context).
/// Add `TRACKPADEDGE_BACKDROP=1` to cover the screen with a plain gradient first, so nothing
/// personal shows behind the shot.
@MainActor
enum Demo {
    static let mode = ProcessInfo.processInfo.environment["TRACKPADEDGE_DEMO"]
    static var isOn: Bool { mode != nil }
    static let defaults: UserDefaults = {
        let suite = "TrackpadEdge.demo"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite) ?? .standard
    }()

    private static var backdrop: NSWindow?
    static let notch = ProcessInfo.processInfo.environment["TRACKPADEDGE_DEMO_NOTCH"].flatMap(Double.init).map { CGFloat($0) }

    static func run() {
        guard let mode else { return }
        if ProcessInfo.processInfo.environment["TRACKPADEDGE_BACKDROP"] == "1" { showBackdrop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let parts = mode.split(separator: ":").map(String.init)
            switch parts.first {
            case "settings":
                SettingsWindow.shared.show()
                // Sharpest shot: centre it on the highest-resolution screen.
                if let window = SettingsWindow.shared.window,
                   let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) {
                    let area = screen.visibleFrame
                    window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2,
                                                  y: area.maxY - window.frame.height - 20))
                }
            case "hud":
                let variant = HUDVariant.clamp(parts.count > 1 ? Int(parts[1]) ?? 5 : 5)
                let kind: HUDKind = parts.count > 2 && parts[2] == "brightness" ? .brightness : .volume
                let hud = HUDController.shared
                hud.variantProvider = { variant }
                hud.notchOverride = notch
                if let screen = NSScreen.main {
                    // Variant 10 sits by the pointer: pretend it's a little left of centre.
                    hud.mouseOverride = NSPoint(x: screen.frame.midX - 220, y: screen.frame.midY + 60)
                }
                hud.setCompanion(0.48, for: .brightness)
                hud.setCompanion(0.62, for: .volume)
                hud.hold(kind, value: kind == .volume ? 0.62 : 0.48)
            default:
                break
            }
        }
    }

    /// A plain gradient over the whole screen (menu bar included), under the indicator.
    private static func showBackdrop() {
        guard let screen = NSScreen.main else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .statusBar
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = GradientView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        backdrop = window
    }

    private final class GradientView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSGradient(colors: [NSColor(srgbRed: 0.20, green: 0.27, blue: 0.48, alpha: 1),
                                NSColor(srgbRed: 0.42, green: 0.36, blue: 0.58, alpha: 1),
                                NSColor(srgbRed: 0.78, green: 0.56, blue: 0.62, alpha: 1)])?
                .draw(in: bounds, angle: -60)
            // A notch for context, the width the indicators are laid out for
            if let notch = Demo.notch {
                let rect = NSRect(x: bounds.midX - notch / 2, y: bounds.maxY - 38, width: notch, height: 58)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            }
        }
    }
}
