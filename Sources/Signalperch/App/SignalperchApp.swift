import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = MonitorStore()
    private var statusBar: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBar = StatusBarController(store: store)
        installMenu()
        store.start()
        if ProcessInfo.processInfo.arguments.contains("--show-panel") {
            DispatchQueue.main.async { [weak self] in self?.statusBar?.showPanel() }
        }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--show-service"), ProcessInfo.processInfo.arguments.count > index + 1,
           let provider = Provider.all.first(where: { $0.id == ProcessInfo.processInfo.arguments[index + 1] }) {
            statusBar?.showDetails(provider)
        }
    }
    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Signalperch")
        let settings = NSMenuItem(title: "Settings…", action: #selector(showPreferences), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Signalperch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    @objc private func showPreferences() { statusBar?.showPreferences() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBar?.showPanel(); return true
    }
}
@main
@MainActor
enum SignalperchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
