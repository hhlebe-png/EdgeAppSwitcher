import XCTest
import AppKit
@testable import EdgeAppSwitcher

@MainActor final class ActivationServiceTests: XCTestCase {
    func target(_ backend: FakeActivationBackend) -> AppInstance { AppInstance(token: backend.liveToken, bundleURL: nil) }
    func testTrueWithoutConfirmationTimesOut() async {
        let backend = FakeActivationBackend()
        let result = await ActivationService(backend: backend).activate(target: target(backend), yieldingFromSelf: false)
        XCTAssertEqual(result, .timedOut)
        XCTAssertEqual(backend.requestCount, 1)
        XCTAssertEqual(backend.lastTimeout, .seconds(1))
    }
    func testRejectsDeadOrReusedPID() async {
        let backend = FakeActivationBackend()
        let stale = AppInstance(token: InstanceToken(pid: 42, launchDate: Date(timeIntervalSince1970: 0)), bundleURL: nil)
        let result = await ActivationService(backend: backend).activate(target: stale, yieldingFromSelf: false)
        XCTAssertEqual(result, .rejected)
        XCTAssertEqual(backend.requestCount, 0)
    }
    func testCancelIgnoresLateConfirmation() async {
        let backend = FakeActivationBackend(); backend.suspend = true
        let service = ActivationService(backend: backend)
        let task = Task { await service.activate(target: target(backend), yieldingFromSelf: false) }
        while backend.continuation == nil { await Task.yield() }
        service.cancel()
        backend.continuation?.resume(returning: true)
        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }
    func testAlreadyFrontmostDoesNotRequest() async {
        let backend = FakeActivationBackend(); backend.frontmost = true
        let result = await ActivationService(backend: backend).activate(target: target(backend), yieldingFromSelf: false)
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(backend.requestCount, 0)
    }
    func testYieldPrecedesRequestOnlyWhenRequested() async {
        for yield in [false, true] {
            let backend = FakeActivationBackend(); backend.confirmation = true
            _ = await ActivationService(backend: backend).activate(target: target(backend), yieldingFromSelf: yield)
            XCTAssertEqual(backend.events, yield ? ["yield", "request"] : ["request"])
        }
    }
    func testRejectedRequestDoesNotWait() async {
        let backend = FakeActivationBackend(); backend.accepted = false
        let result = await ActivationService(backend: backend).activate(target: target(backend), yieldingFromSelf: false)
        XCTAssertEqual(result, .rejected)
        XCTAssertNil(backend.lastTimeout)
    }
    func testHiddenApplicationUnhidesBeforeActivation() async {
        let backend = FakeActivationBackend(); backend.hidden = true; backend.confirmation = true
        let result = await ActivationService(backend: backend).activate(target: target(backend), yieldingFromSelf: false)
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(backend.events, ["unhide", "request"])
        XCTAssertEqual(backend.lastTimeout, .seconds(1))
    }
    func testUnhideFailureRejectsWithoutRequest() async {
        let backend = FakeActivationBackend(); backend.hidden = true; backend.unhideAccepted = false
        let result = await ActivationService(backend: backend).activate(target: target(backend), yieldingFromSelf: true)
        XCTAssertEqual(result, .rejected)
        XCTAssertEqual(backend.events, ["unhide"])
        XCTAssertNil(backend.lastTimeout)
    }
    func testAlreadyFrontmostHiddenApplicationStillUnhides() async {
        let backend = FakeActivationBackend(); backend.hidden = true; backend.frontmost = true
        let result = await ActivationService(backend: backend).activate(target: target(backend), yieldingFromSelf: true)
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(backend.events, ["unhide"])
        XCTAssertNil(backend.lastTimeout)
    }
    func testVisibleApplicationDoesNotUnhide() async {
        let backend = FakeActivationBackend(); backend.confirmation = true
        let result = await ActivationService(backend: backend).activate(target: target(backend), yieldingFromSelf: false)
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(backend.events, ["request"])
    }
    func testDeadApplicationDoesNotUnhide() async {
        let backend = FakeActivationBackend(); backend.hidden = true
        let stale = AppInstance(token: InstanceToken(pid: 42, launchDate: Date(timeIntervalSince1970: 0)), bundleURL: nil)
        let result = await ActivationService(backend: backend).activate(target: stale, yieldingFromSelf: true)
        XCTAssertEqual(result, .rejected)
        XCTAssertEqual(backend.events, [])
        XCTAssertNil(backend.lastTimeout)
    }

