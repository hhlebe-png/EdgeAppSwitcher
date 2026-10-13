import SwiftUI
import Observation

@MainActor @Observable final class BarViewState {
    var pairDestination: PairDestination?
    var pairSelected = false
    var rows: [BarRow] = []
    var message: String?
    var focusedTarget: BarFocusTarget?
    var focusedID: AppID? {
        get { if case .app(let id) = focusedTarget { return id }; return nil }
        set { focusedTarget = newValue.map(BarFocusTarget.app) }
    }
    var hoveredID: AppID?
    var selectedID: AppID?
    let motion = BarMotionState()
    var presentationID: UInt64 = 0

    func resetInteraction() { focusedID = nil; hoveredID = nil; selectedID = nil; pairSelected = false }
    func feedback(for row: BarRow) -> BarCellFeedback {
        let selected = row.isEnabled && selectedID == row.id
        let emphasized = row.isEnabled && (hoveredID == row.id || focusedID == row.id || selected)
        return BarCellFeedback(offsetY: motion.reduceMotion || selected || !emphasized ? 0 : -2,
                               scale: motion.reduceMotion ? 1 : (selected ? 0.97 : (emphasized ? 1.05 : 1)),
                               isEmphasized: emphasized, isSelected: selected)
    }
}

struct BarView: View {
    let state: BarViewState
    let select: (AppID) -> Void
    let hover: (String?, CGPoint) -> Void
    var focusName: (String, CGPoint) -> Void = { _, _ in }

    var selectPair: (AppID) -> Void = { _ in }

