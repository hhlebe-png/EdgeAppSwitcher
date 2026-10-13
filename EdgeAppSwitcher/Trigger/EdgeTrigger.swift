import Foundation

struct TriggerSample {
    let time: Duration
    let point: CGPoint
    let pressedButtons: Int
    let screens: [ScreenDescriptor]
    let side: EdgeSide
}

enum TriggerAction: Equatable {
    case none
    case show(ScreenID)
    case hide
}

/// All elapsed time comes from samples; no timer or operating-system state is read here.
struct EdgeTrigger {
    private struct Candidate {
        let screen: ScreenID
        let side: EdgeSide
        let start: Duration
    }
    private struct Display {
        let screen: ScreenID
        let panelFrame: CGRect
        let corridor: CGRect
        let keyboardMode: Bool
    }
    private var requiresExit = true
    private var previousScreen: ScreenID?
    private var lastTime: Duration?
    private var candidate: Candidate?
    private var display: Display?
    private var tooltipFrame: CGRect?
    private var exitStart: Duration?
    private var insidePress = false
    private var previousButtons = 0

    mutating func reset(requireExit: Bool) {
        self = EdgeTrigger()
        requiresExit = requireExit
    }

    mutating func didShow(screen: ScreenID, panelFrame: CGRect, corridor: CGRect, keyboardMode: Bool) {
        candidate = nil
        display = Display(screen: screen, panelFrame: panelFrame, corridor: corridor, keyboardMode: keyboardMode)
        tooltipFrame = nil
        exitStart = nil
        insidePress = false
        previousButtons = 0
        requiresExit = true
        previousScreen = screen
    }

    // Pending activation owns the visible interaction until it completes.
    mutating func deferExit() { exitStart = nil }

    mutating func setTooltipFrame(_ frame: CGRect?) {
        tooltipFrame = frame
    }

    mutating func sample(_ input: TriggerSample) -> TriggerAction {
        guard input.time >= .zero, lastTime.map({ input.time >= $0 }) ?? true else {
            reset(requireExit: true)
            return .none
        }
        let delayed = lastTime.map { input.time - $0 > .milliseconds(500) } ?? false
        lastTime = input.time

        if let display {
            guard !display.keyboardMode else { return .none }
            let insidePanel = display.panelFrame.contains(input.point)
            if input.pressedButtons != 0, previousButtons == 0, insidePanel { insidePress = true }
            previousButtons = input.pressedButtons
            if input.pressedButtons == 0 { insidePress = false }
            if insidePress || insidePanel || display.corridor.contains(input.point) || tooltipFrame?.contains(input.point) == true {
                exitStart = nil
            } else {
                if exitStart == nil || delayed { exitStart = input.time }
                if let exitStart, input.time - exitStart >= .milliseconds(300) {
                    reset(requireExit: true)
                    return .hide
                }
            }
            return .none
        }

        let screen = ScreenGeometry.screen(at: input.point, screens: input.screens, previous: previousScreen)
        previousScreen = screen?.id
        guard let screen else { candidate = nil; return .none }
        if requiresExit {
            let distance = input.side == .left ? input.point.x - screen.frame.minX : screen.frame.maxX - input.point.x
            if distance >= 12 { requiresExit = false }
            candidate = nil
            return .none
        }
        guard input.pressedButtons == 0,
              ScreenGeometry.triggerRegion(screen: screen, side: input.side)?.contains(input.point) == true else {
            candidate = nil
            return .none
        }
        if delayed || candidate?.screen != screen.id || candidate?.side != input.side {
            candidate = Candidate(screen: screen.id, side: input.side, start: input.time)
            return .none
        }
        if let candidate, input.time - candidate.start >= .milliseconds(250) {
            self.candidate = nil
            requiresExit = true
            return .show(screen.id)
        }
        return .none
    }
}
