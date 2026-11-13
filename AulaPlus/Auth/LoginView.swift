import SwiftUI
import WebKit

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var pkce = PKCE.make()
    @State private var showWeb = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)
            AppMark()
            VStack(spacing: 8) {
                Text("Aula+").font(.largeTitle.bold())
                Text("Beskeder, kalender og ugeplan —\nhurtigt og overskueligt.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("bolt.fill", .orange, "Åbner med det samme", "Alt gemmes på telefonen og opdateres i baggrunden.")
                feature("figure.and.child.holdinghands", .teal, "Hele dagen på ét blik", "Komme/gå, skema og beskeder for hvert barn.")
                feature("bell.badge.fill", .red, "Besked når der sker noget", "Notifikationer om nye beskeder og opslag.")
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            if let notice = error ?? app.loginNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }
            Spacer()
            Button {
                pkce = PKCE.make()
                error = nil
                showWeb = true
            } label: {
                Group {
                    if working { ProgressView().tint(.white) } else { Text("Log ind med MitID") }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .disabled(working)
            .padding(.horizontal, 24)
            Label("Uofficiel app. Dine data går kun mellem din telefon og Aula.", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .background(
            LinearGradient(colors: [Color.brand.opacity(0.12), Color(.systemBackground)],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        .sheet(isPresented: $showWeb) {
            NavigationStack {
                MitIDWebView(url: pkce.authorizeURL) { callback in
                    showWeb = false
                    Task { await finish(callback) }
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("MitID")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuller") { showWeb = false }
                    }
                }
            }
        }
    }

    private func feature(_ icon: String, _ color: Color, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func finish(_ url: URL) async {
        working = true
        defer { working = false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value
        let state = items.first { $0.name == "state" }?.value
        do {
            guard state == pkce.state else { throw AuthError.stateMismatch }
            guard let code else { throw AuthError.missingCode }
            try await TokenStore.shared.exchange(code: code, verifier: pkce.verifier)
            await app.didLogin()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Runs Aula's own OIDC → UniLogin → MitID pages and hands back the
/// `https://app-private.aula.dk?code=…` redirect instead of loading it.
struct MitIDWebView: UIViewRepresentable {
    let url: URL
    let onCallback: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCallback: onCallback) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // lets MitID remember your username
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCallback: (URL) -> Void
        private var done = false

        init(onCallback: @escaping (URL) -> Void) { self.onCallback = onCallback }

        private func isCallback(_ url: URL?) -> Bool {
            url?.host == AulaConfig.redirectHost
        }

        private func complete(_ url: URL) {
            guard !done else { return }
            done = true
            onCallback(url)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.allow) }
            if isCallback(url) {
                decisionHandler(.cancel)
                complete(url)
                return
            }
            // MitID app hand-off and other custom schemes go to the system.
            if let scheme = url.scheme?.lowercased(), !["http", "https", "about", "blob", "data"].contains(scheme) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            if let url = webView.url, isCallback(url) {
                webView.stopLoading()
                complete(url)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let failing = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
            if let failing, isCallback(failing) { complete(failing) }
        }
    }
}