    var body: some View {
        let presentation = state.presentationID
        return GeometryReader { geometry in
            VStack(spacing: 0) {
                if let destination = state.pairDestination {
                    GeometryReader { pairGeometry in
                        PairCell(destination: destination, focused: state.focusedTarget == .pair, selected: state.pairSelected,
                                 offsetX: state.motion.offsetX, reduceMotion: state.motion.reduceMotion) {
                            guard state.presentationID == presentation else { return }
                            selectPair(destination.id)
                        }
                        .onChange(of: state.focusedTarget, initial: true) { _, target in
                            if target == .pair { showPairFocusName(destination, frame: pairGeometry.frame(in: .named("bar")), presentation: presentation) }
                        }
                        .onChange(of: destination.id) { _, _ in
                            showPairFocusName(destination, frame: pairGeometry.frame(in: .named("bar")), presentation: presentation)
                        }
                        .onChange(of: destination.name) { _, _ in
                            showPairFocusName(destination, frame: pairGeometry.frame(in: .named("bar")), presentation: presentation)
                        }
                        .onChange(of: pairGeometry.frame(in: .named("bar"))) { _, frame in
                            showPairFocusName(destination, frame: frame, presentation: presentation)
                        }
                    }
                    .frame(height: 56)
                    Color.primary.opacity(0.15)
                        .frame(height: 1)
                        .offset(x: state.motion.offsetX)
                        .allowsHitTesting(false)
                }
                appList(presentation: presentation)
                    .frame(height: max(0, geometry.size.height - (state.pairDestination == nil ? 0 : 57)))
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .id(state.presentationID)
        .coordinateSpace(.named("bar"))
        .background {
            RoundedRectangle(cornerRadius: 12).fill(.thinMaterial)
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.6), lineWidth: 1) }
                .offset(x: state.motion.offsetX)
                .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 12))
        .opacity(state.motion.opacity)
        .transaction { if state.motion.reduceMotion { $0.disablesAnimations = true } }
        .environment(\.colorScheme, .light)
        .accessibilityLabel("アプリ切替バー")
        .accessibilityValue(state.message ?? "")
    }

    private func showPairFocusName(_ destination: PairDestination, frame: CGRect, presentation: UInt64) {
        guard state.presentationID == presentation, state.focusedTarget == .pair,
              !state.pairSelected, state.selectedID == nil, state.message == nil else { return }
        focusName(destination.name, CGPoint(x: frame.midX, y: frame.midY))
    }

    private func appList(presentation: UInt64) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    if let message = state.message {
                        Text(message)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .frame(width: 56)
                            .padding(.vertical, 4)
                            .offset(x: state.motion.offsetX)
                            .id("message")
                    }
                    if state.rows.isEmpty {
                        Text("切替対象なし")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .frame(width: 64, height: 56)
                            .offset(x: state.motion.offsetX)
                    }
                    ForEach(state.rows) { row in
                        BarCell(row: row, focused: state.focusedID == row.id,
                                feedback: state.feedback(for: row), offsetX: state.motion.offsetX,
                                reduceMotion: state.motion.reduceMotion,
                                select: {
                                    guard state.presentationID == presentation else { return }
                                    select(row.id)
                                }, hover: { name, point in
                                    guard state.presentationID == presentation else { return }
                                    if name != nil { state.hoveredID = row.id }
                                    else if state.hoveredID == row.id { state.hoveredID = nil }
                                    hover(name, point)
                                }, focusName: { name, point in
                                    guard state.presentationID == presentation,
                                          state.focusedID == row.id, state.selectedID == nil,
                                          state.message == nil else { return }
                                    focusName(name, point)
                                })
                            .id(row.id)
                    }
                }
                .padding(.vertical, 8)
            }
            // .hidden can retain a legacy scroller gutter and clip our 64pt cells.
            .scrollIndicators(.never)
            .onChange(of: state.message) { _, message in
                if message != nil { proxy.scrollTo("message", anchor: .top) }
            }
            .onChange(of: state.focusedID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

private struct BarCell: View {
    let row: BarRow
    let focused: Bool
    let feedback: BarCellFeedback
    let offsetX: CGFloat
    let reduceMotion: Bool
    let select: () -> Void
    let hover: (String?, CGPoint) -> Void
    let focusName: (String, CGPoint) -> Void

    var body: some View {
        GeometryReader { geometry in
            Button(action: select) {
                ZStack {
                    // A stationary hit plane; only its decoration moves.
                    Color.clear
                    BarCellDecoration(row: row, focused: focused, feedback: feedback,
                                      reduceMotion: reduceMotion)
                        .offset(x: offsetX)
                        .allowsHitTesting(false)
                }
                // The button and its named geometry never receive a transform.
                .frame(width: 64, height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(BarCellButtonStyle())
            .disabled(!row.isEnabled)
            .opacity(row.isEnabled ? 1 : 0.35)
            .accessibilityLabel("\(row.name)、切り替え")
            .accessibilityValue(row.isFrontmost ? "前面" : (row.isEnabled ? "" : "終了"))
            .onChange(of: focused, initial: true) { _, focused in
                if focused {
                    let frame = geometry.frame(in: .named("bar"))
                    focusName(row.name, CGPoint(x: frame.midX, y: frame.midY))
                }
            }
            .onChange(of: geometry.frame(in: .named("bar"))) { _, frame in
                if focused { focusName(row.name, CGPoint(x: frame.midX, y: frame.midY)) }
            }
            .onHover { inside in
                let frame = geometry.frame(in: .named("bar"))
                hover(inside ? row.name : nil, CGPoint(x: frame.midX, y: frame.midY))
            }
        }
        .frame(width: 64, height: 56)
    }
}

private extension EnvironmentValues {
    @Entry var barCellPressed = false
}

private struct BarCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Native mouse-down feedback and pending keyboard/mouse selection share decoration.
        configuration.label.environment(\.barCellPressed, configuration.isPressed)
    }
}

private struct BarCellDecoration: View {
    let row: BarRow
    let focused: Bool
    let feedback: BarCellFeedback
    let reduceMotion: Bool
    @Environment(\.barCellPressed) private var isPressed

    var body: some View {
        let response = feedback.pressing(isPressed, reduceMotion: reduceMotion)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.accentColor.opacity(response.isSelected ? 0.3 : (response.isEmphasized ? 0.2 : 0)))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(focused ? Color.primary : .clear, lineWidth: 2) }
                .padding(4)
            Group {
                if let icon = row.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app").resizable()
                }
            }
            .scaledToFit()
            .frame(width: 40, height: 40)
            .scaleEffect(response.scale)
            .offset(y: response.offsetY)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if row.isFrontmost {
                Circle().fill(Color.primary.opacity(0.7)).frame(width: 4, height: 4).padding(.leading, 3)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: response)
    }
}
