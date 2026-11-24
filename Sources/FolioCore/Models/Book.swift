import Foundation

/// 电子书核心领域模型
public struct Book: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let hash: String
    public let title: String
    public let subtitle: String
    public let authors: String
    public let publisher: String
    public let year: String
    public let language: String
    public let fileExtension: String
    public let sizeBytes: Int64?
    public let sizeText: String
    public let isbn10: String
    public let isbn13: String
    public let coverURL: String
    public let description: String
    public let categories: [String]
    public let edition: String
    public let pages: Int?
    public let rating: Double?
    public let href: String
    public let historyDate: String?

    /// 唯一引用键（用于去重与多格式标识）
    public var ref: String { "\(id):\(hash)" }

    /// 格式化展示的文件大小
    public var formattedSize: String {
        if !sizeText.isEmpty {
            return sizeText
        }
        guard let bytes = sizeBytes, bytes > 0 else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 规范化大写格式名（例如 EPUB、PDF）
    public var displayExtension: String {
        fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// 适合展示的 ISBN（优先 ISBN-13）
    public var displayISBN: String {
        if !isbn13.isEmpty { return isbn13 }
        return isbn10
    }

    public init(
        id: String,
        hash: String,
        title: String,
        subtitle: String = "",
        authors: String = "",
        publisher: String = "",
        year: String = "",
        language: String = "",
        fileExtension: String = "",
        sizeBytes: Int64? = nil,
        sizeText: String = "",
        isbn10: String = "",
        isbn13: String = "",
        coverURL: String = "",
        description: String = "",
        categories: [String] = [],
        edition: String = "",
        pages: Int? = nil,
        rating: Double? = nil,
        href: String = "",
        historyDate: String? = nil
    ) {
        self.id = id
        self.hash = hash
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.publisher = publisher
        self.year = year
        self.language = language
        self.fileExtension = fileExtension
        self.sizeBytes = sizeBytes
        self.sizeText = sizeText
        self.isbn10 = isbn10
        self.isbn13 = isbn13
        self.coverURL = coverURL
        self.description = description
        self.categories = categories
        self.edition = edition
        self.pages = pages
        self.rating = rating
        self.href = href
        self.historyDate = historyDate
    }
}

/// 同一本书的可下载格式版本
public struct BookFormat: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let hash: String
    public let fileExtension: String
    public let sizeBytes: Int64?
    public let sizeText: String

    public var ref: String { "\(id):\(hash)" }

    public var displayExtension: String {
        fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public var formattedSize: String {
        if !sizeText.isEmpty { return sizeText }
        guard let bytes = sizeBytes, bytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public init(
        id: String,
        hash: String,
        fileExtension: String,
        sizeBytes: Int64? = nil,
        sizeText: String = ""
    ) {
        self.id = id
        self.hash = hash
        self.fileExtension = fileExtension
        self.sizeBytes = sizeBytes
        self.sizeText = sizeText
    }
}

/// 分页书籍结果集
public struct BookPage: Hashable, Codable, Sendable {
    public let books: [Book]
    public let page: Int
    public let totalPages: Int

    public var hasMore: Bool {
        page < totalPages && !books.isEmpty
    }

    public init(books: [Book], page: Int, totalPages: Int) {
        self.books = books
        self.page = page
        self.totalPages = totalPages
    }
}

/// 搜索排序选项
public enum SearchSort: String, CaseIterable, Identifiable, Codable, Sendable {
    case bestMatch = "bestmatch"
    case popular = "popular"
    case year = "year"
    case title = "title"
    case date = "date"
    case fileSize = "filesize"

    public var id: String { rawValue }

    /// 传输给 EAPI 的排序值（默认相关度不传）
    public var wireValue: String? {
        switch self {
        case .bestMatch: return nil
        default: return rawValue
        }
    }

    /// 中文界面展示名
    public var displayName: String {
        switch self {
        case .bestMatch: return "最相关"
        case .popular: return "最热门"
        case .year: return "出版年份"
        case .title: return "书名排序"
        case .date: return "最新入库"
        case .fileSize: return "文件大小"
        }
    }
}

/// 搜索条件聚合模型
public struct SearchQuery: Hashable, Codable, Sendable {
    public var message: String
    public var exact: Bool
    public var yearFrom: Int?
    public var yearTo: Int?
    public var languages: [String]
    public var extensions: [String]
    public var sort: SearchSort

    public var hasActiveFilters: Bool {
        exact || yearFrom != nil || yearTo != nil || !languages.isEmpty || !extensions.isEmpty || sort != .bestMatch
    }

    public init(
        message: String = "",
        exact: Bool = false,
        yearFrom: Int? = nil,
        yearTo: Int? = nil,
        languages: [String] = [],
        extensions: [String] = [],
        sort: SearchSort = .bestMatch
    ) {
        self.message = message
        self.exact = exact
        self.yearFrom = yearFrom
        self.yearTo = yearTo
        self.languages = languages
        self.extensions = extensions
        self.sort = sort
    }
}

/// 支持的语言筛选项
public struct SearchLanguage: Identifiable, Hashable, Codable, Sendable {
    public let code: String
    public let name: String

    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

/// 搜索筛选项集合（语言 + 扩展名）
public struct SearchFilterOptions: Hashable, Codable, Sendable {
    public let languages: [SearchLanguage]
    public let extensions: [String]

    /// 离线或服务端暂不可用时的常用默认筛选项
    public static let fallback = SearchFilterOptions(
        languages: [
            SearchLanguage(code: "chinese", name: "中文"),
            SearchLanguage(code: "english", name: "English"),
            SearchLanguage(code: "japanese", name: "日本語"),
            SearchLanguage(code: "german", name: "Deutsch"),
            SearchLanguage(code: "french", name: "Français"),
            SearchLanguage(code: "spanish", name: "Español"),
            SearchLanguage(code: "russian", name: "Русский"),
        ],
        extensions: ["epub", "pdf", "mobi", "azw3", "fb2", "txt", "djvu", "rtf"]
    )

    public init(languages: [SearchLanguage], extensions: [String]) {
        self.languages = languages
        self.extensions = extensions
    }
}
