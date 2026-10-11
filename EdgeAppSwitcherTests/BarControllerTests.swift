import AppKit
import XCTest
@testable import EdgeAppSwitcher

@MainActor final class FakeBarPresentation: BarPresentation {
    var pairDestination: PairDestination?
    var pairSelected = false
    func updatePair(_ destination: PairDestination?) { pairDestination = destination }
    func setPairSelected(_ selected: Bool) { pairSelected = selected }
    var presentations = 0
    var dismissals = 0
    var messages: [String] = []
    var rows: [BarRow] = []
    var selectedID: AppID?
    var selections: [AppID?] = []
    func setSelected(_ id: AppID?) { selectedID = id; selections.append(id) }
    func present(rows: [BarRow], frame: CGRect, keyboardMode: Bool) { presentations += 1; self.rows = rows }
    func update(rows: [BarRow]) { self.rows = rows }
    func showMessage(_ text: String) { messages.append(text) }
    func dismiss() { dismissals += 1 }
}

@MainActor final class BarControllerTests: XCTestCase {
    let screen = ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 780), isPrimary: true)
    func withPair(_ body: (BarController, RunningAppStore, RecencyStore, PairStore, FakeActivationBackend, FakeBarPresentation, AppID, AppID) async -> Void) async {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RunningAppStore(); store.replace([rawApp(42, url: "/A.app"), rawApp(43, url: "/B.app"), rawApp(44, url: "/B.app")])
        let a = AppID.bundleURL(URL(fileURLWithPath: "/A.app")); let b = AppID.bundleURL(URL(fileURLWithPath: "/B.app"))
        let pair = PairStore(defaults: defaults); XCTAssertTrue(pair.register(a: a, b: b, records: store.records, frontmost: a))
        let recency = RecencyStore(); recency.recordActivation(rawApp(44, url: "/B.app").instance.token, records: store.records)
        let backend = FakeActivationBackend(); backend.liveToken = rawApp(44, url: "/B.app").instance.token
        let presentation = FakeBarPresentation()
        let controller = BarController(store: store, recency: recency, activation: ActivationService(backend: backend), presentation: presentation, pairStore: pair, frontmost: { rawApp(42, url: "/A.app").instance })
        controller.show(screen: screen, side: .left, keyboardMode: false)
        await body(controller, store, recency, pair, backend, presentation, a, b)
    }
    func testPairSelectUsesPreferredLiveInstance() async {
        await withPair { controller, _, _, pair, backend, presentation, a, b in
            XCTAssertEqual(presentation.pairDestination?.id, b)
            backend.confirmation = true
            await controller.selectPair(displayed: b)
            XCTAssertEqual(backend.requestCount, 1)
            XCTAssertEqual(backend.waitedTarget?.token.pid, 44)
            XCTAssertEqual(presentation.dismissals, 1)
            XCTAssertEqual(pair.lastUsed, a)
        }
    }
    func testMissingOrChangedPairDoesNotRequest() async {
        for change in 0..<4 {
            await withPair { controller, store, _, pair, backend, presentation, a, b in
                if change == 0 { store.replace([]) }
                if change == 1 { pair.clear() }
                if change == 3 { pair.register(a: b, b: a, records: store.records, frontmost: a) }
                await controller.selectPair(displayed: change == 2 ? a : b)
                XCTAssertEqual(backend.requestCount, 0)
                XCTAssertEqual(presentation.messages.last, "切り替えできませんでした")
            }
        }
    }
    func testPairFailureKeepsBarAndHistory() async {
        await withPair { controller, _, _, pair, backend, presentation, a, b in
            for accepted in [false, true] {
                backend.accepted = accepted
                await controller.selectPair(displayed: b)
                XCTAssertTrue(controller.isVisible)
                XCTAssertFalse(presentation.pairSelected)
                XCTAssertEqual(pair.lastUsed, a)
            }
            XCTAssertEqual(presentation.dismissals, 0)
        }
    }
    func testPairSelectionLateResultCannotCloseReopenedBar() async {
        await withPair { controller, _, _, _, backend, presentation, _, b in
            backend.suspend = true
            let task = Task { await controller.selectPair(displayed: b) }
            for _ in 0..<100 where backend.continuation == nil { await Task.yield() }
            guard let continuation = backend.continuation else { XCTFail("Pair did not request"); return }
            XCTAssertTrue(presentation.pairSelected)
            await controller.selectPair(displayed: b)
            XCTAssertEqual(backend.requestCount, 1)
            controller.hide(); controller.show(screen: self.screen, side: .left, keyboardMode: false)
            continuation.resume(returning: true); backend.continuation = nil
            await task.value
            XCTAssertTrue(controller.isVisible)
            XCTAssertFalse(presentation.pairSelected)
            XCTAssertEqual(presentation.dismissals, 1)
        }
    }
    func testKeyboardPairUsesOriginalExternalFrontmost() async {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RunningAppStore(); let a = rawApp(42, url: "/A.app"); let b = rawApp(43, url: "/B.app")
        store.replace([a, b]); let pair = PairStore(defaults: defaults)
        pair.register(a: store.records[0].id, b: store.records[1].id, records: store.records, frontmost: nil)
        pair.observe(.bundleURL(URL(fileURLWithPath: "/A.app")))
        var current: AppInstance? = a.instance
        let presentation = FakeBarPresentation(); let backend = FakeActivationBackend()
        let controller = BarController(store: store, recency: RecencyStore(), activation: ActivationService(backend: backend), presentation: presentation, pairStore: pair, frontmost: { current })
        controller.show(screen: screen, side: .left, keyboardMode: true)
        current = nil; controller.refresh()
        XCTAssertEqual(presentation.pairDestination?.id, .bundleURL(URL(fileURLWithPath: "/B.app")))
    }
    func fixture() -> (BarController, RunningAppStore, FakeActivationBackend, FakeBarPresentation) {
        let store = RunningAppStore()
        store.replace([rawApp(42, bundle: "a")])
        let backend = FakeActivationBackend()
        let presentation = FakeBarPresentation()
        let controller = BarController(store: store, recency: RecencyStore(), activation: ActivationService(backend: backend), presentation: presentation, frontmost: { nil })
        controller.show(screen: screen, side: .left, keyboardMode: false)
        return (controller, store, backend, presentation)
    }
    func testSelectionFeedbackDoesNotDelayRequestAndResetsForRetry() async {
        for keyboard in [false, true] {
            let (controller, store, backend, presentation) = fixture()
            controller.show(screen: screen, side: .right, keyboardMode: keyboard)
            backend.suspend = true
            let id = store.records[0].id
            let selection = Task { await controller.select(id) }
            for _ in 0..<100 where backend.continuation == nil { await Task.yield() }
            guard let continuation = backend.continuation else {
                backend.suspend = false
                selection.cancel()
                await selection.value
                XCTFail("Selection did not reach confirmation wait")
                return
            }
            XCTAssertEqual(backend.requestCount, 1, "Request must run without a feedback delay")
            XCTAssertEqual(presentation.selectedID, id)
            continuation.resume(returning: false); backend.continuation = nil
            await selection.value
            XCTAssertNil(presentation.selectedID)
            XCTAssertEqual(presentation.messages.last, "OSが切替を完了しませんでした")
            backend.suspend = false; backend.accepted = false
            await controller.select(id)
            XCTAssertEqual(backend.requestCount, 2)
            XCTAssertNil(presentation.selectedID)
            XCTAssertEqual(presentation.messages.last, "切り替えできませんでした")
        }
    }
    func testReopenClearsFeedbackAndLateSelectionCannotPressOrDismissIt() async {
        let (controller, store, backend, presentation) = fixture()
        backend.suspend = true
        let selection = Task { await controller.select(store.records[0].id) }
        for _ in 0..<100 where backend.continuation == nil { await Task.yield() }
        guard let continuation = backend.continuation else {
            backend.suspend = false
            selection.cancel()
            await selection.value
            XCTFail("Selection did not reach confirmation wait")
            return
        }
        XCTAssertNotNil(presentation.selectedID)
        controller.hide()
        XCTAssertNil(presentation.selectedID)
        controller.show(screen: screen, side: .right, keyboardMode: true)
        XCTAssertNil(presentation.selectedID)
        continuation.resume(returning: true); backend.continuation = nil
        await selection.value
        XCTAssertNil(presentation.selectedID)
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(presentation.dismissals, 1)
    }
    func testSelectionYieldsOnlyWhenActuallyFrontmost() async {
        for mode in [false, true] {
            for selfFrontmost in [false, true] {
                let store = RunningAppStore(); store.replace([rawApp(42, bundle: "a")])
                let backend = FakeActivationBackend(); backend.confirmation = true
                let controller = BarController(store: store, recency: RecencyStore(),
                    activation: ActivationService(backend: backend), presentation: FakeBarPresentation(),
                    isSelfFrontmost: { selfFrontmost }, frontmost: { nil })
                controller.show(screen: screen, side: .left, keyboardMode: mode)
                await controller.select(store.records[0].id)
                XCTAssertEqual(backend.events.contains("yield"), selfFrontmost)
            }
        }
    }
    func testEscapeYieldsOnlyWhenActuallyFrontmostAndSkipsDeadOriginal() async {
        for selfFrontmost in [false, true] {
            for alive in [false, true] {
                let backend = FakeActivationBackend(); backend.originalAlive = alive
                let original = rawApp(42, bundle: "original").instance
                let controller = BarController(store: RunningAppStore(), recency: RecencyStore(),
                    activation: ActivationService(backend: backend), presentation: FakeBarPresentation(),
                    isSelfFrontmost: { selfFrontmost }, frontmost: { original })
                controller.show(screen: screen, side: .left, keyboardMode: true)
                controller.hide(returnFocus: true)
                for _ in 0..<100 { await Task.yield() }
                XCTAssertEqual(backend.events.contains("yield"), selfFrontmost && alive)
                XCTAssertEqual(backend.requestCount, alive ? 1 : 0)
            }
        }
    }
    func testFailedSelectionRetainsBarAndShowsMessage() async {
        let (controller, store, backend, presentation) = fixture()
        backend.accepted = false
        await controller.select(store.records[0].id)
        XCTAssertEqual(presentation.messages.last, "切り替えできませんでした")
        backend.accepted = true
        await controller.select(store.records[0].id)
        XCTAssertEqual(presentation.messages.last, "OSが切替を完了しませんでした")
        XCTAssertEqual(presentation.dismissals, 0)
        XCTAssertTrue(controller.isVisible)
    }
    func testOnlyConfirmedSelectionHides() async {
        let (controller, store, backend, presentation) = fixture()
        backend.confirmation = true
        await controller.select(store.records[0].id)
        XCTAssertEqual(presentation.dismissals, 1)
        XCTAssertFalse(controller.isVisible)
    }
    func testHideIgnoresLateSelection() async {
        let (controller, store, backend, presentation) = fixture()
        backend.suspend = true
        let id = store.records[0].id
        let selection = Task { await controller.select(id) }
        for _ in 0..<100 where backend.continuation == nil { await Task.yield() }
        guard let continuation = backend.continuation else {
            backend.suspend = false
            selection.cancel()
            await selection.value
            XCTFail("Selection did not suspend")
            return
        }
        await controller.select(id)
        XCTAssertEqual(backend.requestCount, 1)
        controller.hide()
        controller.show(screen: screen, side: .left, keyboardMode: false)
        continuation.resume(returning: true)
        backend.continuation = nil
        await selection.value
        XCTAssertEqual(presentation.presentations, 2)
        XCTAssertEqual(presentation.dismissals, 1)
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(presentation.messages.isEmpty)
    }
    func testSelectionResolvesCurrentInstanceAtClickTime() async {
        let (controller, store, backend, _) = fixture()
        store.replace([rawApp(42, bundle: "a"), rawApp(43, bundle: "a")])
        controller.hide()
        controller.show(screen: screen, side: .left, keyboardMode: false)
        let id = store.records[0].id
        store.replace([rawApp(43, bundle: "a")])
        backend.liveToken = store.records[0].instances[0].token
        await controller.select(id)
        XCTAssertEqual(backend.waitedTarget?.token, backend.liveToken)
    }
    func testEscapeRestoresRetainedOriginalInstance() async {
        let store = RunningAppStore()
        let original = rawApp(42, bundle: "original").instance
        var current: AppInstance? = original
        let backend = FakeActivationBackend()
        let presentation = FakeBarPresentation()
        let controller = BarController(store: store, recency: RecencyStore(), activation: ActivationService(backend: backend), presentation: presentation, isSelfFrontmost: { true }, frontmost: { current })
        controller.show(screen: screen, side: .left, keyboardMode: true)
        current = rawApp(99, bundle: "other").instance
        controller.hide(returnFocus: true)
        for _ in 0..<100 where backend.waitedTarget == nil { await Task.yield() }
        XCTAssertEqual(backend.waitedTarget?.token, original.token)
        XCTAssertTrue(backend.events.contains("yield"))
    }
    func testReopenCancelsPendingFocusRestoration() async {
        let store = RunningAppStore()
        let backend = FakeActivationBackend()
        let controller = BarController(store: store, recency: RecencyStore(), activation: ActivationService(backend: backend), presentation: FakeBarPresentation(), frontmost: { rawApp(42).instance })
        controller.show(screen: screen, side: .left, keyboardMode: true)
        controller.hide(returnFocus: true)
        controller.show(screen: screen, side: .left, keyboardMode: false)
        await Task.yield()
        XCTAssertEqual(backend.requestCount, 0)
    }
    func testRestartAtClickTimeCannotActivateEndedRow() async {
        let (controller, store, backend, presentation) = fixture()
        let id = store.records[0].id
        store.replace([rawApp(42, date: 2, bundle: "a")])
        backend.liveToken = store.records[0].instances[0].token
        await controller.select(id)
        XCTAssertEqual(backend.requestCount, 0)
        XCTAssertFalse(presentation.rows[0].isEnabled)
        XCTAssertEqual(presentation.messages.last, "切り替えできませんでした")
    }
    func testOverlappingInstanceSurvivorCanBeSelectedWithoutReopening() async {
        let (controller, store, backend, presentation) = fixture()
        let id = store.records[0].id
        store.replace([rawApp(42, bundle: "a"), rawApp(43, bundle: "a")])
        controller.refresh()
        store.replace([rawApp(43, bundle: "a")])
        controller.refresh()
        backend.liveToken = store.records[0].instances[0].token
        backend.confirmation = true
        await controller.select(id)
        XCTAssertEqual(backend.requestCount, 1)
        XCTAssertEqual(backend.waitedTarget?.token, backend.liveToken)
        XCTAssertEqual(presentation.presentations, 1)
        XCTAssertEqual(presentation.dismissals, 1)
        XCTAssertTrue(presentation.messages.isEmpty)
    }
    func testTrueRestartCannotReviveAfterLaterOverlap() async {
        let (controller, store, backend, presentation) = fixture()
        let id = store.records[0].id
        store.replace([rawApp(43, bundle: "a")])
        controller.refresh()
        store.replace([rawApp(43, bundle: "a"), rawApp(44, bundle: "a")])
        controller.refresh()
        backend.liveToken = store.records[0].instances[0].token
        await controller.select(id)
        XCTAssertEqual(backend.requestCount, 0)
        XCTAssertFalse(presentation.rows[0].isEnabled)
        XCTAssertEqual(presentation.messages.last, "切り替えできませんでした")
        XCTAssertTrue(controller.isVisible)
    }
}
