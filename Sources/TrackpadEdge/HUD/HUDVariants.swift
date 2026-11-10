import AppKit
import SwiftUI

// The ten indicator designs, ported from the author's earlier app's HUD lab (real Liquid Glass, macOS 26+).
// Measurements of macOS's own volume popover (macOS 27, 1440×900 pt screen): 292 × 64 pt panel,
// ~20 pt continuous corners, 225 pt track ~4 pt thick, 17 dots 13.47 pt apart; it appears in
// ~300 ms (scale 0.94 → 1, anchored at the top centre, no bounce) and stays ~1.1 s after the last change.

enum HUDKind: Equatable, Sendable {
    case volume, brightness

    var name: String { self == .volume ? "Sound" : "Display" }
    var high: String { self == .volume ? "speaker.wave.3.fill" : "sun.max.fill" }
    var low: String { self == .volume ? "speaker.fill" : "sun.min.fill" }
}

/// Everything a variant needs to draw itself.
struct HUDContent: Equatable {
    var kind: HUDKind = .volume
    var volume = 0.62
    var brightness = 0.48
    var muted = false
    var pulse = 0
    /// Variant 5 only: narrows to a thin line a second after the last change.
    var thin = false
    /// The output device's name, used as the title the way macOS shows it.
    var volumeTitle = "MacBook Pro Speakers"
    /// The real notch width of the screen the indicator is on; nil without a notch.
    var notchWidth: CGFloat?
    /// The notch's height (the menu bar's on those Macs), so the island covers it exactly.
    var notchHeight: CGFloat = 33

    /// The shown value: muted volume reads as 0.
    func value(_ k: HUDKind) -> Double {
        k == .volume ? (muted ? 0 : volume) : brightness
    }
    var value: Double { value(kind) }

    func title(_ k: HUDKind) -> String { k == .volume ? volumeTitle : "Display" }

    /// The big icon: muted (or 0 %) volume shows the crossed-out speaker.
    func symbol(_ k: HUDKind) -> String {
        k == .volume && (muted || volume <= 0.001) ? "speaker.slash.fill" : k.high
    }
}

enum HUDVariant {
    static let all = Array(1...10)
    static let defaultVariant = 5

    static func name(_ n: Int) -> String {
        switch n {
        case 1: "Original (macOS 27.0)"
        case 2: "Segmented (macOS 27.2)"
        case 3: "Classic centre"
        case 4: "Island"
        case 5: "Edge column"
        case 6: "Compact capsule"
        case 7: "Control Centre module"
        case 8: "Pair"
        case 9: "Ring"
        default: "Near cursor"
        }
    }

    static func detail(_ n: Int) -> String {
        switch n {
        case 1: "macOS's own popover, under the menu bar icon"
        case 2: "One big icon and 16 segments, under the menu bar"
        case 3: "The classic square in the lower centre"
        case 4: "Beside the notch, or a black island at the top"
        case 5: "A glass column at the right edge; thins after a second"
        case 6: "A small capsule with the number, under the menu bar"
        case 7: "Device name and a thick slider, top right"
        case 8: "Volume and brightness together, top right"
        case 9: "A thin ring with the number, lower centre"
        default: "A small capsule next to the pointer"
        }
    }

    static func clamp(_ n: Int) -> Int { all.contains(n) ? n : defaultVariant }
}

// MARK: - Shared pieces

let hudEase = Animation.spring(duration: 0.32, bounce: 0)          // entry and value: no bounce
let hudValueAnim = Animation.spring(duration: 0.24, bounce: 0)
let hudExit = Animation.easeIn(duration: 0.2)
/// Variant 5 slides in from the right edge and back out (the production timings).
let hudEdgeIn = Animation.spring(duration: 0.5, bounce: 0.1)
let hudEdgeOut = Animation.spring(duration: 0.4, bounce: 0)
let hudThin = Animation.spring(duration: 0.45, bounce: 0)

/// Entry/exit: scale 0.94 → 1 around the given point, opacity, and a 4 pt blur (like macOS's own).
/// With Reduce Motion: opacity only.
struct Materialize: ViewModifier {
    let shown: Bool; let anchor: UnitPoint; let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.94, anchor: anchor)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 4)
    }
}

