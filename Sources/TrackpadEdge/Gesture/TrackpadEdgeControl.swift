import AppKit
import CoreAudio
import CoreGraphics
import IOKit.hid

/// Two fingers on the trackpad's right edge control the volume, on the left edge the brightness
/// (a setting swaps the sides). Ported from the author's earlier app; the rules live in
/// `EdgeGesture`.
///
/// How it works:
///   · fingers are read from Apple's private `MultitouchSupport` framework (BetterTouchTool and
///     MiddleClick use the same route), loaded with `dlopen`: if a future macOS drops it, the
///     feature quietly turns off and the app keeps running;
///   · a cheap check runs on the sensor thread itself, so frames reach the app only when two
///     fingers touch down at an edge; ordinary trackpad use costs next to nothing;
///   · the Touch Bar is a "multitouch device" too: devices less than 3 cm tall are skipped;
///   · while the fingers wait for the slide-in, horizontal scrolling is held back (so the slide
///     doesn't swipe a browser back) but vertical scrolling passes through untouched; once
///     control starts, all scroll and gesture events are blocked until the fingers lift;
///   · volume is written on its own queue, at most 30 times a second; frames never pile up.
@MainActor
final class TrackpadEdgeControl {
    static let shared = TrackpadEdgeControl()

    private let volume = SystemVolume()
    private let brightness = SystemBrightness()

    private var gesture = EdgeGesture()
    private var running = false
    private var devices: [UnsafeMutableRawPointer] = []
    private var keyMonitor: Any?
    private var wakeObserver: Any?
    private var lastKey = Date.distantPast
    private var lastFrame = Date.distantPast
    private var watchdog: Timer?

    // The control in progress
    private var kind: HUDKind = .volume
    private var startValue: Float = 0
    private var lastWritten: Float = -1
    private var startMuted = false

    /// False when MultitouchSupport can't be loaded (or there is no trackpad).
    var isAvailable: Bool { MT.shared.isAvailable }

    // MARK: On / off

    func setEnabled(_ on: Bool) {
        on ? start() : stop()
    }

