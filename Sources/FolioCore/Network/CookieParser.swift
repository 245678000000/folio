import Foundation

/// Cookie 与会话凭据解析工具（兼容浏览器 Cookie 头、JSON 导出与 HTTPCookie 列表）
public enum CookieParser {
    public struct ParsedCredentials: Equatable, Sendable {
        public let remixUserID: String
        public let remixUserKey: String
        public let cookies: [String: String]

        public init(remixUserID: String, remixUserKey: String, cookies: [String: String]) {
            self.remixUserID = remixUserID
            self.remixUserKey = remixUserKey
            self.cookies = cookies
        }
    }

    private static let ignoredCookieAttributes: Set<String> = [
        "path", "domain", "expires", "max-age", "secure", "httponly", "samesite", "priority",
    ]

    /// 从任意粘贴文本（Cookie 请求头或 JSON）提取 remix_userid / remix_userkey
    public static func parse(rawText: String) throws -> ParsedCredentials {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("cookie:") {
            text = String(text.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else {
            throw EapiError.invalidParameters("Cookie 内容为空")
        }

        let map: [String: String]
        if text.hasPrefix("{") || text.hasPrefix("[") {
            map = parseJSON(text)
        } else {
            map = parseHeader(text)
        }

        return try buildCredentials(from: map)
    }

    /// 从 WKHTTPCookieStore 读取到的 HTTPCookie 数组提取目标域名会话凭据
    public static func extract(from httpCookies: [HTTPCookie], matchingHost host: String) -> ParsedCredentials? {
        let lowerHost = host.lowercased()
        var merged: [String: String] = [:]

        for cookie in httpCookies {
            let cookieDomain = cookie.domain
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            let domainMatches = cookieDomain.isEmpty
                || lowerHost == cookieDomain
                || lowerHost.hasSuffix(".\(cookieDomain)")
                || cookieDomain.hasSuffix(".\(lowerHost)")
            guard domainMatches else { continue }

            let name = cookie.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !value.isEmpty {
                merged[name] = value
            }
        }

        return try? buildCredentials(from: merged)
    }

    private static func buildCredentials(from rawMap: [String: String]) throws -> ParsedCredentials {
        let userID = rawMap[Session.userIDCookieName] ?? ""
        let userKey = rawMap[Session.userKeyCookieName] ?? rawMap["remix_user_key"] ?? ""
        guard !userID.isEmpty, !userKey.isEmpty else {
            throw EapiError.invalidParameters("未找到完整的 remix_userid 与 remix_userkey")
        }
        var cookies = rawMap
        cookies[Session.userIDCookieName] = userID
        cookies[Session.userKeyCookieName] = userKey
        return ParsedCredentials(remixUserID: userID, remixUserKey: userKey, cookies: cookies)
    }

    private static func parseHeader(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for piece in text.split(whereSeparator: { $0 == ";" || $0 == "\n" }) {
            let item = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eqIdx = item.firstIndex(of: "=") else { continue }
            let key = String(item[..<eqIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(item[item.index(after: eqIdx)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            guard !key.isEmpty, !value.isEmpty, !ignoredCookieAttributes.contains(key.lowercased()) else {
                continue
            }
            result[key] = value
        }
        return result
    }

    private static func parseJSON(_ text: String) -> [String: String] {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }

        var result: [String: String] = [:]
        if let dict = raw as? [String: Any] {
            let source = (dict["cookies"] as? [String: Any]) ?? dict
            for (k, v) in source {
                if let str = v as? String, !str.isEmpty {
                    result[k] = str
                } else if let obj = v as? [String: Any], let val = obj["value"] as? String, !val.isEmpty {
                    result[k] = val
                }
            }
        } else if let arr = raw as? [[String: Any]] {
            for item in arr {
                if let name = (item["name"] as? String) ?? (item["key"] as? String),
                   let value = item["value"] as? String,
                   !name.isEmpty, !value.isEmpty {
                    result[name] = value
                }
            }
        }
        return result
    }
}
