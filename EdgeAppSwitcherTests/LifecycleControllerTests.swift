import XCTest
@testable import EdgeAppSwitcher

@MainActor final class FakePointerSampler: PointerSampler {
    var startCount = 0
    var stopCount = 0
    var interval: Duration?
    var tolerance: Duration?
    var handler: ((CGPoint, Int, Duration) -> Void)?
    func start(interval: Duration, tolerance: Duration, handler: @escaping (CGPoint, Int, Duration) -> Void) {
        startCount += 1; self.interval = interval; self.tolerance = tolerance; self.handler = handler
    }
    func stop() { stopCount += 1 }
    func emit(_ x: Double, _ time: Int) { handler?(CGPoint(x: x, y: 400), 0, .milliseconds(time)) }
}

@MainActor final class LifecycleControllerTests: XCTestCase {
    func testPauseSleepAndSessionStopSampling() {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults); let sampler = FakePointerSampler()
        let lifecycle = LifecycleController(settings: settings, sampler: sampler, closeAndReset: {}, refreshSources: {})
        lifecycle.start()
        XCTAssertEqual(sampler.interval, .milliseconds(100)); XCTAssertEqual(sampler.tolerance, .milliseconds(20))
        lifecycle.handle(.willSleep); lifecycle.handle(.screensSleep); lifecycle.handle(.sessionInactive)
        lifecycle.handle(.didWake); lifecycle.handle(.screensWake)
        XCTAssertFalse(lifecycle.canSample); XCTAssertEqual(sampler.startCount, 1)
        lifecycle.handle(.sessionActive)
        XCTAssertTrue(lifecycle.canSample); XCTAssertEqual(sampler.startCount, 2)
        settings.isPaused = true; lifecycle.handle(.settingsChanged)
        XCTAssertFalse(lifecycle.canSample); XCTAssertEqual(sampler.stopCount, 2)
    }
    func testWakeDoesNotOverrideUserPause() {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults); settings.isPaused = true
        let sampler = FakePointerSampler()
        let lifecycle = LifecycleController(settings: settings, sampler: sampler, closeAndReset: {}, refreshSources: {})
        lifecycle.start(); lifecycle.handle(.willSleep); lifecycle.handle(.didWake)
        XCTAssertFalse(lifecycle.canSample); XCTAssertEqual(sampler.startCount, 0)
    }
    func testScreenRemovalClosesBeforeRefreshingAndSpaceDoesNotRefresh() {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var events: [String] = []
        let lifecycle = LifecycleController(settings: SettingsStore(defaults: defaults), sampler: FakePointerSampler(), closeAndReset: { events.append("close") }, refreshSources: { events.append("refresh") })
        lifecycle.start(); events = []
        lifecycle.handle(.screensChanged); XCTAssertEqual(events, ["close", "refresh"])
        events = []; lifecycle.handle(.spaceChanged); XCTAssertEqual(events, ["close"])
    }
    func testStoppedGenerationRejectsOldCallbacksAfterRestart() {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let sampler = FakePointerSampler(); var ticks = 0
        let lifecycle = LifecycleController(settings: SettingsStore(defaults: defaults), sampler: sampler, closeAndReset: {}, refreshSources: {})
        lifecycle.onSample = { _, _, _ in ticks += 1 }
        lifecycle.start(); let old = sampler.handler
        lifecycle.stop(); lifecycle.start(); old?(.zero, 0, .zero)
        XCTAssertEqual(ticks, 0)
        sampler.emit(20, 100); XCTAssertEqual(ticks, 1)
        lifecycle.stop(); sampler.emit(20, 200); XCTAssertEqual(ticks, 1)
    }
}
