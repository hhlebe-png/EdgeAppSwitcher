import AppKit
import XCTest
@testable import EdgeAppSwitcher

final class PairResolverTests: XCTestCase {
    private let aURL = URL(fileURLWithPath: "/Applications/Alpha.app")
    private let bURL = URL(fileURLWithPath: "/Applications/Beta.app")
    private var a: AppID { .bundleURL(aURL) }
    private var b: AppID { .bundleURL(bURL) }
    private var pair: AppPair { AppPair(a: aURL, b: bURL) }
    private func record(_ url: URL, pid: Int32 = 1, instances: [AppInstance]? = nil) -> AppRecord {
        AppRecord(id: .bundleURL(url), name: "Running " + url.deletingPathExtension().lastPathComponent,
                  icon: NSImage(size: NSSize(width: 16, height: 16)),
                  instances: instances ?? [AppInstance(token: InstanceToken(pid: pid, launchDate: Date(timeIntervalSince1970: Double(pid))), bundleURL: url)])
    }
    func testAlternatesAndReturnsLastSide() {
        let resolver = PairResolver()
        let records = [record(aURL), record(bURL, pid: 2)]
        let c = AppID.bundleURL(URL(fileURLWithPath: "/Third.app"))
        for (frontmost, lastUsed, expected) in [(a as AppID?, nil as AppID?, b), (b, nil, a), (c, b, b), (c, nil, a), (nil, b, b), (nil, nil, a), (c, c, a)] {
            let destination = resolver.destination(pair: pair, lastUsed: lastUsed, frontmost: frontmost, records: records)
            XCTAssertEqual(destination?.id, expected)
            XCTAssertEqual(destination?.isEnabled, true)
            XCTAssertEqual(destination?.name, expected == a ? "Running Alpha" : "Running Beta")
            XCTAssertNotNil(destination?.icon)
        }
    }
    func testUnavailableDestinationNeverFallsBack() {
        let resolver = PairResolver()
        for records in [[record(aURL)], [record(aURL), record(bURL, instances: [])]] {
            let destination = resolver.destination(pair: pair, lastUsed: a, frontmost: a, records: records)
            XCTAssertEqual(destination?.id, b)
            XCTAssertEqual(destination?.isEnabled, false)
            XCTAssertEqual(destination?.name, "Beta")
            XCTAssertNil(destination?.icon)
        }
    }
    func testRestartUsesBundleURLNotOldPID() {
        let resolver = PairResolver()
        let restarted = record(bURL, pid: 999)
        XCTAssertEqual(resolver.destination(pair: pair, lastUsed: nil, frontmost: a, records: [restarted])?.isEnabled, true)
        let moved = record(URL(fileURLWithPath: "/Other/Beta.app"), pid: 999)
        let identifier = AppRecord(id: .bundleIdentifier("same.identifier"), name: "Beta", icon: nil, instances: moved.instances)
        XCTAssertEqual(resolver.destination(pair: pair, lastUsed: nil, frontmost: a, records: [moved, identifier])?.isEnabled, false)
        let mismatched = record(bURL, instances: moved.instances)
        XCTAssertEqual(resolver.destination(pair: pair, lastUsed: nil, frontmost: a, records: [mismatched])?.isEnabled, false)
    }
    func testEndedInstanceIsUnavailableAndLiveSiblingEnablesDestination() {
        let ended = InstanceToken(pid: 4, launchDate: nil)
        let resolver = PairResolver(isLiveInstance: { $0.token != ended })
        let stale = AppInstance(token: ended, bundleURL: bURL)
        let live = AppInstance(token: InstanceToken(pid: 5, launchDate: nil), bundleURL: bURL)
        let disabled = resolver.destination(pair: pair, lastUsed: nil, frontmost: a, records: [record(bURL, instances: [stale])])
        XCTAssertEqual(disabled?.isEnabled, false)
        XCTAssertEqual(disabled?.name, "Beta")
        XCTAssertNil(disabled?.icon)
        XCTAssertEqual(resolver.destination(pair: pair, lastUsed: nil, frontmost: a, records: [record(bURL, instances: [stale, live])])?.isEnabled, true)
    }
    func testUnregisteredReturnsNil() {
        XCTAssertNil(PairResolver().destination(pair: nil, lastUsed: b, frontmost: a, records: [record(aURL), record(bURL)]))
    }
}
