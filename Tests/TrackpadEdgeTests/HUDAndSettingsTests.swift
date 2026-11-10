import CoreGraphics
import Foundation
import Testing
@testable import TrackpadEdge

@Suite("Indicator variants")
struct HUDVariantTests {

    @Test func tenVariantsDefaultFive() {
        #expect(HUDVariant.all == Array(1...10))
        #expect(HUDVariant.defaultVariant == 5)
        #expect(HUDVariant.name(5) == "Edge column")
        #expect(Set(HUDVariant.all.map(HUDVariant.name)).count == 10)
        #expect(HUDVariant.clamp(0) == 5)
        #expect(HUDVariant.clamp(11) == 5)
        #expect(HUDVariant.clamp(7) == 7)
    }

    @Test func everyVariantFitsOnScreen() {
        let screens = [CGSize(width: 1440, height: 900), CGSize(width: 1512, height: 982), CGSize(width: 1024, height: 640)]
        for screen in screens {
            for notch in [nil, CGFloat(186)] as [CGFloat?] {
                for variant in HUDVariant.all {
                    for kind in [HUDKind.volume, .brightness] {
                        for mouse in [CGPoint(x: 10, y: 10), CGPoint(x: screen.width - 2, y: screen.height - 2), CGPoint(x: 600, y: 400)] {
                            let box = HUDLayout.box(variant, kind: kind, screen: screen, mouse: mouse, notchWidth: notch)
                            let center = HUDLayout.center(variant, kind: kind, screen: screen, mouse: mouse, notchWidth: notch)
                            let bounds = CGRect(origin: .zero, size: screen)
                            #expect(bounds.contains(box), "variant \(variant) box \(box)")
                            #expect(box.contains(center), "variant \(variant) centre outside its window")
                        }
                    }
                }
            }
        }
    }

    @Test func edgeColumnSitsAtTheRightEdgeMiddle() {
        let screen = CGSize(width: 1440, height: 900)
        let c = HUDLayout.center(5, kind: .volume, screen: screen, mouse: .zero, notchWidth: nil)
        #expect(c == CGPoint(x: 1440 - 37, y: 450))
        let box = HUDLayout.box(5, kind: .volume, screen: screen, mouse: .zero, notchWidth: nil)
        #expect(box.maxX == 1440)      // so it can slide in from the edge
    }

    @Test func menuBarVariantsMatchTheMeasuredSpots() {
        let screen = CGSize(width: 1440, height: 900)
        #expect(HUDLayout.center(1, kind: .volume, screen: screen, mouse: .zero, notchWidth: nil).x == 1084)
        #expect(HUDLayout.center(1, kind: .brightness, screen: screen, mouse: .zero, notchWidth: nil).x == 1121)
    }

    @Test func timings() {
        #expect(HUDLayout.timing(5).thin == 1.0)
        #expect(HUDLayout.timing(5).hide == 1.8)
        for n in HUDVariant.all where n != 5 {
            #expect(HUDLayout.timing(n).thin == nil)
            #expect(HUDLayout.timing(n).hide == 1.1)
        }
    }

    @Test func mutedVolumeReadsAsZero() {
        var c = HUDContent()
        c.volume = 0.7; c.muted = true
        #expect(c.value(.volume) == 0)
        #expect(c.symbol(.volume) == "speaker.slash.fill")
        c.muted = false
        #expect(c.value(.volume) == 0.7)
        #expect(c.symbol(.volume) == "speaker.wave.3.fill")
        #expect(c.symbol(.brightness) == "sun.max.fill")
    }
}

@Suite("Settings")
struct SettingsTests {

    /// An in-memory store: nothing is written to disk.
    private final class MemoryStore: SettingsStore {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    private func withFreshDefaults(_ body: (MemoryStore) -> Void) {
        body(MemoryStore())
    }

    @Test func defaults() {
        withFreshDefaults { d in
            let s = AppSettings(defaults: d)
            #expect(s.enabled)
            #expect(!s.swapEdges)
            #expect(s.hudVariant == 5)
        }
    }

    @Test func savesAndReloads() {
        withFreshDefaults { d in
            let s = AppSettings(defaults: d)
            s.swapEdges = true
            s.hudVariant = 9
            s.enabled = false
            let again = AppSettings(defaults: d)
            #expect(again.swapEdges)
            #expect(again.hudVariant == 9)
            #expect(!again.enabled)
        }
    }

    @Test func unknownVariantFallsBackToFive() {
        withFreshDefaults { d in
            d.set(42, forKey: AppSettings.Keys.hudVariant)
            #expect(AppSettings(defaults: d).hudVariant == 5)
        }
    }
}

@Suite("Macs with a notch")
struct NotchLayoutTests {
    private let screen = CGSize(width: 1512, height: 982)    // 14" MacBook Pro

    @Test func menuBarIndicatorsMoveDownWithATallerMenuBar() {
        for variant in [1, 2, 6, 7, 8] {
            let plain = HUDLayout.center(variant, kind: .volume, screen: screen, mouse: .zero, notchWidth: nil, menuBar: 24)
            let notched = HUDLayout.center(variant, kind: .volume, screen: screen, mouse: .zero, notchWidth: 185, menuBar: 38)
            #expect(notched.y - plain.y == 14, "variant \(variant)")
            // It never overlaps the taller menu bar
            let size = HUDLayout.size(variant, notchWidth: 185)
            #expect(notched.y - size.height / 2 > 38, "variant \(variant)")
        }
    }

    @Test func islandWrapsTheNotch() {
        let size = HUDLayout.size(4, notchWidth: 185, notchHeight: 38)
        #expect(size == CGSize(width: 185 + 168, height: 38))
        let c = HUDLayout.center(4, kind: .volume, screen: screen, mouse: .zero, notchWidth: 185, menuBar: 38)
        #expect(c == CGPoint(x: screen.width / 2, y: 19))      // flush with the top edge, centred on the notch
        let box = HUDLayout.box(4, kind: .volume, screen: screen, mouse: .zero, notchWidth: 185, menuBar: 38)
        #expect(box.minY == 0)
    }

    @Test func hiddenMenuBarKeepsTheMeasuredSpot() {
        let c = HUDLayout.center(1, kind: .volume, screen: CGSize(width: 1440, height: 900), mouse: .zero, notchWidth: nil, menuBar: 0)
        #expect(c.y == 72)
    }
}
