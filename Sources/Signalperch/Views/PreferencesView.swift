import SwiftUI
import AppKit
import ServiceManagement

struct PreferencesView: View {
    @Bindable var store: MonitorStore
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    var body: some View {
        Form {
            Section("Services") {
                ForEach(Provider.all) { provider in
                    Toggle(isOn: Binding(get: { store.enabledIDs.contains(provider.id) }, set: { store.setEnabled(provider, $0) })) {
                        HStack(spacing: 10) { ServiceLogo(provider: provider, size: 18); Text(provider.name) }
                    }
                }
            }
            Section("Monitoring") {
                Picker("Check every", selection: $store.interval) {
                    Text("30 seconds").tag(30); Text("1 minute").tag(60)
                    Text("2 minutes").tag(120); Text("5 minutes").tag(300)
                }
                Text("Shows provider-reported status. Checks run while your Mac is awake and Signalperch is running.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch { loginError = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Notifications") {
                Toggle("Notify about outages and issues", isOn: $store.alertsEnabled)
                    .onChange(of: store.alertsEnabled) { _, enabled in
                        if enabled { Task { await store.enableNotifications() } }
                    }
                Toggle("Notify when services recover", isOn: $store.recoveryAlerts)
                Toggle("Play a sound", isOn: $store.sound)
                HStack {
                    Text(permissionText).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Test notification") { Task { await store.testNotification() } }
                }
                if store.notificationStatus == .denied {
                    Button("Open notification settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
                if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Section {
                Text("Signalperch 0.3.1 · No API keys required").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await store.updatePermission(); loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    private var permissionText: String {
        switch store.notificationStatus {
        case .authorized, .provisional: "Notifications allowed"
        case .denied: "Notifications blocked by macOS"
        default: "Notification permission needed"
        }
    }
}
