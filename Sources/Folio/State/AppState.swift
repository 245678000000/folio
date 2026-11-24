import AppKit
import FolioCore
import Foundation
import Observation
import SwiftUI

/// 左侧边栏主导航枚举
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case mostPopular
    case recently
    case recommended
    case search
    case saved
    case downloaded
    case transfers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostPopular: return "热门精选"
        case .recently: return "最新上架"
        case .recommended: return "个性推荐"
        case .search: return "搜索书库"
        case .saved: return "云端收藏"
        case .downloaded: return "下载记录"
        case .transfers: return "传输队列"
        }
    }

    var icon: String {
        switch self {
        case .mostPopular: return "flame"
        case .recently: return "sparkles"
        case .recommended: return "wand.and.stars"
        case .search: return "magnifyingglass"
        case .saved: return "bookmark"
        case .downloaded: return "clock.arrow.circlepath"
        case .transfers: return "arrow.down.circle"
        }
    }
}

/// 轻提示消息模型
struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// 应用全局单一可信状态容器
@MainActor
@Observable
final class AppState {
    // MARK: - 核心依赖
    let eapiClient: EapiClient
    private let liveService: LiveLibraryService
    private let demoService: DemoLibraryService
    private let sessionStore: SessionStoreProtocol
    private let settingsStore: SettingsStore
    private let downloadExecutor: DownloadExecutor

    // MARK: - 导航与窗口态
    var selectedNav: SidebarItem = .mostPopular
    var isInspectorPresented: Bool = false
    var isAuthSheetPresented: Bool = false
    var shouldFocusSearchField: Bool = false

    // MARK: - 配置与认证状态
    var settings: AppSettings
    var session: Session?
    var profile: AccountProfile?
    var isDemoMode: Bool

    // MARK: - 书籍列表与加载态
    var books: [Book] = []
    var currentPage: Int = 1
    var totalPages: Int = 1
    var isLoadingList: Bool = false
    var isLoadingMore: Bool = false
    var listError: EapiError?

    // MARK: - 搜索与筛选
    var searchText: String = ""
    var searchQuery: SearchQuery = SearchQuery()
    var filterOptions: SearchFilterOptions = .fallback
    var showSearchFilters: Bool = false

    // MARK: - 云端收藏集合（用于即时星标反馈）
    var savedBookIDs: Set<String> = []

    // MARK: - 右侧检视器（书籍详情）
    var selectedBook: Book?
    var inspectorDetail: Book?
    var inspectorFormats: [BookFormat] = []
    var inspectorSimilar: [Book] = []
    var isLoadingInspector: Bool = false
    var isLoadingFormats: Bool = false

    // MARK: - 下载传输队列
    var downloadTasks: [DownloadTaskItem] = []
    private var runningDownloads: [UUID: Task<Void, Never>] = [:]
    private var activeListTask: Task<Void, Never>?
    private var activeInspectorTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?

    // MARK: - 轻提示
    var toast: ToastMessage?

    var activeService: LibraryServiceProtocol {
        isDemoMode ? demoService : liveService
    }

    var activeDownloadCount: Int {
        downloadTasks.filter { $0.status.isActive }.count
    }

    var hasMorePages: Bool {
        currentPage < totalPages && !books.isEmpty
    }

