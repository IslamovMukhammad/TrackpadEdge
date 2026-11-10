import Foundation

/// The gesture itself, with no system calls: frames from the trackpad go in, decisions come out.
/// `TrackpadEdgeControl` feeds it and turns its outputs into volume, brightness, the indicator and
/// scroll blocking. Kept pure so the rules can be tested with made-up frames.
///
/// The rules (ported from the author's earlier app, plus the accidental-scroll guard):
///   · two fingers must *touch down* at an edge: one within ~6 mm of it, the other within ~25 mm;
///   · nothing starts within 0.6 s of a key press, and a palm-sized contact is ignored;
///   · **accidental-scroll guard:** control starts only after both fingers first slide *inward*
///     from the edge (≥ 6 mm). Moving up or down before that never starts it: once the fingers
///     travel 4 mm vertically without sliding in, the touch counts as a scroll and is left alone
///     until every finger lifts;
///   · after the slide-in, up/down changes the value: 70 mm of travel = 0 → 100 %;
///   · adding or lifting a finger ends it.
///
/// Coordinates are the trackpad's normalised 0…1 values: x left → right, y bottom → top.
struct EdgeGesture {
    enum Edge: Equatable { case right, left }

    struct Contact: Equatable {
        let id: Int32
        /// MultitouchSupport's touch state: 3 = touched down, 4 = touching; the rest are
        /// hovering or lifting.
        let state: Int32
        let x: Float
        let y: Float
        let size: Float
    }

    struct Limits: Equatable {
        /// One of the two fingers must touch down within ~6 mm of the edge.
        var pairZone: Float = 0.95
        /// The other one must be on the same side too (within ~25 mm).
        var pairReach: Float = 0.8
        /// Sliding inward this far starts control.
        var pairInwardMM: Float = 6
        /// Moving this far up or down *before* sliding inward marks the touch as a scroll.
        var scrollMM: Float = 4
        /// Finger travel for 0 → 100 % (the trackpad is ~78 mm tall).
        var fullRangeMM: Float = 70
        /// A jump bigger than this in one frame is a sensor glitch and is dropped.
        var glitchMM: Float = 6
        /// Smoothing of the finger's y (0…1, smaller = smoother).
        var smoothing: Float = 0.35
        var palmSize: Float = 2.5
        var typingGuard: TimeInterval = 0.6
    }

    enum Phase: Equatable {
        case idle
        /// Two fingers at an edge, waiting for the slide-in. Horizontal scrolling is held back.
        case armed
        /// Slid inward: up/down now changes the value. All scrolling is held back.
        case controlling
        /// This touch is ignored until every finger lifts.
        case ignored
    }

    enum Output: Equatable {
        /// Two fingers touched down at this edge.
        case armed(Edge)
        /// The fingers slid inward: control starts now.
        case began(Edge)
        /// Change since `began`, as a fraction of the full range (+ = up).
        case moved(Float)
        /// The armed or controlling touch ended (lifted, a finger added, a scroll, or cancelled).
        case ended(wasControlling: Bool)
    }

    let limits: Limits
    /// The trackpad's size in millimetres.
    var surfaceMM: (w: Float, h: Float)

    private(set) var phase: Phase = .idle
    private(set) var edge: Edge = .right
    private var trackedIDs: [Int32]?
    private var startX: Float = 0, startY: Float = 0
    private var lastY: Float = 0, smoothY: Float = 0
    private var anchorY: Float = 0

    init(limits: Limits = Limits(), surfaceMM: (w: Float, h: Float) = (127, 78)) {
        self.limits = limits
        self.surfaceMM = surfaceMM
    }

    /// True while frames matter: a touch is being followed, or ignored until it lifts.
    var isActive: Bool { phase != .idle }

    /// One multitouch frame. `sinceKey` is the time since the last key press.
    mutating func frame(_ contacts: [Contact], sinceKey: TimeInterval) -> Output? {
        let touching = contacts.filter { $0.state == 3 || $0.state == 4 }

        if touching.isEmpty {
            let output = endOutput()
            reset()
            return output
        }
        if phase == .ignored { return nil }

        let ids = touching.map(\.id).sorted()
        guard let trackedIDs else {
            // A new touch: two fingers at an edge (right or left), not while typing
            guard sinceKey > limits.typingGuard, touching.allSatisfy({ $0.size < limits.palmSize }) else {
                phase = .ignored; return nil
            }
            let xs = touching.map(\.x)
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
            if touching.count == 2, maxX >= limits.pairZone, minX >= 1 - limits.pairReach {
                edge = .right
            } else if touching.count == 2, minX <= 1 - limits.pairZone, maxX <= limits.pairReach {
                edge = .left
            } else if touching.count == 1, maxX >= limits.pairZone || minX <= 1 - limits.pairZone {
                return nil                       // one finger at the edge: waiting for the second
            } else {
                phase = .ignored; return nil
            }
            self.trackedIDs = ids
            let c = centroid(touching)
            startX = c.x; startY = c.y
            lastY = c.y; smoothY = c.y
            phase = .armed
            return .armed(edge)
        }
        guard ids == trackedIDs else {
            // A finger was added or lifted: it ends, the rest is ignored until every finger lifts
            return ignore()
        }

        let touch = centroid(touching)
        // The sensor at the edge sometimes jumps far for one frame: drop that frame
        if abs(touch.y - lastY) * surfaceMM.h > limits.glitchMM { return nil }
        lastY = touch.y
        smoothY += (touch.y - smoothY) * limits.smoothing

        if phase == .armed {
            let inwardMM = (edge == .right ? startX - touch.x : touch.x - startX) * surfaceMM.w
            if inwardMM >= limits.pairInwardMM {
                phase = .controlling
                anchorY = smoothY
                return .began(edge)
            }
            // Accidental-scroll guard: vertical movement alone never starts control.
            let dyMM = (smoothY - startY) * surfaceMM.h
            if abs(dyMM) >= limits.scrollMM { return ignore() }
            return nil
        }
        return .moved((smoothY - anchorY) * surfaceMM.h / limits.fullRangeMM)
    }

    /// Frames stopped arriving (sleep, the trackpad went away): end whatever was going on.
    mutating func cancel() -> Output? {
        let output = endOutput()
        reset()
        return output
    }

    private mutating func ignore() -> Output? {
        let output = endOutput()
        trackedIDs = nil
        phase = .ignored
        return output
    }

    private func endOutput() -> Output? {
        switch phase {
        case .armed: .ended(wasControlling: false)
        case .controlling: .ended(wasControlling: true)
        case .idle, .ignored: nil
        }
    }

    private mutating func reset() {
        trackedIDs = nil
        phase = .idle
    }

    private func centroid(_ touches: [Contact]) -> (x: Float, y: Float) {
        let n = Float(touches.count)
        return (touches.reduce(0) { $0 + $1.x } / n, touches.reduce(0) { $0 + $1.y } / n)
    }
}
