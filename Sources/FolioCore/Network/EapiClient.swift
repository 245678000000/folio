import Foundation

/// 表单 URL 编码构造器
public struct FormURLEncoder: Sendable {
    private var items: [(String, String)] = []

    public init() {}

    public mutating func add(_ name: String, _ value: String) {
        items.append((name, value))
    }

    public func encodedString() -> String {
        items.map { key, value in
            "\(Self.escape(key))=\(Self.escape(value))"
        }.joined(separator: "&")
    }

    public func encodedData() -> Data {
        Data(encodedString().utf8)
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// 下载解析结果：明确给出可直接流式下载的 URLRequest 与服务端建议文件名
public struct ResolvedDownloadTarget: Sendable {
    public let request: URLRequest
    public let suggestedFilename: String?
    public let directData: Data?
    public let directResponse: HTTPURLResponse?

    public init(
        request: URLRequest,
        suggestedFilename: String? = nil,
        directData: Data? = nil,
        directResponse: HTTPURLResponse? = nil
    ) {
        self.request = request
        self.suggestedFilename = suggestedFilename
        self.directData = directData
        self.directResponse = directResponse
    }
}

/// 域名连通性探测结果
public struct DomainProbeResult: Sendable, Equatable {
    public let host: String
    public let reachable: Bool
    public let latencyMs: Int
    public let statusCode: Int?
    public let message: String

    public init(host: String, reachable: Bool, latencyMs: Int, statusCode: Int?, message: String) {
        self.host = host
        self.reachable = reachable
        self.latencyMs = latencyMs
        self.statusCode = statusCode
        self.message = message
    }
}

/// Z-Library EAPI 异步并发客户端
public actor EapiClient {
    private var proxy: ProxyConfiguration
    private var urlSession: URLSession
    private let protocolClasses: [AnyClass]?

    public init(
        proxy: ProxyConfiguration = .systemDefault,
        protocolClasses: [AnyClass]? = nil
    ) {
        self.proxy = proxy
        self.protocolClasses = protocolClasses
        self.urlSession = ProxySessionFactory.makeSession(
            proxy: proxy,
            protocolClasses: protocolClasses
        )
    }

    /// 运行时动态切换代理配置
    public func updateProxy(_ newProxy: ProxyConfiguration) {
        guard newProxy != proxy else { return }
        self.proxy = newProxy
        self.urlSession.finishTasksAndInvalidate()
        self.urlSession = ProxySessionFactory.makeSession(
            proxy: newProxy,
            protocolClasses: protocolClasses
        )
    }

    /// 供下载器复用的当前网络配置快照
    public func currentProxyConfiguration() -> ProxyConfiguration {
        proxy
    }

    // MARK: - 认证与账户

    /// 邮箱 + 密码登录 `/eapi/user/login`
    public func login(domain rawDomain: String, email: String, password: String) async throws -> Session {
        let host = try DomainPolicy.normalizeHost(rawDomain)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            throw EapiError.invalidParameters("邮箱和密码不能为空")
        }

        var form = FormURLEncoder()
        form.add("email", trimmedEmail)
        form.add("password", password)

        let exchange = try await executeJSON(
            host: host,
            path: EapiEndpoints.login,
            method: "POST",
            formBody: form.encodedData(),
            session: nil
        )

        let root = exchange.root
        let userObj = EapiJSONParser.object(root, "user")
        var cookies = Self.parseSetCookies(from: exchange.response)

        let userID = userObj.flatMap { EapiJSONParser.string($0, "id") }
            ?? cookies[Session.userIDCookieName]
            ?? EapiJSONParser.string(root, "remix_userid")
            ?? EapiJSONParser.string(root, "user_id")
            ?? ""

        let userKey = userObj.flatMap { EapiJSONParser.string($0, "remix_userkey") ?? EapiJSONParser.string($0, "remix_user_key") }
            ?? cookies[Session.userKeyCookieName]
            ?? cookies["remix_user_key"]
            ?? EapiJSONParser.string(root, "remix_userkey")
            ?? EapiJSONParser.string(root, "remix_user_key")
            ?? ""

        guard !userID.isEmpty, !userKey.isEmpty else {
            throw EapiError.parse("登录已成功响应，但缺少 remix_userid 或 remix_userkey 凭据")
        }

        cookies[Session.userIDCookieName] = userID
        cookies[Session.userKeyCookieName] = userKey

        let resolvedEmail = userObj.flatMap { EapiJSONParser.string($0, "email") } ?? trimmedEmail

        return Session(
            remixUserID: userID,
            remixUserKey: userKey,
            domain: host,
            email: resolvedEmail,
            cookies: cookies
        )
    }

    /// 获取账户资料与每日下载配额 `/eapi/user/profile`
    public func profile(session: Session) async throws -> AccountProfile {
        let exchange = try await executeJSON(
            host: session.domain,
            path: EapiEndpoints.profile,
            method: "GET",
            formBody: nil,
            session: session
        )
        let root = exchange.root
        let userObj = EapiJSONParser.object(root, "user") ?? root

        let id = EapiJSONParser.string(userObj, "id") ?? session.remixUserID
        let email = EapiJSONParser.string(userObj, "email") ?? session.email
        let name = EapiJSONParser.string(userObj, "name") ?? ""
        let kindleEmail = EapiJSONParser.string(userObj, "kindle_email") ?? ""

        let usedToday = EapiJSONParser.int(userObj, "downloads_today")
        let dailyLimit = EapiJSONParser.int(userObj, "downloads_limit")
        let resetText = EapiJSONParser.string(userObj, "downloads_reset_time")
        let quota: DownloadQuota? = if let used = usedToday, let limit = dailyLimit {
            DownloadQuota(usedToday: used, dailyLimit: limit, resetDescription: resetText)
        } else {
            nil
        }

        return AccountProfile(
            id: id,
            email: email,
            name: name,
            kindleEmail: kindleEmail,
            domain: session.domain,
            quota: quota,
            isDemo: false
        )
    }

    // MARK: - 搜索与发现

    /// 搜索电子书 `POST /eapi/book/search`
    public func search(
        query: SearchQuery,
        page: Int = 1,
        limit: Int = 30,
        session: Session?,
        fallbackDomain: String? = nil
    ) async throws -> BookPage {
        let trimmedMessage = query.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw EapiError.invalidParameters("搜索关键词不能为空")
        }

        let host = try resolveHost(session: session, fallbackDomain: fallbackDomain)
        let requestedPage = max(1, page)
        let clampedLimit = min(50, max(1, limit))

        var form = FormURLEncoder()
        form.add("message", trimmedMessage)
        form.add("page", String(requestedPage))
        form.add("limit", String(clampedLimit))
        if query.exact {
            form.add("e", "1")
        }
        if let yearFrom = query.yearFrom {
            form.add("yearFrom", String(yearFrom))
        }
        if let yearTo = query.yearTo {
            form.add("yearTo", String(yearTo))
        }
        if let wireSort = query.sort.wireValue {
            form.add("order", wireSort)
        }
        for language in query.languages {
            let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty {
                form.add("languages[]", normalized)
            }
        }
        for ext in query.extensions {
            let normalized = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty {
                form.add("extensions[]", normalized)
            }
        }

        do {
            let exchange = try await executeJSON(
                host: host,
                path: EapiEndpoints.search,
                method: "POST",
                formBody: form.encodedData(),
                session: session
            )
            return BookMapper.page(from: exchange.root, requestedPage: requestedPage)
        } catch let EapiError.server(_, message)
            where message.lowercased().contains("access denied") || message.contains("拒绝访问") {
            throw EapiError.searchRefused
        }
    }

