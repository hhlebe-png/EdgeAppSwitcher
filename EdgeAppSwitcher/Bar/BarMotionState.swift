import Foundation
import Observation

// One sampled visual presentation, retargeted from its current value rather than queued.
// It never owns a panel frame or a cell/tooltip hit region.
@MainActor @Observable final class BarMotionState {
    enum Phase { case hidden, appearing, shown, dismissing }
    private(set) var phase: Phase = .hidden
    private(set) var generation: UInt64 = 0
    private(set) var opacity: Double = 0
    private(set) var offsetX: CGFloat = 0
    private(set) var reduceMotion = false
    private var side: EdgeSide = .left
    private var startTime: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var startOpacity: Double = 0
    private var startOffset: CGFloat = 0
    private var targetOpacity: Double = 0
    private var targetOffset: CGFloat = 0

    var isAnimating: Bool { phase == .appearing || phase == .dismissing }

    func present(side: EdgeSide, reduceMotion: Bool, now: TimeInterval) {
        _ = advance(now: now, generation: generation)
        self.side = side
        self.reduceMotion = reduceMotion
        if phase == .hidden {
            opacity = 0
            offsetX = reduceMotion ? 0 : edgeOffset
        }
        retarget(phase: .appearing, opacity: 1, offset: 0, duration: 0.18, now: now)
    }

    func dismiss(now: TimeInterval) {
        _ = advance(now: now, generation: generation)
        guard phase != .hidden else { return }
        retarget(phase: .dismissing, opacity: 0, offset: edgeOffset, duration: 0.12, now: now)
    }

    func setReduceMotion(_ value: Bool, now: TimeInterval) {
        guard reduceMotion != value else { return }
        _ = advance(now: now, generation: generation)
        reduceMotion = value
        generation &+= 1
        if value {
            if phase == .dismissing || phase == .hidden { settleHidden() }
            else { phase = .shown; opacity = 1; offsetX = 0 }
        }
    }

    // False means no work remains for this token. Obsolete ticks cannot publish or hide.
    @discardableResult func advance(now: TimeInterval, generation token: UInt64) -> Bool {
        guard token == generation, isAnimating else { return false }
        let elapsed = max(0, now - startTime)
        if elapsed >= duration - 0.000000001 {
            if phase == .dismissing { settleHidden() }
            else { phase = .shown; opacity = 1; offsetX = 0 }
            return false
        }
        let progress = min(1, elapsed / duration)
        let eased = phase == .appearing
            ? progress * progress * (3 - 2 * progress)
            : 1 - pow(1 - progress, 3)
        opacity = startOpacity + (targetOpacity - startOpacity) * eased
        offsetX = startOffset + (targetOffset - startOffset) * eased
        return true
    }

    private var edgeOffset: CGFloat { side == .left ? -8 : 8 }
    private func retarget(phase: Phase, opacity: Double, offset: CGFloat,
                          duration: TimeInterval, now: TimeInterval) {
        generation &+= 1
        self.phase = phase
        startTime = now; self.duration = duration
        startOpacity = self.opacity; startOffset = offsetX
        targetOpacity = opacity; targetOffset = offset
        if reduceMotion {
            if phase == .dismissing { settleHidden() }
            else { self.phase = .shown; self.opacity = 1; offsetX = 0 }
        }
    }
    private func settleHidden() { phase = .hidden; opacity = 0; offsetX = 0 }
}

struct BarCellFeedback: Equatable {
    let offsetY: CGFloat
    let scale: CGFloat
    let isEmphasized: Bool
    let isSelected: Bool

    func pressing(_ isPressed: Bool, reduceMotion: Bool) -> BarCellFeedback {
        guard isPressed else { return self }
        return BarCellFeedback(offsetY: 0, scale: reduceMotion ? 1 : 0.97,
                               isEmphasized: true, isSelected: true)
    }
}
