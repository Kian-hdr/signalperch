import SwiftUI

struct StatusDashboard: View {
    let snapshot: Snapshot?
    let health: Health?
    let uptime: [String: ComponentUptime]
    let interval: Int
    let incidents: [Incident]
    let activeIncidents: [Incident]
    let loading: Bool
    let historyAvailable: Bool
    let showIncidents: () -> Void
    let showComponent: (String) -> Void

    private var components: [Component] {
        (snapshot?.components ?? []).filter { $0.group != true }
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
    }
    private var badge: DetailStatusBadge { DetailStatusBadge(health: health) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: badge.symbol).font(.system(size: 26)).foregroundStyle(badge.color)
                        .frame(width: 50, height: 50).background(badge.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(health == .operational ? "All systems operational" : health == nil ? "Status unavailable" : "Some systems are affected")
                            .font(.title2.weight(.semibold))
                        Text(health == nil ? "Waiting for a fresh provider check." : snapshot?.description ?? "Checking official status…")
                            .font(.callout).foregroundStyle(.secondary)
                        if let snapshot {
                            HStack(spacing: 4) {
                                Text("Checked")
                                Text(snapshot.checkedAt, style: .relative)
                                Text("ago · every \(interval)s")
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                ForEach(activeIncidents.prefix(2)) { incident in
                    Button(action: showIncidents) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(badge.color).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(incident.name).font(.headline).foregroundStyle(.primary)
                                Text(incident.status.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption.weight(.medium)).foregroundStyle(badge.color)
                                Text(incident.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(badge.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(badge.color.opacity(0.18)) }
                    }.buttonStyle(.plain).accessibilityLabel("View incident: \(incident.name)")
                }
                HStack {
                    Text("System status").font(.headline)
                    Spacer()
                    Label("Latest check", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Imported history, followed by the current status. Hover any column for details.")
                    .font(.caption).foregroundStyle(.secondary)
                if components.isEmpty {
                    Text(loading ? "Loading components…" : "No component data available.").foregroundStyle(.secondary)
                }
                ForEach(components) { component in
                    ComponentTimelineRow(component: component,
                        currentHealth: health == nil ? nil : componentHealth(component.status),
                        cells: historyCells(component), current: currentCell(component),
                        leadingLabel: "Recent history", trailingLabel: "Now",
                        metric: uptimeLabel(component),
                        showIncidents: showIncidents, showComponent: { showComponent(component.name) })
                }
                HStack(spacing: 18) {
                    legend("Operational", .green)
                    legend("Issues", .orange)
                    legend("Outage", .red)
                    legend("Unknown", .secondary.opacity(0.3))
                }
                Text("History uses official availability data where published, otherwise reported incidents. Gray means unmeasured. Now updates on every provider check.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }
    }

    private func uptimeLabel(_ component: Component) -> String? {
        guard let source = uptime[component.id], let value = source.reportedUptime ?? source.uptime60 else { return nil }
        return "\(value)% uptime · \(source.reportedPeriodDays ?? 60) days"
    }
    private func currentCell(_ component: Component) -> StatusTimelineCell {
        let current = health == nil ? nil : componentHealth(component.status)
        let badge = DetailStatusBadge(health: current)
        let matching = activeIncidents.filter { incident in
            incident.components?.contains { $0.id == component.id } == true
        }
        let checked = snapshot?.checkedAt.formatted(date: .abbreviated, time: .standard) ?? "Not checked"
        return StatusTimelineCell(id: "now", title: "Latest check · " + checked, health: current,
            detail: ([badge.title] + matching.map { "\($0.name)\n\($0.detail)" }).joined(separator: "\n\n"))
    }

    private func historyCells(_ component: Component) -> [StatusTimelineCell] {
        if let official = uptime[component.id] {
            return official.days.map { day in
                StatusTimelineCell(id: day.id, title: day.date.formatted(date: .abbreviated, time: .omitted), health: day.health,
                    detail: ([day.downtimeDescription] + day.incidentTitles).joined(separator: "\n\n"))
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: Date())
        return (-59...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today), let end = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            let reports = historyAvailable ? incidents.filter { incident in
                let matches = incident.components?.contains { $0.id == component.id } == true || incident.incident_updates?.contains { $0.affected_components?.contains { $0.code == component.id } == true } == true
                guard matches, let start = incident.timestamp, start < end else { return false }
                if let resolved = StatusDate.parse(incident.resolved_at) { return resolved >= date }
                return incident.active || start >= date
            } : []
            let status: Health? = reports.isEmpty ? nil : reports.contains { ["major", "critical"].contains($0.impact ?? "") } ? .outage : .degraded
            return StatusTimelineCell(id: date.ISO8601Format(), title: date.formatted(date: .abbreviated, time: .omitted) + " (UTC)", health: status,
                detail: reports.isEmpty ? "Availability not measured. No incident in the returned feed for this component." : reports.map { "\($0.name)\n\($0.detail)" }.joined(separator: "\n\n"))
        }
    }
    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private func componentHealth(_ status: String) -> Health? {
    switch status {
    case "operational": .operational
    case "under_maintenance": .maintenance
    case "degraded_performance": .degraded
    case "partial_outage", "major_outage": .outage
    default: nil
    }
}

private struct StatusTimelineCell: Identifiable {
    let id: String
    let title: String
    let health: Health?
    let detail: String
}

private struct ComponentTimelineRow: View {
    let component: Component
    let currentHealth: Health?
    let cells: [StatusTimelineCell]
    let current: StatusTimelineCell
    let leadingLabel: String
    let trailingLabel: String
    let metric: String?
    let showIncidents: () -> Void
    let showComponent: () -> Void
    @State private var hovered: StatusTimelineCell?

    private var badge: DetailStatusBadge { DetailStatusBadge(health: currentHealth) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            columns
            axis
        }.padding(14)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)) }
            .overlay(alignment: .bottomLeading) { hoverCard }
            .zIndex(hovered == nil ? 0 : 1)
    }
    private var header: some View {
        HStack {
            Button(action: showComponent) {
                HStack(spacing: 8) {
                    Image(systemName: badge.symbol).foregroundStyle(badge.color)
                    Text(component.name).font(.headline).foregroundStyle(.primary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            Spacer(minLength: 8)
            badge
        }
    }
    private var columns: some View {
        HStack(spacing: 3) {
            ForEach(0..<cells.count, id: \.self) { index in
                cellButton(cells[index])
            }
            Divider().frame(height: 24).padding(.horizontal, 3)
            cellButton(current).frame(width: 14)
        }
    }
    private func cellButton(_ cell: StatusTimelineCell) -> some View {
        let label = component.name + ", " + cell.title + ": " + cell.detail
        let help = cell.title + "\n" + cell.detail
        let selected = hovered?.id == cell.id
        return Button(action: showIncidents) {
            TimelineColumn(health: cell.health, highlighted: selected)
        }.buttonStyle(PlainButtonStyle())
            .onHover { inside in
                if inside { hovered = cell } else { hovered = nil }
            }
            .help(help)
            .accessibilityLabel(label)
    }
    private var axis: some View {
        HStack {
            Text(leadingLabel)
            Spacer()
            if let metric { Text(metric).monospacedDigit(); Spacer() }
            Text(trailingLabel)
        }.font(.caption2).foregroundStyle(.secondary)
    }
    @ViewBuilder private var hoverCard: some View {
        if let hovered {
            VStack(alignment: .leading, spacing: 8) {
                Text(hovered.title).font(.callout.weight(.semibold))
                Text(hovered.detail).font(.callout).foregroundStyle(.secondary).lineLimit(6)
            }.padding(14).frame(maxWidth: 360, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)) }
                .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                .offset(y: 85).allowsHitTesting(false)
        }
    }
}

private struct TimelineColumn: View {
    let health: Health?
    let highlighted: Bool
    private var color: Color {
        if let health { return DetailStatusBadge(health: health).color }
        return Color.secondary.opacity(0.18)
    }
    var body: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(color)
            .frame(maxWidth: .infinity).frame(height: 30)
            .overlay {
                RoundedRectangle(cornerRadius: 2.5)
                    .strokeBorder(Color.primary.opacity(highlighted ? 0.7 : 0), lineWidth: 1)
            }
    }
}
