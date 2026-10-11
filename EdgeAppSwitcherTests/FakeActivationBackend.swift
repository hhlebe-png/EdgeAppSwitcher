import Foundation
@testable import EdgeAppSwitcher

@MainActor final class FakeActivationBackend: ActivationBackend {
    var liveToken = InstanceToken(pid: 42, launchDate: Date(timeIntervalSince1970: 1))
    var originalAlive = true
    var eligible = true
    var waitedTarget: AppInstance?
    var hidden = false
    var unhideAccepted = true
    var frontmost = false
    var accepted = true
    var confirmation = false
    var suspend = false
    var continuation: CheckedContinuation<Bool, Never>?
    var events: [String] = []
    var lastTimeout: Duration?
    var requestCount: Int { events.filter { $0 == "request" }.count }
    func isAlive(_ target: AppInstance) -> Bool { originalAlive && target.token == liveToken }
    func isEligible(_ target: AppInstance) -> Bool { eligible }
    func isHidden(_ target: AppInstance) -> Bool { hidden }
    func unhide(_ target: AppInstance) -> Bool { events.append("unhide"); return unhideAccepted }
    func isFrontmost(_ target: AppInstance) -> Bool { isAlive(target) && frontmost }
    func yieldTo(_ target: AppInstance) { events.append("yield") }
    func request(_ target: AppInstance) -> Bool { events.append("request"); return accepted }
    func waitForFrontmost(_ target: AppInstance, timeout: Duration) async -> Bool {
        waitedTarget = target
        lastTimeout = timeout
        if suspend { return await withCheckedContinuation { continuation = $0 } }
        return confirmation
    }
}