    var preferredColorScheme: ColorScheme? {
        switch settings.appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    init(
        sessionStore: SessionStoreProtocol = KeychainSessionStore(),
        settingsStore: SettingsStore = SettingsStore()
    ) {
        let loadedSettings = settingsStore.load()
        let loadedSession = sessionStore.loadSession()

        self.settingsStore = settingsStore
        self.sessionStore = sessionStore
        self.settings = loadedSettings
        self.session = loadedSession

        let client = EapiClient(proxy: loadedSettings.proxy)
        self.eapiClient = client
        self.liveService = LiveLibraryService(client: client)
        self.demoService = DemoLibraryService()
        self.downloadExecutor = DownloadExecutor(proxy: loadedSettings.proxy)

        // 若本地尚无登录会话，则默认开启离线演示书库，避免冷启动空白墙
        if loadedSession == nil {
            self.isDemoMode = true
        } else {
            self.isDemoMode = loadedSettings.isDemoMode
        }
    }

    // MARK: - 启动初始化

    func bootstrap() async {
        await CoverImageCache.shared.updateProxy(settings.proxy)
        await refreshAccountContext()
        await loadCurrentSection()
    }

    func refreshAccountContext() async {
        do {
            let fetchedProfile = try await activeService.profile(session: session)
            self.profile = fetchedProfile
        } catch {
            if !isDemoMode {
                self.profile = session.map {
                    AccountProfile(id: $0.remixUserID, email: $0.email, domain: $0.domain)
                }
            }
        }

        // 静默同步首页收藏 ID，用于书墙星标回显
        if let saved = try? await activeService.savedBooks(page: 1, limit: 50, session: session) {
            self.savedBookIDs = Set(saved.books.map(\.id))
        }

        // 拉取筛选语言与格式
        let domain = session?.domain ?? settings.lastDomain
        if let options = try? await activeService.filterOptions(domain: domain) {
            self.filterOptions = options
        }
    }

    // MARK: - 导航与数据加载

    func selectNavigation(_ item: SidebarItem) {
        selectedNav = item
        if item == .transfers {
            listError = nil
            return
        }
        if item == .search {
            if searchQuery.message.isEmpty {
                books = []
                listError = nil
                currentPage = 1
                totalPages = 1
                return
            }
        }
        Task {
            await loadCurrentSection()
        }
    }

    func loadCurrentSection() async {
        activeListTask?.cancel()
        if selectedNav == .transfers { return }

        let targetNav = selectedNav
        let task = Task { @MainActor in
            isLoadingList = true
            listError = nil
            currentPage = 1
            totalPages = 1

            do {
                let fallbackDomain = settings.lastDomain.isEmpty ? nil : settings.lastDomain
                switch targetNav {
                case .mostPopular:
                    let list = try await activeService.mostPopular(session: session, fallbackDomain: fallbackDomain)
                    try Task.checkCancellation()
                    books = list
                case .recently:
                    let list = try await activeService.recently(session: session, fallbackDomain: fallbackDomain)
                    try Task.checkCancellation()
                    books = list
                case .recommended:
                    let list = try await activeService.recommended(session: session)
                    try Task.checkCancellation()
                    books = list
                case .search:
                    guard !searchQuery.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        books = []
                        isLoadingList = false
                        return
                    }
                    let page = try await activeService.search(
                        query: searchQuery,
                        page: 1,
                        limit: 30,
                        session: session,
                        fallbackDomain: fallbackDomain
                    )
                    try Task.checkCancellation()
                    books = page.books
                    currentPage = page.page
                    totalPages = page.totalPages
                case .saved:
                    let page = try await activeService.savedBooks(page: 1, limit: 30, session: session)
                    try Task.checkCancellation()
                    books = page.books
                    currentPage = page.page
                    totalPages = page.totalPages
                    savedBookIDs.formUnion(page.books.map(\.id))
                case .downloaded:
                    let page = try await activeService.downloadedBooks(page: 1, limit: 30, session: session)
                    try Task.checkCancellation()
                    books = page.books
                    currentPage = page.page
                    totalPages = page.totalPages
                case .transfers:
                    break
                }
            } catch is CancellationError {
                return
            } catch let error as EapiError {
                if error != .cancelled {
                    listError = error
                }
            } catch {
                listError = .network(error.localizedDescription)
            }
            isLoadingList = false
        }
        activeListTask = task
        await task.value
    }