/// Variant 5: slides in from the right edge and back. Transform and opacity only, so a new value
/// in the middle of closing turns it around from where it is.
struct SlideFromEdge: ViewModifier {
    let shown: Bool; let reduceMotion: Bool
    func body(content: Content) -> some View {
        content.offset(x: shown || reduceMotion ? 0 : 74).opacity(shown ? 1 : 0)
    }
}

/// Hitting 0 % or 100 %: a quick stretch that springs back.
struct LimitSquash: ViewModifier {
    let pulse: Int; let anchor: UnitPoint; let vertical: Bool
    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: pulse) { view, v in
            view.scaleEffect(x: vertical ? 1 - 0.03 * v : 1 + 0.025 * v, y: vertical ? 1 + 0.025 * v : 1 - 0.03 * v, anchor: anchor)
        } keyframes: { _ in
            LinearKeyframe(1, duration: 0.07)
            SpringKeyframe(0, duration: 0.4, spring: .init(duration: 0.4, bounce: 0.35))
        }
    }
}

func pct(_ v: Double) -> Int { Int((v * 100).rounded()) }

/// A rounded track with its filled part.
struct HUDBar: View {
    let value: Double; var height: CGFloat = 4; var track = Color.white.opacity(0.16); var fill = Color.white
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(height, g.size.width * value))
            }
        }.frame(height: height)
    }
}

// MARK: - 1 · Original (macOS 27.0/27.1), to the measured pixels

struct V1: View {
    let c: HUDContent
    var body: some View {
        let k = c.kind, value = c.value
        ZStack(alignment: .topLeading) {
            Text(c.title(k)).font(.system(size: 13, weight: .semibold)).lineLimit(1).frame(width: 258, alignment: .leading).offset(x: 17.5, y: 10)
            Image(systemName: k.low).font(.system(size: 11, weight: .medium)).frame(width: 14, height: 14).position(x: 21, y: 41.5)
            Image(systemName: k.high).font(.system(size: 12.5, weight: .medium)).frame(width: 18, height: 16).position(x: 269.5, y: 41.5)
                .symbolEffect(.bounce, value: c.pulse)
            HUDBar(value: value, height: 4).frame(width: 225).position(x: 33 + 112.5, y: 40.5)
            ForEach(0..<17, id: \.self) { i in
                Circle().fill(.white.opacity(0.13)).frame(width: 2.2, height: 2.2).position(x: 37.5 + Double(i) * 13.47, y: 46.5)
            }
        }
        .frame(width: 292, height: 64, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .modifier(LimitSquash(pulse: c.pulse, anchor: .leading, vertical: false))
    }
}

// MARK: - 2 · macOS 27.2 style: one big icon, 16 segments, quarter steps

struct V2: View {
    let c: HUDContent
    var body: some View {
        let k = c.kind, value = c.value
        VStack(alignment: .leading, spacing: 9) {
            Text(c.title(k)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            HStack(spacing: 12) {
                Image(systemName: c.symbol(k), variableValue: value).font(.system(size: 17, weight: .medium)).frame(width: 24)
                    .symbolEffect(.bounce, value: c.pulse)
                HStack(spacing: 3) {
                    ForEach(0..<16, id: \.self) { i in
                        let f = (min(1, max(0, value * 16 - Double(i))) * 4).rounded() / 4   // quarter segment
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(.white.opacity(0.18))
                                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(.white).frame(width: g.size.width * f)
                            }
                        }.frame(height: 7)
                    }
                }
            }
        }
        .padding(.horizontal, 17).padding(.top, 12).padding(.bottom, 14)
        .frame(width: 292, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .modifier(LimitSquash(pulse: c.pulse, anchor: .leading, vertical: false))
    }
}

// MARK: - 3 · Classic centre bezel, in glass (200×200, 16 squares)

struct V3: View {
    let c: HUDContent
    var body: some View {
        let k = c.kind, value = c.value
        ZStack {
            Image(systemName: c.symbol(k), variableValue: value).font(.system(size: 80, weight: .regular)).position(x: 100, y: 83)
                .symbolEffect(.bounce, value: c.pulse)
            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { i in
                    let f = (min(1, max(0, value * 16 - Double(i))) * 4).rounded() / 4
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.25))
                        Rectangle().fill(.white).frame(width: 7.5 * f)
                    }.frame(width: 7.5, height: 7.5)
                }
            }.position(x: 100, y: 165)
        }
        .frame(width: 200, height: 200)
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
    }
}

