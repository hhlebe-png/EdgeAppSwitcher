import AppKit

@MainActor protocol BarPresentation: AnyObject {
    func prepare(screen: ScreenDescriptor, side: EdgeSide)
    func present(rows: [BarRow], frame: CGRect, keyboardMode: Bool)
    func update(rows: [BarRow])
    func showMessage(_ text: String)
    func setSelected(_ id: AppID?)
    func updatePair(_ destination: PairDestination?)
    func setPairSelected(_ selected: Bool)
    func dismiss()
}

extension BarPresentation {
    func updatePair(_ destination: PairDestination?) {}
    func setPairSelected(_ selected: Bool) {}
    func prepare(screen: ScreenDescriptor, side: EdgeSide) {}
}

@MainActor final class BarController {
    let model = BarModel()
    private let pairStore: PairStore?
    private var displayedPair: AppPair?
    private let store: RunningAppStore
    private let recency: RecencyStore
    private let activation: ActivationService
    private let presentation: any BarPresentation
    private let isSelfFrontmost: @MainActor () -> Bool
    private let frontmost: @MainActor () -> AppInstance?
    private var originalFrontmost: AppInstance?
    private var generation: UInt64 = 0
    private var focusTask: Task<Void, Never>?
    private(set) var isVisible = false
    private(set) var isSelecting = false
    private(set) var selectionTarget: InstanceToken?
    private(set) var keyboardMode = false
    private(set) var frame: CGRect = .zero
    var onHide: (() -> Void)?

    init(store: RunningAppStore, recency: RecencyStore, activation: ActivationService,
         presentation: any BarPresentation, pairStore: PairStore? = nil,
         isSelfFrontmost: @escaping @MainActor () -> Bool = {
             NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
         },
         frontmost: @escaping @MainActor () -> AppInstance? = {
             NSWorkspace.shared.frontmostApplication.map { AppInstance(application: $0) }
         }) {
        self.pairStore = pairStore
        self.store = store; self.recency = recency; self.activation = activation
        self.presentation = presentation; self.frontmost = frontmost; self.isSelfFrontmost = isSelfFrontmost
    }

    func show(screen: ScreenDescriptor, side: EdgeSide, keyboardMode: Bool) {
        generation &+= 1
        focusTask?.cancel(); focusTask = nil
        activation.cancel()
        isSelecting = false
        selectionTarget = nil
        presentation.setSelected(nil)
        presentation.setPairSelected(false)
        // Repositioning an already open bar must preserve its snapshot and return target.
        if !isVisible {
            originalFrontmost = frontmost()
            model.open(records: store.records, orderedIDs: recency.orderedIDs(records: store.records))
        }
        self.keyboardMode = keyboardMode
        isVisible = true
        refresh()
        // Empty state needs one cell's height to keep its message legible.
        frame = ScreenGeometry.panelFrame(screen: screen, side: side, itemCount: max(1, model.rows.count),
            fixedHeight: displayedPair == nil ? 0 : 57)
        presentation.prepare(screen: screen, side: side)
        presentation.present(rows: model.rows, frame: frame, keyboardMode: keyboardMode)
    }

    func refresh() {
        guard isVisible else { return }
        let token = frontmost()?.token
        let frontID = store.records.first { record in record.instances.contains { $0.token == token } }?.id
        model.refresh(records: store.records, frontmost: frontID)
        presentation.update(rows: model.rows)
        displayedPair = pairStore?.pair
        presentation.updatePair(resolvePair())
    }

    func hide(returnFocus: Bool = false) {
        generation &+= 1
        activation.cancel()
        focusTask?.cancel(); focusTask = nil
        let target = originalFrontmost
        originalFrontmost = nil
        let wasVisible = isVisible
        isVisible = false; isSelecting = false; selectionTarget = nil; keyboardMode = false
        presentation.setSelected(nil)
        presentation.setPairSelected(false)
        model.close()
        presentation.dismiss()
        if wasVisible { onHide?() }
        if returnFocus, wasVisible, let target {
            let current = generation
            focusTask = Task { [weak self] in
                guard let self, self.generation == current, !Task.isCancelled else { return }
                _ = await self.activation.activate(target: target, yieldingFromSelf: self.isSelfFrontmost())
            }
        }
    }

    func observeFrontmost(_ token: InstanceToken?) {
        if let token { recency.recordActivation(token, records: store.records) }
        pairStore?.observe(appID(for: token))
        refresh()
    }

    private func appID(for token: InstanceToken?) -> AppID? {
        guard let token else { return nil }
        return store.records.first { $0.instances.contains { $0.token == token } }?.id
    }

    private func resolvePair() -> PairDestination? {
        let instance = keyboardMode ? originalFrontmost : frontmost()
        return PairResolver().destination(pair: pairStore?.pair, lastUsed: pairStore?.lastUsed,
            frontmost: appID(for: instance?.token), records: store.records)
    }

    func selectPair(displayed: AppID) async {
        guard isVisible, !isSelecting else { return }
        // Capture the rendered registration before refresh can replace its destination.
        let registration = displayedPair
        let destination = resolvePair()
        guard registration != nil, registration == pairStore?.pair,
              let destination, destination.id == displayed, destination.isEnabled,
              let target = store.resolve(displayed, preferred: recency.preferredInstance(for: displayed)) else {
            refresh()
            presentation.showMessage("切り替えできませんでした")
            return
        }
        await activateSelection(target: target, pairSelection: true, id: displayed)
    }

    func select(_ id: AppID) async {
        guard isVisible, !isSelecting else { return }
        refresh()
        guard model.rows.contains(where: { $0.id == id && $0.isEnabled }),
              let target = store.resolve(id, preferred: recency.preferredInstance(for: id)) else {
            presentation.showMessage("切り替えできませんでした")
            return
        }
        await activateSelection(target: target, pairSelection: false, id: id)
    }

    private func activateSelection(target: AppInstance, pairSelection: Bool, id: AppID) async {
        isSelecting = true
        selectionTarget = target.token
        presentation.setSelected(pairSelection ? nil : id)
        presentation.setPairSelected(pairSelection)
        let current = generation
        let result = await activation.activate(target: target, yieldingFromSelf: isSelfFrontmost())
        guard current == generation, isVisible else { return }
        isSelecting = false
        selectionTarget = nil
        presentation.setSelected(nil)
        presentation.setPairSelected(false)
        switch result {
        case .confirmed: hide()
        case .rejected: presentation.showMessage("切り替えできませんでした")
        case .timedOut: presentation.showMessage("OSが切替を完了しませんでした")
        case .cancelled: break
        }
    }
}