    func loadNextPage() async {
        guard !isLoadingMore, hasMorePages else { return }
        let nextPage = currentPage + 1
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let fallbackDomain = settings.lastDomain.isEmpty ? nil : settings.lastDomain
            let page: BookPage
            switch selectedNav {
            case .search:
                page = try await activeService.search(
                    query: searchQuery,
                    page: nextPage,
                    limit: 30,
                    session: session,
                    fallbackDomain: fallbackDomain
                )
            case .saved:
                page = try await activeService.savedBooks(page: nextPage, limit: 30, session: session)
            case .downloaded:
                page = try await activeService.downloadedBooks(page: nextPage, limit: 30, session: session)
            default:
                return
            }

            var existingRefs = Set(books.map(\.ref))
            let appended = page.books.filter { existingRefs.insert($0.ref).inserted }
            books.append(contentsOf: appended)
            currentPage = page.page
            totalPages = page.totalPages
        } catch let error as EapiError {
            showToast(error.localizedDescription, isError: true)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: - 搜索交互

    func submitSearch(keyword: String? = nil) {
        let raw = (keyword ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        searchText = raw
        searchQuery.message = raw
        recordSearchHistory(raw)
        selectedNav = .search
        Task {
            await loadCurrentSection()
        }
    }

    func applySearchFilters() {
        guard !searchQuery.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        selectedNav = .search
        Task {
            await loadCurrentSection()
        }
    }

    func clearSearchFilters() {
        let message = searchQuery.message
        searchQuery = SearchQuery(message: message)
        if !message.isEmpty {
            applySearchFilters()
        }
    }

    private func recordSearchHistory(_ term: String) {
        var history = settings.searchHistory.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        history.insert(term, at: 0)
        settings.searchHistory = Array(history.prefix(12))
        persistSettings()
    }

    func clearSearchHistory() {
        settings.searchHistory = []
        persistSettings()
    }

    // MARK: - 右侧检视器（书籍详情）

    func inspect(book: Book) {
        selectedBook = book
        inspectorDetail = book
        inspectorFormats = []
        inspectorSimilar = []
        isInspectorPresented = true

        activeInspectorTask?.cancel()
        let ref = book.ref
        activeInspectorTask = Task { @MainActor in
            isLoadingInspector = true
            isLoadingFormats = true
            let fallbackDomain = settings.lastDomain.isEmpty ? nil : settings.lastDomain

            async let detailFetch = try? activeService.bookDetail(
                id: book.id,
                hash: book.hash,
                session: session,
                fallbackDomain: fallbackDomain
            )
            async let formatsFetch = try? activeService.bookFormats(
                id: book.id,
                hash: book.hash,
                session: session
            )
            async let similarFetch = try? activeService.similarBooks(
                id: book.id,
                hash: book.hash,
                session: session,
                fallbackDomain: fallbackDomain
            )

            let (detail, formats, similar) = await (detailFetch, formatsFetch, similarFetch)
            guard !Task.isCancelled, selectedBook?.ref == ref else { return }

            if let detail {
                inspectorDetail = detail
            }
            inspectorFormats = formats ?? []
            inspectorSimilar = similar ?? []
            isLoadingInspector = false
            isLoadingFormats = false
        }
    }

    func closeInspector() {
        activeInspectorTask?.cancel()
        isInspectorPresented = false
    }

    // MARK: - 收藏与下载历史操作

    func isSaved(_ book: Book) -> Bool {
        savedBookIDs.contains(book.id)
    }

    func toggleSaved(_ book: Book) {
        let targetState = !savedBookIDs.contains(book.id)
        if targetState {
            savedBookIDs.insert(book.id)
        } else {
            savedBookIDs.remove(book.id)
        }

        Task {
            do {
                try await activeService.setBookSaved(id: book.id, saved: targetState, session: session)
                showToast(targetState ? "已加入云端收藏" : "已取消收藏", isError: false)
                if !targetState && selectedNav == .saved {
                    books.removeAll { $0.id == book.id }
                }
            } catch {
                // 失败时回滚乐观状态
                if targetState {
                    savedBookIDs.remove(book.id)
                } else {
                    savedBookIDs.insert(book.id)
                }
                showToast(error.localizedDescription, isError: true)
            }
        }
    }

    func deleteCloudHistoryRecord(_ book: Book) {
        Task {
            do {
                try await activeService.deleteDownloadHistory(id: book.id, session: session)
                books.removeAll { $0.id == book.id }
                showToast("已从云端下载记录移除", isError: false)
            } catch {
                showToast(error.localizedDescription, isError: true)
            }
        }
    }

    // MARK: - 下载与本地打开

    func startDownload(book: Book, format: BookFormat? = nil) {
        let targetID = format?.id ?? book.id
        let targetHash = format?.hash ?? book.hash
        let targetExt = format?.fileExtension ?? (book.fileExtension.isEmpty ? "epub" : book.fileExtension)

        if !isDemoMode && session == nil {
            isAuthSheetPresented = true
            showToast("请先登录 Z-Library 账号后再下载电子书", isError: true)
            return
        }

        let item = DownloadTaskItem(
            book: book,
            targetID: targetID,
            targetHash: targetHash,
            targetExtension: targetExt,
            status: .queued
        )
        downloadTasks.insert(item, at: 0)
        showToast("已开始下载《\(book.title)》（\(item.displayExtension)）", isError: false)
        launchDownloadTask(item)
    }

    func retryDownload(_ item: DownloadTaskItem) {
        updateDownloadStatus(id: item.id, status: .queued)
        launchDownloadTask(item)
    }

    func cancelDownload(_ item: DownloadTaskItem) {
        runningDownloads[item.id]?.cancel()
        runningDownloads.removeValue(forKey: item.id)
        updateDownloadStatus(id: item.id, status: .cancelled)
    }

    func clearFinishedDownloads() {
        downloadTasks.removeAll { !$0.status.isActive }
    }

    /// 调用系统默认阅读器（Apple Books / Readest / 预览等）打开本地电子书
    func openDownloadedFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            showToast("本地文件不存在，可能已被移动或删除", isError: true)
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 在 Finder 中定位已下载文件
    func revealInFinder(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            showToast("本地文件不存在", isError: true)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func launchDownloadTask(_ item: DownloadTaskItem) {
        let taskID = item.id
        let destinationDir = settings.downloadDirectoryURL
        let useDemo = isDemoMode
        let currentSession = session
        let executor = downloadExecutor
        let client = eapiClient
        let demo = demoService

        let reportStatus: @Sendable (DownloadItemStatus) -> Void = { [weak self] status in
            Task { @MainActor in
                self?.updateDownloadStatus(id: taskID, status: status)
            }
        }

        let task = Task { [weak self] in
            do {
                if useDemo {
                    _ = try await executor.downloadDemo(
                        book: item.book,
                        targetExtension: item.targetExtension,
                        destinationDirectory: destinationDir,
                        onStatus: reportStatus
                    )
                    await demo.recordDemoDownload(bookID: item.book.id)
                } else {
                    guard let currentSession else {
                        throw EapiError.notLoggedIn
                    }
                    _ = try await executor.downloadLive(
                        book: item.book,
                        targetID: item.targetID,
                        targetHash: item.targetHash,
                        targetExtension: item.targetExtension,
                        session: currentSession,
                        client: client,
                        destinationDirectory: destinationDir,
                        onStatus: reportStatus
                    )
                }

                await MainActor.run { [weak self] in
                    self?.runningDownloads.removeValue(forKey: taskID)
                    self?.showToast("《\(item.book.title)》下载完成，可在传输队列一键打开阅读", isError: false)
                }
                await self?.refreshAccountContext()
            } catch let error as EapiError where error == .cancelled {
                await MainActor.run { [weak self] in
                    self?.runningDownloads.removeValue(forKey: taskID)
                    self?.updateDownloadStatus(id: taskID, status: .cancelled)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.runningDownloads.removeValue(forKey: taskID)
                    self?.updateDownloadStatus(id: taskID, status: .failed(message: error.localizedDescription))
                    self?.showToast("下载失败：\(error.localizedDescription)", isError: true)
                }
            }
        }
        runningDownloads[taskID] = task
    }

    private func updateDownloadStatus(id: UUID, status: DownloadItemStatus) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == id }) else { return }
        downloadTasks[index].status = status
    }

