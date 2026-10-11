import XCTest
@testable import EdgeAppSwitcher

@MainActor final class BarModelTests: XCTestCase {
    func testSnapshotDoesNotReorderOrInsertWhileOpen() {
        let store = RunningAppStore()
        store.replace([rawApp(1, bundle: "a"), rawApp(2, bundle: "b")])
        let original = store.records
        let model = BarModel()
        model.open(records: original, orderedIDs: original.map(\.id))
        store.replace([rawApp(3, bundle: "c"), rawApp(1, bundle: "a")])
        model.refresh(records: store.records, frontmost: original[0].id)
        XCTAssertEqual(model.rows.map(\.id), original.map(\.id))
        XCTAssertFalse(model.rows[1].isEnabled)
        XCTAssertTrue(model.rows[0].isFrontmost)
    }
    func testEmptySnapshotCanClose() {
        let model = BarModel()
        model.open(records: [], orderedIDs: [])
        model.close()
        XCTAssertTrue(model.rows.isEmpty)
    }
    func testRestartDoesNotReviveEndedSnapshotRow() {
        let store = RunningAppStore()
        store.replace([rawApp(1, bundle: "a")])
        let model = BarModel()
        model.open(records: store.records, orderedIDs: store.records.map(\.id))
        store.replace([rawApp(1, date: 2, bundle: "a")])
        model.refresh(records: store.records, frontmost: nil)
        XCTAssertFalse(model.rows[0].isEnabled)
        model.open(records: store.records, orderedIDs: store.records.map(\.id))
        XCTAssertTrue(model.rows[0].isEnabled)
    }
    func testTooltipCannotResurrectAfterCloseOrNewHover() {
        let tooltip = BarTooltipState()
        let first = tooltip.begin()
        tooltip.cancel()
        XCTAssertFalse(tooltip.reveal("old", generation: first))
        let second = tooltip.begin()
        XCTAssertFalse(tooltip.reveal("old", generation: first))
        XCTAssertTrue(tooltip.reveal("new", generation: second))
        XCTAssertEqual(tooltip.text, "new")
    }
    func testTooltipClampsToVisibleScreenOnBothSides() {
        let visible = CGRect(x: -500, y: -300, width: 400, height: 300)
        for side in [EdgeSide.left, .right] {
            let frame = BarTooltipState.frame(size: CGSize(width: 250, height: 50), anchor: CGPoint(x: -100, y: 0), side: side, visibleFrame: visible)
            XCTAssertTrue(visible.contains(frame))
        }
    }
    func testOverlappingInstancesPreserveGroupContinuity() {
        let store = RunningAppStore()
        store.replace([rawApp(1, bundle: "a")])
        let model = BarModel()
        let ids = store.records.map(\.id)
        model.open(records: store.records, orderedIDs: ids)
        store.replace([rawApp(1, bundle: "a"), rawApp(2, bundle: "a")])
        model.refresh(records: store.records, frontmost: nil)
        store.replace([rawApp(2, bundle: "a")])
        model.refresh(records: store.records, frontmost: ids[0])
        XCTAssertEqual(model.rows.map(\.id), ids)
        XCTAssertTrue(model.rows[0].isEnabled)
        XCTAssertTrue(model.rows[0].isFrontmost)
    }
    func testTrueRestartRemainsDisabledAcrossLaterOverlap() {
        let store = RunningAppStore()
        store.replace([rawApp(1, bundle: "a")])
        let model = BarModel()
        model.open(records: store.records, orderedIDs: store.records.map(\.id))
        store.replace([rawApp(2, bundle: "a")])
        model.refresh(records: store.records, frontmost: nil)
        store.replace([rawApp(2, bundle: "a"), rawApp(3, bundle: "a")])
        model.refresh(records: store.records, frontmost: store.records[0].id)
        XCTAssertFalse(model.rows[0].isEnabled)
        XCTAssertFalse(model.rows[0].isFrontmost)
    }
}
