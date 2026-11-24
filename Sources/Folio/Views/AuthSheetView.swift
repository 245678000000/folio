import FolioCore
import SwiftUI

/// 双模式登录弹窗（邮箱密码登录 / remix_userid + remix_userkey 直连 + 域名连通性检测）
struct AuthSheetView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    enum AuthMode: String, CaseIterable, Identifiable {
        case password = "邮箱密码"
        case token = "Token 直连"
        var id: String { rawValue }
    }

    @State private var mode: AuthMode = .password
    @State private var domainInput: String = ""
    @State private var emailInput: String = ""
    @State private var passwordInput: String = ""
    @State private var userIDInput: String = ""
    @State private var userKeyInput: String = ""

    @State private var isSubmitting = false
    @State private var isProbing = false
    @State private var probeResult: DomainProbeResult?
    @State private var errorMessage: String?

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

                if mode == .password {
                    passwordFields
                } else {
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
        .padding(24)
        .frame(width: 450)
        .onAppear {
            domainInput = appState.session?.domain ?? appState.settings.lastDomain
            emailInput = appState.session?.email ?? ""
            userIDInput = appState.session?.remixUserID ?? ""
            userKeyInput = appState.session?.remixUserKey ?? ""
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
                Text("凭据仅保存在本机 macOS 钥匙串中，绝不上传至第三方服务。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var domainField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("服务器域名（推荐填写个人专属域名）")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("例如：your-personal.z-lib.fm", text: $domainInput)
                    .textFieldStyle(.roundedBorder)

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
            }

            if let probeResult {
                HStack(spacing: 5) {
                    Circle()
                        .fill(probeResult.reachable ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(probeResult.message)
                        .font(.system(size: 11))
                        .foregroundStyle(probeResult.reachable ? Color.secondary : Color.orange)
                }
            }

            if !appState.settings.recentDomains.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(appState.settings.recentDomains, id: \.self) { host in
                            Button(host) {
                                domainInput = host
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(FolioTheme.subtleFill))
                        }
                    }
                }
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

            Text("提示：若邮箱密码登录触发上游风控，可在浏览器登录后复制 Cookie 中的 remix_userid 与 remix_userkey 直接接入。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canSubmit: Bool {
        let hasDomain = !domainInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasDomain else { return false }
        switch mode {
        case .password:
            return !emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !passwordInput.isEmpty
        case .token:
            return !userIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !userKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                case .password:
                    try await appState.signInWithPassword(
                        domain: domainInput,
                        email: emailInput,
                        password: passwordInput
                    )
                case .token:
                    try await appState.signInWithTokens(
                        domain: domainInput,
                        userID: userIDInput,
                        userKey: userKeyInput
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
