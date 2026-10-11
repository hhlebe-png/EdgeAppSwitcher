import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let onSettingsChanged: () -> Void
    var pairModel: PairSettingsModel? = nil
    var body: some View {
        Form {
            Picker("表示側", selection: $settings.side) {
                Text("左").tag(EdgeSide.left)
                Text("右").tag(EdgeSide.right)
            }
            .pickerStyle(.segmented)
            Toggle("一時停止", isOn: $settings.isPaused)
            if let pairModel { PairSettingsView(model: pairModel, onSettingsChanged: onSettingsChanged) }
        }
        .padding(20)
        .frame(width: 340)
        .onChange(of: settings.side) { _, _ in onSettingsChanged() }
        .onChange(of: settings.isPaused) { _, _ in onSettingsChanged() }
    }
}
