import AppKit

@MainActor final class AppCoordinator {
    private let settings: SettingsStore
    private let controller: BarController
    private let screens: () -> [ScreenDescriptor]
    private let pointer: () -> CGPoint
    private let tooltipFrame: () -> CGRect?
    private let startSources: () -> Void
    private let stopSources: () -> Void
    private let refreshSources: () -> Void
    private let observeActivation: (@escaping (InstanceToken) -> Void) -> Void
    private var focusFirst: () -> Void
    private var installMenu: () -> Void = {}
    private var stopUI: () -> Void = {}
    private var refreshMenu: () -> Void = {}
    private let workspaceCenter: NotificationCenter
    private let applicationCenter: NotificationCenter
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var trigger = EdgeTrigger()
    private var started = false
    private var generation: UInt64 = 0
    private let sampler: any PointerSampler
    private lazy var lifecycle = LifecycleController(settings: settings, sampler: sampler,
        closeAndReset: { [weak self] in self?.closeAndReset() },
        refreshSources: { [weak self] in self?.refreshSources() })

    init(settings: SettingsStore, sampler: any PointerSampler, controller: BarController,
         screens: @escaping () -> [ScreenDescriptor], pointer: @escaping () -> CGPoint,
         tooltipFrame: @escaping () -> CGRect?, startSources: @escaping () -> Void,
         stopSources: @escaping () -> Void, refreshSources: @escaping () -> Void,
         focusFirst: @escaping () -> Void,
         observeActivation: @escaping (@escaping (InstanceToken) -> Void) -> Void = { _ in },
         workspaceCenter: NotificationCenter, applicationCenter: NotificationCenter) {
        self.settings = settings; self.sampler = sampler; self.controller = controller
        self.screens = screens; self.pointer = pointer; self.tooltipFrame = tooltipFrame
        self.startSources = startSources; self.stopSources = stopSources; self.refreshSources = refreshSources
        self.observeActivation = observeActivation; self.focusFirst = focusFirst; self.workspaceCenter = workspaceCenter; self.applicationCenter = applicationCenter
    }

    convenience init() {
        let settings = SettingsStore(defaults: .standard)
        let pairStore = PairStore(defaults: .standard)
        let store = RunningAppStore(); let recency = RecencyStore(); let panel = BarPanel()
        let controller = BarController(store: store, recency: recency,
            activation: ActivationService(backend: WorkspaceActivationBackend()), presentation: panel, pairStore: pairStore)
        let source = WorkspaceAppSource(onAppsChanged: { apps in
            store.replace(apps); recency.reconcile(records: store.records); controller.refresh()
        }, onFrontmostChanged: { token in
            controller.observeFrontmost(token)
        })
        self.init(settings: settings, sampler: AppKitPointerSampler(), controller: controller,
            screens: { AppKitScreenSource.current() }, pointer: { NSEvent.mouseLocation },
            tooltipFrame: { panel.tooltipFrame }, startSources: { source.start() },
            stopSources: { source.stop() }, refreshSources: { source.refresh() }, focusFirst: {},
            observeActivation: { source.onActivationObserved = $0 },
            workspaceCenter: NSWorkspace.shared.notificationCenter, applicationCenter: .default)
        // Captured by the UI closures, the handler lives exactly as long as this coordinator.
        var keyboard: BarKeyboardHandler?
        let pairModel = PairSettingsModel(store: pairStore, records: { store.records }, frontmost: {
            guard let token = NSWorkspace.shared.frontmostApplication.map({ AppInstance(application: $0).token }) else { return nil }
            return store.records.first { $0.instances.contains { $0.token == token } }?.id
        })
        let menu = MenuController(settings: settings, onShow: { [weak self] in self?.showExplicitly() },
            onSettingsChanged: { [weak self] in self?.settingsChanged() },
            onQuit: { [weak self] in self?.stop(); NSApp.terminate(nil) }, pairModel: pairModel)
        installMenu = {
            keyboard = BarKeyboardHandler(panel: panel, controller: controller)
            panel.onSelect = { [weak controller] id in Task { await controller?.select(id) } }
            panel.onSelectPair = { [weak controller] id in Task { await controller?.selectPair(displayed: id) } }
            menu.install()
        }
        focusFirst = { keyboard?.focusFirst() }
        stopUI = { keyboard?.stop(); keyboard = nil; panel.onSelect = nil; panel.onSelectPair = nil; menu.stop() }
        refreshMenu = { menu.refresh() }
    }

