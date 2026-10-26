import Foundation
import Observation
import AppKit
import UserNotifications

@MainActor @Observable
final class MonitorStore {
    var enabledIDs: Set<String> {
        didSet {
            defaults.set(Array(enabledIDs).sorted(), forKey: "enabledProviders")
            for id in oldValue.symmetricDifference(enabledIDs) { readings[id] = nil; baseline[id] = nil; generations[id, default: 0] += 1 }
            persistBaseline()
            Task { await refresh() }
        }
    }
    var providerOrder: [String] { didSet { defaults.set(providerOrder, forKey: "providerOrder") } }
    var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: "alertsEnabled") } }
    var recoveryAlerts: Bool { didSet { defaults.set(recoveryAlerts, forKey: "recoveryAlerts") } }
    var sound: Bool { didSet { defaults.set(sound, forKey: "sound") } }
    var interval: Int { didSet { defaults.set(interval, forKey: "interval"); startTimer() } }
    var readings: [String: ServiceReading] = [:]
    var refreshing = false
    var now = Date()
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    var notice: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let client = StatusClient()
    @ObservationIgnored lazy var notifications = NotificationService()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var generations: [String: Int] = [:]
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var baseline: [String: Snapshot]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        providerOrder = ServicePriority.normalized(defaults.stringArray(forKey: "providerOrder") ?? [])
        enabledIDs = Set(defaults.stringArray(forKey: "enabledProviders") ?? ["openai", "claude", "github", "cloudflare", "supabase", "vercel"])
        alertsEnabled = defaults.object(forKey: "alertsEnabled") as? Bool ?? true
        recoveryAlerts = defaults.object(forKey: "recoveryAlerts") as? Bool ?? true
        sound = defaults.object(forKey: "sound") as? Bool ?? true
        let savedInterval = defaults.integer(forKey: "interval")
        interval = [30, 60, 120, 300].contains(savedInterval) ? savedInterval : 60
        baseline = defaults.data(forKey: "baseline").flatMap { try? JSONDecoder().decode([String: Snapshot].self, from: $0) } ?? [:]
        // Persisted observations are useful for deduplication, but never imply a fresh live status.
        for provider in Provider.all where enabledIDs.contains(provider.id) {
            if let snapshot = baseline[provider.id] { readings[provider.id] = ServiceReading(snapshot: snapshot, error: "Checking live status…") }
        }
    }
    var providers: [Provider] {
        providerOrder.compactMap { id in Provider.all.first { $0.id == id && enabledIDs.contains(id) } }
    }
    var popupHeight: CGFloat { max(320, CGFloat(providers.count) * 60 + 164) }
    var primaryProvider: Provider? { providers.first }
    func reorderProviders(moving sources: [String], before destination: String?) {
        saveEnabledOrder(ServicePriority.reordered(providers.map(\.id), moving: sources, before: destination))
    }
    func moveProviders(from offsets: IndexSet, to destination: Int) {
        saveEnabledOrder(ServicePriority.moved(providers.map(\.id), from: offsets, to: destination))
    }
    private func saveEnabledOrder(_ order: [String]) {
        providerOrder = ServicePriority.normalized(order + providerOrder.filter { !enabledIDs.contains($0) })
    }
    var maxAge: TimeInterval { TimeInterval(max(180, interval + 45)) }
    var attentionProvider: Provider? {
        providers.filter { !reading($0).unavailable(at: now, maxAge: maxAge) && reading($0).snapshot?.health != .operational }
            .max { (reading($0).snapshot?.health ?? .operational) < (reading($1).snapshot?.health ?? .operational) }
    }
    var unavailableCount: Int { providers.filter { reading($0).unavailable(at: now, maxAge: maxAge) }.count }
    var menuTitle: String {
        guard let provider = primaryProvider else { return "No services" }
        let current = reading(provider)
        let status = current.unavailable(at: now, maxAge: maxAge) ? (refreshing ? "Checking…" : "Unavailable") : current.snapshot?.health.title ?? "Unavailable"
        let others = providers.filter { $0.id != provider.id && !reading($0).unavailable(at: now, maxAge: maxAge) && reading($0).snapshot?.health != .operational }.count
        return "\(provider.name): \(status)" + (others > 0 ? " · \(others) other issues" : "")
    }
    var menuSymbol: String { attentionProvider == nil ? (unavailableCount > 0 ? "questionmark.circle" : "checkmark.circle") : "exclamationmark.triangle" }
    func reading(_ provider: Provider) -> ServiceReading { readings[provider.id] ?? ServiceReading() }
    func setEnabled(_ provider: Provider, _ enabled: Bool) {
        if enabled { enabledIDs.insert(provider.id) } else { enabledIDs.remove(provider.id) }
    }
    func start() {
        startTimer()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
                self?.now = Date()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task {
            await updatePermission()
            if alertsEnabled && notificationStatus == .notDetermined { await enableNotifications() }
            await refresh()
        }
    }
    private func startTimer() {
        timer?.cancel()
        let delay = interval
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(delay)) } catch { break }
                guard let self else { break }
                self.now = Date()
                Task { await self.refresh() }
            }
        }
    }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        now = Date()
        let requested = providers
        let requestGenerations = generations
        await withTaskGroup(of: (String, Result<Snapshot, Error>).self) { group in
            for provider in requested {
                let client = self.client
                group.addTask {
                    do { return (provider.id, .success(try await client.fetch(provider))) }
                    catch { return (provider.id, .failure(error)) }
                }
            }
            for await (id, result) in group {
                guard enabledIDs.contains(id), generations[id, default: 0] == requestGenerations[id, default: 0], let provider = requested.first(where: { $0.id == id }) else { continue }
                switch result {
                case .success(let snapshot):
                    let alert = AlertPolicy.alert(provider: provider.name, previous: baseline[id], current: snapshot, recoveries: recoveryAlerts)
                    readings[id] = ServiceReading(snapshot: snapshot)
                    baseline[id] = snapshot
                    persistBaseline()
                    if alertsEnabled, let alert {
                        do { try await notifications.send(alert, provider: provider, sound: sound) }
                        catch { notice = "Could not deliver notification: \(error.localizedDescription)" }
                    }
                case .failure(let error):
                    var reading = reading(provider)
                    reading.error = error.localizedDescription
                    readings[id] = reading
                }
            }
        }
        now = Date(); refreshing = false
        await updatePermission()
        // A provider enabled during an in-flight batch is checked immediately after that batch.
        if providers.contains(where: { !requested.contains($0) || generations[$0.id, default: 0] != requestGenerations[$0.id, default: 0] }) { await refresh() }
    }
    private func persistBaseline() { if let data = try? JSONEncoder().encode(baseline) { defaults.set(data, forKey: "baseline") } }
    func updatePermission() async { notificationStatus = await notifications.authorization() }
    func enableNotifications() async {
        do {
            let granted = try await notifications.requestPermission()
            alertsEnabled = granted
            if !granted { notice = "Allow Signalperch in System Settings → Notifications to receive outage alerts." }
        } catch { notice = error.localizedDescription }
        await updatePermission()
    }
    func testNotification() async {
        await updatePermission()
        guard notificationStatus == .authorized || notificationStatus == .provisional else {
            notice = "Notifications need permission. Enable them first."; return
        }
        do {
            try await notifications.send(StatusAlert(title: "Signalperch test", body: "Outage and recovery notifications are ready."), provider: nil, sound: sound)
            notice = "Test notification submitted to macOS. Focus settings may silence banners."
        } catch { notice = error.localizedDescription }
    }
}
