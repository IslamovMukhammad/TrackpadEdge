import CoreGraphics
import SwiftUI

/// Where each variant sits on the screen. Coordinates are top-left based, in points.
/// The indicator gets a small window around its own spot (not the whole screen), with room for
/// the entry blur and the squash at 0 %/100 %.
enum HUDLayout {
    /// Room around the indicator inside its window.
    static let margin: CGFloat = 40

    /// The variant's nominal size.
    static func size(_ variant: Int, notchWidth: CGFloat?, notchHeight: CGFloat = 33) -> CGSize {
        switch variant {
        case 1: CGSize(width: 292, height: 64)
        case 2: CGSize(width: 292, height: 72)
        case 3: CGSize(width: 200, height: 200)
        case 4: notchWidth.map { CGSize(width: 168 + $0, height: notchHeight) } ?? CGSize(width: 188, height: 32)
        case 5: CGSize(width: 58, height: 198)
        case 6: CGSize(width: 248, height: 38)
        case 7: CGSize(width: 320, height: 98)
        case 8: CGSize(width: 280, height: 104)
        case 9: CGSize(width: 136, height: 136)
        default: CGSize(width: 178, height: 28)
        }
    }

    /// The menu bar's height when it can't be read (hidden or full screen): the measured 33 pt.
    static let defaultMenuBar: CGFloat = 33

    /// The top of the indicators that hang under the menu bar: 7 pt below it, like macOS's own.
    /// On a Mac with a notch the menu bar is taller, so they move down with it.
    /// The island beside a notch is as tall as the notch (the menu bar on those Macs); at least
    /// the measured 33 pt.
    static func notchHeight(menuBar: CGFloat) -> CGFloat { max(33, menuBar) }

    static func top(menuBar: CGFloat) -> CGFloat { (menuBar > 0 ? menuBar : defaultMenuBar) + 7 }

    /// The centre of the variant on a screen of this size. `mouse` is the pointer (variant 10).
    /// Variants 1 and 2 sit under the Sound / Display menu bar icons, measured on a 1440 pt wide
    /// screen (x 1084 and 1121) and kept at the same distance from the right edge.
    static func center(_ variant: Int, kind: HUDKind, screen: CGSize, mouse: CGPoint, notchWidth: CGFloat?,
                       menuBar: CGFloat = defaultMenuBar) -> CGPoint {
        let w = screen.width, h = screen.height
        let iconX = w - (kind == .volume ? 356 : 319)
        let top = top(menuBar: menuBar)
        switch variant {
        case 1, 2: return CGPoint(x: iconX, y: top + 32)
        case 3: return CGPoint(x: w / 2, y: h - 140 - 100)
        case 4: return CGPoint(x: w / 2, y: notchWidth == nil ? 16 : notchHeight(menuBar: menuBar) / 2)
        case 5: return CGPoint(x: w - 14 - 23, y: h / 2)
        case 6: return CGPoint(x: w / 2, y: top + 19)
        case 7: return CGPoint(x: w - 12 - 160, y: top + 48)
        case 8: return CGPoint(x: w - 12 - 140, y: top + 66)
        case 9: return CGPoint(x: w / 2, y: h - 140 - 68)
        default:
            // Below and right of the pointer, kept on screen
            let size = size(10, notchWidth: nil)
            let x = min(max(mouse.x + 22 + size.width / 2, size.width / 2 + 8), w - size.width / 2 - 8)
            let y = min(max(mouse.y + 26 + size.height / 2, size.height / 2 + 8), h - size.height / 2 - 8)
            return CGPoint(x: x, y: y)
        }
    }

    /// The indicator's window: its spot plus a margin, kept inside the screen. Variant 5 runs to
    /// the right edge so it can slide in from there.
    static func box(_ variant: Int, kind: HUDKind, screen: CGSize, mouse: CGPoint, notchWidth: CGFloat?,
                    menuBar: CGFloat = defaultMenuBar) -> CGRect {
        let c = center(variant, kind: kind, screen: screen, mouse: mouse, notchWidth: notchWidth, menuBar: menuBar)
        let s = size(variant, notchWidth: notchWidth, notchHeight: notchHeight(menuBar: menuBar))
        var rect = CGRect(x: c.x - s.width / 2 - margin, y: c.y - s.height / 2 - margin,
                          width: s.width + 2 * margin, height: s.height + 2 * margin)
        if variant == 5 { rect.size.width = screen.width - rect.minX }
        return rect.intersection(CGRect(origin: .zero, size: screen)).integral
    }

    /// The point entry and exit scale around.
    static func anchor(_ variant: Int) -> UnitPoint {
        switch variant {
        case 3, 9: .center
        case 5: .trailing
        case 10: .topLeading
        default: .top
        }
    }

    /// How long it stays after the last change: variant 5 narrows after 1 s and closes after
    /// 1.8 s (the production timings); the others close after 1.1 s, like macOS's own.
    static func timing(_ variant: Int) -> (thin: TimeInterval?, hide: TimeInterval) {
        variant == 5 ? (1.0, 1.8) : (nil, 1.1)
    }
}
