import AppKit
import SwiftUI
import Observation

@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let store: MonitorStore
    private let item = NSStatusBar.system.statusItem(withLength: 36)
    private let badgeView = StatusBadgeView(frame: NSRect(x: 22, y: 4, width: 11, height: 11))
    private var panel: NSPanel?
    private let navigation = PopupNavigation()
    private var outsideClick: Any?
    private var localClick: Any?
    private var stopObserving = false

    init(store: MonitorStore) {
        self.store = store
        super.init()
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.setAccessibilityLabel("Signalperch")
        badgeView.imageScaling = .scaleProportionallyDown
        badgeView.setAccessibilityElement(false)
        item.button?.addSubview(badgeView)
        trackStatus()
    }
    private func trackStatus() {
        guard !stopObserving else { return }
        withObservationTracking {
            updateIndicator()
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackStatus() }
        }
    }
    private func updateIndicator() {
        let size = popupSize
        if let panel, panel.contentView?.frame.size != size {
            let top = panel.frame.maxY
            panel.setContentSize(size)
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
            positionPanel()
            panel.invalidateShadow()
        }
        let provider = store.primaryProvider
        let reading = provider.map { store.reading($0) }
        let unavailable = reading?.unavailable(at: store.now, maxAge: store.maxAge) ?? true
        let health = unavailable ? nil : reading?.snapshot?.health
        let logo = provider.flatMap { ServiceLogo.templateImage(for: $0) }
        let icon = NSImage(size: NSSize(width: 30, height: 18), flipped: false) { _ in
            if let logo {
                logo.draw(in: NSRect(x: 0, y: 1, width: 16, height: 16))
            } else {
                NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: nil)?
                    .draw(in: NSRect(x: 0, y: 1, width: 16, height: 16))
            }
            return true
        }
        icon.isTemplate = true
        item.button?.image = icon
        item.button?.imagePosition = .imageOnly
        item.button?.title = ""
        item.button?.toolTip = "Signalperch: \(store.menuTitle)"
        item.button?.setAccessibilityLabel("Signalperch: \(store.menuTitle)")
        badgeView.image = NSImage(systemSymbolName: Self.badgeSymbol(health), accessibilityDescription: nil)
        badgeView.image?.isTemplate = true
        badgeView.contentTintColor = Self.badgeColor(health)
        if let bounds = item.button?.bounds, bounds.height > 0 {
            badgeView.frame = NSRect(x: bounds.midX + 5, y: bounds.midY - 5.5, width: 11, height: 11)
        }
    }
    private static func badgeSymbol(_ health: Health?) -> String {
        switch health {
        case .operational: "checkmark.circle.fill"
        case .outage: "xmark.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .maintenance: "wrench.adjustable"
        default: "questionmark.circle"
        }
    }
    private static func badgeColor(_ health: Health?) -> NSColor {
        switch health {
        case .operational: .systemGreen
        case .outage: .systemRed
        case .degraded: .systemOrange
        case .maintenance: .systemBlue
        default: .secondaryLabelColor
        }
    }
    @objc private func togglePanel() {
        if panel?.isVisible == true { dismissPanel() } else { showPanel() }
    }
    func showPanel() {
        if let panel, panel.isVisible { panel.makeKeyAndOrderFront(nil); return }
        if panel == nil {
            let size = popupSize
            let inspect = ProcessInfo.processInfo.arguments.contains("--inspect-panel")
            let created = StatusPanelWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: inspect ? [.titled, .closable] : [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            created.title = "Signalperch Status"
            created.isOpaque = false
            created.hidesOnDeactivate = false
            created.backgroundColor = .clear
            created.hasShadow = true
            created.level = inspect ? .normal : .popUpMenu
            created.isReleasedWhenClosed = false
            created.collectionBehavior = ProcessInfo.processInfo.arguments.contains("--inspect-panel") ? [.moveToActiveSpace, .fullScreenAuxiliary] : [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
            created.contentView = GlassSurface.make(content: PopupContent(store: store, navigation: navigation, openDetails: { [weak self] provider in self?.showDetails(provider) }, openPreferences: { [weak self] in self?.showPreferences() }, goBack: { [weak self] in self?.showServices() }), size: size)
            panel = created
        }
        guard let panel else { return }
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        if ProcessInfo.processInfo.arguments.contains("--inspect-panel") { return }
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // Menu-bar clicks can arrive through the global monitor before the
            // status button's mouse-up action. Let that button own its toggle.
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self, !self.isStatusButtonClick(at: location) else { return }
                self.dismissPanel()
            }
        }
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if event.type == .keyDown && event.keyCode == 53 { self?.dismissPanel(); return nil }
            if event.type != .keyDown, event.window !== self?.panel, event.window !== self?.item.button?.window {
                let location = event.window?.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin ?? NSEvent.mouseLocation
                if self?.isStatusButtonClick(at: location) != true { self?.dismissPanel() }
            }
            return event
        }
    }
    private func isStatusButtonClick(at screenLocation: NSPoint) -> Bool {
        guard let button = item.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(screenLocation)
    }
    func dismissPanel() {
        panel?.orderOut(nil)
        if let outsideClick { NSEvent.removeMonitor(outsideClick); self.outsideClick = nil }
        if let localClick { NSEvent.removeMonitor(localClick); self.localClick = nil }
    }
    private var popupSize: NSSize {
        let height = item.button?.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        switch navigation.route {
        case .services: return NSSize(width: 380, height: min(store.popupHeight, height - 24))
        case .details: return NSSize(width: 660, height: min(740, height - 24))
        case .preferences: return NSSize(width: 490, height: min(740, height - 24))
        }
    }
    private func positionPanel() {
        guard let panel else { return }
        let display = item.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let anchor: NSRect
        if let button = item.button, let barWindow = button.window {
            anchor = barWindow.convertToScreen(button.convert(button.bounds, to: nil))
        } else {
            anchor = NSRect(x: display.maxX - 48, y: display.maxY, width: 36, height: 22)
        }
        let x = min(max(anchor.midX - panel.frame.width / 2, display.minX + 8), display.maxX - panel.frame.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: max(display.minY + 8, anchor.minY - panel.frame.height - 8)))
    }
    private func showServices() {
        navigation.route = .services
        updateIndicator()
    }
    func showPreferences() {
        navigation.route = .preferences
        updateIndicator()
        showPanel()
    }
    func showDetails(_ provider: Provider) {
        navigation.route = .details(provider)
        updateIndicator()
        showPanel()
    }
}

@MainActor
private final class StatusPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { ProcessInfo.processInfo.arguments.contains("--inspect-panel") }
}

@MainActor
private final class StatusBadgeView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
