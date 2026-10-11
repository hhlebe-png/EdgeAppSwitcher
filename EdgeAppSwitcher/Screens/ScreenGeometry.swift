import AppKit

typealias ScreenID = UInt32

struct ScreenDescriptor: Equatable {
    let id: ScreenID
    let frame: CGRect
    let visibleFrame: CGRect
    let isPrimary: Bool
}

enum EdgeSide: String {
    case left
    case right
}

enum ScreenGeometry {
    static func screen(at point: CGPoint, screens: [ScreenDescriptor], previous: ScreenID?) -> ScreenDescriptor? {
        let matches = screens.filter {
            point.x >= $0.frame.minX && point.x <= $0.frame.maxX &&
            point.y >= $0.frame.minY && point.y <= $0.frame.maxY
        }
        guard !matches.isEmpty else { return nil }
        if let previous, let prior = matches.first(where: { $0.id == previous }) { return prior }
        if let primary = matches.first(where: \.isPrimary) { return primary }
        return matches.min { $0.id < $1.id }
    }

    static func triggerRegion(screen: ScreenDescriptor, side: EdgeSide) -> CGRect? {
        let height = screen.frame.height - 128
        guard height > 0, screen.frame.width > 0 else { return nil }
        let width = min(2, screen.frame.width)
        let x = side == .left ? screen.frame.minX : screen.frame.maxX - width
        return CGRect(x: x, y: screen.frame.minY + 64, width: width, height: height)
    }

    static func panelFrame(screen: ScreenDescriptor, side: EdgeSide, itemCount: Int, fixedHeight: CGFloat = 0) -> CGRect {
        let visible = screen.visibleFrame
        let width = min(64, max(0, visible.width))
        let height = min(max(0, Double(max(0, itemCount)) * 56 + 16 + max(0, fixedHeight)), max(0, visible.height - 32))
        let inset = min(8, max(0, (visible.width - width) / 2))
        let x = side == .left ? visible.minX + inset : visible.maxX - inset - width
        let y = visible.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func corridor(screen: ScreenDescriptor, side: EdgeSide, panelFrame: CGRect) -> CGRect {
        let y = panelFrame.minY
        let height = panelFrame.height
        switch side {
        case .left:
            let innerEdge = max(screen.frame.minX, panelFrame.minX)
            return CGRect(x: screen.frame.minX, y: y, width: max(0, innerEdge - screen.frame.minX), height: height)
        case .right:
            let innerEdge = min(screen.frame.maxX, panelFrame.maxX)
            return CGRect(x: innerEdge, y: y, width: max(0, screen.frame.maxX - innerEdge), height: height)
        }
    }
}