    private func start() {
        guard !running, MT.shared.isAvailable else { return }
        running = true
        devices = MT.shared.trackpads()
        if let first = devices.first { gesture.surfaceMM = MT.shared.surfaceMM(first) }
        for device in devices { MT.shared.register(device) }
        Self.debug("listening on \(devices.count) trackpad(s), surface \(gesture.surfaceMM) mm, input monitoring: \(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue) (0 granted, 1 denied, 2 unknown), accessibility: \(AXIsProcessTrusted())")
        if Self.log {
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let now = rawFrameCount
                    let r = lastRejectedPair
                    if r.4 != TrackpadEdgeControl.loggedRejects {
                        Self.debug(String(format: "pair turned down #%d: x %.3f / %.3f, already-outside %@ / %@", r.4, r.0, r.1, "\(r.2)", "\(r.3)"))
                        TrackpadEdgeControl.loggedRejects = r.4
                    }
                    if now != TrackpadEdgeControl.loggedFrames {
                        Self.debug("raw sensor frames so far: \(now)")
                        TrackpadEdgeControl.loggedFrames = now
                    }
                }
            }
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { _ in
            MainActor.assumeIsolated { TrackpadEdgeControl.shared.lastKey = Date() }
        }
        // After sleep the devices have to be opened again
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let me = TrackpadEdgeControl.shared
                guard me.running else { return }
                me.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { me.start() }
            }
        }
    }

    private func stop() {
        guard running else { return }
        running = false
        for device in devices { MT.shared.unregister(device) }
        devices = []
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        if let output = gesture.cancel() { handle(output) }
        edgeActive = false
    }

    // MARK: Frames

    /// One multitouch frame (main thread).
    fileprivate func frame(_ contacts: [EdgeGesture.Contact]) {
        guard running else { return }
        lastFrame = Date()
        let output = gesture.frame(contacts, sinceKey: Date().timeIntervalSince(lastKey))
        if let output { handle(output) }
        edgeActive = gesture.isActive
    }

    /// `TRACKPADEDGE_LOG=1` prints each gesture decision (for checking the guard on a real trackpad).
    private static let log = ProcessInfo.processInfo.environment["TRACKPADEDGE_LOG"] == "1"

    private static var loggedFrames = 0
    private static var loggedRejects = 0

    private static func debug(_ message: @autoclosure () -> String) {
        guard log else { return }
        FileHandle.standardError.write(Data("[TrackpadEdge] \(message())\n".utf8))
    }

    private func handle(_ output: EdgeGesture.Output) {
        if case .moved = output {} else { Self.debug("\(output)") }
        switch output {
        case .armed:
            setScrollBlock(.horizontal)
            startWatchdog()
        case .began(let edge):
            setScrollBlock(.all)
            begin(kind: Self.kind(for: edge, swapped: AppSettings.shared.swapEdges))
        case .moved(let delta):
            update(delta)
        case .ended(let wasControlling):
            if wasControlling { Self.debug("\(kind) ended at \(Int((lastWritten * 100).rounded())) % (started at \(Int((startValue * 100).rounded())) %)") }
            watchdog?.invalidate(); watchdog = nil
            releaseScroll(afterControl: wasControlling)
            if wasControlling { HUDController.shared.release() }
        }
    }

    /// Right edge → volume, left edge → brightness; the setting swaps them.
    static func kind(for edge: EdgeGesture.Edge, swapped: Bool) -> HUDKind {
        (edge == .right) != swapped ? .volume : .brightness
    }

    private func begin(kind: HUDKind) {
        self.kind = kind
        startValue = currentValue()
        lastWritten = startValue
        startMuted = kind == .volume && volume.isMuted
        if kind == .volume { VolumeWriter.shared.prepare(unmute: startMuted) }
        // The pair variant shows both values: read the other one once.
        let other = kind == .volume ? brightness.brightness : (volume.isMuted ? 0 : volume.volume)
        HUDController.shared.setCompanion(Double(other), for: kind == .volume ? .brightness : .volume)
        HUDController.shared.setVolumeTitle(volume.deviceName)
        showHUD(startValue)
    }

    private func update(_ delta: Float) {
        let value = min(1, max(0, startValue + delta))
        guard abs(value - lastWritten) >= 0.001 else { return }
        let hitLimit = (value == 1 || value == 0) && lastWritten != value
        lastWritten = value
        switch kind {
        case .volume: VolumeWriter.shared.write(value); if value > 0 { startMuted = false }
        case .brightness: brightness.brightness = value
        }
        if hitLimit {
            // Silent: only a trackpad tick, so the finger feels it reached the end
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        showHUD(value)
    }

    private func currentValue() -> Float {
        switch kind {
        case .volume: volume.isMuted ? 0 : volume.volume
        case .brightness: brightness.brightness
        }
    }

    private func showHUD(_ value: Float) {
        HUDController.shared.track(kind, value: Double(value), muted: kind == .volume && startMuted)
    }

    /// If frames stop (sleep, the trackpad went away), the scroll block and the indicator must not hang.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated {
                let me = TrackpadEdgeControl.shared
                guard Date().timeIntervalSince(me.lastFrame) > 0.35 else { return }
                if let output = me.gesture.cancel() { me.handle(output) }
                me.watchdog?.invalidate(); me.watchdog = nil
                edgeActive = false
            }
        }
    }

    // MARK: Scroll blocking

    // An event tap at the HID level. It's installed on first use and enabled only while a touch
    // is being followed; the rest of the time no event passes through TrackpadEdge.
    private var tap: CFMachPort?
    private var scrollGeneration = 0

    private func setScrollBlock(_ mode: ScrollBlock) {
        scrollGeneration += 1
        scrollBlock = mode
        updateTap()
    }

    /// After control macOS keeps sending "momentum" scroll for ~0.5 s once the fingers lift:
    /// that is blocked too. A touch that never started control is released at once.
    private func releaseScroll(afterControl: Bool) {
        guard scrollBlock != .none else { return }
        guard afterControl else { setScrollBlock(.none); return }
        let generation = scrollGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.scrollGeneration == generation, !self.gesture.isActive || self.gesture.phase == .ignored else { return }
            self.setScrollBlock(.none)
        }
    }

    private func updateTap() {
        let need = scrollBlock != .none
        if need, tap == nil { installTap() }
        if let tap { CGEvent.tapEnable(tap: tap, enable: need) }
    }

    private func installTap() {
        // Scroll (22) and trackpad gestures: gesture 29, magnify 30, swipe 31
        var mask = CGEventMask(0)
        for raw: UInt32 in [CGEventType.scrollWheel.rawValue, 29, 30, 31] { mask |= CGEventMask(1) << raw }
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: scrollTapCallback, userInfo: nil) else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        tap = port
        scrollTap = port
    }
}

// MARK: - Scroll tap (runs on the main run loop)

nonisolated enum ScrollBlock: Sendable { case none, horizontal, all }

nonisolated(unsafe) private var scrollBlock = ScrollBlock.none
nonisolated(unsafe) private var scrollTap: CFMachPort?

