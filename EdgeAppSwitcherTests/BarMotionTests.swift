import AppKit
import XCTest
import SwiftUI
@testable import EdgeAppSwitcher

@MainActor final class BarMotionTests: XCTestCase {
    func testPairHoverDoesNotPublishName() {
        var shown: [String] = []
        let names = BarNameCallbacks(showKeyboardName: { name, _ in shown.append(name) })
        names.hover("Pair App", .zero)
        names.hover(nil, .zero)
        XCTAssertTrue(shown.isEmpty)
        names.focusName("Pair App", .zero)
        XCTAssertEqual(shown, ["Pair App"])
    }

    func testPairPresentationUsesLiveIconAndDisabledAccessibility() {
        let icon = NSImage(size: NSSize(width: 40, height: 40))
        let id = AppID.bundleIdentifier("pair")
        let live = PairCellPresentation(destination: PairDestination(id: id, name: "Editor", icon: icon, isEnabled: true))
        XCTAssertTrue(live.icon === icon)
        XCTAssertEqual(live.accessibilityLabel, "作業ペア、Editorへ切り替え")
        XCTAssertEqual(live.accessibilityValue, "")
        XCTAssertEqual(live.opacity, 1)
        let stopped = PairCellPresentation(destination: PairDestination(id: id, name: "Editor", icon: icon, isEnabled: false))
        XCTAssertNil(stopped.icon)
        XCTAssertEqual(stopped.accessibilityValue, "未起動")
        XCTAssertEqual(stopped.opacity, 0.35)
    }

    func testMouseNamesStayHiddenWhileKeyboardNamesRemainAvailable() {
        var shown: [(String, CGPoint)] = []
        let names = BarNameCallbacks(showKeyboardName: { shown.append(($0, $1)) })
        names.hover("Mouse App", CGPoint(x: 32, y: 36))
        names.hover(nil, CGPoint(x: 32, y: 36))
        XCTAssertTrue(shown.isEmpty)
        names.focusName("Keyboard App", CGPoint(x: 32, y: 92))
        XCTAssertEqual(shown.map { $0.0 }, ["Keyboard App"])
        XCTAssertEqual(shown.first?.1, CGPoint(x: 32, y: 92))
    }