    // MARK: - 认证与域名配置

    /// 邮箱 + 密码登录
    func signInWithPassword(domain: String, email: String, password: String) async throws {
        let newSession = try await eapiClient.login(domain: domain, email: email, password: password)
        try applyAuthenticatedSession(newSession)
        await refreshAccountContext()
        await loadCurrentSection()
        showToast("已成功连接 \(newSession.domain)", isError: false)
    }

    /// Token / Cookie 直连登录（先验证 Profile 有效性，保留网页捕获的完整 Cookie）
    func signInWithTokens(
        domain: String,
        userID: String,
        userKey: String,
        cookies: [String: String] = [:]
    ) async throws {
        let host = try DomainPolicy.normalizeHost(domain)
        let cleanID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = userKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty, !cleanKey.isEmpty else {
            throw EapiError.invalidParameters("请完整填写 remix_userid 与 remix_userkey")
        }

        let candidate = Session(
            remixUserID: cleanID,
            remixUserKey: cleanKey,
            domain: host,
            cookies: cookies
        )
        let verifiedProfile = try await eapiClient.profile(session: candidate)
        let enrichedSession = Session(
            remixUserID: cleanID,
            remixUserKey: cleanKey,
            domain: host,
            email: verifiedProfile.email,
            cookies: cookies
        )
        try applyAuthenticatedSession(enrichedSession)
        self.profile = verifiedProfile
        await refreshAccountContext()
        await loadCurrentSection()
        showToast("登录验证通过，已连接 \(host)", isError: false)
    }