    /// 获取热门书籍 `/eapi/book/most-popular`
    public func mostPopular(session: Session?, fallbackDomain: String? = nil) async throws -> [Book] {
        let host = try resolveHost(session: session, fallbackDomain: fallbackDomain)
        let exchange = try await executeJSON(
            host: host,
            path: EapiEndpoints.mostPopular,
            method: "GET",
            formBody: nil,
            session: session
        )
        return BookMapper.list(from: exchange.root)
    }

    /// 获取最新上架书籍 `/eapi/book/recently`
    public func recently(session: Session?, fallbackDomain: String? = nil) async throws -> [Book] {
        let host = try resolveHost(session: session, fallbackDomain: fallbackDomain)
        let exchange = try await executeJSON(
            host: host,
            path: EapiEndpoints.recently,
            method: "GET",
            formBody: nil,
            session: session
        )
        return BookMapper.list(from: exchange.root)
    }

    /// 获取个性化推荐 `/eapi/user/book/recommended`
    public func recommended(session: Session) async throws -> [Book] {
        let exchange = try await executeJSON(
            host: session.domain,
            path: EapiEndpoints.recommended,
            method: "GET",
            formBody: nil,
            session: session
        )
        return BookMapper.list(from: exchange.root)
    }

    // MARK: - 书籍详情、格式与相似推荐

