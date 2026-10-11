import AppKit
import XCTest
@testable import EdgeAppSwitcher

@MainActor final class AppCoordinatorTests: XCTestCase {
    func testPairHistoryTracksObservedExternalActivation() {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let a = rawApp(42, url: "/A.app"); let b = rawApp(43, url: "/B.app"); let c = rawApp(44, url: "/C.app")
        let store = RunningAppStore(); store.replace([a, b, c])
        let pair = PairStore(defaults: defaults)
        let aid = AppID.bundleURL(URL(fileURLWithPath: "/A.app")); let bid = AppID.bundleURL(URL(fileURLWithPath: "/B.app"))
        pair.register(a: aid, b: bid, records: store.records, frontmost: nil)
        let controller = BarController(store: store, recency: RecencyStore(), activation: ActivationService(backend: FakeActivationBackend()), presentation: FakeBarPresentation(), pairStore: pair, frontmost: { nil })
        let source = WorkspaceAppSource(onAppsChanged: { store.replace($0) }, onFrontmostChanged: { controller.observeFrontmost($0) })
        source.deliverActivation(a); XCTAssertEqual(pair.lastUsed, aid)
        source.deliverActivation(b); XCTAssertEqual(pair.lastUsed, bid)
        source.deliverActivation(c); source.deliverActivation(rawApp(99, selfApp: true)); controller.observeFrontmost(nil)
        XCTAssertEqual(pair.lastUsed, bid)
        store.replace([a]); controller.refresh()
        XCTAssertEqual(pair.lastUsed, bid)
    }
    func testStartStopAreIdempotentAndNotificationsUseCorrectCenters() {
        withFixture { coordinator, sampler, _, _, workspace, application, actions in
            coordinator.start(); coordinator.start()
            XCTAssertEqual(sampler.startCount, 1); XCTAssertEqual(actions.starts, 1)
            application.post(name: NSWorkspace.willSleepNotification, object: nil)
            XCTAssertEqual(sampler.stopCount, 0)
            workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
            XCTAssertEqual(sampler.stopCount, 1)
            coordinator.stop(); coordinator.stop()
            XCTAssertEqual(actions.stops, 1)
            workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            XCTAssertEqual(sampler.startCount, 1)
            coordinator.start(); XCTAssertEqual(sampler.startCount, 2)
            coordinator.stop()
        }
    }
    func testResumeRequiresExitAndRefreshesFrontmost() {
        withFixture { coordinator, sampler, controller, _, workspace, _, actions in
            coordinator.start(); sampler.emit(20, 0); sampler.emit(0, 100); sampler.emit(0, 400)
            XCTAssertTrue(controller.isVisible); XCTAssertFalse(controller.keyboardMode)
            workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
            XCTAssertFalse(controller.isVisible)
            let before = actions.refreshes
            workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            XCTAssertEqual(actions.refreshes, before + 1)
            sampler.emit(0, 500); sampler.emit(0, 800); XCTAssertFalse(controller.isVisible)
            sampler.emit(20, 900); sampler.emit(0, 1000); sampler.emit(0, 1300)
            XCTAssertTrue(controller.isVisible)
            coordinator.stop()
        }
    }
    func testExplicitShowPauseEmptyFrameTooltipAndHideReset() {
        withFixture { coordinator, sampler, controller, settings, _, application, actions in
            coordinator.start(); coordinator.showExplicitly()
            XCTAssertTrue(controller.keyboardMode); XCTAssertEqual(actions.focuses, 1)
            XCTAssertEqual(controller.frame.height, 72)
            controller.hide(); sampler.emit(0, 0); sampler.emit(0, 300)
            XCTAssertFalse(controller.isVisible)
            sampler.emit(20, 400); sampler.emit(0, 500); sampler.emit(0, 800)
            actions.tooltip = CGRect(x: 90, y: 380, width: 100, height: 40)
            sampler.emit(100, 900); sampler.emit(100, 1200); XCTAssertTrue(controller.isVisible)
            application.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            XCTAssertFalse(controller.isVisible)
            settings.isPaused = true; coordinator.settingsChanged(); coordinator.showExplicitly()
            XCTAssertFalse(controller.isVisible); XCTAssertEqual(actions.focuses, 1)
            coordinator.stop()
        }
    }
    func testExternalActivationDismissesKeyboardBarAndRequiresExit() {
        withFixture { coordinator, sampler, controller, _, _, _, actions in
            coordinator.start(); coordinator.showExplicitly()
            sampler.emit(900, 0); sampler.emit(900, 400)
            XCTAssertTrue(controller.isVisible)
            actions.activation?(InstanceToken(pid: 42, launchDate: nil))
            XCTAssertFalse(controller.isVisible)
            sampler.emit(0, 0); sampler.emit(0, 300)
            XCTAssertFalse(controller.isVisible)
            coordinator.stop()
        }
    }
    func testExternalActivationKeepsPointerSnapshotVisible() {
        withFixture { coordinator, sampler, controller, _, _, _, actions in
            coordinator.start(); sampler.emit(20, 0); sampler.emit(0, 100); sampler.emit(0, 400)
            let ids = controller.model.rows.map(\.id)
            actions.activation?(InstanceToken(pid: 42, launchDate: nil))
            XCTAssertTrue(controller.isVisible); XCTAssertEqual(controller.model.rows.map(\.id), ids)
            coordinator.stop()
        }
    }
    func testExplicitShowFallsBackToPrimaryAndNoScreensDoesNothing() {
        withFixture { coordinator, _, controller, _, _, _, actions in
            coordinator.start()
            actions.pointer = CGPoint(x: 9000, y: 9000)
            coordinator.showExplicitly()
            XCTAssertTrue(controller.isVisible); XCTAssertTrue(controller.keyboardMode)
            XCTAssertEqual(controller.frame, ScreenGeometry.panelFrame(screen: actions.screens[0], side: .left, itemCount: 1))
            controller.hide(); actions.screens = []
            coordinator.showExplicitly()
            XCTAssertFalse(controller.isVisible); XCTAssertEqual(actions.focuses, 1)
            coordinator.stop()
        }
    }
    func testObsoleteActivationCallbackCannotDismissRestartedBar() {
        withFixture { coordinator, _, controller, _, _, _, actions in
            coordinator.start(); let old = actions.activation
            coordinator.stop(); old?(InstanceToken(pid: 42, launchDate: nil))
            coordinator.start(); coordinator.showExplicitly()
            old?(InstanceToken(pid: 42, launchDate: nil))
            XCTAssertTrue(controller.isVisible)
            actions.activation?(InstanceToken(pid: 42, launchDate: nil))
            XCTAssertFalse(controller.isVisible)
            coordinator.stop()
        }
    }
    func testActivationDuringSelectionPreservesMatchingConfirmationOnly() async {
        for keyboard in [false, true] {
            for matching in [false, true] {
                let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
                defer { defaults.removePersistentDomain(forName: name) }
                let store = RunningAppStore(); store.replace([rawApp(42, bundle: "a")])
                let backend = FakeActivationBackend(); backend.liveToken = store.records[0].instances[0].token; backend.suspend = true
                let controller = BarController(store: store, recency: RecencyStore(), activation: ActivationService(backend: backend), presentation: FakeBarPresentation(), isSelfFrontmost: { false }, frontmost: { nil })
                let screen = ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), isPrimary: true)
                let sampler = FakePointerSampler(); var activation: ((InstanceToken) -> Void)?
                let coordinator = AppCoordinator(settings: SettingsStore(defaults: defaults), sampler: sampler, controller: controller, screens: { [screen] }, pointer: { CGPoint(x: 20, y: 400) }, tooltipFrame: { nil }, startSources: {}, stopSources: {}, refreshSources: {}, focusFirst: {}, observeActivation: { activation = $0 }, workspaceCenter: NotificationCenter(), applicationCenter: NotificationCenter())
                coordinator.start()
                if keyboard { coordinator.showExplicitly() }
                else { sampler.emit(20, 0); sampler.emit(0, 100); sampler.emit(0, 400) }
                let task = Task { await controller.select(store.records[0].id) }
                for _ in 0..<100 where backend.continuation == nil { await Task.yield() }
                guard let continuation = backend.continuation else {
                    backend.suspend = false; task.cancel(); await task.value; coordinator.stop()
                    XCTFail("Selection did not reach confirmation wait"); continue
                }
                activation?(matching ? backend.liveToken : InstanceToken(pid: 99, launchDate: nil))
                XCTAssertEqual(controller.isVisible, !keyboard || matching)
                XCTAssertEqual(controller.isSelecting, !keyboard || matching)
                continuation.resume(returning: true); backend.continuation = nil
                await task.value
                XCTAssertFalse(controller.isVisible)
                coordinator.stop()
            }
        }
    }
    final class Actions { var starts = 0; var stops = 0; var refreshes = 0; var focuses = 0; var tooltip: CGRect?; var pointer = CGPoint(x: 20, y: 400); var screens: [ScreenDescriptor] = []; var activation: ((InstanceToken) -> Void)? }
    func withFixture(_ body: (AppCoordinator, FakePointerSampler, BarController, SettingsStore, NotificationCenter, NotificationCenter, Actions) -> Void) {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults); let sampler = FakePointerSampler()
        let controller = BarController(store: RunningAppStore(), recency: RecencyStore(), activation: ActivationService(backend: FakeActivationBackend()), presentation: FakeBarPresentation(), frontmost: { nil })
        let screen = ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), isPrimary: true)
        let workspace = NotificationCenter(); let application = NotificationCenter(); let actions = Actions(); actions.screens = [screen]
        let coordinator = AppCoordinator(settings: settings, sampler: sampler, controller: controller, screens: { actions.screens }, pointer: { actions.pointer }, tooltipFrame: { actions.tooltip }, startSources: { actions.starts += 1 }, stopSources: { actions.stops += 1 }, refreshSources: { actions.refreshes += 1 }, focusFirst: { actions.focuses += 1 }, observeActivation: { actions.activation = $0 }, workspaceCenter: workspace, applicationCenter: application)
        body(coordinator, sampler, controller, settings, workspace, application, actions)
    }
}
