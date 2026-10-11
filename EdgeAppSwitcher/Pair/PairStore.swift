import Foundation
import Observation

struct AppPair: Equatable {
    let a: URL
    let b: URL
}

@MainActor @Observable final class PairStore {
    private struct Payload: Codable {
        let version: Int
        let a: String
        let b: String
    }
    private static let key = "workPairV1"
    private let defaults: UserDefaults
    private let isLiveInstance: (AppInstance) -> Bool
    private(set) var pair: AppPair?
    private(set) var lastUsed: AppID?

    init(defaults: UserDefaults, isLiveInstance: @escaping (AppInstance) -> Bool = { $0.runningApplication?.isTerminated != true }) {
        self.defaults = defaults
        self.isLiveInstance = isLiveInstance
        guard let data = defaults.data(forKey: Self.key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1,
              let a = Self.bundleURL(payload.a),
              let b = Self.bundleURL(payload.b), a != b else { return }
        pair = AppPair(a: a, b: b)
    }

    @discardableResult
    func register(a: AppID, b: AppID, records: [AppRecord], frontmost: AppID?) -> Bool {
        guard let first = runningBundleURL(a, records: records),
              let second = runningBundleURL(b, records: records), first != second,
              let data = try? JSONEncoder().encode(Payload(version: 1, a: first.absoluteString, b: second.absoluteString)) else { return false }
        defaults.set(data, forKey: Self.key)
        guard defaults.data(forKey: Self.key) == data else { return false }
        pair = AppPair(a: first, b: second)
        lastUsed = nil
        observe(frontmost)
        return true
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
        pair = nil
        lastUsed = nil
    }

    func observe(_ id: AppID?) {
        guard let pair, case .bundleURL(let url) = id,
              let normalized = Self.bundleURL(url.absoluteString),
              normalized == pair.a || normalized == pair.b else { return }
        lastUsed = .bundleURL(normalized)
    }

    private static func bundleURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost",
              url.path.hasPrefix("/"), url.path != "/",
              url.query == nil, url.fragment == nil else { return nil }
        return url.standardizedFileURL
    }

    private func runningBundleURL(_ id: AppID, records: [AppRecord]) -> URL? {
        guard case .bundleURL(let url) = id,
              let normalized = Self.bundleURL(url.absoluteString),
              let record = records.first(where: { $0.id == id }),
              record.instances.contains(where: { instance in
                  isLiveInstance(instance) && instance.bundleURL.flatMap { Self.bundleURL($0.absoluteString) } == normalized
              }) else { return nil }
        return normalized
    }
}
