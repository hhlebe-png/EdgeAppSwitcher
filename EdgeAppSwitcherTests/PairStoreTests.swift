import XCTest
@testable import EdgeAppSwitcher

@MainActor final class PairStoreTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "PairStoreTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
        defaults.removePersistentDomain(forName: name)
        XCTAssertTrue(defaults.persistentDomain(forName: name)?.isEmpty ?? true)
    }
    private let a = AppID.bundleURL(URL(fileURLWithPath: "/A.app"))
    private let b = AppID.bundleURL(URL(fileURLWithPath: "/B.app"))
    private let c = AppID.bundleURL(URL(fileURLWithPath: "/C.app"))
    private func records() -> [AppRecord] {
        let apps = RunningAppStore()
        apps.replace([rawApp(1, url: "/A.app"), rawApp(2, url: "/B.app"), rawApp(3, url: "/C.app")])
        return apps.records
    }
    func testRegistrationRoundTripAndClear() {
        withDefaults { defaults in
            defaults.set("right", forKey: "edgeSide")
            defaults.set(true, forKey: "isPaused")
            let store = PairStore(defaults: defaults)
            XCTAssertTrue(store.register(a: a, b: b, records: records(), frontmost: b))
            XCTAssertEqual(store.lastUsed, b)
            let restored = PairStore(defaults: defaults)
            XCTAssertEqual(restored.pair, store.pair)
            XCTAssertNil(restored.lastUsed)
            let payload = try! JSONSerialization.jsonObject(with: defaults.data(forKey: "workPairV1")!) as! [String: Any]
            XCTAssertEqual(payload["version"] as? Int, 1)
            XCTAssertEqual(payload["a"] as? String, "file:///A.app")
            XCTAssertEqual(Set(payload.keys), ["version", "a", "b"])
            restored.clear()
            XCTAssertNil(restored.pair)
            XCTAssertNil(defaults.object(forKey: "workPairV1"))
            XCTAssertEqual(defaults.string(forKey: "edgeSide"), "right")
            XCTAssertTrue(defaults.bool(forKey: "isPaused"))
        }
    }
    func testInvalidRegistrationKeepsExistingPair() {
        withDefaults { defaults in
            let store = PairStore(defaults: defaults)
            XCTAssertTrue(store.register(a: a, b: b, records: records(), frontmost: a))
            let original = store.pair
            let data = defaults.data(forKey: "workPairV1")
            let token = InstanceToken(pid: 9, launchDate: nil)
            let instanceOnly = AppRecord(id: .instance(token), name: "Unknown", icon: nil, instances: [AppInstance(token: token, bundleURL: nil)])
            for (first, second, candidates) in [(a, a, records()), (a, c, []), (a, .instance(token), records() + [instanceOnly]), (a, b, records().map { AppRecord(id: $0.id, name: $0.name, icon: nil, instances: []) })] {
                XCTAssertFalse(store.register(a: first, b: second, records: candidates, frontmost: nil))
                XCTAssertEqual(store.pair, original)
                XCTAssertEqual(store.lastUsed, a)
                XCTAssertEqual(defaults.data(forKey: "workPairV1"), data)
            }
        }
    }
    func testEndedSnapshotRejectsRegistrationAndLiveSiblingAllowsIt() {
        withDefaults { defaults in
            let ended = InstanceToken(pid: 30, launchDate: Date(timeIntervalSince1970: 1))
            let live = InstanceToken(pid: 31, launchDate: Date(timeIntervalSince1970: 1))
            let cURL = URL(fileURLWithPath: "/C.app")
            let store = PairStore(defaults: defaults, isLiveInstance: { $0.token != ended })
            XCTAssertTrue(store.register(a: a, b: b, records: records(), frontmost: b))
            let original = store.pair
            let originalData = defaults.data(forKey: "workPairV1")
            let stale = AppRecord(id: c, name: "C", icon: nil, instances: [AppInstance(token: ended, bundleURL: cURL)])
            let candidates = records().filter { $0.id != c } + [stale]
            XCTAssertFalse(store.register(a: a, b: c, records: candidates, frontmost: a))
            XCTAssertEqual(store.pair, original)
            XCTAssertEqual(defaults.data(forKey: "workPairV1"), originalData)
            XCTAssertEqual(store.lastUsed, b)
            let surviving = AppRecord(id: c, name: "C", icon: nil, instances: stale.instances + [AppInstance(token: live, bundleURL: cURL)])
            XCTAssertTrue(store.register(a: a, b: c, records: records().filter { $0.id != c } + [surviving], frontmost: c))
            XCTAssertEqual(store.pair?.b, cURL)
            XCTAssertEqual(store.lastUsed, c)
        }
    }

    func testMalformedAndUnknownSchemaPreservesRawDefaults() {
        withDefaults { defaults in
            for raw in ["broken", "{}", "{\"version\":2,\"a\":\"file:///A.app\",\"b\":\"file:///B.app\"}", "{\"version\":1,\"a\":\"file:///A.app\",\"b\":\"file:///A.app\"}", "{\"version\":1,\"a\":\"https://example.com/A.app\",\"b\":\"file:///B.app\"}", "{\"version\":1,\"a\":\"relative.app\",\"b\":\"file:///B.app\"}"] {
                let data = Data(raw.utf8)
                defaults.set(data, forKey: "workPairV1")
                XCTAssertNil(PairStore(defaults: defaults).pair)
                XCTAssertEqual(defaults.data(forKey: "workPairV1"), data)
            }
        }
    }
    func testMovedBundleIsNotIdentifierMatch() {
        withDefaults { defaults in
            let store = PairStore(defaults: defaults)
            XCTAssertTrue(store.register(a: a, b: b, records: records(), frontmost: nil))
            store.observe(.bundleURL(URL(fileURLWithPath: "/Moved/A.app")))
            store.observe(.bundleIdentifier("same.identifier"))
            XCTAssertNil(store.lastUsed)
            let moved = AppRecord(id: .bundleURL(URL(fileURLWithPath: "/Moved/A.app")), name: "A", icon: nil, instances: records()[0].instances)
            XCTAssertFalse(store.register(a: a, b: b, records: [moved] + records().filter { $0.id != a }, frontmost: nil))
        }
    }
    func testObserveOnlyPairAndResetOnChange() {
        withDefaults { defaults in
            let store = PairStore(defaults: defaults)
            XCTAssertTrue(store.register(a: a, b: b, records: records(), frontmost: c))
            XCTAssertNil(store.lastUsed)
            store.observe(a)
            XCTAssertEqual(store.lastUsed, a)
            store.observe(nil)
            store.observe(c)
            XCTAssertEqual(store.lastUsed, a)
            store.observe(b)
            XCTAssertEqual(store.lastUsed, b)
            XCTAssertTrue(store.register(a: a, b: c, records: records(), frontmost: b))
            XCTAssertNil(store.lastUsed)
            store.observe(c)
            XCTAssertEqual(store.lastUsed, c)
            store.clear()
            XCTAssertNil(store.lastUsed)
        }
    }
}
