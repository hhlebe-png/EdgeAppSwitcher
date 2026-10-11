import AppKit
import SwiftUI

@MainActor final class MenuController: NSObject, NSMenuDelegate {
    private let settings: SettingsStore
    private let pairModel: PairSettingsModel?
    private let onShow: () -> Void
    private let onSettingsChanged: () -> Void
    private let onQuit: () -> Void
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var showItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    init(settings: SettingsStore, onShow: @escaping () -> Void,
         onSettingsChanged: @escaping () -> Void, onQuit: @escaping () -> Void, pairModel: PairSettingsModel? = nil) {
        self.settings = settings; self.onShow = onShow; self.pairModel = pairModel
        self.onSettingsChanged = onSettingsChanged; self.onQuit = onQuit
        super.init()
    }
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: "アプリ切替バー")
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self
        showItem = add("切替バーを表示", action: #selector(showBar), to: menu)
        pauseItem = add("一時停止", action: #selector(togglePause), to: menu)
        _ = add("設定…", action: #selector(showSettings), to: menu)
        _ = add("終了", action: #selector(quit), to: menu)
        item.menu = menu; statusItem = item
        refresh()
    }
    func stop() {
        settingsWindow?.orderOut(nil); settingsWindow = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil; showItem = nil; pauseItem = nil
    }
    func menuWillOpen(_ menu: NSMenu) { refresh() }
    func refresh() {
        showItem?.isEnabled = !settings.isPaused
        showItem?.title = settings.isPaused ? "切替バーを表示（一時停止中）" : "切替バーを表示"
        pauseItem?.title = settings.isPaused ? "再開" : "一時停止"
        pauseItem?.state = settings.isPaused ? .on : .off
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item); return item
    }
    @objc private func showBar() { guard !settings.isPaused else { return }; onShow() }
    @objc private func togglePause() { settings.isPaused.toggle(); refresh(); onSettingsChanged() }
    @objc private func showSettings() {
        onSettingsChanged()
        pairModel?.cancel()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 380, height: 340),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "設定"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, onSettingsChanged: { [weak self] in
                self?.refresh(); self?.onSettingsChanged()
            }, pairModel: pairModel))
            window.center(); settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { onQuit() }
}
