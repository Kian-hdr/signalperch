import SwiftUI
import AppKit

struct StatusPanel: View {
    let store: MonitorStore
    let openDetails: (Provider) -> Void
    let openPreferences: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signalperch").font(.headline)
                    Text(store.menuTitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").font(.body)
                }.buttonStyle(.borderless).disabled(store.refreshing)
                    .help("Refresh all services").accessibilityLabel("Refresh all services")
            }.padding(18)
            Divider().padding(.horizontal, 14)
            Text("Drag to reorder · First service in menu bar")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 8)
            ReorderableServiceList(store: store, openDetails: openDetails)
            Spacer(minLength: 0)
            Divider().padding(.horizontal, 14)
            HStack {
                if store.alertsEnabled && store.notificationStatus != .authorized && store.notificationStatus != .provisional {
                    Button("Enable alerts") { Task { await store.enableNotifications() } }.buttonStyle(.link)
                } else {
                    Text("Checks every \(store.interval)s").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: openPreferences) { Image(systemName: "gearshape") }.buttonStyle(.borderless)
                    .help("Settings").accessibilityLabel("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.borderless).help("Quit Signalperch").accessibilityLabel("Quit Signalperch")
            }.padding(18)
        }.frame(width: 380, height: store.popupHeight)
    }
}