// MARK: - 4 · Island: either side of the notch; on a screen without one, a solid island at the top edge

struct V4: View {
    let c: HUDContent
    var body: some View {
        let k = c.kind, value = c.value
        let icon = Image(systemName: c.symbol(k), variableValue: value).font(.system(size: 14, weight: .semibold))
            .symbolEffect(.bounce, value: c.pulse)
        let meter = HStack(spacing: 8) {
            HUDBar(value: value, height: 4, track: .white.opacity(0.22)).frame(width: c.notchWidth == nil ? 92 : 40)
            Text("\(pct(value))").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText(value: value * 100)).frame(width: 24, alignment: .trailing)
        }
        Group {
            if let notch = c.notchWidth {
                HStack(spacing: 0) {
                    icon.frame(width: 78).padding(.leading, 6)
                    Spacer().frame(width: notch)
                    meter.frame(width: 78).padding(.trailing, 6)
                }.frame(height: c.notchHeight)
            } else {
                HStack(spacing: 12) { icon.frame(width: 20); meter }
                    .padding(.horizontal, 16).frame(height: 32)
            }
        }
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous).fill(.black))
        .foregroundStyle(.white)
    }
}

// MARK: - 5 · Edge column (iOS-like): full first, thin after a second. The production design.

struct V5: View {
    let c: HUDContent

    private let height: CGFloat = 186
    /// The icon centre's height above the column's bottom, and the icon box
    private let iconBottom: CGFloat = 23
    private let iconBox: CGFloat = 18

    var body: some View {
        let width: CGFloat = c.thin ? 12 : 46
        let level = c.value
        ZStack(alignment: .bottom) {
            Capsule().fill(.white.opacity(0.16))
            // The filled part is exactly proportional; the column's own shape rounds its bottom
            Rectangle().fill(.white).frame(height: height * level)
            if !c.thin {
                // Two layers: white over the empty part, dark over the filled part; the border runs across the icon
                ZStack {
                    icon.foregroundStyle(.white.opacity(0.9))
                    icon.foregroundStyle(.black.opacity(0.72))
                        .mask(alignment: .bottom) {
                            Rectangle().frame(height: max(0, height * level - iconBottom + iconBox / 2))
                        }
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(height: iconBox)
                .padding(.bottom, iconBottom - iconBox / 2)
                .symbolEffect(.bounce, value: c.pulse)
                .transition(.opacity)
            }
        }
        .frame(width: width - (c.thin ? 4 : 12), height: height)
        .clipShape(Capsule())          // while narrowing, the icon must not stick out
        .padding(c.thin ? 2 : 6)
        .glassEffect(.regular, in: .capsule)
        .modifier(LimitSquash(pulse: c.pulse, anchor: .bottom, vertical: true))
    }

    private var icon: some View {
        Image(systemName: c.symbol(c.kind), variableValue: c.value)
    }
}

// MARK: - 6 · Compact capsule under the menu bar, with the number

struct V6: View {
    let c: HUDContent
    var body: some View {
        let k = c.kind, value = c.value
        HStack(spacing: 12) {
            Image(systemName: c.symbol(k), variableValue: value).font(.system(size: 15, weight: .semibold)).frame(width: 22)
                .symbolEffect(.bounce, value: c.pulse)
            HUDBar(value: value, height: 4).frame(width: 140)
            Text("\(pct(value))").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText(value: value * 100)).frame(width: 28, alignment: .trailing)
        }
        .padding(.leading, 16).padding(.trailing, 18).frame(height: 38)
        .glassEffect(.regular, in: .capsule)
        .modifier(LimitSquash(pulse: c.pulse, anchor: .leading, vertical: false))
    }
}

// MARK: - 7 · Control Centre module: device name and a thick slider (icon inside the filled part)

