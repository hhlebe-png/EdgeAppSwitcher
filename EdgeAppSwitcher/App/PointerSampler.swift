import AppKit

@MainActor protocol PointerSampler: AnyObject {
    func start(interval: Duration, tolerance: Duration, handler: @escaping (CGPoint, Int, Duration) -> Void)
    func stop()
}

@MainActor final class AppKitPointerSampler: PointerSampler {
    private var timer: Timer?
    private var handler: ((CGPoint, Int, Duration) -> Void)?
    private var generation: UInt64 = 0
    private let clock = ContinuousClock()
    private let origin = ContinuousClock.now

    func start(interval: Duration, tolerance: Duration, handler: @escaping (CGPoint, Int, Duration) -> Void) {
        guard timer == nil else { return }
        generation &+= 1
        self.handler = handler
        let current = generation
        let timer = Timer(timeInterval: interval.secondsValue, repeats: true) { [weak self] _ in
            // This timer is installed exclusively on the main run loop.
            MainActor.assumeIsolated {
                guard let self, self.timer != nil, self.generation == current else { return }
                self.handler?(NSEvent.mouseLocation, Int(NSEvent.pressedMouseButtons), self.origin.duration(to: self.clock.now))
            }
        }
        timer.tolerance = tolerance.secondsValue
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stop() {
        generation &+= 1
        timer?.invalidate(); timer = nil; handler = nil
    }
}

private extension Duration {
    var secondsValue: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
