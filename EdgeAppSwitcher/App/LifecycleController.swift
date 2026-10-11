import Foundation

enum LifecycleEvent {
    case willSleep, didWake, screensSleep, screensWake, sessionInactive, sessionActive
    case screensChanged, spaceChanged, settingsChanged, terminate
}

@MainActor final class LifecycleController {
    private let settings: SettingsStore
    private let sampler: any PointerSampler
    private let closeAndReset: () -> Void
    private let refreshSources: () -> Void
    private var started = false
    private var sleeping = false
    private var screensSleeping = false
    private var sessionInactive = false
    private var generation: UInt64 = 0
    private(set) var canSample = false
    // The brief's start signature needs a destination for samples; keep it explicit.
    var onSample: ((CGPoint, Int, Duration) -> Void)?

    init(settings: SettingsStore, sampler: any PointerSampler, closeAndReset: @escaping () -> Void, refreshSources: @escaping () -> Void) {
        self.settings = settings; self.sampler = sampler
        self.closeAndReset = closeAndReset; self.refreshSources = refreshSources
    }
    func start() {
        guard !started else { return }
        started = true
        sleeping = false; screensSleeping = false; sessionInactive = false
        closeAndReset()
        reconcile()
    }
    func stop() {
        guard started else { return }
        started = false
        closeAndReset()
        reconcile()
    }
    func handle(_ event: LifecycleEvent) {
        guard started else { return }
        closeAndReset()
        switch event {
        case .willSleep: sleeping = true
        case .didWake: sleeping = false
        case .screensSleep: screensSleeping = true
        case .screensWake: screensSleeping = false
        case .sessionInactive: sessionInactive = true
        case .sessionActive: sessionInactive = false
        case .screensChanged: refreshSources()
        case .spaceChanged, .settingsChanged: break
        case .terminate: stop(); return
        }
        reconcile()
    }
    private func reconcile() {
        let enabled = started && !settings.isPaused && !sleeping && !screensSleeping && !sessionInactive
        guard enabled != canSample else { return }
        generation &+= 1
        canSample = enabled
        if enabled {
            refreshSources()
            let current = generation
            sampler.start(interval: .milliseconds(100), tolerance: .milliseconds(20)) { [weak self] point, buttons, time in
                guard let self, self.canSample, self.generation == current else { return }
                self.onSample?(point, buttons, time)
            }
        } else {
            sampler.stop()
        }
    }
}