    /// 获取书籍详情 `/eapi/book/{id}/{hash}`
    public func bookDetail(id: String, hash: String, session: Session?, fallbackDomain: String? = nil) async throws -> Book {
        guard BookMapper.isSafeRef(id, hash) else {
            throw EapiError.invalidParameters("无效的书籍标识")
        }
        let host = try resolveHost(session: session, fallbackDomain: fallbackDomain)
        let exchange = try await executeJSON(
            host: host,
            path: EapiEndpoints.detail(id: id, hash: hash),
            method: "GET",
            formBody: nil,
            session: session
        )
        let bookObj = EapiJSONParser.object(exchange.root, "book") ?? exchange.root
        guard let book = BookMapper.book(from: bookObj) else {
            throw EapiError.parse("书籍详情响应缺少必要字段")
        }
        return book
    }

    /// 获取多格式版本 `/eapi/book/{id}/{hash}/formats`
    public func bookFormats(id: String, hash: String, session: Session) async throws -> [BookFormat] {
        guard BookMapper.isSafeRef(id, hash) else {
            throw EapiError.invalidParameters("无效的书籍标识")
        }
        let exchange = try await executeJSON(
            host: session.domain,
            path: EapiEndpoints.formats(id: id, hash: hash),
            method: "GET",
            formBody: nil,
            session: session
        )
        return BookMapper.formats(from: exchange.root)
    }

    /// 获取相似推荐书籍 `/eapi/book/{id}/{hash}/similar`
    public func similarBooks(id: String, hash: String, session: Session?, fallbackDomain: String? = nil) async throws -> [Book] {
        guard BookMapper.isSafeRef(id, hash) else {
            throw EapiError.invalidParameters("无效的书籍标识")
        }
        let host = try resolveHost(session: session, fallbackDomain: fallbackDomain)
        let exchange = try await executeJSON(
            host: host,
            path: EapiEndpoints.similar(id: id, hash: hash),
            method: "GET",
            formBody: nil,
            session: session
        )
        let targetRef = "\(id):\(hash)"
        var seen = Set<String>()
        return BookMapper.list(from: exchange.root).filter { book in
            book.ref != targetRef && seen.insert(book.ref).inserted
        }
    }

    // MARK: - 云端收藏与下载记录

    /// 获取云端收藏列表 `/eapi/user/book/saved`
    public func savedBooks(page: Int = 1, limit: Int = 30, session: Session) async throws -> BookPage {
        let requestedPage = max(1, page)
        let clampedLimit = min(50, max(1, limit))
        let path = "\(EapiEndpoints.saved)?page=\(requestedPage)&limit=\(clampedLimit)"
        let exchange = try await executeJSON(
            host: session.domain,
            path: path,
            method: "GET",
            formBody: nil,
            session: session
        )
        return BookMapper.page(from: exchange.root, requestedPage: requestedPage)
    }

