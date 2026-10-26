import SwiftUI
import AppKit

struct ServiceLogo: View {
    let provider: Provider
    var size: CGFloat = 24

    @MainActor static func templateImage(for provider: Provider) -> NSImage? { ServiceLogoImages.image(for: provider.id) }

    var body: some View {
        Group {
            if let image = ServiceLogoImages.image(for: provider.id) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: provider.symbol)
                    .resizable()
                    .scaledToFit()
            }
        }
        // Every vector has tight, square optical bounds. A small common inset
        // matches the visual weight of native toolbar and menu bar symbols.
        .frame(width: size * 0.9, height: size * 0.9)
        .frame(width: size, height: size)
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }
}

@MainActor
private enum ServiceLogoImages {
    private static var images: [String: NSImage] = [:]

    static func image(for id: String) -> NSImage? {
        if let image = images[id] { return image }
        guard let url = Bundle.module.url(forResource: "\(id)-template", withExtension: "pdf", subdirectory: "Resources"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 24, height: 24)
        images[id] = image
        return image
    }
}

extension Health {
    var color: Color {
        switch self { case .operational: .green; case .maintenance: .blue; case .degraded: .orange; case .outage: .red }
    }
}