    func testWindowlessViewKeepsCellAnchorAndLayoutFixedDuringMotionAndFeedback() {
        let state = BarViewState()
        let id = AppID.bundleIdentifier("a")
        state.rows = [BarRow(id: id, name: "A", icon: nil, isEnabled: true, isFrontmost: false)]
        state.focusedID = id
        state.motion.present(side: .left, reduceMotion: false, now: 0)
        var anchors: [CGPoint] = []
        // No NSWindow, ordering, focus, event injection, or application activation.
        let hosting = NSHostingView(rootView: BarView(state: state, select: { _ in },
            hover: { _, _ in }, focusName: { _, point in anchors.append(point) }))
        hosting.frame = CGRect(x: 0, y: 0, width: 64, height: 72)
        func layout() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            hosting.layoutSubtreeIfNeeded()
        }
        layout()
        let bounds = hosting.bounds
        let initial = anchors.last
        XCTAssertNotNil(initial, "Headless layout must measure a real cell anchor")
        _ = state.motion.advance(now: 0.09, generation: state.motion.generation)
        state.hoveredID = id
        layout()
        XCTAssertEqual(hosting.bounds, bounds)
        XCTAssertEqual(anchors.last, initial)
        // Force a new focus measurement after motion; do not merely reuse the old callback.
        state.focusedID = nil; layout()
        let measurements = anchors.count
        state.focusedID = id; layout()
        XCTAssertGreaterThan(anchors.count, measurements)
        XCTAssertEqual(anchors.last, initial)
        state.selectedID = id; layout()
        XCTAssertEqual(hosting.bounds, bounds)
        state.motion.setReduceMotion(true, now: 0.09)
        state.resetInteraction(); layout()
        let reducedMeasurements = anchors.count
        state.focusedID = id; layout()
        XCTAssertGreaterThan(anchors.count, reducedMeasurements)
        XCTAssertEqual(anchors.last, initial)
        XCTAssertEqual(hosting.bounds, bounds)
    }
    func testAppearanceMovesFromOppositeEdgesIntoFinalVisualPosition() {
        for side in [EdgeSide.left, .right] {
            let motion = BarMotionState()
            motion.present(side: side, reduceMotion: false, now: 0)
            XCTAssertEqual(motion.offsetX, side == .left ? -8 : 8)
            XCTAssertEqual(motion.opacity, 0)
            let token = motion.generation
            XCTAssertTrue(motion.advance(now: 0.09, generation: token))
            XCTAssertGreaterThan(motion.opacity, 0)
            XCTAssertLessThan(motion.opacity, 1)
            XCTAssertLessThan(abs(motion.offsetX), 8)
            XCTAssertFalse(motion.advance(now: 0.18, generation: token))
            XCTAssertEqual(motion.phase, .shown)
            XCTAssertEqual(motion.offsetX, 0)
            XCTAssertEqual(motion.opacity, 1)
        }
    }
    func testDismissReopenRetargetsCurrentVisualAndRejectsStaleCompletion() {
        let motion = BarMotionState()
        motion.present(side: .right, reduceMotion: false, now: 0)
        _ = motion.advance(now: 0.18, generation: motion.generation)
        motion.dismiss(now: 1)
        let obsolete = motion.generation
        _ = motion.advance(now: 1.06, generation: obsolete)
        XCTAssertGreaterThan(motion.offsetX, 0)
        let opacity = motion.opacity, offset = motion.offsetX
        motion.present(side: .right, reduceMotion: false, now: 1.06)
        XCTAssertEqual(motion.opacity, opacity)
        XCTAssertEqual(motion.offsetX, offset)
        XCTAssertFalse(motion.advance(now: 2, generation: obsolete))
        XCTAssertEqual(motion.phase, .appearing)
        _ = motion.advance(now: 1.24, generation: motion.generation)
        XCTAssertEqual(motion.phase, .shown)
        XCTAssertEqual(motion.opacity, 1)
        XCTAssertEqual(motion.offsetX, 0)
        motion.dismiss(now: 3)
        _ = motion.advance(now: 3.12, generation: motion.generation)
        XCTAssertEqual(motion.phase, .hidden)
        XCTAssertEqual(motion.opacity, 0)
        XCTAssertEqual(motion.offsetX, 0)
    }
    func testReduceMotionSnapsActiveShowAndDismissAndInvalidatesWork() {
        let motion = BarMotionState()
        motion.present(side: .left, reduceMotion: false, now: 0)
        let appearing = motion.generation
        _ = motion.advance(now: 0.06, generation: appearing)
        motion.setReduceMotion(true, now: 0.06)
        XCTAssertEqual(motion.phase, .shown)
        XCTAssertEqual(motion.opacity, 1)
        XCTAssertEqual(motion.offsetX, 0)
        XCTAssertFalse(motion.advance(now: 1, generation: appearing))
        motion.setReduceMotion(false, now: 1)
        motion.dismiss(now: 2)
        let dismissing = motion.generation
        motion.setReduceMotion(true, now: 2.04)
        XCTAssertEqual(motion.phase, .hidden)
        XCTAssertEqual(motion.offsetX, 0)
        XCTAssertFalse(motion.advance(now: 3, generation: dismissing))
        motion.present(side: .right, reduceMotion: true, now: 4)
        XCTAssertEqual(motion.phase, .shown)
        motion.dismiss(now: 5)
        XCTAssertEqual(motion.phase, .hidden)
    }
    func testNativePressUsesSameResponseAsSelectionAndReleaseRestoresHover() {
        let state = BarViewState()
        let id = AppID.bundleIdentifier("a")
        let row = BarRow(id: id, name: "A", icon: nil, isEnabled: true, isFrontmost: false)
        state.hoveredID = id
        let hovered = state.feedback(for: row)
        let pressed = hovered.pressing(true, reduceMotion: false)
        state.selectedID = id
        XCTAssertEqual(pressed, state.feedback(for: row))
        XCTAssertEqual(hovered.pressing(false, reduceMotion: false), hovered)
        let reduced = hovered.pressing(true, reduceMotion: true)
        XCTAssertEqual(reduced.scale, 1)
        XCTAssertEqual(reduced.offsetY, 0)
        XCTAssertTrue(reduced.isSelected)
    }
    func testHoverAndFocusUseSameEffectAndSelectionWinsUntilReset() {
        let state = BarViewState()
        let id = AppID.bundleIdentifier("a")
        let row = BarRow(id: id, name: "A", icon: nil, isEnabled: true, isFrontmost: false)
        state.rows = [row]
        let resting = state.feedback(for: row)
        state.hoveredID = id
        let hovered = state.feedback(for: row)
        XCTAssertLessThan(hovered.offsetY, resting.offsetY)
        XCTAssertGreaterThan(hovered.scale, resting.scale)
        state.hoveredID = nil; state.focusedID = id
        XCTAssertEqual(state.feedback(for: row), hovered)
        state.selectedID = id
        let selected = state.feedback(for: row)
        XCTAssertLessThan(selected.scale, resting.scale)
        XCTAssertTrue(selected.isSelected)
        state.motion.setReduceMotion(true, now: 0)
        XCTAssertEqual(state.feedback(for: row).scale, 1)
        XCTAssertEqual(state.feedback(for: row).offsetY, 0)
        XCTAssertTrue(state.feedback(for: row).isSelected)
        XCTAssertTrue(state.feedback(for: row).isEmphasized)
        state.resetInteraction()
        XCTAssertNil(state.selectedID); XCTAssertNil(state.hoveredID); XCTAssertNil(state.focusedID)
        XCTAssertEqual(state.feedback(for: row), resting)
    }
}