    /// 收藏或取消收藏书籍
    public func setBookSaved(id: String, saved: Bool, session: Session) async throws {
        guard BookMapper.isNumericID(id) else {
            throw EapiError.invalidParameters("收藏操作需要数字书籍 ID")
        }
        let path = saved ? EapiEndpoints.saveBook(id: id) : EapiEndpoints.unsaveBook(id: id)
        _ = try await executeJSON(
            host: session.domain,
            path: path,
            method: "GET",
            formBody: nil,
            session: session
        )
    }

    /// 获取云端下载历史 `/eapi/user/book/downloaded`
    public func downloadedBooks(page: Int = 1, limit: Int = 30, session: Session) async throws -> BookPage {
        let requestedPage = max(1, page)
        let clampedLimit = min(50, max(1, limit))
        let path = "\(EapiEndpoints.downloaded)?page=\(requestedPage)&limit=\(clampedLimit)"
        let exchange = try await executeJSON(
            host: session.domain,
            path: path,
            method: "GET",
            formBody: nil,
            session: session
        )
        return BookMapper.page(from: exchange.root, requestedPage: requestedPage, includeHistoryDate: true)
    }

    /// 删除云端单条下载历史 `/eapi/user/book/{id}/delete`
    public func deleteDownloadHistory(id: String, session: Session) async throws {
        guard BookMapper.isNumericID(id) else {
            throw EapiError.invalidParameters("删除记录需要数字书籍 ID")
        }
        _ = try await executeJSON(
            host: session.domain,
            path: EapiEndpoints.deleteHistory(id: id),
            method: "GET",
            formBody: nil,
            session: session
        )
    }

    // MARK: - 元信息与域名探测

    /// 拉取服务端支持的语言与文件格式列表（公开接口，不传凭据）
    public func filterOptions(domain rawDomain: String) async throws -> SearchFilterOptions {
        let host = try DomainPolicy.normalizeHost(rawDomain)
        async let languages = fetchLanguages(host: host)
        async let extensions = fetchExtensions(host: host)
        let (langList, extList) = try await (languages, extensions)

        guard !langList.isEmpty || !extList.isEmpty else {
            return .fallback
        }
        return SearchFilterOptions(
            languages: langList.isEmpty ? SearchFilterOptions.fallback.languages : langList,
            extensions: extList.isEmpty ? SearchFilterOptions.fallback.extensions : extList
        )
    }

