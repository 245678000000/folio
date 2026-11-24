import FolioCore
import SwiftUI

/// 主应用三段式窗口骨架（毛玻璃侧边栏 + 主书墙 + 右侧书籍检视器）
struct MainWindowView: View {
    @Bindable var appState: AppState
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
        } detail: {
            LibraryContentView(appState: appState)
                .inspector(isPresented: $appState.isInspectorPresented) {
                    BookInspectorView(appState: appState)
                        .inspectorColumnWidth(min: 310, ideal: 348, max: 430)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .principal) {
                toolbarSearchBar
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Picker("视图模式", selection: Binding(
                    get: { appState.settings.displayMode },
                    set: { appState.updateDisplayMode($0) }
                )) {
                    Image(systemName: "square.grid.2x2")
                        .help("封面网格视图")
                        .tag(BooksDisplayMode.grid)
                    Image(systemName: "list.bullet")
                        .help("简洁列表视图")
                        .tag(BooksDisplayMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 72)

                Button {
                    Task { await appState.loadCurrentSection() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新当前页面 (⌘R)")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.isInspectorPresented.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("显示或隐藏书籍详情面板")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.toast {
                ToastBannerView(message: toast.text, isError: toast.isError)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $appState.isAuthSheetPresented) {
            AuthSheetView(appState: appState)
        }
        .onChange(of: appState.shouldFocusSearchField) { _, triggered in
            if triggered {
                isSearchFocused = true
                appState.shouldFocusSearchField = false
            }
        }
        .onKeyPress(.escape) {
            if appState.isInspectorPresented {
                appState.closeInspector()
                return .handled
            }
            return .ignored
        }
        .preferredColorScheme(appState.preferredColorScheme)
        .frame(minWidth: 920, minHeight: 600)
        .task {
            await appState.bootstrap()
        }
    }

    /// 顶栏融合极简搜索框
    private var toolbarSearchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索书名、作者或 ISBN… (⌘K)", text: $appState.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isSearchFocused)
                .onSubmit {
                    appState.submitSearch()
                }

            if !appState.searchText.isEmpty {
                Button {
                    appState.searchText = ""
                    if appState.selectedNav == .search {
                        appState.searchQuery.message = ""
                        appState.books = []
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5.5)
        .frame(minWidth: 260, idealWidth: 340, maxWidth: 440)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FolioTheme.subtleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSearchFocused ? FolioTheme.accent.opacity(0.6) : FolioTheme.hairlineBorder, lineWidth: 1)
        )
    }
}
