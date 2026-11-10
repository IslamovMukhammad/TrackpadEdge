import Testing
@testable import TrackpadEdge

/// Made-up multitouch frames. The trackpad is 127 × 78 mm, so 0.01 in x ≈ 1.3 mm and 0.01 in y ≈ 0.8 mm.
private func touch(_ id: Int32, _ x: Float, _ y: Float, state: Int32 = 4, size: Float = 1) -> EdgeGesture.Contact {
    .init(id: id, state: state, x: x, y: y, size: size)
}

/// Two fingers side by side, centred at (x, y), 0.04 apart.
private func pair(_ x: Float, _ y: Float) -> [EdgeGesture.Contact] {
    [touch(1, x + 0.02, y), touch(2, x - 0.02, y + 0.03)]
}

private let notTyping: Double = 10

/// Feeds frames and collects everything the gesture said.
private func run(_ gesture: inout EdgeGesture, _ frames: [[EdgeGesture.Contact]], sinceKey: Double = notTyping) -> [EdgeGesture.Output] {
    frames.compactMap { gesture.frame($0, sinceKey: sinceKey) }
}

/// Vertical steps of 0.02 (≈ 1.6 mm per frame, well under the glitch limit).
private func vertical(x: Float, from y: Float, steps: Int, by dy: Float = 0.02) -> [[EdgeGesture.Contact]] {
    (1...steps).map { pair(x, y + Float($0) * dy) }
}

@Suite("Accidental-scroll guard")
struct ScrollGuardTests {

    @Test func inwardThenVerticalControls() {
        var g = EdgeGesture()
        var out = run(&g, [pair(0.95, 0.4)])
        #expect(out == [.armed(.right)])
        // Slide 0.06 inward (≈ 7.6 mm), keeping the height
        out = run(&g, [pair(0.93, 0.4), pair(0.91, 0.4), pair(0.89, 0.4)])
        #expect(out == [.began(.right)])
        #expect(g.phase == .controlling)
        // Then up: the value rises
        out = run(&g, vertical(x: 0.89, from: 0.4, steps: 10))
        let deltas = out.compactMap { if case .moved(let d) = $0 { d } else { nil } }
        #expect(deltas.count == 10)
        #expect(deltas.last! > 0.1)
        #expect(zip(deltas, deltas.dropFirst()).allSatisfy { $0 < $1 })
        // Lifting ends it
        #expect(g.frame([], sinceKey: notTyping) == .ended(wasControlling: true))
        #expect(g.phase == .idle)
    }

    @Test func inwardThenDownLowersTheValue() {
        var g = EdgeGesture()
        _ = run(&g, [pair(0.95, 0.6), pair(0.92, 0.6), pair(0.89, 0.6)])
        #expect(g.phase == .controlling)
        let out = run(&g, vertical(x: 0.89, from: 0.6, steps: 10, by: -0.02))
        if case .moved(let d) = out.last { #expect(d < -0.1) } else { Issue.record("no move") }
    }

    @Test func verticalOnlyNearTheEdgeNeverControls() {
        var g = EdgeGesture()
        #expect(run(&g, [pair(0.95, 0.3)]) == [.armed(.right)])
        // An ordinary two-finger scroll right at the edge: straight up, a long way
        let out = run(&g, vertical(x: 0.95, from: 0.3, steps: 25))
        #expect(out == [.ended(wasControlling: false)])     // released as a scroll, nothing else
        #expect(g.phase == .ignored)
        #expect(g.frame([], sinceKey: notTyping) == nil)
        #expect(g.phase == .idle)
    }

    @Test func verticalOnlyDownwardAlsoNeverControls() {
        var g = EdgeGesture()
        let out = run(&g, [pair(0.03, 0.8)] + vertical(x: 0.03, from: 0.8, steps: 25, by: -0.02))
        #expect(out == [.armed(.left), .ended(wasControlling: false)])
    }

    @Test func slidingInAfterScrollingStillNeverControls() {
        var g = EdgeGesture()
        var frames = [pair(0.95, 0.3)] + vertical(x: 0.95, from: 0.3, steps: 8)
        // …then the same fingers drift inward: still the scroll, not control
        frames += [pair(0.92, 0.46), pair(0.88, 0.46), pair(0.84, 0.46), pair(0.80, 0.46)]
        frames += vertical(x: 0.80, from: 0.46, steps: 10)
        let out = run(&g, frames)
        #expect(!out.contains { if case .began = $0 { true } else { false } })
        #expect(!out.contains { if case .moved = $0 { true } else { false } })
    }

    @Test func smallWobbleBeforeSlidingInIsFine() {
        var g = EdgeGesture()
        // ≈ 1.6 mm of vertical wobble (under 4 mm), then the slide-in
        let out = run(&g, [pair(0.95, 0.5), pair(0.95, 0.51), pair(0.94, 0.52), pair(0.91, 0.52), pair(0.88, 0.52)])
        #expect(out == [.armed(.right), .began(.right)])
    }

    @Test func slidingOutwardDoesNotStartControl() {
        var g = EdgeGesture()
        // Fingers 25 mm from the right edge would be "outward" if they moved right: no start
        let out = run(&g, [pair(0.95, 0.5), pair(0.97, 0.5), pair(0.98, 0.5)])
        #expect(out == [.armed(.right)])
        #expect(g.phase == .armed)
    }
}

@Suite("Edge gesture rules (ported)")
struct EdgeGestureRuleTests {

