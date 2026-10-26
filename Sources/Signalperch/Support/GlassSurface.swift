import AppKit
import SwiftUI

/// One shared native popup surface. The active backdrop cannot fade when the
/// nonactivating menu panel loses main-window status or SwiftUI content updates.
@MainActor
enum GlassSurface {
    static func make<Content: View>(content: Content, size: NSSize) -> NSView {
        let bounds = NSRect(origin: .zero, size: size)
        let hosting = PopupHostingView(rootView: content.environment(\.appearsActive, true))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]

        // Keep a native, explicitly active material behind the dynamic glass.
        // No custom color, alpha, appearance override, or OS setting is needed.
        let backdrop = NSVisualEffectView(frame: bounds)
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.autoresizingMask = [.width, .height]
        backdrop.wantsLayer = true
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true

        if #available(macOS 26, *) {
            backdrop.layer?.cornerRadius = 22
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .regular
            glass.cornerRadius = 22
            glass.autoresizingMask = [.width, .height]
            glass.contentView = hosting
            backdrop.addSubview(glass)
        } else {
            backdrop.layer?.cornerRadius = 18
            backdrop.addSubview(hosting)
        }
        return backdrop
    }
}

/// Render the changing foreground normally, outside AppKit's vibrancy blending.
@MainActor
private final class PopupHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { false }
}
