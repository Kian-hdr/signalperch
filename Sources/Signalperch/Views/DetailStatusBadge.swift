import SwiftUI

/// Text and symbols accompany color, including unfamiliar provider states.
struct DetailStatusBadge: View {
    let title: String
    let symbol: String
    let color: Color

    private init(title: String, symbol: String, color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    init(health: Health?) {
        switch health {
        case .operational: (title, symbol, color) = ("Operational", "checkmark.circle.fill", .green)
        case .maintenance: (title, symbol, color) = ("Maintenance", "wrench.adjustable", .blue)
        case .degraded: (title, symbol, color) = ("Issues", "exclamationmark.triangle.fill", .orange)
        case .outage: (title, symbol, color) = ("Outage", "xmark.circle.fill", .red)
        case nil: (title, symbol, color) = ("Unavailable", "questionmark.circle", .secondary)
        }
    }

    init(componentStatus: String) {
        switch componentStatus {
        case "operational": self.init(health: .operational)
        case "under_maintenance": self.init(health: .maintenance)
        case "degraded_performance": self.init(health: .degraded)
        case "partial_outage", "major_outage":
            self.init(title: componentStatus == "partial_outage" ? "Partial outage" : "Major outage", symbol: "xmark.circle.fill", color: .red)
        default:
            self.init(title: componentStatus.replacingOccurrences(of: "_", with: " ").capitalized, symbol: "questionmark.circle", color: .secondary)
        }
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.10), in: Capsule())
            .fixedSize()
    }
}
