import Foundation

enum ActivationResult: Equatable { case confirmed, rejected, timedOut, cancelled }

struct ActivationAttempt {
    let result: ActivationResult
    // nil means this attempt never issued an activation request.
    let requestAccepted: Bool?
}

@MainActor protocol ActivationBackend {
    func isAlive(_ target: AppInstance) -> Bool
    func isEligible(_ target: AppInstance) -> Bool
    func isHidden(_ target: AppInstance) -> Bool
    func unhide(_ target: AppInstance) -> Bool
    func isFrontmost(_ target: AppInstance) -> Bool
    func yieldTo(_ target: AppInstance)
    func request(_ target: AppInstance) -> Bool
    func waitForFrontmost(_ target: AppInstance, timeout: Duration) async -> Bool
}

@MainActor final class ActivationService {
    private let backend: any ActivationBackend
    private var generation: UInt64 = 0
    init(backend: any ActivationBackend) { self.backend = backend }
    func cancel() { generation &+= 1 }

    func activate(target: AppInstance, yieldingFromSelf: Bool) async -> ActivationResult {
        await activateWithEvidence(target: target, yieldingFromSelf: yieldingFromSelf).result
    }

    func activateWithEvidence(target: AppInstance, yieldingFromSelf: Bool) async -> ActivationAttempt {
        generation &+= 1
        let attempt = generation
        guard backend.isAlive(target), backend.isEligible(target) else {
            return ActivationAttempt(result: .rejected, requestAccepted: nil)
        }
        if backend.isHidden(target), !backend.unhide(target) {
            return ActivationAttempt(result: .rejected, requestAccepted: nil)
        }
        if backend.isFrontmost(target) { return ActivationAttempt(result: .confirmed, requestAccepted: nil) }
        if yieldingFromSelf { backend.yieldTo(target) }
        let accepted = backend.request(target)
        guard accepted else { return ActivationAttempt(result: .rejected, requestAccepted: false) }
        let confirmed = await backend.waitForFrontmost(target, timeout: .seconds(1))
        guard generation == attempt, !Task.isCancelled else {
            return ActivationAttempt(result: .cancelled, requestAccepted: true)
        }
        guard backend.isAlive(target), backend.isEligible(target) else {
            return ActivationAttempt(result: .rejected, requestAccepted: true)
        }
        return ActivationAttempt(result: confirmed ? .confirmed : .timedOut, requestAccepted: true)
    }
}
