import FolioCore
import SwiftUI

/// 原生毛玻璃左侧边栏 + 底部账户配额卡片
struct SidebarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { appState.selectedNav },
                set: { newValue in
                    if let newValue {
                        appState.selectNavigation(newValue)
                    }
                }
            )) {
                Section("发现") {
                    navRow(.mostPopular)
                    navRow(.recently)
                    navRow(.recommended)
                }

                Section("检索") {
                    navRow(.search)
                }

                Section("我的书库") {
                    navRow(.saved, badge: appState.savedBookIDs.isEmpty ? nil : appState.savedBookIDs.count)
                    navRow(.downloaded)
                }

                Section("本地传输") {
                    navRow(
                        .transfers,
                        badge: appState.activeDownloadCount > 0 ? appState.activeDownloadCount : nil,
                        highlightBadge: appState.activeDownloadCount > 0
                    )
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .opacity(0.45)

            accountFooterCard
                .padding(12)
        }
        .background(.ultraThinMaterial)
        .navigationSplitViewColumnWidth(min: 196, ideal: 218, max: 260)
    }

    private func navRow(_ item: SidebarItem, badge: Int? = nil, highlightBadge: Bool = false) -> some View {
        HStack(spacing: 8) {
            Label(item.title, systemImage: item.icon)
                .font(.system(size: 13, weight: .regular))
            Spacer(minLength: 4)
            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(highlightBadge ? Color.white : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(highlightBadge ? FolioTheme.accent : FolioTheme.subtleFill)
                    )
            }
        }
        .tag(item)
    }

    private var accountFooterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(appState.isDemoMode ? Color.orange.opacity(0.16) : FolioTheme.accent.opacity(0.16))
                        .frame(width: 30, height: 30)
                    Image(systemName: appState.isDemoMode ? "books.vertical.fill" : "person.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(appState.isDemoMode ? Color.orange : FolioTheme.accent)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 5) {
                        Text(appState.profile?.displayTitle ?? (appState.isDemoMode ? "演示书库" : "未登录"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)

                        if appState.isDemoMode {
                            Text("演示")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.14)))
                        }
                    }

                    Text(appState.isDemoMode ? "点击连接 Z-Library 账号" : (appState.session?.domain ?? "已连接"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if let quota = appState.profile?.quota, quota.dailyLimit > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("今日下载额度")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("剩余 \(quota.remaining) / \(quota.dailyLimit)")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(quota.remaining == 0 ? Color.red : Color.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(FolioTheme.subtleFill)
                            Capsule()
                                .fill(quota.remaining == 0 ? Color.red.opacity(0.8) : FolioTheme.accent)
                                .frame(width: max(4, geo.size.width * (1.0 - quota.progress)))
                        }
                    }
                    .frame(height: 4)
                }
            }

            HStack(spacing: 6) {
                Button {
                    appState.isAuthSheetPresented = true
                } label: {
                    Text(appState.isDemoMode ? "登录账号" : "切换账号")
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if appState.isDemoMode, appState.session != nil {
                    Button {
                        appState.switchToLiveSession()
                    } label: {
                        Image(systemName: "bolt.horizontal.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("切回已登录账号")
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FolioTheme.cardSurface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(FolioTheme.hairlineBorder, lineWidth: 0.75)
        )
    }
}
