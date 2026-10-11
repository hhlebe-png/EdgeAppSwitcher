import AppKit

struct PairDestination {
    let id: AppID
    let name: String
    let icon: NSImage?
    let isEnabled: Bool
}

struct PairResolver {
    private let isLiveInstance: (AppInstance) -> Bool

    init(isLiveInstance: @escaping (AppInstance) -> Bool = { $0.runningApplication?.isTerminated != true }) {
        self.isLiveInstance = isLiveInstance
    }

    func destination(pair: AppPair?, lastUsed: AppID?, frontmost: AppID?, records: [AppRecord]) -> PairDestination? {
        guard let pair else { return nil }
        let a = AppID.bundleURL(pair.a)
        let b = AppID.bundleURL(pair.b)
        let id: AppID
        if frontmost == a {
            id = b
        } else if frontmost == b {
            id = a
        } else {
            id = lastUsed == b ? b : a
        }
        let url = id == a ? pair.a : pair.b
        if let record = records.first(where: { record in
            record.id == id && record.instances.contains(where: { instance in
                isLiveInstance(instance) && instance.bundleURL?.standardizedFileURL == url
            })
        }) {
            return PairDestination(id: id, name: record.name, icon: record.icon, isEnabled: true)
        }
        return PairDestination(id: id, name: url.deletingPathExtension().lastPathComponent, icon: nil, isEnabled: false)
    }
}
