import AppKit
import LibertyCore
import SwiftUI
import WebKit

/// Shows a Nexus Mods page inside the app so a free account can finish an
/// install without leaving for a browser.
///
/// Nexus only mints a download token when you press *Mod Manager Download* on
/// their own page; the API refuses otherwise, for free accounts. That button
/// fires an `nxm://` link, which this view intercepts and hands to the
/// installer. Nothing is bypassed — Nexus still serves the page and still sees
/// the click. The only change is which window hosts it.
///
/// Deliberately not done here: spoofing the user agent. Nexus sits behind
/// Cloudflare, and an embedded web view is exactly what bot protection looks
/// for. Dressing up as Safari to slip past it would be evasion rather than
/// convenience, so the stock agent is used and any challenge is left for the
/// user to complete, exactly as they would in a browser.
struct NexusWebSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mod: NexusModSummary

    @State private var isLoading = true
    @State private var failure: String?

    private var filesURL: URL {
        URL(string: "https://www.nexusmods.com/\(NexusClient.gameDomain)/mods/\(mod.id)?tab=files")
            ?? mod.pageURL
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(verbatim: mod.name ?? "")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.hdText)
                    .lineLimit(1)
                if isLoading { ProgressView().controlSize(.small) }
                Spacer()
                Button("Open in Browser") {
                    NSWorkspace.shared.open(filesURL)
                }
                .buttonStyle(HDSecondaryButtonStyle())
                .help("If this page will not load here, finish the install in your browser instead.")
                Button("Close") { dismiss() }
                    .buttonStyle(HDSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            Text("Press “Mod Manager Download” on this page. Liberty Loader takes it from there.")
                .font(.caption)
                .foregroundStyle(Color.hdMuted)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if let failure {
                HDBanner(icon: "wifi.exclamationmark", color: .hdDanger,
                         title: Text("Couldn't load the page"), message: Text(verbatim: failure)) {
                    Button("Open in Browser") { NSWorkspace.shared.open(filesURL) }
                        .buttonStyle(HDSecondaryButtonStyle())
                }
                .padding(12)
            }

            NexusWebView(url: filesURL, isLoading: $isLoading, failure: $failure) { link in
                Task {
                    await model.installFromNexus(link)
                    dismiss()
                }
            }
        }
        .frame(width: 900, height: 680)
        .background(Color.hdBackground)
        .preferredColorScheme(.dark)
    }
}

/// The web view itself. Intercepts `nxm://` rather than letting the system
/// hand it back to the app through Launch Services, which would work but would
/// bounce focus out of the window for no reason.
private struct NexusWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var failure: String?
    let onLink: (NXMLink) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // The default store is persistent, so a Nexus sign-in survives
        // reopening the window. It is separate from Safari's cookies, so the
        // user signs in here once.
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: NexusWebView
        init(_ parent: NexusWebView) { self.parent = parent }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow); return
            }
            if url.scheme?.lowercased() == "nxm" {
                decisionHandler(.cancel)
                if let link = NXMLink(url: url) {
                    DispatchQueue.main.async { self.parent.onLink(link) }
                }
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.failure = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.failure = error.localizedDescription
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            parent.isLoading = false
            // A cancelled load is usually our own nxm:// interception, not a problem.
            if (error as NSError).code == NSURLErrorCancelled { return }
            parent.failure = error.localizedDescription
        }
    }
}
