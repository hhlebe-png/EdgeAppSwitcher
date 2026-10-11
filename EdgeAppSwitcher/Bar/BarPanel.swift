import AppKit
import SwiftUI

// Only keyboard focus produces a visual name; mouse emphasis stays in BarViewState.
@MainActor struct BarNameCallbacks {
    let hover: (String?, CGPoint) -> Void = { _, _ in }
    let focusName: (String, CGPoint) -> Void
    init(showKeyboardName: @escaping (String, CGPoint) -> Void) {
        focusName = showKeyboardName
    }
}

@MainActor final class BarPanel: NSPanel, BarPresentation {
    let viewState = BarViewState()
    var onSelectPair: ((AppID) -> Void)?
    var onSelect: ((AppID) -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?
    private var keyboardMode = false
    private var generation: UInt64 = 0
    private var motionTask: Task<Void, Never>?
    private var screenDescriptor: ScreenDescriptor?
    private var side: EdgeSide = .left
    private var tooltipWindow: NSWindow?

    var tooltipFrame: CGRect? {
        guard tooltipWindow?.isVisible == true else { return nil }
        return tooltipWindow?.frame
    }

    override var canBecomeKey: Bool { keyboardMode }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(accessibilityDisplayOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        let names = BarNameCallbacks(showKeyboardName: { [weak self] name, point in
            guard let self else { return }
            self.cancelTooltip()
            self.showLabel(name, at: CGPoint(x: self.frame.midX, y: self.frame.maxY - point.y))
        })
        contentView = FirstMouseHostingView(rootView: BarView(state: viewState, select: { [weak self] id in
            self?.onSelect?(id)
        }, hover: names.hover, focusName: names.focusName, selectPair: { [weak self] id in
            self?.onSelectPair?(id)
        }))
    }

    override func sendEvent(_ event: NSEvent) {
        // Dispatch before a SwiftUI button/scroll view can consume navigation keys.
        if event.type == .keyDown, onKeyDown?(event) == true { return }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }

    func prepare(screen: ScreenDescriptor, side: EdgeSide) {
        screenDescriptor = screen
        self.side = side
    }

    func present(rows: [BarRow], frame: CGRect, keyboardMode: Bool) {
        generation &+= 1
        motionTask?.cancel(); motionTask = nil
        cancelTooltip()
        self.keyboardMode = keyboardMode
        viewState.rows = rows
        viewState.message = nil
        viewState.presentationID &+= 1
        viewState.resetInteraction()
        viewState.motion.present(side: side,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            now: ProcessInfo.processInfo.systemUptime)
        setFrame(frame, display: true)
        ignoresMouseEvents = false
        // SwiftUI owns visual opacity; AppKit never starts a competing alpha animator.
        alphaValue = 1
        orderFrontRegardless()
        if keyboardMode { makeKey() }
        runMotion()
    }

    func update(rows: [BarRow]) { viewState.rows = rows }

    func updatePair(_ destination: PairDestination?) { viewState.pairDestination = destination }

    func setPairSelected(_ selected: Bool) {
        viewState.pairSelected = selected
        if selected { cancelTooltip() }
    }

    func setSelected(_ id: AppID?) {
        viewState.selectedID = id
        if id != nil { cancelTooltip() }
    }

    func showMessage(_ text: String) {
        viewState.message = text
        cancelTooltip()
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func dismiss() {
        generation &+= 1
        motionTask?.cancel(); motionTask = nil
        cancelTooltip()
        keyboardMode = false
        viewState.resetInteraction()
        // Clicks pass through immediately, including during the visual fade.
        ignoresMouseEvents = true
        let now = ProcessInfo.processInfo.systemUptime
        viewState.motion.setReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, now: now)
        viewState.motion.dismiss(now: now)
        runMotion()
    }

    // Selector observers are removed automatically when this panel is deallocated.
    // Hop to MainActor because notification delivery need not originate on the main thread.
    @objc nonisolated private func accessibilityDisplayOptionsChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.viewState.motion.setReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                                  now: ProcessInfo.processInfo.systemUptime)
            self.runMotion()
        }
    }

    private func runMotion() {
        motionTask?.cancel(); motionTask = nil
        guard viewState.motion.isAnimating else {
            if viewState.motion.phase == .hidden { orderOut(nil) }
            return
        }
        let presentation = generation
        let motion = viewState.motion.generation
        // This task exists only for the bounded transition; a new target cancels it.
        motionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == presentation,
                      self.viewState.motion.generation == motion else { return }
                if !self.viewState.motion.advance(now: ProcessInfo.processInfo.systemUptime, generation: motion) {
                    if self.viewState.motion.phase == .hidden { self.orderOut(nil) }
                    self.motionTask = nil
                    return
                }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
    }

    private func cancelTooltip() {
        tooltipWindow?.orderOut(nil)
    }

    private func showLabel(_ text: String, at point: CGPoint) {
        guard let screenDescriptor, isVisible, !ignoresMouseEvents else { return }
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        let width = min(240, max(80, label.intrinsicContentSize.width + 20))
        let bounds = BarTooltipState.frame(size: CGSize(width: width, height: 48),
            anchor: CGPoint(x: side == .left ? frame.maxX : frame.minX, y: point.y),
            side: side, visibleFrame: screenDescriptor.visibleFrame)
        let window: NSWindow
        if let existing = tooltipWindow { window = existing } else {
            window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.ignoresMouseEvents = true
            window.hasShadow = true
            window.backgroundColor = .windowBackgroundColor
            window.appearance = NSAppearance(named: .aqua)
            tooltipWindow = window
        }
        let content = NSView(frame: CGRect(origin: .zero, size: bounds.size))
        label.frame = content.bounds.insetBy(dx: 10, dy: 7)
        label.autoresizingMask = [.width, .height]
        content.addSubview(label)
        window.contentView = content
        window.setFrame(bounds, display: true)
        window.orderFrontRegardless()
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
