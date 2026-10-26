import SwiftUI

struct MenuBarIndicator: View {
    let store: MonitorStore
    var body: some View {
        HStack(spacing: 4) {
            if let provider = store.primaryProvider,
               let health = store.reading(provider).snapshot?.health {
                ServiceLogo(provider: provider, size: 16)
                Image(systemName: symbol(for: health))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(store.reading(provider).unavailable(at: store.now, maxAge: store.maxAge) ? Color.secondary : health.color)
            } else {
                Image(systemName: store.unavailableCount > 0 ? "questionmark.circle" : "checkmark.circle")
                    .font(.system(size: 15, weight: .regular))
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signalperch: \(store.menuTitle)")
        .help("Signalperch: \(store.menuTitle). Click for all service statuses.")
    }
    private func symbol(for health: Health) -> String {
        switch health {
        case .operational: "checkmark.circle"
        case .maintenance: "wrench.adjustable"
        case .degraded: "exclamationmark.triangle.fill"
        case .outage: "xmark.circle.fill"
        }
    }
}
