import AppKit

@MainActor final class WorkspaceActivationBackend: ActivationBackend {
    private let workspace: NSWorkspace
    init(workspace: NSWorkspace = .shared) { self.workspace = workspace }

    func isAlive(_ target: AppInstance) -> Bool {
        guard let application = target.runningApplication, !application.isTerminated,
              application.processIdentifier == target.token.pid else { return false }
        if let date = target.token.launchDate { return application.launchDate == date }
        return true
    }
    func isEligible(_ target: AppInstance) -> Bool {
        guard isAlive(target), let application = target.runningApplication else { return false }
        return application.activationPolicy == .regular && application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }
    func isHidden(_ target: AppInstance) -> Bool {
        guard isAlive(target), let application = target.runningApplication else { return false }
        return application.isHidden
    }
    func unhide(_ target: AppInstance) -> Bool {
        guard isEligible(target), let application = target.runningApplication else { return false }
        return application.unhide()
    }
    func isFrontmost(_ target: AppInstance) -> Bool {
        guard isAlive(target), let frontmost = workspace.frontmostApplication else { return false }
        return frontmost.processIdentifier == target.token.pid && frontmost.launchDate == target.token.launchDate
    }
    func yieldTo(_ target: AppInstance) {
        // Unhide may have changed frontmost state since the controller decided to yield.
        guard workspace.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
              isEligible(target), let application = target.runningApplication else { return }
        NSApp.yieldActivation(to: application)
    }
    func request(_ target: AppInstance) -> Bool {
        guard isEligible(target), let application = target.runningApplication else {
            return false
        }
        return application.activate(options: [])
    }
    func waitForFrontmost(_ target: AppInstance, timeout: Duration) async -> Bool {
        let waiter = FrontmostWaiter(backend: self, target: target, center: workspace.notificationCenter)
        return await waiter.wait(timeout: timeout)
    }
}

@MainActor private final class FrontmostWaiter {
    let backend: WorkspaceActivationBackend
    let target: AppInstance
    let center: NotificationCenter
    var observer: NSObjectProtocol?
    var timer: Task<Void, Never>?
    var continuation: CheckedContinuation<Bool, Never>?
    init(backend: WorkspaceActivationBackend, target: AppInstance, center: NotificationCenter) {
        self.backend = backend; self.target = target; self.center = center
    }
    func wait(timeout: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.backend.isFrontmost(self.target) else { return }
                    self.finish(true)
                }
            }
            // Recheck after observer registration: activation may have completed before waiting.
            if backend.isFrontmost(target) { finish(true); return }
            timer = Task { @MainActor [self] in
                do { try await Task.sleep(for: timeout) } catch { return }
                finish(backend.isFrontmost(target))
            }
        }
    }
    func finish(_ result: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        if let observer { center.removeObserver(observer); self.observer = nil }
        timer?.cancel(); timer = nil
        continuation.resume(returning: result)
    }
}
