import AppKit

struct BarRow: Identifiable {
    let id: AppID
    let name: String
    let icon: NSImage?
    let isEnabled: Bool
    let isFrontmost: Bool
}

@MainActor final class BarModel {
    private(set) var rows: [BarRow] = []
    private var continuingInstances: [AppID: [AppInstance]] = [:]

    func open(records: [AppRecord], orderedIDs: [AppID]) {
        close()
        let recordsByID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<AppID> = []
        rows = orderedIDs.compactMap { id in
            guard seen.insert(id).inserted, let record = recordsByID[id] else { return nil }
            continuingInstances[id] = record.instances
            return BarRow(id: id, name: record.name, icon: record.icon, isEnabled: !record.instances.isEmpty, isFrontmost: false)
        }
    }

    func refresh(records: [AppRecord], frontmost: AppID?) {
        let recordsByID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rows = rows.map { row in
            let record = recordsByID[row.id]
            let liveInstances = record?.instances.filter { $0.runningApplication?.isTerminated != true } ?? []
            let liveTokens = Set(liveInstances.map(\.token))
            // Once ended, a snapshot row stays disabled until the next opening.
            let previous = (continuingInstances[row.id] ?? []).filter { $0.runningApplication?.isTerminated != true }
            let enabled = row.isEnabled && previous.contains { liveTokens.contains($0.token) }
            // Carry observed overlap forward: a1 -> a1+a2 -> a2 is one live group.
            // Do not update a tombstone, even if later instances overlap each other.
            if enabled { continuingInstances[row.id] = liveInstances }
            return BarRow(id: row.id, name: record?.name ?? row.name, icon: record?.icon ?? row.icon,
                          isEnabled: enabled, isFrontmost: enabled && row.id == frontmost)
        }
    }

    func close() { rows = []; continuingInstances = [:] }
}

// A delayed hover can publish only while its presentation generation is current.
@MainActor final class BarTooltipState {
    private(set) var generation: UInt64 = 0
    private(set) var text: String?
    func cancel() { generation &+= 1; text = nil }
    func begin() -> UInt64 { cancel(); return generation }
    @discardableResult func reveal(_ text: String, generation: UInt64) -> Bool {
        guard generation == self.generation else { return false }
        self.text = text
        return true
    }

    static func frame(size: CGSize, anchor: CGPoint, side: EdgeSide, visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, max(0, visibleFrame.width))
        let height = min(size.height, max(0, visibleFrame.height))
        let desiredX = side == .left ? anchor.x + 8 : anchor.x - width - 8
        return CGRect(x: min(max(desiredX, visibleFrame.minX), visibleFrame.maxX - width),
                      y: min(max(anchor.y - height / 2, visibleFrame.minY), visibleFrame.maxY - height),
                      width: width, height: height)
    }
}
