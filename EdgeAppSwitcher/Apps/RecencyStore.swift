import Foundation

@MainActor final class RecencyStore {
    private var baselineOrder: [AppID] = []
    // Most recent first: array order is a monotonic observation sequence, independent of clocks.
    private var activations: [InstanceToken] = []
    private var tokenIDs: [InstanceToken: AppID] = [:]

    func bootstrap(records: [AppRecord], frontmost: InstanceToken?) {
        baselineOrder = records.sorted(by: RunningAppStore.nameOrder).map(\.id)
        activations = []
        tokenIDs = [:]
        reconcile(records: records)
        if let frontmost { recordActivation(frontmost, records: records) }
    }

    func reconcile(records: [AppRecord]) {
        let previousTokens = Set(tokenIDs.keys)
        tokenIDs = Dictionary(records.flatMap { record in record.instances.map { ($0.token, record.id) } }, uniquingKeysWith: { first, _ in first })
        let liveTokens = Set(tokenIDs.keys)
        activations.removeAll { !liveTokens.contains($0) }
        let liveIDs = Set(records.map(\.id))
        // A restarted bundle must be appended even when termination and launch coalesce into one refresh.
        let continuingIDs = Set(previousTokens.intersection(liveTokens).compactMap { tokenIDs[$0] })
        baselineOrder.removeAll { !liveIDs.contains($0) || (!previousTokens.isEmpty && !continuingIDs.contains($0)) }
        let missing = records.filter { !baselineOrder.contains($0.id) }.sorted(by: RunningAppStore.nameOrder)
        baselineOrder.append(contentsOf: missing.map(\.id))
    }

    func recordActivation(_ token: InstanceToken, records: [AppRecord]) {
        reconcile(records: records)
        guard tokenIDs[token] != nil else { return }
        activations.removeAll { $0 == token }
        activations.insert(token, at: 0)
    }

    func orderedIDs(records: [AppRecord]) -> [AppID] {
        reconcile(records: records)
        let observedIDs = activations.compactMap { tokenIDs[$0] }.reduce(into: [AppID]()) { ids, id in
            if !ids.contains(id) { ids.append(id) }
        }
        return observedIDs + baselineOrder.filter { !observedIDs.contains($0) }
    }

    func preferredInstance(for id: AppID) -> InstanceToken? {
        activations.first { tokenIDs[$0] == id }
    }
}
