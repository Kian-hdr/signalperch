import SwiftUI

struct ServiceDetailView: View {
    let provider: Provider
    let store: MonitorStore
    @State private var details: ServiceDetails?
    @State private var error: String?
    @State private var loading = false
    @State private var tab = "overview"
    @State private var componentSearch = ""
    @State private var pageRefresh = 0
    @State private var uptime: [String: ComponentUptime] = [:]
    @State private var officialURL: URL?
    init(provider: Provider, store: MonitorStore) {
        self.provider = provider
        self.store = store
        _uptime = State(initialValue: Dictionary(uniqueKeysWithValues: UptimeHistoryCache.load(provider).map { ($0.id, $0) }))
    }
    private var snapshot: Snapshot? {
        let monitored = store.reading(provider).snapshot
        if let monitored, monitored.checkedAt > (details?.snapshot.checkedAt ?? .distantPast) { return monitored }
        return details?.snapshot ?? monitored
    }
    private var currentHealth: Health? {
        guard let snapshot, store.now.timeIntervalSince(snapshot.checkedAt) <= store.maxAge else { return nil }
        let monitored = store.reading(provider)
        if snapshot.checkedAt == monitored.snapshot?.checkedAt {
            guard monitored.error == nil else { return nil }
        } else if error != nil { return nil }
        return snapshot.health
    }
    private var activeIncidents: [Incident] {
        let fromHistory = Dictionary(uniqueKeysWithValues: (details?.incidents ?? []).map { ($0.id, $0) })
        return (snapshot?.incidents ?? []).map { current in
            guard let history = fromHistory[current.id] else { return current }
            return IncidentClient.mergeIncident(history, with: current)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ServiceLogo(provider: provider, size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.name).font(.title3.weight(.semibold))
                    Text(provider.host).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                DetailStatusBadge(health: currentHealth)
                Button {
                    pageRefresh += 1
                    Task { await store.refresh(); await load() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh status and official dashboard")
                    .accessibilityLabel("Refresh status").disabled(loading)
            }.padding(.horizontal, 20).padding(.vertical, 14)
            Picker("Detail section", selection: $tab) {
                Text("Overview").tag("overview")
                Text("Incidents").tag("incidents")
                Text("Components").tag("components")
                Text("Maintenance").tag("maintenance")
                Text("Official page").tag("official")
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 20).padding(.bottom, 14)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 10)
            }
            Group {
                switch tab {
                case "incidents": incidentContent
                case "components": ComponentList(components: snapshot?.components ?? [], fresh: currentHealth != nil, initialSearch: componentSearch).id(componentSearch)
                case "overview":
                    StatusDashboard(snapshot: snapshot, health: currentHealth, uptime: uptime, interval: store.interval, incidents: details?.incidents ?? [], activeIncidents: activeIncidents, loading: loading, historyAvailable: details != nil && !(details?.limitations.contains { $0.hasPrefix("Recent incident history could not be loaded") } ?? true), showIncidents: { tab = "incidents" }, showComponent: { name in componentSearch = name; tab = "components" })
                case "maintenance": maintenanceContent
                default:
                    OfficialStatusView(url: officialURL ?? provider.pageURL, refresh: pageRefresh)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)) }
            .padding(.horizontal, 14).padding(.bottom, 12)
            HStack {
                if let date = details?.fetchedAt { Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))") }
                Spacer()
                Text(tab == "official" ? "Live official dashboard" : "Provider-reported status").foregroundStyle(.secondary)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 16)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.openURL, OpenURLAction { url in
            officialURL = url
            tab = "official"
            return .handled
        }).task(id: provider.id) { await load() }
        .onChange(of: store.reading(provider).snapshot?.checkedAt) { _, _ in Task { await load() } }
    }
    private var incidentContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                let current = activeIncidents
                Text("Active incidents").font(.title3.weight(.semibold))
                if current.isEmpty && !loading { Text("No active incidents reported.").foregroundStyle(.secondary) }
                ForEach(current) { incident in IncidentTimeline(incident: incident, provider: provider) }
                Divider()
                Text("Recent incident history").font(.title3.weight(.semibold))
                Text("Recent incidents returned by the provider's API. Official page shows the provider's complete charts and archive.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(details?.incidents.filter { !$0.active } ?? []) { incident in
                    DisclosureGroup {
                        IncidentTimeline(incident: incident, provider: provider).padding(.top, 12)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(incident.name).font(.body.weight(.medium))
                            HStack {
                                Text(incident.status.capitalized)
                                if let date = incident.timestamp { Text(date.formatted(date: .abbreviated, time: .shortened)) }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
                ForEach(details?.limitations ?? [], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var maintenanceContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                Text("Scheduled and recent maintenance").font(.title3.weight(.semibold))
                if let details, details.scheduledMaintenances.isEmpty {
                    if provider.id == "openai" || details.limitations.contains(where: { $0.hasPrefix("Maintenance history could not be loaded") }) {
                        Text("Maintenance history is unavailable. See Official page for the provider's complete dashboard.").foregroundStyle(.secondary)
                    } else {
                        Text("No maintenance entries reported.").foregroundStyle(.secondary)
                    }
                }
                ForEach((details?.limitations ?? []).filter { $0.hasPrefix("Maintenance history could not be loaded") }, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                ForEach(details?.scheduledMaintenances ?? []) { incident in IncidentTimeline(incident: incident, provider: provider) }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        do {
            details = try await IncidentClient().fetch(provider)
            if let components = details?.components {
                let fetched = try? await UptimeClient().fetch(provider, components: components)
                uptime = Dictionary(uniqueKeysWithValues: (fetched ?? []).map { ($0.id, $0) })
                if let fetched, !fetched.isEmpty { UptimeHistoryCache.save(fetched, for: provider) }
            }
        }
        catch { uptime = [:]; self.error = "Details couldn't be refreshed: \(error.localizedDescription)" }
        loading = false
    }
}
private struct IncidentTimeline: View {
    let incident: Incident
    let provider: Provider
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(incident.name).font(.headline).textSelection(.enabled)
                Spacer()
                Text(incident.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            if let date = incident.timestamp {
                Text("Started \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            if let from = StatusDate.parse(incident.scheduled_for) {
                Text("Scheduled \(from.formatted(date: .abbreviated, time: .shortened))\(StatusDate.parse(incident.scheduled_until).map { " to " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !incident.affectedComponentNames.isEmpty {
                Text("Affected: \(incident.affectedComponentNames.joined(separator: ", "))").font(.callout).foregroundStyle(.secondary)
            }
            ForEach((incident.incident_updates ?? []).map(TimelineEntry.init)) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Color.secondary.opacity(0.5)).frame(width: 6, height: 6).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.update.status?.capitalized ?? "Update").font(.callout.weight(.semibold))
                            Spacer()
                            if let date = entry.update.timestamp { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                        }
                        Text((try? AttributedString(markdown: entry.update.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(entry.update.body))
                            .font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Link("Open official incident ↗", destination: incident.officialURL(for: provider)).font(.caption)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}
private struct TimelineEntry: Identifiable {
    let update: Incident.Update
    var id: String { update.id ?? [update.display_at ?? "", update.created_at ?? "", update.status ?? "", update.body].joined(separator: "|") }
    init(_ update: Incident.Update) { self.update = update }
}
private struct ComponentList: View {
    let components: [Component]
    let fresh: Bool
    @State private var search: String
    init(components: [Component], fresh: Bool, initialSearch: String = "") {
        self.components = components
        self.fresh = fresh
        _search = State(initialValue: initialSearch)
    }
    @State private var onlyAffected = false
    private var filtered: [Component] {
        components.filter { component in
            (!onlyAffected || component.status != "operational") && (search.isEmpty || component.name.localizedCaseInsensitiveContains(search))
        }.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search all components", text: $search).textFieldStyle(.roundedBorder)
                Toggle("Only affected", isOn: $onlyAffected).toggleStyle(.checkbox)
            }.padding(.horizontal, 16).padding(.top, 16)
            List(filtered) { component in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(component.name).fontWeight(component.group == true ? .semibold : .regular)
                        if let description = component.description, !description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    DetailStatusBadge(componentStatus: fresh ? component.status : "unavailable")
                }.padding(.vertical, 4)
            }
            Text("\(filtered.count) of \(components.count) components").font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
        }
    }
}
