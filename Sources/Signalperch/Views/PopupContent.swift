import SwiftUI
import Observation

@MainActor
@Observable
final class PopupNavigation {
    enum Route { case services, details(Provider), preferences }
    var route: Route = .services
}

struct PopupContent: View {
    let store: MonitorStore
    let navigation: PopupNavigation
    let openDetails: (Provider) -> Void
    let openPreferences: () -> Void
    let goBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch navigation.route {
            case .services:
                StatusPanel(store: store, openDetails: openDetails, openPreferences: openPreferences)
            case .details(let provider):
                navigationBar(provider.name)
                ServiceDetailView(provider: provider, store: store).id(provider.id)
            case .preferences:
                navigationBar("Settings")
                PreferencesView(store: store)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func navigationBar(_ title: String) -> some View {
        HStack {
            Button(action: goBack) { Label("Services", systemImage: "chevron.left") }
                .buttonStyle(.plain).accessibilityLabel("Back to services")
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Button(action: openPreferences) { Image(systemName: "gearshape") }
                .buttonStyle(.plain).accessibilityLabel("Settings")
        }.padding(18)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 14) }
    }
}
