import Foundation
import Observation

@MainActor @Observable final class SettingsStore {
    private let defaults: UserDefaults
    var side: EdgeSide { didSet { defaults.set(side == .left ? "left" : "right", forKey: "edgeSide") } }
    var isPaused: Bool { didSet { defaults.set(isPaused, forKey: "isPaused") } }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        side = defaults.string(forKey: "edgeSide") == "right" ? .right : .left
        isPaused = defaults.bool(forKey: "isPaused")
    }
}
