import XCTest
import Observation
@testable import EdgeAppSwitcher

@MainActor final class PairSettingsTests: XCTestCase {
    private func fixture(_ body: (PairStore, RunningAppStore, PairSettingsModel) -> Void) {
        let name = "PairSettingsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PairStore(defaults: defaults)
        let apps = RunningAppStore()
        apps.replace([rawApp(1, url: "/A.app"), rawApp(2, url: "/B.app"), rawApp(3, url: "/C.app")])
        let model = PairSettingsModel(store: store, records: { apps.records }, frontmost: { nil })
        body(store, apps, model)
    }
    private let a = AppID.bundleURL(URL(fileURLWithPath: "/A.app"))
    private let b = AppID.bundleURL(URL(fileURLWithPath: "/B.app"))
    private let c = AppID.bundleURL(URL(fileURLWithPath: "/C.app"))
    func testDraftCancelLeavesSavedPair() {
        fixture { store, apps, model in
            XCTAssertTrue(store.register(a: a, b: b, records: apps.records, frontmost: b))
            model.cancel(); model.draftB = c; model.cancel()
            XCTAssertEqual(model.draftB, b)
            XCTAssertEqual(store.lastUsed, b)
            XCTAssertEqual(store.pair?.b, URL(fileURLWithPath: "/B.app"))
        }
    }
    func testSaveRechecksTerminatedCandidate() {
        fixture { store, apps, model in
            model.draftA = a; model.draftB = b
            apps.replace([rawApp(1, url: "/A.app")])
            XCTAssertFalse(model.save())
            XCTAssertNil(store.pair)
            XCTAssertEqual(model.candidates().map(\.id), [a])
        }
    }
    func testChangeAndClearResetHistory() {
        fixture { store, apps, model in
            XCTAssertTrue(store.register(a: a, b: b, records: apps.records, frontmost: b))
            model.draftA = a; model.draftB = c
            XCTAssertTrue(model.save())
            XCTAssertNil(store.lastUsed)
            store.observe(c); model.clear()
            XCTAssertNil(store.pair); XCTAssertNil(store.lastUsed)
            XCTAssertNil(model.draftA); XCTAssertNil(model.draftB)
        }
    }
    func testCandidatesObserveSourceChangesWhileSettingsRemainOpen() {
        fixture { _, apps, model in
            let changed = XCTestExpectation(description: "candidate source changed")
            withObservationTracking {
                XCTAssertEqual(model.candidates().count, 3)
            } onChange: { changed.fulfill() }
            apps.replace([rawApp(1, url: "/A.app")])
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 0.1), .completed)
            XCTAssertEqual(model.candidates().map(\.id), [a])
        }
    }
}
