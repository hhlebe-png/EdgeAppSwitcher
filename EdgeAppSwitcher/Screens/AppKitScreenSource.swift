import AppKit

enum AppKitScreenSource {
    static func current() -> [ScreenDescriptor] {
        let screens = NSScreen.screens
        let primaryScreen = screens.first
        return screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return ScreenDescriptor(
                id: number.uint32Value,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                isPrimary: screen === primaryScreen
            )
        }
    }
}
