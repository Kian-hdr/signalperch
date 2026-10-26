import SwiftUI
import WebKit

/// Display the actual provider charts. Summary feeds do not supply uptime metrics.
struct OfficialStatusView: View {
    let url: URL
    var refresh: Int = 0
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0

    var body: some View {
        ZStack {
            StatusDashboardWebView(url: url, refresh: refresh + retry, loading: $loading, error: $error)
            if loading {
                ProgressView("Loading official dashboard…")
                    .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            if let error {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Official dashboard couldn't load").font(.headline)
                    Text(error).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try again") { retry += 1 }
                    Text("Incidents and Components are still available above.").font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 380)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

private struct StatusDashboardWebView: NSViewRepresentable {
    let url: URL
    let refresh: Int
    @Binding var loading: Bool
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        context.coordinator.load(web, url: url, refresh: refresh)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.owner = self
        if context.coordinator.requestedURL != url || context.coordinator.refresh != refresh {
            context.coordinator.load(web, url: url, refresh: refresh)
        }
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.navigationDelegate = nil
        web.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var owner: StatusDashboardWebView
        var requestedURL: URL?
        var refresh = -1

        init(owner: StatusDashboardWebView) { self.owner = owner }

        func load(_ web: WKWebView, url: URL, refresh: Int) {
            requestedURL = url
            self.refresh = refresh
            web.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            owner.loading = true
            owner.error = nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            owner.loading = false
            owner.error = nil
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failed(error)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failed(error)
        }
        private func failed(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            owner.loading = false
            owner.error = error.localizedDescription
        }
    }
}
