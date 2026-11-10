import Foundation
import Observation

/// Every setting, saved in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings(defaults: Demo.isOn ? Demo.defaults : .standard)

    /// Volume and brightness from the trackpad edges.
    var enabled: Bool { didSet { save(enabled, Keys.enabled); onEnabled?(enabled) } }
    /// Off: right edge = volume, left edge = brightness. On: the other way round.
    var swapEdges: Bool { didSet { save(swapEdges, Keys.swapEdges) } }
    /// The indicator design, 1…10 (5 = "Edge column").
    var hudVariant: Int { didSet { save(hudVariant, Keys.hudVariant) } }

    @ObservationIgnored var onEnabled: ((Bool) -> Void)?
    @ObservationIgnored private let defaults: SettingsStore

    enum Keys {
        static let enabled = "enabled"
        static let swapEdges = "swapEdges"
        static let hudVariant = "hudVariant"
    }

    init(defaults: SettingsStore = UserDefaults.standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        swapEdges = defaults.object(forKey: Keys.swapEdges) as? Bool ?? false
        hudVariant = HUDVariant.clamp(defaults.object(forKey: Keys.hudVariant) as? Int ?? HUDVariant.defaultVariant)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}

/// Where settings live: UserDefaults in the app, a plain dictionary in tests (nothing on disk).
protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}
