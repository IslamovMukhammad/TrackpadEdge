import AppKit
import Combine
import SwiftUI

/// The on-screen indicator for volume and brightness.
///
/// macOS doesn't let other apps show its own volume popover, so TrackpadEdge draws one of ten
/// designs (Settings ▸ Indicator; variant 5 "Edge column" by default).
///
/// Built not to get in the way:
///   · one panel is reused for the app's lifetime; no window is created per change;
///   · the panel never takes focus, lets the mouse through, and is taken off screen while hidden;
///   · every show bumps a generation number, so an old timer can't close a newer indicator;
///   · springs everywhere: if a new value arrives while it closes, it turns around from where it is;
///   · with Reduce Motion: fades only, no movement.
@MainActor
final class HUDController {
    static let shared = HUDController()

    let model = HUDModel()
    private var panel: NSPanel?
    private var generation = 0
    /// A finger is on the trackpad edge: the indicator stays and doesn't narrow or close.
    private var held = false

    /// Which design to use; read when the indicator appears.
    var variantProvider: () -> Int = { AppSettings.shared.hudVariant }
    /// Demo screenshots: where to pretend the pointer is (global coordinates).
    var mouseOverride: NSPoint?
    /// Demo screenshots: pretend the screen has a notch this wide (and a notched Mac's menu bar).
    var notchOverride: CGFloat?

    // MARK: Live control

    /// Live control from the trackpad edge: a value arrives with every frame, so instead of a long
    /// spring it's a very short, damped move and the indicator sticks to the finger.
    func track(_ kind: HUDKind, value: Double, muted: Bool = false) {
        guard held, model.shown else {
            held = true
            show(kind, value: value, muted: muted)
            return
        }
        let clamped = min(1, max(0, value))
        let current = model.content.value
        // Invisible changes (< 0.4 %) aren't redrawn
        guard kind != model.content.kind || muted != model.content.muted || abs(clamped - current) >= 0.004
                || clamped == 0 || clamped == 1 else { return }
        let hitLimit = (clamped >= 1 && current < 1) || (clamped <= 0 && current > 0)
        withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 1)) {
            set(kind, clamped, muted: muted)
        }
        if hitLimit && !model.reduceMotion { model.content.pulse += 1 }
    }

    /// The finger lifted: the indicator stays a moment, then narrows and closes as usual.
    func release() {
        guard held else { return }
        held = false
        show(model.content.kind, value: model.content.value(model.content.kind), muted: model.content.muted)
    }

    /// The other value, for the pair variant (8).
    func setCompanion(_ value: Double, for kind: HUDKind) {
        if kind == .volume { model.content.volume = value } else { model.content.brightness = value }
    }

    func setVolumeTitle(_ title: String) { model.content.volumeTitle = title }

    // MARK: Showing and hiding

    func show(_ kind: HUDKind, value: Double, muted: Bool = false) {
        generation += 1
        let current = generation
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let clamped = min(1, max(0, value))

        let panel = ensurePanel()
        if !model.shown {
            model.variant = HUDVariant.clamp(variantProvider())
            place(panel, kind: kind)
            panel.orderFrontRegardless()
        }

        // One "bump" when it reaches a limit
        let before = model.content.value
        let hitLimit = (clamped >= 1 && before < 1) || (clamped <= 0 && before > 0)
        withAnimation(model.shown ? hudValueAnim : nil) {
            set(kind, clamped, muted: muted)
        }
        if hitLimit && !reduceMotion && model.shown { model.content.pulse += 1 }

        let variant = model.variant
        if !model.shown {
            model.reduceMotion = reduceMotion
            let entry: Animation = reduceMotion ? .easeOut(duration: 0.2) : (variant == 5 ? hudEdgeIn : hudEase)
            withAnimation(entry) { model.shown = true }
        }
        if model.content.thin {
            withAnimation(hudThin) { model.content.thin = false }
        }

        guard !held else { return }      // a finger is on the edge: no timers
        let timing = HUDLayout.timing(variant)
        if let thin = timing.thin {
            DispatchQueue.main.asyncAfter(deadline: .now() + thin) { [weak self] in
                guard let self, self.generation == current, !self.held, self.model.shown else { return }
                withAnimation(hudThin) { self.model.content.thin = true }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.hide) { [weak self] in
            guard let self, self.generation == current, !self.held else { return }
            self.hide(generation: current)
        }
    }

    /// Hides it now (Settings changed, the app quits a demo).
    func hideNow() {
        held = false
        generation += 1
        hide(generation: generation)
    }

    /// Keeps it on screen with these values until `hideNow()` (demo screenshots).
    func hold(_ kind: HUDKind, value: Double) {
        held = true
        show(kind, value: value)
    }

    private func hide(generation current: Int) {
        guard model.shown else { return }
        let reduceMotion = model.reduceMotion
        let exit: Animation = reduceMotion ? .easeIn(duration: 0.2) : (model.variant == 5 ? hudEdgeOut : hudExit)
        withAnimation(exit) { model.shown = false }
        // Once the animation is over the panel leaves the screen, unless it was shown again meanwhile
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, self.generation == current, !self.model.shown else { return }
            self.panel?.orderOut(nil)
            self.model.content.thin = false
        }
    }

    /// A short run on screen with made-up values, to try a design from Settings.
    /// It never touches the real volume or brightness.
    func preview(_ variant: Int) {
        let saved = variantProvider
        hideNowImmediately()
        variantProvider = { variant }
        held = true
        show(.volume, value: 0.62)
        variantProvider = saved
        let steps: [(Double, Double)] = [(0.2, 0.68), (0.35, 0.75), (0.5, 0.81), (0.65, 0.87)]
        for (delay, value) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.held else { return }
                self.track(.volume, value: value)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.release() }
    }

    private func hideNowImmediately() {
        held = false
        generation += 1
        model.shown = false
        model.content.thin = false
        panel?.orderOut(nil)
    }

    private func set(_ kind: HUDKind, _ value: Double, muted: Bool) {
        model.content.kind = kind
        if kind == .volume {
            model.content.volume = value
            model.content.muted = muted
        } else {
            model.content.brightness = value
        }
    }

    // MARK: Panel

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar, so the island (variant 4) can sit beside the notch
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        let host = NSHostingView(rootView: HUDStageView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        return panel
    }

    /// On the screen the pointer is on: wherever your eyes are.
    private func place(_ panel: NSPanel, kind: HUDKind) {
        let mouse = mouseOverride ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let frame = screen.frame
        let notch = notchOverride ?? Self.notchWidth(screen)
        let menuBar = notchOverride != nil ? 38 : Self.menuBarHeight(screen)
        let local = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        let variant = model.variant
        let box = HUDLayout.box(variant, kind: kind, screen: frame.size, mouse: local, notchWidth: notch, menuBar: menuBar)
        let center = HUDLayout.center(variant, kind: kind, screen: frame.size, mouse: local, notchWidth: notch, menuBar: menuBar)
        model.content.notchWidth = notch
        model.content.notchHeight = HUDLayout.notchHeight(menuBar: menuBar)
        model.center = CGPoint(x: center.x - box.minX, y: center.y - box.minY)
        model.boxSize = box.size
        panel.setFrame(NSRect(x: frame.minX + box.minX, y: frame.maxY - box.maxY, width: box.width, height: box.height),
                       display: false)
    }
}

