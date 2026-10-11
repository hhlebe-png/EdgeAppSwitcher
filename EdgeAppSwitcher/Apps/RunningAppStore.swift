import AppKit
import Observation

@MainActor @Observable final class RunningAppStore {
    private(set) var records: [AppRecord] = []

    func replace(_ apps: [RawApp]) {
        let eligible = apps.filter { $0.isRegular && !$0.isTerminated && !$0.isSelf }
        let grouped = Dictionary(grouping: eligible) { app -> AppID in
            if let url = app.instance.bundleURL { return .bundleURL(url.standardizedFileURL) }
            if let identifier = app.bundleIdentifier, !identifier.isEmpty { return .bundleIdentifier(identifier) }
            return .instance(app.instance.token)
        }
        records = grouped.map { id, apps in
            let sorted = apps.sorted { Self.latestFirst($0.instance, $1.instance) }
            let name = sorted.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
                ?? sorted.first?.instance.bundleURL?.deletingPathExtension().lastPathComponent
                ?? "名称不明のアプリ"
            return AppRecord(id: id, name: name, icon: sorted.compactMap(\.icon).first ?? NSImage(named: NSImage.applicationIconName), instances: sorted.map(\.instance))
        }.sorted(by: Self.nameOrder)
    }

    func resolve(_ id: AppID, preferred: InstanceToken?) -> AppInstance? {
        guard let record = records.first(where: { $0.id == id }) else { return nil }
        let surviving = record.instances.filter { $0.runningApplication?.isTerminated != true }
        if let preferred, let instance = surviving.first(where: { $0.token == preferred }) { return instance }
        return surviving.sorted(by: Self.latestFirst).first
    }

    static func nameOrder(_ lhs: AppRecord, _ rhs: AppRecord) -> Bool {
        let comparison = lhs.name.compare(rhs.name, options: [.caseInsensitive, .numeric], locale: Locale(identifier: "ja_JP"))
        return comparison == .orderedSame ? lhs.id.sortKey < rhs.id.sortKey : comparison == .orderedAscending
    }

    private static func latestFirst(_ lhs: AppInstance, _ rhs: AppInstance) -> Bool {
        switch (lhs.token.launchDate, rhs.token.launchDate) {
        case (.some(let left), .some(let right)) where left != right: return left > right
        case (.some, .none): return true
        case (.none, .some): return false
        default: break
        }
        return lhs.token.pid < rhs.token.pid
    }
}