    private func fetchLanguages(host: String) async throws -> [SearchLanguage] {
        let langResult = try await executeJSON(
            host: host,
            path: EapiEndpoints.languages,
            method: "GET",
            formBody: nil,
            session: nil
        )
        guard let langMap = EapiJSONParser.object(langResult.root, "languages") else {
            return []
        }
        return langMap.compactMap { key, value -> SearchLanguage? in
            guard let label = value as? String, !key.isEmpty, !label.isEmpty else { return nil }
            return SearchLanguage(code: key.lowercased(), name: label)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func fetchExtensions(host: String) async throws -> [String] {
        let extResult = try await executeJSON(
            host: host,
            path: EapiEndpoints.extensions,
            method: "GET",
            formBody: nil,
            session: nil
        )
        guard let extArr = EapiJSONParser.array(extResult.root, "extensions") else {
            return []
        }
        var seen = Set<String>()
        return extArr.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { BookMapper.isSafeExtension($0) && seen.insert($0).inserted }
    }

    /// 公开域名列表 `/eapi/info/domains`（不附带任何认证凭据）
    public func availableDomains(domain rawDomain: String) async throws -> [String] {
        let host = try DomainPolicy.normalizeHost(rawDomain)
        let exchange = try await executeJSON(
            host: host,
            path: EapiEndpoints.domains,
            method: "GET",
            formBody: nil,
            session: nil
        )
        guard let rawDomains = EapiJSONParser.array(exchange.root, "domains") else {
            return []
        }
        var seen = Set<String>()
        var hosts: [String] = []
        for item in rawDomains {
            let raw: String?
            if let str = item as? String {
                raw = str
            } else if let obj = item as? EapiJSONParser.JSONObject {
                raw = EapiJSONParser.string(obj, "domain")
                    ?? EapiJSONParser.string(obj, "host")
                    ?? EapiJSONParser.string(obj, "url")
            } else {
                raw = nil
            }
            if let candidate = raw, let normalized = try? DomainPolicy.normalizeHost(candidate),
               seen.insert(normalized).inserted {
                hosts.append(normalized)
            }
        }
        return hosts
    }

    /// 快速检测域名可用性与延迟
    public func probeDomain(_ rawDomain: String) async -> DomainProbeResult {
        let host: String
        do {
            host = try DomainPolicy.normalizeHost(rawDomain)
        } catch {
            return DomainProbeResult(
                host: rawDomain,
                reachable: false,
                latencyMs: 0,
                statusCode: nil,
                message: error.localizedDescription
            )
        }

        let start = Date()
        do {
            let request = try buildRequest(
                host: host,
                path: EapiEndpoints.domains,
                method: "GET",
                formBody: nil,
                session: nil
            )
            let (_, response) = try await urlSession.data(for: request)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            let ok = (200...299).contains(code)
            return DomainProbeResult(
                host: host,
                reachable: ok,
                latencyMs: elapsed,
                statusCode: code,
                message: ok ? "连接正常（\(elapsed) ms）" : "HTTP \(code)，请确认域名是否支持 EAPI"
            )
        } catch {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            return DomainProbeResult(
                host: host,
                reachable: false,
                latencyMs: elapsed,
                statusCode: nil,
                message: "连接失败：\(error.localizedDescription)"
            )
        }
    }

    // MARK: - 下载链接解析（兼容直接文件流与 JSON 两阶段下发）

    /// 解析 `/eapi/book/{id}/{hash}/file`：返回实际下载目标请求（或直接下发的二进制数据）
    public func resolveDownloadTarget(id: String, hash: String, session: Session) async throws -> ResolvedDownloadTarget {
        guard BookMapper.isSafeRef(id, hash) else {
            throw EapiError.invalidParameters("无效的书籍下载标识")
        }

        let initialRequest = try buildRequest(
            host: session.domain,
            path: EapiEndpoints.file(id: id, hash: hash),
            method: "GET",
            formBody: nil,
            session: session
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: initialRequest)
        } catch let error as URLError where error.code == .cancelled {
            throw EapiError.cancelled
        } catch {
            throw EapiError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw EapiError.network("未收到有效的 HTTP 响应")
        }

        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()

        // 情况 A：返回 JSON，需要解析 `file.downloadLink` 并二次请求真实下载地址
        if contentType.contains("json") {
            let root = try EapiJSONParser.parseObject(from: data)
            if let error = inspectJSONError(root: root, statusCode: http.statusCode) {
                throw error
            }
            guard let rawLink = EapiJSONParser.extractDownloadLink(from: root) else {
                let reason = EapiJSONParser.string(root, "error")
                    ?? EapiJSONParser.object(root, "file").flatMap { EapiJSONParser.string($0, "description") }
                    ?? "服务端未下发可用下载链接"
                if reason.lowercased().contains("daily limit") || reason.lowercased().contains("daily download") {
                    throw EapiError.quotaExhausted(reason)
                }
                throw EapiError.server(statusCode: http.statusCode, message: reason)
            }

            let resolvedURL = try resolveRelativeOrAbsoluteHTTPSURL(rawLink, baseHost: session.domain)
            var fileRequest = URLRequest(url: resolvedURL)
            fileRequest.httpMethod = "GET"
            fileRequest.setValue(EapiHeaders.userAgent, forHTTPHeaderField: "User-Agent")

            // 仅当目标下载链接与当前会话同域时才附带凭据，外部签名 CDN 不传凭据
            if resolvedURL.host?.lowercased() == session.domain.lowercased() {
                fileRequest.setValue(EapiHeaders.sourceValue, forHTTPHeaderField: EapiHeaders.sourceKey)
                fileRequest.setValue(session.remixUserID, forHTTPHeaderField: EapiHeaders.remixUserID)
                fileRequest.setValue(session.remixUserKey, forHTTPHeaderField: EapiHeaders.remixUserKey)
                if !session.cookieHeader.isEmpty {
                    fileRequest.setValue(session.cookieHeader, forHTTPHeaderField: EapiHeaders.cookie)
                }
            }

            let suggestedName = EapiJSONParser.object(root, "file").flatMap { fileObj in
                if let desc = EapiJSONParser.string(fileObj, "description"),
                   let ext = EapiJSONParser.string(fileObj, "extension") {
                    return "\(desc).\(ext)"
                }
                return nil
            }
            return ResolvedDownloadTarget(request: fileRequest, suggestedFilename: suggestedName)
        }

        // 情况 B：返回 HTML，通常是配额用尽、未登录跳转或域名被拦截页
        if contentType.contains("text/html") {
            let html = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            if html.contains("daily limit") || html.contains("daily download") {
                throw EapiError.quotaExhausted("今日下载配额已用尽，请明日再试。")
            }
            if html.contains("login") || http.statusCode == 401 || http.statusCode == 403 {
                throw EapiError.sessionExpired
            }
            throw EapiError.server(statusCode: http.statusCode, message: "下载接口返回了网页而非电子书文件，请切换个人专属域名后重试")
        }

        // 情况 C：HTTP 非 2xx
        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, bodyText: String(data: data, encoding: .utf8) ?? "")
        }