/// What the tap does with one event. Pure, so it can be tested.
nonisolated func scrollTapDrops(type: UInt32, mode: ScrollBlock, deltaX: Double, deltaY: Double) -> Bool {
    let isScroll = type == CGEventType.scrollWheel.rawValue
    switch mode {
    case .none: return false
    case .all: return isScroll || (29...31).contains(type)
    case .horizontal: return isScroll && abs(deltaX) > abs(deltaY)
    }
}

private let scrollTapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if scrollBlock != .none, let scrollTap { CGEvent.tapEnable(tap: scrollTap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    let dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
    let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
    if scrollTapDrops(type: type.rawValue, mode: scrollBlock, deltaX: dx, deltaY: dy) { return nil }
    return Unmanaged.passUnretained(event)
}

// MARK: - MultitouchSupport (private framework, loaded with dlopen)

private typealias MTCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

/// Written by the main thread: an edge touch is being followed, or ignored until it lifts.
nonisolated(unsafe) var edgeActive = false
/// Sensor thread only: frames received (shown by the debug log).
nonisolated(unsafe) var rawFrameCount = 0
/// Debug log only: the last pair of fingers the pre-check turned down (x0, x1, outside0, outside1).
nonisolated(unsafe) var lastRejectedPair: (Float, Float, Bool, Bool, Int) = (0, 0, false, false, 0)
/// Sensor thread only: fingers that touched down away from the edges.
nonisolated(unsafe) private var outsideIDs = Set<Int32>()

/// Called on the framework's own thread. Fingers are copied and handed to the main thread.
private let contactCallback: MTCallback = { _, touches, count, _, _ in
    rawFrameCount &+= 1
    guard let touches, count > 0 else {
        outsideIDs.removeAll(keepingCapacity: true)
        if edgeActive { FrameMailbox.shared.post([]) }
        return 0
    }
    // Cheap pre-check on the sensor thread, without allocating: unless a touch is being followed,
    // a frame reaches the app only when two fingers *touched down* at an edge.
    if !edgeActive {
        var eligible = false
        func id(_ i: Int) -> Int32 { touches.advanced(by: i * 96).load(fromByteOffset: 16, as: Int32.self) }
        func x(_ i: Int) -> Float { touches.advanced(by: i * 96).load(fromByteOffset: 32, as: Float.self) }
        if count == 1 {
            // One finger at the edge: waiting for the second; one that started inside is remembered
            if x(0) > 0.05 && x(0) < 0.95 { outsideIDs.insert(id(0)) }
        } else if count == 2 {
            let lo = min(x(0), x(1)), hi = max(x(0), x(1))
            if !outsideIDs.contains(id(0)), !outsideIDs.contains(id(1)),
               (hi >= 0.95 && lo >= 0.8) || (lo <= 0.05 && hi <= 0.2) {
                eligible = true
            } else {
                if !(outsideIDs.contains(id(0)) && outsideIDs.contains(id(1))) {
                    lastRejectedPair = (x(0), x(1), outsideIDs.contains(id(0)), outsideIDs.contains(id(1)), lastRejectedPair.4 + 1)
                }
                outsideIDs.insert(id(0)); outsideIDs.insert(id(1))
            }
        } else {
            for i in 0..<Int(count) { outsideIDs.insert(id(i)) }
        }
        guard eligible else { return 0 }
    }
    var contacts: [EdgeGesture.Contact] = []
    contacts.reserveCapacity(Int(count))
    for i in 0..<Int(count) {
        // MTTouch: 96 bytes; identifier @16, state @20, normalized position @32, size @48
        let base = touches.advanced(by: i * 96)
        contacts.append(.init(id: base.load(fromByteOffset: 16, as: Int32.self),
                              state: base.load(fromByteOffset: 20, as: Int32.self),
                              x: base.load(fromByteOffset: 32, as: Float.self),
                              y: base.load(fromByteOffset: 36, as: Float.self),
                              size: base.load(fromByteOffset: 48, as: Float.self)))
    }
    FrameMailbox.shared.post(contacts)
    return 0
}

/// Frames never queue up: if the main thread is busy, an older frame is replaced by the newer one
/// and only one hand-off is pending at a time, so the delay can never grow.
nonisolated private final class FrameMailbox: @unchecked Sendable {
    static let shared = FrameMailbox()
    private let lock = NSLock()
    private var latest: [EdgeGesture.Contact]?
    private var scheduled = false

    nonisolated func post(_ contacts: [EdgeGesture.Contact]) {
        lock.lock()
        // A "fingers lifted" (empty) frame must not be lost by being replaced
        if !(latest?.isEmpty ?? false) || contacts.isEmpty { latest = contacts }
        let needSchedule = !scheduled
        scheduled = true
        lock.unlock()
        guard needSchedule else { return }
        DispatchQueue.main.async { self.drain() }
    }

    nonisolated private func drain() {
        lock.lock()
        let contacts = latest
        latest = nil
        scheduled = false
        lock.unlock()
        guard let contacts else { return }
        MainActor.assumeIsolated { TrackpadEdgeControl.shared.frame(contacts) }
    }
}

/// Writing the volume to CoreAudio takes ~9 ms, so it happens on its own queue and only the
/// newest value is written (the ones in between are dropped).
nonisolated final class VolumeWriter: @unchecked Sendable {
    static let shared = VolumeWriter()
    private let queue = DispatchQueue(label: "trackpadedge.trackpad.volume", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: Float?
    private var scheduled = false
    private var device = AudioDeviceID(0)
    private var unmuteFirst = false
    private var lastWrite = Date.distantPast
    /// At most ~30 writes a second (each one costs coreaudiod ~9 ms)
    private let minInterval: TimeInterval = 1.0 / 30

    /// At the start of each control: the current output device and its mute state
    nonisolated func prepare(unmute: Bool) {
        queue.async {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                  mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var id = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
            self.device = id
            self.unmuteFirst = unmute
        }
    }

    nonisolated func write(_ value: Float) {
        lock.lock()
        pending = value
        let needSchedule = !scheduled
        scheduled = true
        lock.unlock()
        guard needSchedule else { return }
        queue.async { self.drain() }
    }

    nonisolated private func drain() {
        while true {
            lock.lock()
            guard let value = pending else { scheduled = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            guard device != 0 else { continue }
            let wait = minInterval - Date().timeIntervalSince(lastWrite)
            if wait > 0 {
                // A newer value that arrives while waiting replaces this one
                usleep(useconds_t(wait * 1_000_000))
                lock.lock(); let newer = pending; pending = nil; lock.unlock()
                if let newer { lock.lock(); pending = newer; lock.unlock(); continue }
            }
            lastWrite = Date()
            var addr = AudioObjectPropertyAddress(mSelector: 0x766D_7663, mScope: kAudioDevicePropertyScopeOutput,
                                                  mElement: kAudioObjectPropertyElementMain)
            var v = Float32(value)
            AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
            if unmuteFirst && value > 0 {
                unmuteFirst = false
                var mute = AudioObjectPropertyAddress(mSelector: 0x6D75_7465, mScope: kAudioDevicePropertyScopeOutput,
                                                      mElement: kAudioObjectPropertyElementMain)
                var zero: UInt32 = 0
                AudioObjectSetPropertyData(device, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &zero)
            }
        }
    }
}

@MainActor
private final class MT {
    static let shared = MT()

    private typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, MTCallback) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void
    private typealias Dimensions = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

    private let createList: CreateList?
    private let registerFn: Register?
    private let unregisterFn: Register?
    private let startFn: StartFn?
    private let stopFn: StopFn?
    private let dimensions: Dimensions?
    private var keep: [AnyObject] = []

    private init() {
        let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        func sym<T>(_ name: String, _ type: T.Type) -> T? { dlsym(h, name).map { unsafeBitCast($0, to: type) } }
        createList = sym("MTDeviceCreateList", CreateList.self)
        registerFn = sym("MTRegisterContactFrameCallback", Register.self)
        unregisterFn = sym("MTUnregisterContactFrameCallback", Register.self)
        startFn = sym("MTDeviceStart", StartFn.self)
        stopFn = sym("MTDeviceStop", StopFn.self)
        dimensions = sym("MTDeviceGetSensorSurfaceDimensions", Dimensions.self)
    }

    var isAvailable: Bool { createList != nil && registerFn != nil && startFn != nil && dimensions != nil }

    /// Trackpads only: the Touch Bar (~8 mm tall) and other thin sensors are skipped
    func trackpads() -> [UnsafeMutableRawPointer] {
        guard let list = createList?()?.takeRetainedValue() as? [AnyObject] else { return [] }
        keep = list    // the devices live as long as the list does
        return list.map { Unmanaged.passUnretained($0).toOpaque() }.filter { surfaceMM($0).h >= 30 }
    }

    func surfaceMM(_ device: UnsafeMutableRawPointer) -> (w: Float, h: Float) {
        var w: Int32 = 0, h: Int32 = 0
        _ = dimensions?(device, &w, &h)
        return (Float(w) / 100, Float(h) / 100)
    }

    func register(_ device: UnsafeMutableRawPointer) {
        registerFn?(device, contactCallback)
        startFn?(device, 0)
    }

    func unregister(_ device: UnsafeMutableRawPointer) {
        unregisterFn?(device, contactCallback)
        stopFn?(device)
    }
}
