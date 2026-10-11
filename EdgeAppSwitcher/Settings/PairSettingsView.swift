import SwiftUI
import Observation

@MainActor @Observable final class PairSettingsModel {
    var draftA: AppID?
    var draftB: AppID?
    private let store: PairStore
    private let records: () -> [AppRecord]
    private let frontmost: () -> AppID?
    init(store: PairStore, records: @escaping () -> [AppRecord], frontmost: @escaping () -> AppID?) {
        self.store = store; self.records = records; self.frontmost = frontmost
        cancel()
    }
    func save() -> Bool {
        guard let a = draftA, let b = draftB else { return false }
        return store.register(a: a, b: b, records: records(), frontmost: frontmost())
    }
    func cancel() {
        draftA = store.pair.map { .bundleURL($0.a) }
        draftB = store.pair.map { .bundleURL($0.b) }
    }
    func clear() { store.clear(); cancel() }
    func candidates() -> [AppRecord] {
        records().filter { record in
            guard case .bundleURL(let url) = record.id else { return false }
            return record.instances.contains { $0.bundleURL?.standardizedFileURL == url && $0.runningApplication?.isTerminated != true }
        }
    }
}

struct PairSettingsView: View {
    @Bindable var model: PairSettingsModel
    let onSettingsChanged: () -> Void
    @State private var failed = false
    var body: some View {
        Section("作業ペア") {
            candidatePicker("アプリA", selection: $model.draftA)
            candidatePicker("アプリB", selection: $model.draftB)
            HStack {
                Button("保存") {
                    failed = !model.save()
                    if !failed { onSettingsChanged() }
                }
                Button("キャンセル") { model.cancel(); failed = false }
                Button("解除") { model.clear(); failed = false; onSettingsChanged() }
            }
            if failed { Text("起動中の異なるアプリを選択してください").font(.caption).foregroundStyle(.red) }
        }
    }
    private func candidatePicker(_ title: String, selection: Binding<AppID?>) -> some View {
        Picker(title, selection: selection) {
            Text("選択してください").tag(nil as AppID?)
            if let id = selection.wrappedValue, !model.candidates().contains(where: { $0.id == id }) {
                Text("未起動").tag(Optional(id))
            }
            ForEach(model.candidates(), id: \.id) { record in
                Text(record.name).tag(Optional(record.id))
            }
        }
    }
}
