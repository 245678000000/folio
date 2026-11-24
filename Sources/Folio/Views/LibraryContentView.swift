import FolioCore
import SwiftUI

/// 主书库内容展示区（统一承载发现、搜索、收藏、下载记录与传输队列）
struct LibraryContentView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.selectedNav == .transfers {
                DownloadsView(appState: appState)
            } else {
                sectionHeader

                if appState.selectedNav == .search && appState.showSearchFilters {
                    SearchFilterBar(appState: appState)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                contentBody
            }
        }
        .background(FolioTheme.canvasBackground)
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(appState.selectedNav.title)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(.primary)

            if appState.selectedNav == .search && !appState.searchQuery.message.isEmpty {
                Text("“\(appState.searchQuery.message)”")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !appState.books.isEmpty && !appState.isLoadingList {
                Text("\(appState.books.count) 本")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if appState.selectedNav == .search {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.showSearchFilters.toggle()
                    }
                } label: {
                    Label(
                        appState.searchQuery.hasActiveFilters ? "筛选中" : "筛选",
                        systemImage: appState.searchQuery.hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                    .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var contentBody: some View {
        if appState.isLoadingList {
            loadingSkeletonView
        } else if let error = appState.listError {
            EmptyStateView(
                icon: errorIcon(for: error),
                title: "暂时无法加载内容",
                subtitle: [error.localizedDescription, error.recoverySuggestion]
                    .compactMap { $0 }
                    .joined(separator: "\n"),
                actionTitle: "重试",
                secondaryActionTitle: shouldOfferAuthAction(for: error) ? "账号与域名设置" : nil,
                action: {
                    Task { await appState.loadCurrentSection() }
                },
                secondaryAction: shouldOfferAuthAction(for: error)
                    ? { appState.isAuthSheetPresented = true }
                    : nil
            )
        } else if appState.selectedNav == .search && appState.searchQuery.message.isEmpty {
            searchLandingView
        } else if appState.books.isEmpty {
            EmptyStateView(
                icon: emptyIcon,
                title: emptyTitle,
                subtitle: emptySubtitle,
                actionTitle: appState.selectedNav == .search && appState.searchQuery.hasActiveFilters ? "清空筛选条件" : nil,
                action: appState.selectedNav == .search && appState.searchQuery.hasActiveFilters
                    ? { appState.clearSearchFilters() }
                    : nil
            )
        } else {
            switch appState.settings.displayMode {
            case .grid:
                BookGridView(appState: appState, books: appState.books)
            case .list:
                BookListView(appState: appState, books: appState.books)
            }
        }
    }

    /// 搜索页初始优雅引导（展示搜索历史与推荐关键词）
    private var searchLandingView: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(.secondary.opacity(0.65))

            VStack(spacing: 6) {
                Text("输入书名、作者或 ISBN 开始检索")
                    .font(.system(size: 16, weight: .semibold))
                Text("按下 ⌘K 可随时聚焦顶部搜索栏，支持按语言、格式、出版年份筛选。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            if !appState.settings.searchHistory.isEmpty {
                VStack(spacing: 10) {
                    HStack {
                        Text("最近搜索")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("清空") {
                            appState.clearSearchHistory()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: 460)

                    FlowChipGrid(items: appState.settings.searchHistory) { term in
                        appState.submitSearch(keyword: term)
                    }
                    .frame(maxWidth: 460)
                }
            }

            VStack(spacing: 10) {
                Text("试试搜索")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)

                FlowChipGrid(items: ["设计心理学", "Swift", "三体", "Typography", "人类简史", "架构"]) { keyword in
                    appState.submitSearch(keyword: keyword)
                }
                .frame(maxWidth: 460)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 优雅静谧骨架屏
    private var loadingSkeletonView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 152, maximum: 184), spacing: 24)],
                spacing: 28
            ) {
                ForEach(0..<10, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(FolioTheme.subtleFill)
                            .aspectRatio(FolioTheme.coverAspectRatio, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(FolioTheme.subtleFill)
                            .frame(height: 13)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(FolioTheme.subtleFill)
                            .frame(width: 96, height: 10)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
        }
        .redacted(reason: .placeholder)
    }

    private func errorIcon(for error: EapiError) -> String {
        switch error {
        case .notLoggedIn, .sessionExpired: return "person.crop.circle.badge.exclamationmark"
        case .searchRefused, .domainBlocked: return "shield.lefthalf.filled.trianglebadge.exclamationmark"
        case .network: return "wifi.exclamationmark"
        default: return "exclamationmark.triangle"
        }
    }

    private func shouldOfferAuthAction(for error: EapiError) -> Bool {
        switch error {
        case .noDomain, .invalidDomain, .notLoggedIn, .sessionExpired, .searchRefused, .domainBlocked:
            return true
        default:
            return false
        }
    }

    private var emptyIcon: String {
        switch appState.selectedNav {
        case .saved: return "bookmark"
        case .downloaded: return "clock.arrow.circlepath"
        case .search: return "magnifyingglass"
        default: return "books.vertical"
        }
    }

    private var emptyTitle: String {
        switch appState.selectedNav {
        case .saved: return "云端收藏还是空的"
        case .downloaded: return "暂无云端下载记录"
        case .search: return "没有找到匹配的电子书"
        default: return "暂无可展示的书籍"
        }
    }

    private var emptySubtitle: String {
        switch appState.selectedNav {
        case .saved: return "浏览书墙或详情面板时点击书签图标，即可同步收藏到云端。"
        case .downloaded: return "下载过的电子书会自动记录在这里，方便随时回溯。"
        case .search: return "尝试缩短关键词、关闭精确匹配或放宽语言与格式筛选条件。"
        default: return "点击右上角刷新按钮重新拉取书单。"
        }
    }
}

/// 简易自适应标签流布局
private struct FlowChipGrid: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Capsule(style: .continuous).fill(FolioTheme.cardSurface))
                        .overlay(Capsule(style: .continuous).strokeBorder(FolioTheme.hairlineBorder, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