    /// 在系统默认浏览器中直接打开官方网站
    func openOfficialWebsite(preferredDomain: String? = nil) {
        let raw = preferredDomain ?? session?.domain ?? settings.lastDomain
        let host = (try? DomainPolicy.normalizeHost(raw)) ?? DomainPolicy.defaultOfficialHost
        if let url = URL(string: "https://\(host)/") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 在系统默认浏览器中打开指定书籍的官方网页
    func openBookOnOfficialSite(_ book: Book) {
        let raw = session?.domain ?? settings.lastDomain
        let host = (try? DomainPolicy.normalizeHost(raw)) ?? DomainPolicy.defaultOfficialHost
        let urlString: String
        if book.href.hasPrefix("http://") || book.href.hasPrefix("https://") {
            urlString = book.href
        } else if !book.href.isEmpty {
            let path = book.href.hasPrefix("/") ? book.href : "/\(book.href)"
            urlString = "https://\(host)\(path)"
        } else {
            urlString = "https://\(host)/book/\(book.id)/\(book.hash)"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func applyAuthenticatedSession(_ newSession: Session) throws {
        try sessionStore.saveSession(newSession)
        self.session = newSession
        self.isDemoMode = false
        settings.isDemoMode = false
        settings.lastDomain = newSession.domain
        var recents = settings.recentDomains.filter { $0 != newSession.domain }
        recents.insert(newSession.domain, at: 0)
        settings.recentDomains = Array(recents.prefix(6))
        persistSettings()
        isAuthSheetPresented = false
    }

    /// 切换离线演示模式
    func switchToDemoMode() {
        isDemoMode = true
        settings.isDemoMode = true
        persistSettings()
        isAuthSheetPresented = false
        Task {
            await refreshAccountContext()
            await loadCurrentSection()
            showToast("已切换至离线演示书库", isError: false)
        }
    }

    /// 切回已保存的真实账号
    func switchToLiveSession() {
        guard session != nil else {
            isAuthSheetPresented = true
            return
        }
        isDemoMode = false
        settings.isDemoMode = false
        persistSettings()
        Task {
            await refreshAccountContext()
            await loadCurrentSection()
            showToast("已恢复连接 Z-Library 账号", isError: false)
        }
    }

    /// 退出登录并清除 Keychain 凭据
    func signOut() {
        try? sessionStore.clearSession()
        session = nil
        profile = nil
        savedBookIDs = []
        isDemoMode = true
        settings.isDemoMode = true
        persistSettings()
        Task {
            await refreshAccountContext()
            await loadCurrentSection()
            showToast("已退出登录并清除钥匙串凭据", isError: false)
        }
    }

    // MARK: - 偏好设置与代理更新

    func updateProxy(_ proxy: ProxyConfiguration) {
        settings.proxy = proxy
        persistSettings()
        Task {
            await eapiClient.updateProxy(proxy)
            await downloadExecutor.updateProxy(proxy)
            await CoverImageCache.shared.updateProxy(proxy)
            showToast("网络代理配置已生效", isError: false)
        }
    }

    func updateDownloadDirectory(_ url: URL) {
        settings.downloadDirectoryPath = url.path
        persistSettings()
        showToast("下载目录已更改为 \(url.lastPathComponent)", isError: false)
    }

    func updateAppearance(_ mode: AppearanceMode) {
        settings.appearanceMode = mode
        persistSettings()
    }

    func updateDisplayMode(_ mode: BooksDisplayMode) {
        settings.displayMode = mode
        persistSettings()
    }

    func persistSettings() {
        settingsStore.save(settings)
    }

    func showToast(_ message: String, isError: Bool) {
        toastDismissTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            toast = ToastMessage(text: message, isError: isError)
        }
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(isError ? 4.2 : 2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                toast = nil
            }
        }
    }
}