    func testUnknownLaunchDateDeathAndPIDReuseCannotConfirmOriginal() async {
        let backend = FakeActivationBackend()
        backend.liveToken = InstanceToken(pid: 42, launchDate: nil)
        backend.suspend = true
        let selected = target(backend)
        let service = ActivationService(backend: backend)
        let task = Task { await service.activate(target: selected, yieldingFromSelf: false) }
        while backend.continuation == nil { await Task.yield() }
        // A replacement can have the same token while the retained original is dead.
        backend.originalAlive = false
        backend.frontmost = true
        backend.continuation?.resume(returning: true)
        let result = await task.value
        XCTAssertEqual(result, .rejected)
    }
    func testIneligibleApplicationRejectsWithoutActions() async {
        let backend = FakeActivationBackend(); backend.eligible = false; backend.hidden = true
        let result = await ActivationService(backend: backend).activate(target: target(backend), yieldingFromSelf: true)
        XCTAssertEqual(result, .rejected)
        XCTAssertEqual(backend.events, [])
        XCTAssertNil(backend.lastTimeout)
    }

    func testRequestEvidenceIsLocalToEachAttempt() async {
        let backend = FakeActivationBackend(); backend.confirmation = true
        let service = ActivationService(backend: backend)
        let first = await service.activateWithEvidence(target: target(backend), yieldingFromSelf: false)
        XCTAssertEqual(first.requestAccepted, true)
        backend.frontmost = true
        let next = await service.activateWithEvidence(target: target(backend), yieldingFromSelf: false)
        XCTAssertEqual(next.result, .confirmed)
        XCTAssertNil(next.requestAccepted)
        backend.frontmost = false; backend.hidden = true; backend.unhideAccepted = false
        let rejected = await service.activateWithEvidence(target: target(backend), yieldingFromSelf: false)
        XCTAssertEqual(rejected.result, .rejected)
        XCTAssertNil(rejected.requestAccepted)
    }
    func testOverlappingAttemptsKeepTheirOwnRequestEvidence() async {
        let backend = FakeActivationBackend(); backend.suspend = true
        let service = ActivationService(backend: backend)
        let selected = target(backend)
        let first = Task { await service.activateWithEvidence(target: selected, yieldingFromSelf: false) }
        while backend.continuation == nil { await Task.yield() }
        backend.accepted = false
        let second = await service.activateWithEvidence(target: selected, yieldingFromSelf: false)
        backend.continuation?.resume(returning: true)
        let previous = await first.value
        XCTAssertEqual(previous.result, .cancelled)
        XCTAssertEqual(previous.requestAccepted, true)
        XCTAssertEqual(second.result, .rejected)
        XCTAssertEqual(second.requestAccepted, false)
    }
    func testConcreteBackendRejectsSelfAsEligibleTarget() {
        let backend = WorkspaceActivationBackend()
        XCTAssertFalse(backend.isEligible(AppInstance(application: .current)))
    }

    func testConcreteConfirmationRejectsMissingOriginalWithUnknownDate() {
        let backend = WorkspaceActivationBackend()
        let missingOriginal = AppInstance(token: InstanceToken(pid: ProcessInfo.processInfo.processIdentifier, launchDate: nil), bundleURL: nil)
        XCTAssertFalse(backend.isFrontmost(missingOriginal))
    }

}
