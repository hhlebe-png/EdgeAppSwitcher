import XCTest
@testable import EdgeAppSwitcher

@MainActor final class RecencyStoreTests: XCTestCase {
    func testBootstrapAndObservedMRU() {
        let store = RunningAppStore()
        let a = rawApp(1, bundle: "a", name: "A")
        let b = rawApp(2, bundle: "b", name: "B")
        store.replace([b, a])
        let recency = RecencyStore()
        recency.bootstrap(records: store.records, frontmost: b.instance.token)
        XCTAssertEqual(recency.orderedIDs(records: store.records), [.bundleIdentifier("b"), .bundleIdentifier("a")])
        recency.recordActivation(a.instance.token, records: store.records)
        XCTAssertEqual(recency.orderedIDs(records: store.records), [.bundleIdentifier("a"), .bundleIdentifier("b")])
        store.replace([a, b, rawApp(3, bundle: "c", name: "0"), rawApp(4, selfApp: true)])
        recency.reconcile(records: store.records)
        XCTAssertEqual(recency.orderedIDs(records: store.records), [.bundleIdentifier("a"), .bundleIdentifier("b"), .bundleIdentifier("c")])
        recency.recordActivation(InstanceToken(pid: 4, launchDate: Date(timeIntervalSince1970: 1)), records: store.records)
        XCTAssertEqual(recency.orderedIDs(records: store.records).count, 3)
    }
    func testReusedPIDDoesNotInheritHistory() {
        let store = RunningAppStore()
        let old = rawApp(1, date: 1, bundle: "a", name: "A")
        let b = rawApp(2, bundle: "b", name: "B")
        let recency = RecencyStore()
        store.replace([old, b])
        recency.bootstrap(records: store.records, frontmost: old.instance.token)
        store.replace([b])
        recency.reconcile(records: store.records)
        let new = rawApp(1, date: 2, bundle: "a", name: "A")
        store.replace([b, new])
        recency.reconcile(records: store.records)
        XCTAssertEqual(recency.orderedIDs(records: store.records), [.bundleIdentifier("b"), .bundleIdentifier("a")])
        XCTAssertNil(recency.preferredInstance(for: .bundleIdentifier("a")))
    }
    func testPreferredInstanceFallsBackToMostRecentSurvivor() {
        let store = RunningAppStore()
        let a = rawApp(1, url: "/A.app")
        let b = rawApp(2, url: "/A.app")
        let id = AppID.bundleURL(URL(fileURLWithPath: "/A.app"))
        let recency = RecencyStore()
        store.replace([a, b])
        recency.bootstrap(records: store.records, frontmost: a.instance.token)
        recency.recordActivation(b.instance.token, records: store.records)
        XCTAssertEqual(recency.preferredInstance(for: id), b.instance.token)
        store.replace([a])
        recency.reconcile(records: store.records)
        XCTAssertEqual(recency.preferredInstance(for: id), a.instance.token)
    }
    func testTerminatedLatestInstanceRemovesItsAppRecency() {
        let store = RunningAppStore()
        let a1 = rawApp(1, bundle: "a", name: "A")
        let a2 = rawApp(2, bundle: "a", name: "A")
        let b = rawApp(3, bundle: "b", name: "B")
        let recency = RecencyStore()
        store.replace([a1, a2, b])
        recency.bootstrap(records: store.records, frontmost: a1.instance.token)
        recency.recordActivation(b.instance.token, records: store.records)
        recency.recordActivation(a2.instance.token, records: store.records)
        store.replace([a1, b])
        recency.reconcile(records: store.records)
        XCTAssertEqual(recency.orderedIDs(records: store.records), [.bundleIdentifier("b"), .bundleIdentifier("a")])
    }
    func testLastObservedSiblingTerminationRestoresBaselineOrder() {
        let store = RunningAppStore()
        let a1 = rawApp(1, bundle: "a", name: "Z")
        let a2 = rawApp(2, bundle: "a", name: "Z")
        let b = rawApp(3, bundle: "b", name: "A")
        let recency = RecencyStore()
        store.replace([a1, a2, b])
        recency.bootstrap(records: store.records, frontmost: nil)
        XCTAssertEqual(recency.orderedIDs(records: store.records), [.bundleIdentifier("b"), .bundleIdentifier("a")])
        recency.recordActivation(a2.instance.token, records: store.records)
        XCTAssertEqual(recency.orderedIDs(records: store.records), [.bundleIdentifier("a"), .bundleIdentifier("b")])
        store.replace([a1, b])
        recency.reconcile(records: store.records)
        XCTAssertNil(recency.preferredInstance(for: .bundleIdentifier("a")))
        XCTAssertEqual(recency.orderedIDs(records: store.records), [.bundleIdentifier("b"), .bundleIdentifier("a")])
    }
    func testQueuedActivationDeliveryPreservesBThenC() {
        let store = RunningAppStore()
        let a = rawApp(1, bundle: "a", name: "A")
        let b = rawApp(2, bundle: "b", name: "B")
        let c = rawApp(3, bundle: "c", name: "C")
        store.replace([a,b,c])
        let recency = RecencyStore()
        recency.bootstrap(records: store.records, frontmost: a.instance.token)
        var delivered: [InstanceToken] = []
        let source = WorkspaceAppSource(onAppsChanged: { _ in }, onFrontmostChanged: { token in
            if let token { delivered.append(token); recency.recordActivation(token, records: store.records) }
        })
        let queued = [b,c].map { app in { source.deliverActivation(app) } }
        queued.forEach { $0() }
        XCTAssertEqual(delivered, [b.instance.token, c.instance.token])
        XCTAssertEqual(recency.orderedIDs(records: store.records), [.bundleIdentifier("c"), .bundleIdentifier("b"), .bundleIdentifier("a")])
        XCTAssertEqual(recency.preferredInstance(for: .bundleIdentifier("b")), b.instance.token)
        source.deliverActivation(rawApp(4, selfApp: true))
        source.deliverActivation(rawApp(5, regular: false))
        source.deliverActivation(rawApp(6, terminated: true))
        XCTAssertEqual(delivered.count, 2)
    }
    func testBootstrapNameTieUsesIdentifier() {
        let store = RunningAppStore()
        store.replace([rawApp(1, bundle: "z", name: "同名"), rawApp(2, bundle: "a", name: "同名")])
        let recency = RecencyStore()
        recency.bootstrap(records: store.records, frontmost: nil)
        XCTAssertEqual(recency.orderedIDs(records: store.records), [.bundleIdentifier("a"), .bundleIdentifier("z")])
    }
}