extension HUDController {
    /// The real notch width (the gap between the two areas beside it); nil without a notch.
    static func notchWidth(_ screen: NSScreen) -> CGFloat? {
        guard let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else { return nil }
        return r.minX - l.maxX
    }

    /// The menu bar's real height on this screen: taller on a Mac with a notch. 0 when it's hidden
    /// (the layout then uses the measured 33 pt, the way macOS keeps its own popover in place).
    static func menuBarHeight(_ screen: NSScreen) -> CGFloat {
        max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
    }
}

final class HUDModel: ObservableObject {
    @Published var variant = HUDVariant.defaultVariant
    @Published var content = HUDContent()
    @Published var shown = false
    @Published var reduceMotion = false
    /// The indicator's centre inside its window, and the window's size.
    @Published var center = CGPoint.zero
    @Published var boxSize = CGSize(width: 100, height: 100)
}

/// The panel's content: the chosen variant at its spot, with its own entry and exit.
struct HUDStageView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            Group {
                if model.variant == 5 {
                    HUDVariantView(variant: 5, content: model.content)
                        .modifier(SlideFromEdge(shown: model.shown, reduceMotion: model.reduceMotion))
                } else {
                    HUDVariantView(variant: model.variant, content: model.content)
                        .modifier(Materialize(shown: model.shown, anchor: HUDLayout.anchor(model.variant),
                                              reduceMotion: model.reduceMotion))
                }
            }
            .position(model.center)
        }
        .frame(width: model.boxSize.width, height: model.boxSize.height)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}
