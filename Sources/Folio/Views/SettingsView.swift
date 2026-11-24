import AppKit
import FolioCore
import SwiftUI

/// 原生 macOS 偏好设置窗口（⌘, 打开）
struct SettingsView: View {
    @Bindable var appState: AppState

    @State private var proxyMode: ProxyMode = .system
    @State private var proxyHost: String = "127.0.0.1"
    @State private var proxyPortText: String = "7890"

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("常规", systemImage: "gearshape") }

            accountTab
                .tabItem { Label("账号与域名", systemImage: "person.crop.circle") }

            networkTab
                .tabItem { Label("网络与代理", systemImage: "network") }

            aboutTab
                .tabItem { Label("关于", systemImage: "book.closed") }
        }
        .frame(width: 500, height: 320)
        .onAppear {
            proxyMode = appState.settings.proxy.mode
            proxyHost = appState.settings.proxy.host
            proxyPortText = String(appState.settings.proxy.port)
        }
    }

    private var generalTab: some View {
        Form {
            Section("外观与布局") {
                Picker("界面主题", selection: Binding(
                    get: { appState.settings.appearanceMode },
                    set: { appState.updateAppearance($0) }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("默认书单视图", selection: Binding(
                    get: { appState.settings.displayMode },
                    set: { appState.updateDisplayMode($0) }
                )) {
                    ForEach(BooksDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("电子书保存位置") {
                HStack {
                    Text(appState.settings.downloadDirectoryPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("选择目录…") {
                        chooseDownloadFolder()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }

    private var accountTab: some View {
        Form {
            Section("当前连接状态") {
                LabeledContent("运行模式", value: appState.isDemoMode ? "离线演示书库" : "Z-Library EAPI 实连")
                if let session = appState.session {
                    LabeledContent("服务器域名", value: session.domain)
                    LabeledContent("用户 ID", value: session.remixUserID)
                    if !session.email.isEmpty {
                        LabeledContent("账户邮箱", value: session.email)
                    }
                }
                if let quota = appState.profile?.quota {
                    LabeledContent("今日下载配额", value: "已用 \(quota.usedToday) / 上限 \(quota.dailyLimit)（剩余 \(quota.remaining)）")
                }
            }

            Section("账号操作") {
                HStack(spacing: 10) {
                    Button(appState.session == nil ? "登录 Z-Library 账号" : "更换账号或域名") {
                        appState.isAuthSheetPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FolioTheme.accent)

                    if appState.isDemoMode && appState.session != nil {
                        Button("恢复实连模式") {
                            appState.switchToLiveSession()
                        }
                    } else if !appState.isDemoMode {
                        Button("切换演示模式") {
                            appState.switchToDemoMode()
                        }
                    }

                    Spacer()

                    if appState.session != nil {
                        Button("退出登录", role: .destructive) {
                            appState.signOut()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }

    private var networkTab: some View {
        Form {
            Section("代理方式") {
                Picker("代理模式", selection: $proxyMode) {
                    ForEach(ProxyMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if proxyMode != .system {
                    TextField("代理主机", text: $proxyHost)
                    TextField("代理端口", text: $proxyPortText)
                }

                HStack {
                    Spacer()
                    Button("保存并应用代理") {
                        let port = Int(proxyPortText.trimmingCharacters(in: .whitespaces)) ?? 7890
                        let config = ProxyConfiguration(
                            mode: proxyMode,
                            host: proxyHost.trimmingCharacters(in: .whitespacesAndNewlines),
                            port: min(65535, max(1, port))
                        )
                        appState.updateProxy(config)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FolioTheme.accent)
                }
            }

            Section("说明") {
                Text("默认跟随 macOS 系统代理（兼容 Clash / Surge 等系统代理配置）。所有 EAPI 请求已内置客户端来源标识头，且跨域下载重定向会自动剥离账号凭据。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 38))
                .foregroundStyle(FolioTheme.accent)
                .padding(.top, 18)

            Text("Folio")
                .font(.system(size: 20, weight: .bold, design: .serif))

            Text("简洁、美观、轻量的 macOS 原生 Z-Library EAPI 电子书客户端")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            Text("版本 1.0.0 · SwiftUI 原生架构 · 零第三方依赖")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择保存目录"
        panel.directoryURL = appState.settings.downloadDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            appState.updateDownloadDirectory(url)
        }
    }
}
