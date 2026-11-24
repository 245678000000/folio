import AppKit
import FolioCore
import SwiftUI

/// 三模式登录弹窗（官网网页一键登录 / 邮箱密码登录 / Token 或 Cookie 直连）
struct AuthSheetView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    enum AuthMode: String, CaseIterable, Identifiable {
        case web = "官网登录"
        case password = "邮箱密码"
        case token = "Token / Cookie"
        var id: String { rawValue }
    }

    @State private var mode: AuthMode = .web
    @State private var domainInput: String = ""
    @State private var emailInput: String = ""
    @State private var passwordInput: String = ""
    @State private var userIDInput: String = ""
    @State private var userKeyInput: String = ""
    @State private var rawCookieInput: String = ""

    @State private var isSubmitting = false
    @State private var isProbing = false
    @State private var isAutoDiscovering = false
    @State private var probeResult: DomainProbeResult?
    @State private var errorMessage: String?
    @State private var isWebLoginPresented = false

    private var effectiveHost: String {
        (try? DomainPolicy.normalizeHost(domainInput)) ?? DomainPolicy.defaultOfficialHost
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Picker("登录方式", selection: $mode) {
                ForEach(AuthMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 12) {
                domainField

                switch mode {
                case .web:
                    webLoginSection
                case .password:
                    passwordFields
                case .token:
                    tokenFields
                }
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12.5))
                        .padding(.top, 1)
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.11))
                )
            }

            Divider().opacity(0.45)

            footerActions
        }
        .padding(24)
        .frame(width: 480)
        .sheet(isPresented: $isWebLoginPresented) {
            OfficialWebLoginSheet(initialHost: effectiveHost) { capturedDomain, credentials in
                try await appState.signInWithTokens(
                    domain: capturedDomain,
                    userID: credentials.remixUserID,
                    userKey: credentials.remixUserKey,
                    cookies: credentials.cookies
                )
                dismiss()
            }
        }
        .onAppear {
            let initialDomain = appState.session?.domain ?? appState.settings.lastDomain
            domainInput = initialDomain.isEmpty ? DomainPolicy.defaultOfficialHost : initialDomain
            emailInput = appState.session?.email ?? ""
            userIDInput = appState.session?.remixUserID ?? ""
            userKeyInput = appState.session?.remixUserKey ?? ""

            // 首次尚未保存域名时自动并发探测最快可用官方入口
            if initialDomain.isEmpty {
                autoDiscoverOfficialDomain()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(FolioTheme.accent.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(FolioTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("连接 Z-Library EAPI")
                    .font(.system(size: 16, weight: .bold))
                Text("支持直接打开官方网站登录并自动同步会话，凭据仅存于本机钥匙串。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var domainField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("官方入口 / 个人专属域名")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    autoDiscoverOfficialDomain()
                } label: {
                    HStack(spacing: 4) {
                        if isAutoDiscovering {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10.5))
                        }
                        Text(isAutoDiscovering ? "正在探测…" : "自动优选官方域名")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(FolioTheme.accent)
                .disabled(isAutoDiscovering)
            }

            HStack(spacing: 6) {
                TextField("例如：zlib.bz 或个人专属域名", text: $domainInput)
                    .textFieldStyle(.roundedBorder)

                Menu {
                    Section("常用官方入口") {
                        ForEach(DomainPolicy.officialHosts, id: \.self) { host in
                            Button(host) {
                                domainInput = host
                                probeDomain()
                            }
                        }
                    }
                    if !appState.settings.recentDomains.isEmpty {
                        Section("最近使用") {
                            ForEach(appState.settings.recentDomains, id: \.self) { host in
                                Button(host) {
                                    domainInput = host
                                    probeDomain()
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("选择官方入口域名")

                Button {
                    probeDomain()
                } label: {
                    if isProbing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("测速")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isProbing || domainInput.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    appState.openOfficialWebsite(preferredDomain: domainInput)
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.bordered)
                .help("在默认浏览器中打开官方网站")
            }

            if let probeResult {
                HStack(spacing: 5) {
                    Circle()
                        .fill(probeResult.reachable ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text("\(probeResult.host)：\(probeResult.message)")
                        .font(.system(size: 11))
                        .foregroundStyle(probeResult.reachable ? Color.secondary : Color.orange)
                }
            }
        }
    }

    private var webLoginSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("推荐：直接前往官方网站登录（免手动找域名与复制 Cookie）", systemImage: "sparkles")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("点击下方按钮将在应用内打开官方页面。完成账号登录（含人机验证或跳转至个人专属域名）后，Folio 会自动捕获你的域名与登录会话并安全写入 macOS 钥匙串。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(FolioTheme.subtleFill)
            )

            HStack(spacing: 10) {
                Button {
                    errorMessage = nil
                    isWebLoginPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                        Text("打开官方网站登录")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .tint(FolioTheme.accent)
                .controlSize(.large)

                Button {
                    appState.openOfficialWebsite(preferredDomain: domainInput)
                } label: {
                    Label("浏览器访问", systemImage: "arrow.up.right.square")
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var passwordFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("邮箱")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("name@example.com", text: $emailInput)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("密码")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField("输入 Z-Library 账号密码", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var tokenFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("快捷粘贴浏览器 Cookie（可选，自动识别下方字段）")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !rawCookieInput.isEmpty {
                        Button("识别填充") {
                            applyRawCookiePaste()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(FolioTheme.accent)
                    }
                }
                TextField("粘贴 Cookie: remix_userid=...; remix_userkey=... 或 JSON", text: $rawCookieInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .onChange(of: rawCookieInput) { _, newValue in
                        if let parsed = try? CookieParser.parse(rawText: newValue) {
                            userIDInput = parsed.remixUserID
                            userKeyInput = parsed.remixUserKey
                            errorMessage = nil
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("remix_userid")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("浏览器 Cookie 中的 remix_userid", text: $userIDInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("remix_userkey")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField("浏览器 Cookie 中的 remix_userkey", text: $userKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
            }
        }
    }

    private var footerActions: some View {
        HStack {
            Button("进入演示模式") {
                appState.switchToDemoMode()
                dismiss()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Spacer()

            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if mode != .web {
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 68)
                    } else {
                        Text(mode == .password ? "登录连接" : "验证连接")
                            .frame(minWidth: 68)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(FolioTheme.accent)
                .disabled(isSubmitting || !canSubmit)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var canSubmit: Bool {
        let hasDomain = !domainInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasDomain else { return false }
        switch mode {
        case .web:
            return true
        case .password:
            return !emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !passwordInput.isEmpty
        case .token:
            return !userIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !userKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func applyRawCookiePaste() {
        do {
            let parsed = try CookieParser.parse(rawText: rawCookieInput)
            userIDInput = parsed.remixUserID
            userKeyInput = parsed.remixUserKey
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func autoDiscoverOfficialDomain() {
        isAutoDiscovering = true
        Task {
            let best = await appState.eapiClient.discoverFastestOfficialDomain()
            if let best {
                probeResult = best
                if best.reachable {
                    domainInput = best.host
                }
            }
            isAutoDiscovering = false
        }
    }

    private func probeDomain() {
        isProbing = true
        probeResult = nil
        let target = domainInput
        Task {
            let result = await appState.eapiClient.probeDomain(target)
            probeResult = result
            isProbing = false
        }
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                switch mode {
                case .web:
                    isWebLoginPresented = true
                case .password:
                    try await appState.signInWithPassword(
                        domain: domainInput,
                        email: emailInput,
                        password: passwordInput
                    )
                    dismiss()
                case .token:
                    let extraCookies = (try? CookieParser.parse(rawText: rawCookieInput).cookies) ?? [:]
                    try await appState.signInWithTokens(
                        domain: domainInput,
                        userID: userIDInput,
                        userKey: userKeyInput,
                        cookies: extraCookies
                    )
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
