import Foundation

/// 宽容型 JSON 解析工具（兼容 EAPI 服务端数字/字符串混用等不规范响应）
public enum EapiJSONParser {
    public typealias JSONObject = [String: Any]

    /// 将原始字节解析为顶层 JSON 对象
    public static func parseObject(from data: Data) throws -> JSONObject {
        guard !data.isEmpty else {
            throw EapiError.parse("响应体为空")
        }
        do {
            let parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let object = parsed as? JSONObject else {
                throw EapiError.parse("响应体不是有效的 JSON 对象")
            }
            return object
        } catch let error as EapiError {
            throw error
        } catch {
            throw EapiError.parse(error.localizedDescription)
        }
    }

    public static func string(_ dict: JSONObject, _ key: String) -> String? {
        guard let raw = dict[key], !(raw is NSNull) else { return nil }
        if let str = raw as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = raw as? NSNumber {
            // 避免将 Bool 误转成 "1"/"0"
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        return nil
    }

    public static func int(_ dict: JSONObject, _ key: String) -> Int? {
        guard let raw = dict[key], !(raw is NSNull) else { return nil }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? 1 : 0
            }
            return number.intValue
        }
        if let str = raw as? String {
            return Int(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    public static func int64(_ dict: JSONObject, _ key: String) -> Int64? {
        guard let raw = dict[key], !(raw is NSNull) else { return nil }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.int64Value
        }
        if let str = raw as? String {
            return Int64(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    public static func double(_ dict: JSONObject, _ key: String) -> Double? {
        guard let raw = dict[key], !(raw is NSNull) else { return nil }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.doubleValue
        }
        if let str = raw as? String {
            return Double(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    public static func bool(_ dict: JSONObject, _ key: String) -> Bool? {
        guard let raw = dict[key], !(raw is NSNull) else { return nil }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            return number.intValue != 0
        }
        if let str = raw as? String {
            switch str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    public static func object(_ dict: JSONObject, _ key: String) -> JSONObject? {
        dict[key] as? JSONObject
    }

    public static func array(_ dict: JSONObject, _ key: String) -> [Any]? {
        dict[key] as? [Any]
    }

    /// 解析 `/eapi/book/{id}/{hash}/file` 返回的 JSON 下载链接
    public static func extractDownloadLink(from root: JSONObject) -> String? {
        if let fileObj = object(root, "file") {
            if let allow = bool(fileObj, "allowDownload"), !allow {
                return nil
            }
            if let link = string(fileObj, "downloadLink") ?? string(fileObj, "download_link") ?? string(fileObj, "url") {
                return link
            }
        }
        return string(root, "downloadLink") ?? string(root, "download_link") ?? string(root, "url")
    }
}

/// 书籍 JSON 映射与安全引用校验器
public enum BookMapper {
    private static func isASCIIAlphanumeric(_ value: String, maxLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maxLength else { return false }
        return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// 校验书籍 ID 与 Hash 不包含路径穿越等非法字符
    public static func isSafeRef(_ id: String, _ hash: String) -> Bool {
        isASCIIAlphanumeric(id, maxLength: 32) && isASCIIAlphanumeric(hash, maxLength: 64)
    }

    /// 校验纯数字书籍 ID（收藏、删除历史等接口需要）
    public static func isNumericID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy(\.isASCII) && id.allSatisfy(\.isNumber)
    }

    /// 校验文件扩展名合法性
    public static func isSafeExtension(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        guard !lower.isEmpty, lower.count <= 20 else { return false }
        return lower.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
    }

    /// 映射单本书籍 JSON
    public static func book(from dict: EapiJSONParser.JSONObject, includeHistoryDate: Bool = false) -> Book? {
        guard let id = EapiJSONParser.string(dict, "id"),
              let hash = EapiJSONParser.string(dict, "hash"),
              isSafeRef(id, hash) else {
            return nil
        }

        let title = EapiJSONParser.string(dict, "title") ?? "未命名书籍"
        let subtitle = EapiJSONParser.string(dict, "subtitle") ?? ""
        let authors = EapiJSONParser.string(dict, "author") ?? EapiJSONParser.string(dict, "authors") ?? ""
        let publisher = EapiJSONParser.string(dict, "publisher") ?? ""
        let year = EapiJSONParser.string(dict, "year") ?? ""
        let language = EapiJSONParser.string(dict, "language") ?? ""
        let rawExt = (EapiJSONParser.string(dict, "extension") ?? "").lowercased()
        let fileExtension = isSafeExtension(rawExt) ? rawExt : ""
        let sizeBytes = EapiJSONParser.int64(dict, "filesize").flatMap { $0 >= 0 ? $0 : nil }
        let sizeText = EapiJSONParser.string(dict, "filesizeString") ?? ""

        let (isbn10, isbn13) = extractISBNs(from: dict)
        let coverURL = sanitizeCoverURL(EapiJSONParser.string(dict, "cover"))
        let description = stripHTMLTags(EapiJSONParser.string(dict, "description") ?? "")
        let categories = extractCategories(from: dict)
        let edition = EapiJSONParser.string(dict, "edition") ?? ""
        let pages = EapiJSONParser.int(dict, "pages").flatMap { $0 > 0 ? $0 : nil }
        let rating = EapiJSONParser.double(dict, "interestScore") ?? EapiJSONParser.double(dict, "qualityScore")
        let href = EapiJSONParser.string(dict, "href") ?? ""
        let historyDate: String? = includeHistoryDate
            ? (EapiJSONParser.string(dict, "date_download")
                ?? EapiJSONParser.string(dict, "date")
                ?? EapiJSONParser.string(dict, "downloaded_at"))
            : nil

        return Book(
            id: id,
            hash: hash,
            title: title,
            subtitle: subtitle,
            authors: authors,
            publisher: publisher,
            year: year,
            language: language,
            fileExtension: fileExtension,
            sizeBytes: sizeBytes,
            sizeText: sizeText,
            isbn10: isbn10,
            isbn13: isbn13,
            coverURL: coverURL,
            description: description,
            categories: categories,
            edition: edition,
            pages: pages,
            rating: rating,
            href: href,
            historyDate: historyDate
        )
    }

    /// 从顶层响应的 `books` 数组解析书籍列表
    public static func list(from root: EapiJSONParser.JSONObject, includeHistoryDate: Bool = false) -> [Book] {
        guard let rawArray = EapiJSONParser.array(root, "books") else {
            return []
        }
        return rawArray.compactMap { element in
            guard let item = element as? EapiJSONParser.JSONObject else { return nil }
            return book(from: item, includeHistoryDate: includeHistoryDate)
        }
    }

    /// 将响应映射为分页结果
    public static func page(
        from root: EapiJSONParser.JSONObject,
        requestedPage: Int,
        includeHistoryDate: Bool = false
    ) -> BookPage {
        let books = list(from: root, includeHistoryDate: includeHistoryDate)
        let pagination = EapiJSONParser.object(root, "pagination")
        let current = pagination.flatMap { EapiJSONParser.int($0, "current") }.flatMap { $0 > 0 ? $0 : nil } ?? requestedPage
        let explicitNoNext = pagination.flatMap { EapiJSONParser.bool($0, "next") } == false
        let rawTotal = pagination.flatMap { EapiJSONParser.int($0, "total_pages") } ?? current
        let totalPages = (books.isEmpty || explicitNoNext) ? current : max(current, rawTotal)
        return BookPage(books: books, page: current, totalPages: totalPages)
    }

    /// 映射多格式列表
    public static func formats(from root: EapiJSONParser.JSONObject) -> [BookFormat] {
        guard let rawArray = EapiJSONParser.array(root, "books") else { return [] }
        var seen = Set<String>()
        var results: [BookFormat] = []

        for element in rawArray {
            guard let row = element as? EapiJSONParser.JSONObject,
                  let id = EapiJSONParser.string(row, "id"),
                  let hash = EapiJSONParser.string(row, "hash"),
                  let ext = EapiJSONParser.string(row, "extension")?.lowercased(),
                  isSafeRef(id, hash),
                  isSafeExtension(ext) else {
                continue
            }
            let ref = "\(id):\(hash)"
            if seen.insert(ref).inserted {
                results.append(
                    BookFormat(
                        id: id,
                        hash: hash,
                        fileExtension: ext,
                        sizeBytes: EapiJSONParser.int64(row, "filesize").flatMap { $0 >= 0 ? $0 : nil },
                        sizeText: EapiJSONParser.string(row, "filesizeString") ?? ""
                    )
                )
            }
        }
        return results
    }

    /// 清洗并过滤无效或非 HTTPS 封面链接
    public static func sanitizeCoverURL(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let url = components.url else {
            return ""
        }
        let path = components.percentEncodedPath
        if path.contains("//") || path.hasSuffix("/cover-not-exists.png") || path.hasSuffix("/cover-not-exists.jpg") {
            return ""
        }
        return url.absoluteString
    }

    private static func extractCategories(from dict: EapiJSONParser.JSONObject) -> [String] {
        var result: [String] = []
        if let arr = EapiJSONParser.array(dict, "categories") {
            result = arr.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else if let str = EapiJSONParser.string(dict, "categories") {
            result = str.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "，" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else if let single = EapiJSONParser.string(dict, "category") {
            result = [single]
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    private static func extractISBNs(from dict: EapiJSONParser.JSONObject) -> (isbn10: String, isbn13: String) {
        let candidates = [
            EapiJSONParser.string(dict, "isbn13"),
            EapiJSONParser.string(dict, "isbn10"),
            EapiJSONParser.string(dict, "isbn"),
            EapiJSONParser.string(dict, "identifier"),
        ].compactMap { $0 }.joined(separator: ",")

        let tokens = candidates
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
            .map { token in
                token.uppercased().filter { $0.isNumber || $0 == "X" }
            }

        let isbn13 = tokens.first { $0.count == 13 && $0.allSatisfy(\.isNumber) } ?? ""
        let isbn10 = tokens.first { $0.count == 10 } ?? ""
        return (isbn10, isbn13)
    }

    /// 去除服务端简介中偶发的简单 HTML 标签与实体
    private static func stripHTMLTags(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let withoutTags = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