    @Test func leftEdgeSlidesInToTheRight() {
        var g = EdgeGesture()
        let out = run(&g, [pair(0.03, 0.5), pair(0.05, 0.5), pair(0.07, 0.5), pair(0.09, 0.5)])
        #expect(out == [.armed(.left), .began(.left)])
    }

    @Test func fingersStartingInTheMiddleAreIgnored() {
        var g = EdgeGesture()
        let out = run(&g, [pair(0.5, 0.5), pair(0.93, 0.5), pair(0.88, 0.5)])
        #expect(out.isEmpty)
        #expect(g.phase == .ignored)
    }

    @Test func typingGuardIgnoresTheTouch() {
        var g = EdgeGesture()
        #expect(run(&g, [pair(0.95, 0.5)], sinceKey: 0.3).isEmpty)
        #expect(g.phase == .ignored)
        // Ignored until every finger lifts, even after the guard time passes
        #expect(run(&g, [pair(0.91, 0.5), pair(0.88, 0.5)]).isEmpty)
    }

    @Test func palmIsIgnored() {
        var g = EdgeGesture()
        let palm = [touch(1, 0.97, 0.5, size: 3), touch(2, 0.93, 0.5)]
        #expect(g.frame(palm, sinceKey: notTyping) == nil)
        #expect(g.phase == .ignored)
    }

    @Test func oneFingerAtTheEdgeWaitsForTheSecond() {
        var g = EdgeGesture()
        #expect(g.frame([touch(1, 0.97, 0.5)], sinceKey: notTyping) == nil)
        #expect(g.phase == .idle)
        #expect(g.frame([touch(1, 0.97, 0.5), touch(2, 0.93, 0.52)], sinceKey: notTyping) == .armed(.right))
    }

    @Test func threeFingersAreIgnored() {
        var g = EdgeGesture()
        let three = [touch(1, 0.97, 0.5), touch(2, 0.93, 0.5), touch(3, 0.9, 0.5)]
        #expect(g.frame(three, sinceKey: notTyping) == nil)
        #expect(g.phase == .ignored)
    }

    @Test func addingAFingerEndsControl() {
        var g = EdgeGesture()
        _ = run(&g, [pair(0.95, 0.5), pair(0.92, 0.5), pair(0.89, 0.5)])
        #expect(g.phase == .controlling)
        let three = pair(0.89, 0.5) + [touch(3, 0.5, 0.5)]
        #expect(g.frame(three, sinceKey: notTyping) == .ended(wasControlling: true))
        #expect(g.phase == .ignored)
        #expect(run(&g, [pair(0.89, 0.6)]).isEmpty)
    }

