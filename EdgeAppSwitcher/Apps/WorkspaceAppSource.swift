import AppKit

@MainActor final class WorkspaceAppSource {
    private let workspace: NSWorkspace
    private let onAppsChanged: ([RawApp]) -> Void
    private let onFrontmostChanged: (InstanceToken?) -> Void
    private var runningObservation: NSKeyValueObservation?
    private var policyObservations: [NSKeyValueObservation] = []
    private var notifications: [NSObjectProtocol] = []
    private var started = false
    private var generation: UInt64 = 0
    // Actual eligible external activation notifications only; refresh() never calls this.
    var onActivationObserved: ((InstanceToken) -> Void)?

    init(onAppsChanged: @escaping ([RawApp]) -> Void, onFrontmostChanged: @escaping (InstanceToken?) -> Void) {
        workspace = .shared
        self.onAppsChanged = onAppsChanged
        self.onFrontmostChanged = onFrontmostChanged
    }

    func start() {
        guard !started else { return }
        started = true
        generation &+= 1
        let current = generation
        runningObservation = workspace.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshIfStarted() }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            notifications.append(workspace.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshIfStarted() }
            })
        }
        notifications.append(workspace.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            // The main operation queue delivers these callbacks serially. Capture and
            // consume the payload here, before a later activation changes frontmost.
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard let self, self.started, self.generation == current else { return }
                let activated = self.rawApp(application)
                self.refreshCatalogue()
                self.deliverActivation(activated)
                if activated.isRegular, !activated.isTerminated, !activated.isSelf {
                    self.onActivationObserved?(activated.instance.token)
                }
            }
        })
        refresh()
    }

    func stop() {
        started = false
        generation &+= 1
        onActivationObserved = nil
        runningObservation?.invalidate()
        runningObservation = nil
        policyObservations.forEach { $0.invalidate() }
        policyObservations = []
        notifications.forEach { workspace.notificationCenter.removeObserver($0) }
        notifications = []
    }

    func refresh() {
        refreshCatalogue()
        let frontmost = workspace.frontmostApplication.map(rawApp)
        if let frontmost, frontmost.isRegular, !frontmost.isTerminated, !frontmost.isSelf {
            deliverActivation(frontmost)
        } else {
            onFrontmostChanged(nil)
        }
    }

    func deliverActivation(_ app: RawApp) {
        guard app.isRegular, !app.isTerminated, !app.isSelf else { return }
        onFrontmostChanged(app.instance.token)
    }

    private func rawApp(_ app: NSRunningApplication) -> RawApp {
        RawApp(instance: AppInstance(application: app), bundleIdentifier: app.bundleIdentifier, name: app.localizedName, icon: app.icon, isRegular: app.activationPolicy == .regular, isTerminated: app.isTerminated, isSelf: app.processIdentifier == ProcessInfo.processInfo.processIdentifier)
    }

    private func refreshCatalogue() {
        let applications = workspace.runningApplications
        policyObservations.forEach { $0.invalidate() }
        policyObservations = started ? applications.map { app in
            app.observe(\.activationPolicy, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refreshIfStarted() }
            }
        } : []
        onAppsChanged(applications.map(rawApp))
    }

    private func refreshIfStarted() {
        guard started else { return }
        refreshCatalogue()
    }
}
