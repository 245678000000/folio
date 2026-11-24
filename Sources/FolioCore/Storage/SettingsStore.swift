import Foundation

/// 非敏感用户偏好快照
public struct AppSettings: Hashable, Codable, Sendable {
    public var downloadDirectoryPath: String
    public var appearanceMode: AppearanceMode
    public var displayMode: BooksDisplayMode
    public var proxy: ProxyConfiguration
    public var lastDomain: String
    public var recentDomains: [String]
    public var searchHistory: [String]
    public var isDemoMode: Bool

    public static func defaultDownloadDirectory() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        return downloads.appendingPathComponent("Folio", isDirectory: true)
    }

    public var downloadDirectoryURL: URL {
        URL(fileURLWithPath: downloadDirectoryPath, isDirectory: true)
    }

    public static var `default`: AppSettings {
        AppSettings(
            downloadDirectoryPath: defaultDownloadDirectory().path,
            appearanceMode: .system,
            displayMode: .grid,
            proxy: .systemDefault,
            lastDomain: "",
            recentDomains: [],
            searchHistory: [],
            isDemoMode: false
        )
    }

    public init(
        downloadDirectoryPath: String,
        appearanceMode: AppearanceMode = .system,
        displayMode: BooksDisplayMode = .grid,
        proxy: ProxyConfiguration = .systemDefault,
        lastDomain: String = "",
        recentDomains: [String] = [],
        searchHistory: [String] = [],
        isDemoMode: Bool = false
    ) {
        self.downloadDirectoryPath = downloadDirectoryPath
        self.appearanceMode = appearanceMode
        self.displayMode = displayMode
        self.proxy = proxy
        self.lastDomain = lastDomain
        self.recentDomains = recentDomains
        self.searchHistory = searchHistory
        self.isDemoMode = isDemoMode
    }
}

/// 基于 JSON 文件的轻量偏好设置存储（存放在 ~/Library/Application Support/Folio/）
public final class SettingsStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.fileURL = appSupport
                .appendingPathComponent("Folio", isDirectory: true)
                .appendingPathComponent("settings.json")
        }
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    public func save(_ settings: AppSettings) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}