    @Test func liftedFramesWithoutTouchingStatesEnd() {
        var g = EdgeGesture()
        _ = run(&g, [pair(0.95, 0.5), pair(0.92, 0.5), pair(0.89, 0.5)])
        // State 5+ = lifting: no finger is touching any more
        let lifting = [touch(1, 0.91, 0.5, state: 6), touch(2, 0.87, 0.53, state: 6)]
        #expect(g.frame(lifting, sinceKey: notTyping) == .ended(wasControlling: true))
    }

    @Test func glitchFrameIsDropped() {
        var g = EdgeGesture()
        _ = run(&g, [pair(0.95, 0.5), pair(0.92, 0.5), pair(0.89, 0.5)])
        // A one-frame jump of 0.2 (≈ 15.6 mm) is a sensor glitch
        #expect(g.frame(pair(0.89, 0.7), sinceKey: notTyping) == nil)
        #expect(g.frame(pair(0.89, 0.5), sinceKey: notTyping) == .moved(0))
    }

    @Test func seventyMillimetresIsTheFullRange() {
        var g = EdgeGesture()
        _ = run(&g, [pair(0.95, 0.05), pair(0.92, 0.05), pair(0.89, 0.05)])
        // 70 mm on a 78 mm pad = 0.897 of the height, in small steps, then held to settle
        let target: Float = 0.05 + 70 / 78
        var frames = stride(from: Float(0.06), through: target, by: 0.02).map { pair(0.89, $0) }
        frames += Array(repeating: pair(0.89, target), count: 40)
        let out = run(&g, frames)
        if case .moved(let d) = out.last { #expect(abs(d - 1) < 0.01) } else { Issue.record("no move") }
    }

    @Test func cancelEndsWhatWasGoingOn() {
        var g = EdgeGesture()
        _ = run(&g, [pair(0.95, 0.5)])
        #expect(g.cancel() == .ended(wasControlling: false))
        _ = run(&g, [pair(0.95, 0.5), pair(0.92, 0.5), pair(0.89, 0.5)])
        #expect(g.cancel() == .ended(wasControlling: true))
        #expect(g.cancel() == nil)
        #expect(!g.isActive)
    }

    @Test func aNewTouchAfterLiftingWorks() {
        var g = EdgeGesture()
        _ = run(&g, [pair(0.5, 0.5)])
        #expect(g.phase == .ignored)
        _ = g.frame([], sinceKey: notTyping)
        #expect(run(&g, [pair(0.95, 0.5)]) == [.armed(.right)])
    }
}

@Suite("Edge → control mapping and scroll blocking")
struct MappingTests {

    @Test func rightIsVolumeUnlessSwapped() {
        #expect(TrackpadEdgeControl.kind(for: .right, swapped: false) == .volume)
        #expect(TrackpadEdgeControl.kind(for: .left, swapped: false) == .brightness)
        #expect(TrackpadEdgeControl.kind(for: .right, swapped: true) == .brightness)
        #expect(TrackpadEdgeControl.kind(for: .left, swapped: true) == .volume)
    }

    @Test func waitingForTheSlideInLetsVerticalScrollThrough() {
        let scroll: UInt32 = 22
        // Vertical scroll passes; horizontal scroll (a browser's swipe back) is held back
        #expect(!scrollTapDrops(type: scroll, mode: .horizontal, deltaX: 0, deltaY: 12))
        #expect(!scrollTapDrops(type: scroll, mode: .horizontal, deltaX: 2, deltaY: -9))
        #expect(scrollTapDrops(type: scroll, mode: .horizontal, deltaX: -8, deltaY: 1))
        // Gestures are left alone while waiting
        #expect(!scrollTapDrops(type: 29, mode: .horizontal, deltaX: 0, deltaY: 0))
    }

    @Test func whileControllingEverythingIsBlocked() {
        for type: UInt32 in [22, 29, 30, 31] {
            #expect(scrollTapDrops(type: type, mode: .all, deltaX: 0, deltaY: 5))
            #expect(!scrollTapDrops(type: type, mode: .none, deltaX: 9, deltaY: 0))
        }
        // Other events (e.g. mouse moved = 5) are never dropped
        #expect(!scrollTapDrops(type: 5, mode: .all, deltaX: 0, deltaY: 0))
    }
}
