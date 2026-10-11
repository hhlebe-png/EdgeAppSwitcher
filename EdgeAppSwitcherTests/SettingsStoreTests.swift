import XCTest
@testable import EdgeAppSwitcher

@MainActor final class SettingsStoreTests: XCTestCase {
    func testDefaultsAndPersistence() {
        let domain = "Task6Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.side, .left)
        XCTAssertFalse(settings.isPaused)
        settings.side = .right
        settings.isPaused = true
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.side, .right)
        XCTAssertTrue(restored.isPaused)
        defaults.set("invalid", forKey: "edgeSide")
        XCTAssertEqual(SettingsStore(defaults: defaults).side, .left)
    }
}
