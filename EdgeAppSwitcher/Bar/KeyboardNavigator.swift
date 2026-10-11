import AppKit

enum NavigationKey { case up, down, home, end }

enum BarFocusTarget: Equatable { case pair; case app(AppID) }

enum KeyboardNavigator {
    static func move(_ key: NavigationKey, rows: [BarRow], pairEnabled: Bool, current: BarFocusTarget?) -> BarFocusTarget? {
        let targets: [BarFocusTarget] = (pairEnabled ? [.pair] : []) + rows.filter(\.isEnabled).map { .app($0.id) }
        guard !targets.isEmpty else { return nil }
        switch key {
        case .home: return targets.first
        case .end: return targets.last
        case .up:
            guard let current, let index = targets.firstIndex(of: current) else { return targets.last }
            return targets[max(0, index - 1)]
        case .down:
            guard let current, let index = targets.firstIndex(of: current) else { return targets.first }
            return targets[min(targets.count - 1, index + 1)]
        }
    }
    static func move(_ key: NavigationKey, rows: [BarRow], current: AppID?) -> AppID? {
        let ids = rows.filter(\.isEnabled).map(\.id)
        guard !ids.isEmpty else { return nil }
        switch key {
        case .home: return ids.first
        case .end: return ids.last
        case .up:
            guard let current, let index = ids.firstIndex(of: current) else { return ids.last }
            return ids[max(0, index - 1)]
        case .down:
            guard let current, let index = ids.firstIndex(of: current) else { return ids.first }
            return ids[min(ids.count - 1, index + 1)]
        }
    }
}

// Retain alongside the single panel/controller; events remain local to the panel.
@MainActor final class BarKeyboardHandler {
    private weak var panel: BarPanel?
    private weak var controller: BarController?
    init(panel: BarPanel, controller: BarController) {
        self.panel = panel; self.controller = controller
        panel.onKeyDown = { [weak self] event in self?.handle(event) ?? false }
    }
    func focusFirst() {
        guard let panel, let controller, controller.isVisible, controller.keyboardMode else { return }
        panel.viewState.focusedTarget = KeyboardNavigator.move(.home, rows: controller.model.rows, pairEnabled: panel.viewState.pairDestination?.isEnabled == true, current: nil)
    }
    func stop() { panel?.onKeyDown = nil }
    private func handle(_ event: NSEvent) -> Bool {
        guard let panel, let controller, controller.isVisible, controller.keyboardMode,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let key: NavigationKey?
        switch event.keyCode {
        case 126: key = .up
        case 125: key = .down
        case 115: key = .home
        case 119: key = .end
        case 53: controller.hide(returnFocus: true); return true
        case 36, 76, 49:
            switch panel.viewState.focusedTarget {
            case .pair:
                if let destination = panel.viewState.pairDestination, destination.isEnabled {
                    let id = destination.id
                    Task { await controller.selectPair(displayed: id) }
                }
            case .app(let id): Task { await controller.select(id) }
            case nil: break
            }
            return true
        default: return false
        }
        controller.refresh()
        if let key { panel.viewState.focusedTarget = KeyboardNavigator.move(key, rows: controller.model.rows, pairEnabled: panel.viewState.pairDestination?.isEnabled == true, current: panel.viewState.focusedTarget) }
        return true
    }
}
