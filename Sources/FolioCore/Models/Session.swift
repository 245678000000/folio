import Foundation

/// 用户认证会话模型（敏感凭据仅存 Keychain）
public struct Session: Hashable, Codable, Sendable {
    public static let userIDCookieName = "remix_userid"
    public static let userKeyCookieName = "remix_userkey"

    public let remixUserID: String
    public let remixUserKey: String
    /// 规范化后的纯主机名（不含 https:// 与路径）
    public let domain: String
    public let email: String
    public let cookies: [String: String]

    /// 拼接标准 Cookie 请求头
    public var cookieHeader: String {
        var merged = cookies
        if !remixUserID.isEmpty {
            merged[Self.userIDCookieName] = remixUserID
        }
        if !remixUserKey.isEmpty {
            merged[Self.userKeyCookieName] = remixUserKey
        }
        return merged
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    public init(
        remixUserID: String,
        remixUserKey: String,
        domain: String,
        email: String = "",
        cookies: [String: String] = [:]
    ) {
        self.remixUserID = remixUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.remixUserKey = remixUserKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cookies = cookies
    }
}

/// 每日下载配额信息
public struct DownloadQuota: Hashable, Codable, Sendable {
    public let usedToday: Int
    public let dailyLimit: Int
    public let resetDescription: String?

    public var remaining: Int {
        max(0, dailyLimit - usedToday)
    }

    public var progress: Double {
        guard dailyLimit > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedToday) / Double(dailyLimit)))
    }

    public init(usedToday: Int, dailyLimit: Int, resetDescription: String? = nil) {
        self.usedToday = max(0, usedToday)
        self.dailyLimit = max(0, dailyLimit)
        self.resetDescription = resetDescription
    }
}

/// 账户资料信息
public struct AccountProfile: Hashable, Codable, Sendable {
    public let id: String
    public let email: String
    public let name: String
    public let kindleEmail: String
    public let domain: String
    public let quota: DownloadQuota?
    public let isDemo: Bool

    public var displayTitle: String {
        if !name.isEmpty { return name }
        if !email.isEmpty { return email }
        return isDemo ? "演示书库" : "用户 #\(id)"
    }

    public init(
        id: String,
        email: String = "",
        name: String = "",
        kindleEmail: String = "",
        domain: String = "",
        quota: DownloadQuota? = nil,
        isDemo: Bool = false
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.kindleEmail = kindleEmail
        self.domain = domain
        self.quota = quota
        self.isDemo = isDemo
    }
}

/// 代理接入模式
public enum ProxyMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case http
    case socks5

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "跟随 macOS 系统代理"
        case .http: return "自定义 HTTP/HTTPS 代理"
        case .socks5: return "自定义 SOCKS5 代理"
        }
    }
}

/// 网络代理配置
public struct ProxyConfiguration: Hashable, Codable, Sendable {
    public var mode: ProxyMode
    public var host: String
    public var port: Int

    public static let systemDefault = ProxyConfiguration(mode: .system, host: "127.0.0.1", port: 7890)

    public var isValidManualProxy: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...65535).contains(port)
    }

    public init(mode: ProxyMode = .system, host: String = "127.0.0.1", port: Int = 7890) {
        self.mode = mode
        self.host = host
        self.port = port
    }
}

/// 界面外观模式
public enum AppearanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "宣纸浅色"
        case .dark: return "静谧深色"
        }
    }
}

/// 书单视图模式
public enum BooksDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case grid
    case list

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .grid: return "封面网格"
        case .list: return "简洁列表"
        }
    }
}