struct V7: View {
    let c: HUDContent
    var body: some View {
        let k = c.kind, value = c.value
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: k == .volume ? "laptopcomputer" : "display").font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(k.name).font(.system(size: 13, weight: .semibold))
                    Text(k == .volume ? c.volumeTitle : "Built-in Display").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text("\(pct(value))%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: value * 100))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule().fill(.white).frame(width: max(28, g.size.width * value))
                    Image(systemName: c.symbol(k), variableValue: value).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.7)).padding(.leading, 9).symbolEffect(.bounce, value: c.pulse)
                }
            }.frame(height: 28)
        }
        .padding(14).frame(width: 320)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .modifier(LimitSquash(pulse: c.pulse, anchor: .leading, vertical: false))
    }
}

// MARK: - 8 · Pair: volume and brightness together, the changing one large; the glass flows on a switch

struct V8: View {
    let c: HUDContent
    @Namespace private var ns
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                row(.volume)
                row(.brightness)
            }
        }
    }
    @ViewBuilder func row(_ k: HUDKind) -> some View {
        let big = k == c.kind
        let v = c.value(k)
        HStack(spacing: 12) {
            Image(systemName: c.symbol(k), variableValue: v).font(.system(size: big ? 15 : 12, weight: .semibold)).frame(width: 22)
                .foregroundStyle(big ? .primary : .secondary).symbolEffect(.bounce, value: big ? c.pulse : 0)
            VStack(alignment: .leading, spacing: 7) {
                if big {
                    HStack {
                        Text(k.name).font(.system(size: 13, weight: .semibold)); Spacer()
                        Text("\(pct(v))%").font(.system(size: 13, weight: .semibold)).monospacedDigit().contentTransition(.numericText(value: v * 100))
                    }
                }
                HUDBar(value: v, height: big ? 6 : 3, fill: big ? .white : .white.opacity(0.55))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, big ? 13 : 10)
        .frame(width: 280)
        .glassEffect(.regular, in: .rect(cornerRadius: big ? 22 : 17, style: .continuous))
        .glassEffectID(k == .volume ? "v" : "b", in: ns)
    }
}

// MARK: - 9 · Ring: a thin ring like Apple Watch, icon and number in the middle

struct V9: View {
    let c: HUDContent
    var body: some View {
        let k = c.kind, value = c.value
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 6).padding(16)
            Circle().trim(from: 0, to: value).stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(16)
            VStack(spacing: 4) {
                Image(systemName: c.symbol(k), variableValue: value).font(.system(size: 28, weight: .medium)).symbolEffect(.bounce, value: c.pulse)
                Text("\(pct(value))").font(.system(size: 13, weight: .semibold)).monospacedDigit().contentTransition(.numericText(value: value * 100))
            }
        }
        .frame(width: 136, height: 136)
        .glassEffect(.regular, in: .circle)
    }
}

// MARK: - 10 · Near the cursor: the indicator shows up where your eyes are

struct V10: View {
    let c: HUDContent
    var body: some View {
        let k = c.kind, value = c.value
        HStack(spacing: 9) {
            Image(systemName: c.symbol(k), variableValue: value).font(.system(size: 12, weight: .semibold)).frame(width: 18)
                .symbolEffect(.bounce, value: c.pulse)
            HUDBar(value: value, height: 3).frame(width: 96)
            Text("\(pct(value))").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText(value: value * 100)).frame(width: 22, alignment: .trailing)
        }
        .padding(.horizontal, 12).frame(height: 28)
        .glassEffect(.regular, in: .capsule)
        .modifier(LimitSquash(pulse: c.pulse, anchor: .leading, vertical: false))
    }
}

/// One variant, drawn with the given content.
struct HUDVariantView: View {
    let variant: Int
    let content: HUDContent
    var body: some View {
        switch variant {
        case 1: V1(c: content)
        case 2: V2(c: content)
        case 3: V3(c: content)
        case 4: V4(c: content)
        case 5: V5(c: content)
        case 6: V6(c: content)
        case 7: V7(c: content)
        case 8: V8(c: content)
        case 9: V9(c: content)
        default: V10(c: content)
        }
    }
}