        // 情况 D：服务端直接返回了文件二进制内容
        return ResolvedDownloadTarget(
            request: initialRequest,
            suggestedFilename: http.suggestedFilename,
            directData: data,
            directResponse: http
        )
    }

    // MARK: - 内部传输与解析核心

    private struct JSONExchange {
        let root: EapiJSONParser.JSONObject
        let response: HTTPURLResponse
    }

    private func resolveHost(session: Session?, fallbackDomain: String?) throws -> String {
        if let domain = session?.domain, !domain.isEmpty {
            return try DomainPolicy.normalizeHost(domain)
        }
        if let fallback = fallbackDomain, !fallback.isEmpty {
            return try DomainPolicy.normalizeHost(fallback)
        }
        throw EapiError.noDomain
    }

    private func buildRequest(
        host: String,
        path: String,
        method: String,
        formBody: Data?,
        session: Session?
    ) throws -> URLRequest {
        let baseURL = try DomainPolicy.baseURL(for: host)
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: baseURL + normalizedPath) else {
            throw EapiError.invalidParameters("无法拼接请求地址：\(normalizedPath)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(EapiHeaders.accept, forHTTPHeaderField: "Accept")
        request.setValue(EapiHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        // 关键请求头：标识移动端客户端，防止 /eapi/book/search 返回 Access denied
        request.setValue(EapiHeaders.sourceValue, forHTTPHeaderField: EapiHeaders.sourceKey)

        if let formBody {
            request.setValue(EapiHeaders.formContentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = formBody
        }

        if let session {
            request.setValue(session.remixUserID, forHTTPHeaderField: EapiHeaders.remixUserID)
            request.setValue(session.remixUserKey, forHTTPHeaderField: EapiHeaders.remixUserKey)
            let cookie = session.cookieHeader
            if !cookie.isEmpty {
                request.setValue(cookie, forHTTPHeaderField: EapiHeaders.cookie)
            }
        }
        return request
    }

    private func executeJSON(
        host: String,
        path: String,
        method: String,
        formBody: Data?,
        session: Session?
    ) async throws -> JSONExchange {
        let request = try buildRequest(
            host: host,
            path: path,
            method: method,
            formBody: formBody,
            session: session
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw EapiError.cancelled
        } catch {
            throw EapiError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw EapiError.network("未收到有效的 HTTP 响应")
        }

        // 优先尝试解析 JSON 包体，因为 EAPI 即使在 400/401 时也可能返回结构化 JSON 错误信息
        if let root = try? EapiJSONParser.parseObject(from: data) {
            if let apiError = inspectJSONError(root: root, statusCode: http.statusCode) {
                throw apiError
            }
            if (200...299).contains(http.statusCode) || EapiJSONParser.int(root, "success") == 1 {
                return JSONExchange(root: root, response: http)
            }
            let message = EapiJSONParser.string(root, "error")
                ?? EapiJSONParser.string(root, "message")
                ?? ""
            throw mapHTTPError(statusCode: http.statusCode, bodyText: message)
        }

        let bodyText = String(data: data, encoding: .utf8) ?? ""
        if !(200...299).contains(http.statusCode) {
            throw mapHTTPError(statusCode: http.statusCode, bodyText: bodyText)
        }
        throw EapiError.parse("服务端返回了非 JSON 内容（HTTP \(http.statusCode)）")
    }

    private func inspectJSONError(root: EapiJSONParser.JSONObject, statusCode: Int) -> EapiError? {
        if let success = EapiJSONParser.int(root, "success"), success == 0 {
            let message = EapiJSONParser.string(root, "error")
                ?? EapiJSONParser.string(root, "message")
                ?? "请求被服务端拒绝"
            let lower = message.lowercased()
            if lower.contains("daily limit") || lower.contains("daily download") {
                return .quotaExhausted(message)
            }
            if lower.contains("please login") || lower.contains("invalid credentials") || lower.contains("unauthorized") {
                return .sessionExpired
            }
            return .server(statusCode: statusCode, message: message)
        }
        return nil
    }

    private func mapHTTPError(statusCode: Int, bodyText: String) -> EapiError {
        let lower = bodyText.lowercased()
        if lower.contains("daily limit") || lower.contains("daily download") {
            return .quotaExhausted("今日下载额度已用完。")
        }
        if statusCode == 401 || statusCode == 403 || lower.contains("please login") {
            return .sessionExpired
        }
        if statusCode == 513 || statusCode == 517 {
            return .domainBlocked(statusCode)
        }
        let cleanMessage = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = cleanMessage.count > 160 ? String(cleanMessage.prefix(160)) : cleanMessage
        return .server(statusCode: statusCode, message: summary)
    }

    private func resolveRelativeOrAbsoluteHTTPSURL(_ raw: String, baseHost: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let absolute: String
        if trimmed.hasPrefix("//") {
            absolute = "https:\(trimmed)"
        } else if trimmed.lowercased().hasPrefix("https://") {
            absolute = trimmed
        } else if trimmed.lowercased().hasPrefix("http://") {
            throw EapiError.parse("服务端下发的下载地址未使用 HTTPS，已拒绝明文下载")
        } else {
            let path = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
            absolute = "https://\(baseHost)\(path)"
        }

        guard let url = URL(string: absolute), url.scheme?.lowercased() == "https" else {
            throw EapiError.parse("无法解析服务端下发的下载地址")
        }
        return url
    }

    /// 解析响应头中的全部 `Set-Cookie` 键值
    public static func parseSetCookies(from response: HTTPURLResponse) -> [String: String] {
        guard let url = response.url else { return [:] }
        var headerFields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let keyStr = key as? String, let valStr = value as? String {
                headerFields[keyStr] = valStr
            }
        }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        var result: [String: String] = [:]
        for cookie in parsed {
            result[cookie.name] = cookie.value
        }
        return result
    }
}
