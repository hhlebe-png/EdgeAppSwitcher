import AppKit
import XCTest
@testable import EdgeAppSwitcher

final class KeyboardNavigatorTests: XCTestCase {
    func testNavigationSkipsDisabledAndHandlesNoEnabledRows() {
        let first = AppID.bundleIdentifier("first"), last = AppID.bundleIdentifier("last")
        let disabled = BarRow(id: .bundleIdentifier("disabled"), name: "Disabled", icon: nil, isEnabled: false, isFrontmost: false)
        let rows = [BarRow(id: first, name: "First", icon: nil, isEnabled: true, isFrontmost: false), disabled,
                    BarRow(id: last, name: "Last", icon: nil, isEnabled: true, isFrontmost: false)]
        XCTAssertNil(KeyboardNavigator.move(.down, rows: [], current: nil))
        XCTAssertNil(KeyboardNavigator.move(.home, rows: [disabled], current: nil))
        XCTAssertEqual(KeyboardNavigator.move(.home, rows: rows, current: nil), first)
        XCTAssertEqual(KeyboardNavigator.move(.end, rows: rows, current: nil), last)
        XCTAssertEqual(KeyboardNavigator.move(.down, rows: rows, current: first), last)
        XCTAssertEqual(KeyboardNavigator.move(.down, rows: rows, current: last), last)
        XCTAssertEqual(KeyboardNavigator.move(.up, rows: rows, current: last), first)
        XCTAssertEqual(KeyboardNavigator.move(.up, rows: rows, current: first), first)
        XCTAssertEqual(KeyboardNavigator.move(.up, rows: rows, current: nil), last)
    }
    func testPairNavigationOrder() {
        let first = AppID.bundleIdentifier("first"), last = AppID.bundleIdentifier("last")
        let rows = [first, last].map { BarRow(id: $0, name: "App", icon: nil, isEnabled: true, isFrontmost: false) }
        XCTAssertEqual(KeyboardNavigator.move(.home, rows: rows, pairEnabled: true, current: nil), .pair)
        XCTAssertEqual(KeyboardNavigator.move(.down, rows: rows, pairEnabled: true, current: .pair), .app(first))
        XCTAssertEqual(KeyboardNavigator.move(.end, rows: rows, pairEnabled: true, current: nil), .app(last))
        XCTAssertEqual(KeyboardNavigator.move(.up, rows: rows, pairEnabled: true, current: .app(first)), .pair)
    }
    func testDisabledPairSkippedAndNoPairMatchesLegacy() {
        let id = AppID.bundleIdentifier("app")
        let rows = [BarRow(id: id, name: "App", icon: nil, isEnabled: true, isFrontmost: false)]
        for key in [NavigationKey.home, .end, .up, .down] {
            XCTAssertEqual(KeyboardNavigator.move(key, rows: rows, pairEnabled: false, current: nil),
                           KeyboardNavigator.move(key, rows: rows, current: nil).map(BarFocusTarget.app))
        }
        XCTAssertNil(KeyboardNavigator.move(.home, rows: [], pairEnabled: false, current: .pair))
    }
    @MainActor func testEnterPairUsesDisplayedDestinationAndEscapeRestoresExternalApp() async {
        let name = "KeyboardPairTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RunningAppStore()
        store.replace([rawApp(41, url: "/A.app"), rawApp(42, url: "/B.app")])
        let a = AppID.bundleURL(URL(fileURLWithPath: "/A.app"))
        let b = AppID.bundleURL(URL(fileURLWithPath: "/B.app"))
        let pair = PairStore(defaults: defaults)
        XCTAssertTrue(pair.register(a: a, b: b, records: store.records, frontmost: a))
        let original = store.resolve(a, preferred: nil)!
        var current: AppInstance? = original
        let backend = FakeActivationBackend()
        let presentation = FakeBarPresentation()
        let controller = BarController(store: store, recency: RecencyStore(), activation: ActivationService(backend: backend), presentation: presentation, pairStore: pair, isSelfFrontmost: { true }, frontmost: { current })
        let panel = BarPanel() // Never presented; all presentation goes to the fake.
        let handler = BarKeyboardHandler(panel: panel, controller: controller)
        defer { handler.stop(); controller.hide() }
        let screen = ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 780), isPrimary: true)
        func event(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        controller.show(screen: screen, side: .left, keyboardMode: true)
        current = rawApp(ProcessInfo.processInfo.processIdentifier, selfApp: true).instance
        controller.refresh()
        panel.viewState.pairDestination = presentation.pairDestination
        handler.focusFirst()
        XCTAssertEqual(panel.viewState.focusedTarget, .pair)
        XCTAssertEqual(panel.viewState.pairDestination?.id, b)
        XCTAssertEqual(panel.onKeyDown?(event(36)), true)
        for _ in 0..<100 where backend.waitedTarget == nil { await Task.yield() }
        XCTAssertEqual(backend.waitedTarget?.bundleURL, URL(fileURLWithPath: "/B.app"))
        controller.hide()
        current = original
        backend.waitedTarget = nil; backend.liveToken = original.token
        controller.show(screen: screen, side: .left, keyboardMode: true)
        current = rawApp(ProcessInfo.processInfo.processIdentifier, selfApp: true).instance
        XCTAssertEqual(panel.onKeyDown?(event(53)), true)
        for _ in 0..<100 where backend.waitedTarget == nil { await Task.yield() }
        XCTAssertEqual(backend.waitedTarget?.token, original.token)
        XCTAssertFalse(controller.isVisible)
    }
}
