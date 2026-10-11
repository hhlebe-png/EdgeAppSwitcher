import XCTest
@testable import EdgeAppSwitcher

final class ScreenGeometryTests: XCTestCase {
    func testPairFixedHeightPreservesCenterAndScreenLimit() {
        for height in [800.0, 120.0, 40.0, 12.0] {
            let visible = CGRect(x: -500, y: 100, width: 1000, height: height)
            let display = screen(1, frame: visible)
            for side in [EdgeSide.left, .right] {
                let frame = ScreenGeometry.panelFrame(screen: display, side: side, itemCount: 3, fixedHeight: 57)
                XCTAssertEqual(frame.height, min(3 * 56 + 16 + 57, max(0, height - 32)))
                XCTAssertEqual(frame.midY, visible.midY)
                XCTAssertEqual(frame.minX, side == .left ? -492 : 428)
            }
        }
    }

    func testNoPairKeepsOriginalFrame() {
        let display = screen(1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(ScreenGeometry.panelFrame(screen: display, side: .left, itemCount: 3, fixedHeight: 0),
                       CGRect(x: 8, y: 308, width: 64, height: 184))
    }

    func testNegativeCoordinatesAndSharedBoundary() {
        let left = screen(2, frame: CGRect(x: -1000, y: 0, width: 1000, height: 800))
        let primary = screen(1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), primary: true)
        let point = CGPoint(x: -500, y: 400)
        XCTAssertEqual(ScreenGeometry.screen(at: point, screens: [primary, left], previous: nil)?.id, 2)
        let boundary = CGPoint(x: 0, y: 400)
        XCTAssertEqual(ScreenGeometry.screen(at: boundary, screens: [primary, left], previous: 2)?.id, 2)
        XCTAssertEqual(ScreenGeometry.screen(at: boundary, screens: [primary, left], previous: nil)?.id, 1)
        let duplicate = [screen(8, frame: left.frame), screen(3, frame: left.frame)]
        XCTAssertEqual(ScreenGeometry.screen(at: point, screens: duplicate, previous: nil)?.id, 3)
        XCTAssertNil(ScreenGeometry.screen(at: point, screens: [], previous: nil))
    }

    func testTriggerExcludesCorners() {
        let display = screen(1, frame: CGRect(x: -500, y: 100, width: 1000, height: 400))
        let region = ScreenGeometry.triggerRegion(screen: display, side: .left)
        XCTAssertEqual(region, CGRect(x: -500, y: 164, width: 2, height: 272))
        XCTAssertNil(ScreenGeometry.triggerRegion(screen: screen(2, frame: CGRect(x: 0, y: 0, width: 100, height: 128)), side: .right))
    }

    func testPanelUsesVisibleFrame() {
        let display = screen(1, frame: CGRect(x: 0, y: 0, width: 1200, height: 900), visible: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let frame = ScreenGeometry.panelFrame(screen: display, side: .right, itemCount: 20)
        XCTAssertEqual(frame.maxX, 992)
        XCTAssertEqual(frame.width, 64)
        XCTAssertEqual(frame.height, 768)
    }

    func testTinyVisibleFrameClampsSafely() {
        let visible = CGRect(x: -20, y: -10, width: 20, height: 12)
        let display = screen(1, frame: visible, visible: visible)
        for side in [EdgeSide.left, .right] {
            let frame = ScreenGeometry.panelFrame(screen: display, side: side, itemCount: 3)
            XCTAssertTrue(frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite)
            XCTAssertGreaterThanOrEqual(frame.width, 0)
            XCTAssertGreaterThanOrEqual(frame.height, 0)
            XCTAssertTrue(visible.contains(frame))
        }
    }

    func testCorridorIncludesDockInset() {
        let display = screen(1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), visible: CGRect(x: 50, y: 50, width: 900, height: 700))
        let rightPanel = ScreenGeometry.panelFrame(screen: display, side: .right, itemCount: 3)
        let leftPanel = ScreenGeometry.panelFrame(screen: display, side: .left, itemCount: 3)
        XCTAssertEqual(ScreenGeometry.corridor(screen: display, side: .right, panelFrame: rightPanel), CGRect(x: 942, y: 308, width: 58, height: 184))
        XCTAssertEqual(ScreenGeometry.corridor(screen: display, side: .left, panelFrame: leftPanel), CGRect(x: 0, y: 308, width: 58, height: 184))
    }

    private func screen(_ id: ScreenID, frame: CGRect, visible: CGRect? = nil, primary: Bool = false) -> ScreenDescriptor {
        ScreenDescriptor(id: id, frame: frame, visibleFrame: visible ?? frame, isPrimary: primary)
    }
}
