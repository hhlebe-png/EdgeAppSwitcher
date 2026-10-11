import SwiftUI

struct PairCellPresentation {
    let destination: PairDestination
    var icon: NSImage? { destination.isEnabled ? destination.icon : nil }
    var accessibilityLabel: String { "作業ペア、\(destination.name)へ切り替え" }
    var accessibilityValue: String { destination.isEnabled ? "" : "未起動" }
    var opacity: Double { destination.isEnabled ? 1 : 0.35 }
}

struct PairCell: View {
    let destination: PairDestination
    let focused: Bool
    let selected: Bool
    let offsetX: CGFloat
    let reduceMotion: Bool
    let select: () -> Void
    @State private var hovered = false

    var body: some View {
        let display = PairCellPresentation(destination: destination)
        Button(action: select) {
            // Keep the hit plane stationary while its decoration follows bar motion.
            ZStack {
                Color.clear
                PairCellDecoration(display: display, focused: focused, selected: selected,
                                   hovered: hovered, reduceMotion: reduceMotion)
                    .offset(x: offsetX)
                    .allowsHitTesting(false)
            }
            .frame(width: 64, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PairCellButtonStyle())
        .disabled(!destination.isEnabled)
        .opacity(display.opacity)
        .accessibilityLabel(display.accessibilityLabel)
        .accessibilityValue(display.accessibilityValue)
        .onHover { hovered = $0 }
    }
}

private extension EnvironmentValues {
    @Entry var pairCellPressed = false
}

private struct PairCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.pairCellPressed, configuration.isPressed)
    }
}

private struct PairCellDecoration: View {
    let display: PairCellPresentation
    let focused: Bool
    let selected: Bool
    let hovered: Bool
    let reduceMotion: Bool
    @Environment(\.pairCellPressed) private var pressed

    var body: some View {
        let enabled = display.destination.isEnabled
        let chosen = enabled && (selected || pressed)
        let emphasized = enabled && (focused || hovered || chosen)
        let response = BarCellFeedback(
            offsetY: reduceMotion || chosen || !emphasized ? 0 : -2,
            scale: reduceMotion ? 1 : (chosen ? 0.97 : (emphasized ? 1.05 : 1)),
            isEmphasized: emphasized, isSelected: chosen)
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.accentColor.opacity(chosen ? 0.3 : (emphasized ? 0.2 : 0)))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(focused ? Color.primary : .clear, lineWidth: 2) }
                .padding(4)
            Group {
                if let icon = display.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app").resizable()
                }
            }
            .scaledToFit()
            .frame(width: 40, height: 40)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .padding(2)
                    .background(.regularMaterial, in: .rect(cornerRadius: 3))
                    .accessibilityHidden(true)
            }
            .scaleEffect(response.scale)
            .offset(y: response.offsetY)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: response)
    }
}
