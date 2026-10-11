import XCTest
@testable import EdgeAppSwitcher

final class EdgeTriggerTests: XCTestCase {
    private let screen = ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), isPrimary: true)
    private func sample(_ ms: Int, x: CGFloat = 1, y: CGFloat = 400, buttons: Int = 0, screens: [ScreenDescriptor]? = nil, side: EdgeSide = .left) -> TriggerSample {
        TriggerSample(time: .milliseconds(ms), point: CGPoint(x: x, y: y), pressedButtons: buttons, screens: screens ?? [screen], side: side)
    }
    func testDwellRequires250msOnSameScreen() {
        var trigger = EdgeTrigger(); trigger.reset(requireExit: false)
        XCTAssertEqual(trigger.sample(sample(0)), .none)
        XCTAssertEqual(trigger.sample(sample(249)), .none)
        XCTAssertEqual(trigger.sample(sample(250)), .show(screen.id))
        XCTAssertEqual(trigger.sample(sample(300)), .none)
    }
    func testTransitDragAndCornerNeverShow() {
        let other = ScreenDescriptor(id: 2, frame: screen.frame, visibleFrame: screen.frame, isPrimary: true)
        for interrupted in [sample(200, x: 20), sample(200, buttons: 1), sample(200, y: 63), sample(200, y: 737), sample(200, screens: [other])] {
            var trigger = EdgeTrigger(); trigger.reset(requireExit: false)
            XCTAssertEqual(trigger.sample(sample(0)), .none)
            XCTAssertEqual(trigger.sample(interrupted), .none)
            XCTAssertEqual(trigger.sample(sample(250)), .none)
            XCTAssertEqual(trigger.sample(sample(500)), .show(1))
        }
    }
    func testExitWaits300msAndCorridorKeepsOpen() {
        var trigger = EdgeTrigger()
        trigger.didShow(screen: 1, panelFrame: CGRect(x: 8, y: 300, width: 64, height: 200), corridor: CGRect(x: 0, y: 300, width: 8, height: 200), keyboardMode: false)
        XCTAssertEqual(trigger.sample(sample(0, x: 4)), .none)
        XCTAssertEqual(trigger.sample(sample(100, x: 40)), .none)
        trigger.setTooltipFrame(CGRect(x: 80, y: 300, width: 100, height: 50))
        XCTAssertEqual(trigger.sample(sample(200, x: 100, y: 320)), .none)
        XCTAssertEqual(trigger.sample(sample(300, x: 300)), .none)
        XCTAssertEqual(trigger.sample(sample(599, x: 300)), .none)
        XCTAssertEqual(trigger.sample(sample(600, x: 300)), .hide)
        XCTAssertEqual(trigger.sample(sample(601, x: 1)), .none)
    }
    func testReentryCancelsExitCountdownAndTooltipRemovalWorks() {
        var trigger = EdgeTrigger()
        trigger.didShow(screen: 1, panelFrame: CGRect(x: 8, y: 300, width: 64, height: 200), corridor: CGRect(x: 0, y: 300, width: 8, height: 200), keyboardMode: false)
        XCTAssertEqual(trigger.sample(sample(0, x: 300)), .none)
        XCTAssertEqual(trigger.sample(sample(299, x: 40)), .none)
        trigger.setTooltipFrame(CGRect(x: 80, y: 300, width: 100, height: 50))
        trigger.setTooltipFrame(nil)
        XCTAssertEqual(trigger.sample(sample(300, x: 100, y: 320)), .none)
        XCTAssertEqual(trigger.sample(sample(600, x: 100, y: 320)), .hide)
    }
    func testRequires12ptExitAfterClose() {
        for side in [EdgeSide.left, .right] {
            var trigger = EdgeTrigger(); trigger.reset(requireExit: true)
            let edge: CGFloat = side == .left ? 1 : 999
            let eleven: CGFloat = side == .left ? 11 : 989
            let twelve: CGFloat = side == .left ? 12 : 988
            XCTAssertEqual(trigger.sample(sample(0, x: eleven, side: side)), .none)
            XCTAssertEqual(trigger.sample(sample(250, x: edge, side: side)), .none)
            XCTAssertEqual(trigger.sample(sample(500, x: edge, side: side)), .none)
            XCTAssertEqual(trigger.sample(sample(501, x: twelve, side: side)), .none)
            XCTAssertEqual(trigger.sample(sample(502, x: edge, side: side)), .none)
            XCTAssertEqual(trigger.sample(sample(752, x: edge, side: side)), .show(1))
        }
    }
    func testStartupAtEdgeAndDelayedSampleDoesNotAppearImmediately() {
        var trigger = EdgeTrigger()
        XCTAssertEqual(trigger.sample(sample(0)), .none)
        XCTAssertEqual(trigger.sample(sample(300)), .none)
        XCTAssertEqual(trigger.sample(sample(301, x: 12)), .none)
        XCTAssertEqual(trigger.sample(sample(302)), .none)
        XCTAssertEqual(trigger.sample(sample(803)), .none)
        XCTAssertEqual(trigger.sample(sample(1052)), .none)
        XCTAssertEqual(trigger.sample(sample(1053)), .show(1))
    }
    func testExactly500msGapCanCompleteDwell() {
        var trigger = EdgeTrigger(); trigger.reset(requireExit: false)
        XCTAssertEqual(trigger.sample(sample(0)), .none)
        XCTAssertEqual(trigger.sample(sample(500)), .show(1))
    }
    func testNegativeAndReversedTimeResetAndRequireExit() {
        for invalid in [-1, 99] {
            var trigger = EdgeTrigger(); trigger.reset(requireExit: false)
            XCTAssertEqual(trigger.sample(sample(100)), .none)
            XCTAssertEqual(trigger.sample(sample(invalid)), .none)
            XCTAssertEqual(trigger.sample(sample(350)), .none)
            XCTAssertEqual(trigger.sample(sample(351, x: 12)), .none)
            XCTAssertEqual(trigger.sample(sample(352)), .none)
            XCTAssertEqual(trigger.sample(sample(602)), .show(1))
        }
    }
    func testKeyboardModeIgnoresPointerExit() {
        var trigger = EdgeTrigger()
        trigger.didShow(screen: 1, panelFrame: .zero, corridor: .zero, keyboardMode: true)
        XCTAssertEqual(trigger.sample(sample(0, x: 300)), .none)
        XCTAssertEqual(trigger.sample(sample(300, x: 300)), .none)
        XCTAssertEqual(trigger.sample(sample(1000, x: 300)), .none)
    }
    func testResetClearsDisplayAndTooltip() {
        var trigger = EdgeTrigger()
        trigger.didShow(screen: 1, panelFrame: screen.frame, corridor: .zero, keyboardMode: true)
        trigger.setTooltipFrame(screen.frame)
        trigger.reset(requireExit: false)
        XCTAssertEqual(trigger.sample(sample(0)), .none)
        XCTAssertEqual(trigger.sample(sample(250)), .show(1))
    }
}
