import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted tests never create UI or activate other applications.
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        coordinator = AppCoordinator()
        coordinator?.start()
    }
    func applicationWillTerminate(_ notification: Notification) { coordinator?.stop() }
}
