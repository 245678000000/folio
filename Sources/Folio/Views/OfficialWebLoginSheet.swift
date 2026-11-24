import AppKit
import FolioCore
import SwiftUI
import WebKit

/// 内置原生网页浏览器登录弹窗：直达 Z-Library 官方网站，登录成功后自动同步域名与 Cookie 会话
struct OfficialWebLoginSheet: View {
    let initialHost: String
    let onCapturedSession: (_ domain: String, _ credentials: CookieParser.ParsedCredentials) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var controller: WebLoginController
    @State private var addressInput: String
    @State private var statusText: String = "正在打开官方网站，请在页面内完成登录…"
    @State private var isSyncing = false
    @State private var errorMessage: String?

    init(
        initialHost: String,
        onCapturedSession: @escaping (_ domain: String, _ credentials: CookieParser.ParsedCredentials) async throws -> Void
    ) {
        let host = (try? DomainPolicy.normalizeHost(initialHost)) ?? DomainPolicy.defaultOfficialHost
        self.initialHost = host
        self.onCapturedSession = onCapturedSession
        let startURL = URL(string: "https://\(host)/")!
        _controller = State(initialValue: WebLoginController(initialURL: startURL))
        _addressInput = State(initialValue: startURL.absoluteString)
    }

    var body: some View {
        VStack(spacing: 0) {
            browserToolbar
            Divider().opacity(0.45)

            ZStack(alignment: .top) {
                OfficialWebViewRepresentable(controller: controller)
                if controller.isLoading {
                    ProgressView(value: controller.estimatedProgress)
                        .progressViewStyle(.linear)
                        .tint(FolioTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.45)
            bottomStatusBar
        }
        .frame(width: 940, height: 680)
        .onAppear {
            controller.onAutoDetectedCredentials = { host, credentials in
                Task { @MainActor in
                    await handleCaptured(host: host, credentials: credentials)
                }
            }
            controller.onURLChanged = { newURL in
                addressInput = newURL.absoluteString
            }
            controller.loadInitialIfNeeded()
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
            // 后退 / 前进 / 刷新
            HStack(spacing: 4) {
                Button {
                    controller.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!controller.canGoBack)

                Button {
                    controller.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!controller.canGoForward)

                Button {
                    controller.reload()
                } label: {
                    Image(systemName: controller.isLoading ? "xmark" : "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // 地址栏
            TextField("输入官方地址或个人专属域名…", text: $addressInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit {
                    navigateToInput()
                }

            // 备用官方入口快速切换
            Menu {
                ForEach(DomainPolicy.officialHosts, id: \.self) { host in
                    Button("https://\(host)") {
                        let url = URL(string: "https://\(host)/")!
                        addressInput = url.absoluteString
                        controller.load(url: url)
                    }
                }
            } label: {
                Label("切换官方入口", systemImage: "globe")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                if let url = controller.currentURL ?? URL(string: "https://\(initialHost)/") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("在默认浏览器中打开此网址")

            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var bottomStatusBar: some View {
        HStack(spacing: 10) {
            if isSyncing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: errorMessage == nil ? "lock.shield" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5))
                    .foregroundStyle(errorMessage == nil ? FolioTheme.accent : Color.orange)
            }

            Text(errorMessage ?? statusText)
                .font(.system(size: 12))
                .foregroundStyle(errorMessage == nil ? Color.secondary : Color.orange)
                .lineLimit(1)

            Spacer()

            Button {
                manualSync()
            } label: {
                Text(isSyncing ? "正在同步…" : "我已登录，立即同步")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(FolioTheme.accent)
            .controlSize(.small)
            .disabled(isSyncing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func navigateToInput() {
        let trimmed = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if let url = URL(string: normalized), url.scheme?.lowercased() == "https" {
            errorMessage = nil
            controller.load(url: url)
        } else {
            errorMessage = "请输入有效的 HTTPS 官网网址"
        }
    }

    private func manualSync() {
        errorMessage = nil
        statusText = "正在读取当前官网登录会话…"
        controller.inspectCookiesNow { host, credentials in
            Task { @MainActor in
                guard let host, let credentials else {
                    errorMessage = "暂未检测到登录会话（remix_userid / remix_userkey），请确认已在网页中完成登录。"
                    return
                }
                await handleCaptured(host: host, credentials: credentials)
            }
        }
    }

    @MainActor
    private func handleCaptured(host: String, credentials: CookieParser.ParsedCredentials) async {
        guard !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        statusText = "已检测到 \(host) 登录会话，正在验证并同步到 Folio…"
        do {
            try await onCapturedSession(host, credentials)
            dismiss()
        } catch {
            errorMessage = "同步失败：\(error.localizedDescription)"
            isSyncing = false
        }
    }
}

/// 负责托管 WKWebView 导航与 Cookie 监听的控制器
@MainActor
@Observable
final class WebLoginController: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private let initialURL: URL
    private var didStartInitialLoad = false
    private var hasDeliveredSuccess = false

    var currentURL: URL?
    var isLoading: Bool = false
    var estimatedProgress: Double = 0
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    var onURLChanged: ((URL) -> Void)?
    var onAutoDetectedCredentials: ((String, CookieParser.ParsedCredentials) -> Void)?

    private var progressObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?

    init(initialURL: URL) {
        self.initialURL = initialURL

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = EapiHeaders.userAgent
        self.webView = view

        super.init()
        view.navigationDelegate = self
        view.uiDelegate = self

        progressObservation = view.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.estimatedProgress = webView.estimatedProgress
            }
        }
        urlObservation = view.observe(\.url, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                guard let self, let url = webView.url else { return }
                self.currentURL = url
                self.canGoBack = webView.canGoBack
                self.canGoForward = webView.canGoForward
                self.onURLChanged?(url)
            }
        }
    }

    func loadInitialIfNeeded() {
        guard !didStartInitialLoad else { return }
        didStartInitialLoad = true
        load(url: initialURL)
    }

    func load(url: URL) {
        currentURL = url
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reload() {
        if webView.isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    func inspectCookiesNow(completion: @escaping @MainActor (String?, CookieParser.ParsedCredentials?) -> Void) {
        let currentHost = webView.url?.host ?? initialURL.host ?? DomainPolicy.defaultOfficialHost
        let normalizedHost = (try? DomainPolicy.normalizeHost(currentHost)) ?? currentHost
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let credentials = CookieParser.extract(from: cookies, matchingHost: normalizedHost)
            Task { @MainActor in
                completion(normalizedHost, credentials)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let url = webView.url {
            currentURL = url
            onURLChanged?(url)
        }
        checkForAutoLogin()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    /// 兼容网页中 `target="_blank"` 链接在当前登录窗打开，避免弹窗无响应
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    private func checkForAutoLogin() {
        guard !hasDeliveredSuccess else { return }
        inspectCookiesNow { [weak self] host, credentials in
            guard let self, !self.hasDeliveredSuccess, let host, let credentials else { return }
            self.hasDeliveredSuccess = true
            self.onAutoDetectedCredentials?(host, credentials)
        }
    }
}

/// 将 WKWebView 桥接到 SwiftUI
private struct OfficialWebViewRepresentable: NSViewRepresentable {
    let controller: WebLoginController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