    func start() {
        guard !started else { return }
        started = true; generation &+= 1
        controller.onHide = { [weak self] in self?.trigger.reset(requireExit: true) }
        lifecycle.onSample = { [weak self] point, buttons, time in self?.sample(point, buttons, time) }
        observeNotifications()
        let current = generation
        observeActivation { [weak self] token in
            guard let self, self.started, self.generation == current else { return }
            // A matching notification belongs to the pending selection's confirmation.
            // Unrelated external activation dismisses keyboard mode without restoring focus.
            if self.controller.keyboardMode, self.controller.selectionTarget != token {
                self.controller.hide()
            }
        }
        startSources(); installMenu(); lifecycle.start()
    }
    func stop() {
        guard started else { return }
        started = false; generation &+= 1
        lifecycle.stop(); lifecycle.onSample = nil
        observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll()
        stopSources(); stopUI(); controller.onHide = nil
    }
    func settingsChanged() {
        guard started else { return }
        lifecycle.handle(.settingsChanged); refreshMenu()
    }
    func showExplicitly() {
        guard started, lifecycle.canSample, !settings.isPaused else { return }
        let currentScreens = screens()
        guard let screen = ScreenGeometry.screen(at: pointer(), screens: currentScreens, previous: nil)
                ?? currentScreens.first(where: \.isPrimary) else { return }
        show(screen, keyboardMode: true)
        focusFirst()
    }
    private func closeAndReset() {
        controller.hide(); trigger.reset(requireExit: true)
    }
    private func show(_ screen: ScreenDescriptor, keyboardMode: Bool) {
        controller.show(screen: screen, side: settings.side, keyboardMode: keyboardMode)
        trigger.didShow(screen: screen.id, panelFrame: controller.frame,
            corridor: ScreenGeometry.corridor(screen: screen, side: settings.side, panelFrame: controller.frame), keyboardMode: keyboardMode)
    }
    private func sample(_ point: CGPoint, _ buttons: Int, _ time: Duration) {
        guard started, lifecycle.canSample else { return }
        let currentScreens = screens()
        trigger.setTooltipFrame(tooltipFrame())
        switch trigger.sample(TriggerSample(time: time, point: point, pressedButtons: buttons, screens: currentScreens, side: settings.side)) {
        case .none: break
        case .hide: controller.hide()
        case .show(let id):
            if let screen = currentScreens.first(where: { $0.id == id }) { show(screen, keyboardMode: false) }
        }
    }
    private func observeNotifications() {
        let names: [(Notification.Name, LifecycleEvent)] = [
            (NSWorkspace.willSleepNotification, .willSleep), (NSWorkspace.didWakeNotification, .didWake),
            (NSWorkspace.screensDidSleepNotification, .screensSleep), (NSWorkspace.screensDidWakeNotification, .screensWake),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionInactive), (NSWorkspace.sessionDidBecomeActiveNotification, .sessionActive),
            (NSWorkspace.activeSpaceDidChangeNotification, .spaceChanged)]
        for (name, event) in names { observe(name, event: event, center: workspaceCenter) }
        observe(NSApplication.didChangeScreenParametersNotification, event: .screensChanged, center: applicationCenter)
    }
    private func observe(_ name: Notification.Name, event: LifecycleEvent, center: NotificationCenter) {
        let current = generation
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.started, self.generation == current else { return }
                self.lifecycle.handle(event)
            }
        }
        observers.append((center, token))
    }
}
