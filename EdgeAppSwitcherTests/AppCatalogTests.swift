import XCTest
@testable import EdgeAppSwitcher

@MainActor final class AppCatalogTests: XCTestCase {
    func testFiltersAndGroupsRegularApps() {
        let store = RunningAppStore()
        store.replace([rawApp(1, url: "/Apps/A.app"), rawApp(2, url: "/Apps/../Apps/A.app"), rawApp(3, url: "/Other/A.app"), rawApp(4, bundle: "com.apple.finder", name: "Finder"), rawApp(5, selfApp: true), rawApp(6, regular: false), rawApp(7, terminated: true)])
        XCTAssertEqual(store.records.count, 3)
        XCTAssertEqual(store.records.first { $0.id == .bundleURL(URL(fileURLWithPath: "/Apps/A.app")) }?.instances.count, 2)
        XCTAssertTrue(store.records.contains { $0.name == "Finder" })
    }
    func testMissingMetadataUsesFallback() {
        let store = RunningAppStore()
        let unknown = rawApp(1)
        store.replace([unknown, rawApp(2, url: "/Apps/Example.app"), rawApp(3, bundle: "example.bundle")])
        XCTAssertEqual(store.records.first { $0.id == .instance(unknown.instance.token) }?.name, "名称不明のアプリ")
        XCTAssertEqual(store.records.first { $0.id == .bundleURL(URL(fileURLWithPath: "/Apps/Example.app")) }?.name, "Example")
        XCTAssertTrue(store.records.contains { $0.id == .bundleIdentifier("example.bundle") })
    }
    func testResolveUsesLatestSurvivingInstance() {
        let store = RunningAppStore()
        let old = rawApp(1, date: 1, url: "/A.app")
        let new = rawApp(2, date: 2, url: "/A.app")
        let id = AppID.bundleURL(URL(fileURLWithPath: "/A.app"))
        store.replace([old, new])
        XCTAssertEqual(store.resolve(id, preferred: nil)?.token, new.instance.token)
        XCTAssertEqual(store.resolve(id, preferred: old.instance.token)?.token, old.instance.token)
        store.replace([new])
        XCTAssertEqual(store.resolve(id, preferred: old.instance.token)?.token, new.instance.token)
        store.replace([])
        XCTAssertNil(store.resolve(id, preferred: new.instance.token))
    }
    func testMixedLaunchDatePermutationsHaveStableSelectionAndMetadata() {
        let apps = [rawApp(1, date: 1, bundle: "a", name: "Old"), rawApp(2, date: nil, bundle: "a", name: "Unknown"), rawApp(3, date: 3, bundle: "a", name: "Newest")]
        for indices in [[0,1,2], [0,2,1], [1,0,2], [1,2,0], [2,0,1], [2,1,0]] {
            let store = RunningAppStore()
            store.replace(indices.map { apps[$0] })
            XCTAssertEqual(store.records.first?.instances.map { $0.token.pid }, [3,1,2])
            XCTAssertEqual(store.records.first?.name, "Newest")
            XCTAssertEqual(store.resolve(.bundleIdentifier("a"), preferred: nil)?.token.pid, 3)
        }
    }
    func testLaunchDateTiesAndUnknownDatesUseAscendingPID() {
        let store = RunningAppStore()
        let id = AppID.bundleIdentifier("a")
        store.replace([rawApp(8, date: nil, bundle: "a"), rawApp(3, date: nil, bundle: "a")])
        XCTAssertEqual(store.resolve(id, preferred: nil)?.token.pid, 3)
        store.replace([rawApp(8, date: 2, bundle: "a"), rawApp(3, date: 2, bundle: "a")])
        XCTAssertEqual(store.resolve(id, preferred: nil)?.token.pid, 3)
    }
}
