import Foundation

/// Z-Library EAPI 公共请求头常量
public enum EapiHeaders {
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    public static let accept = "application/json"
    public static let formContentType = "application/x-www-form-urlencoded; charset=utf-8"

    /// 移动端来源标识：2026-11 起 `/eapi/book/search` 缺失此头会返回 HTTP 400 Access denied
    public static let sourceKey = "source"
    public static let sourceValue = "android"

    public static let remixUserID = "remix-userid"
    public static let remixUserKey = "remix-userkey"
    public static let cookie = "Cookie"

    /// 跨域重定向时必须剥离的敏感请求头（小写匹配）
    public static let sensitiveHeaderNames: Set<String> = [
        "remix-userid",
        "remix-userkey",
        "remix-user-key",
        "cookie",
        "authorization",
    ]
}

/// Z-Library EAPI 端点路径定义
public enum EapiEndpoints {
    public static let login = "/eapi/user/login"
    public static let profile = "/eapi/user/profile"
    public static let search = "/eapi/book/search"
    public static let mostPopular = "/eapi/book/most-popular"
    public static let recently = "/eapi/book/recently"
    public static let recommended = "/eapi/user/book/recommended"
    public static let saved = "/eapi/user/book/saved"
    public static let downloaded = "/eapi/user/book/downloaded"
    public static let languages = "/eapi/info/languages"
    public static let extensions = "/eapi/info/extensions"
    public static let domains = "/eapi/info/domains"

    public static func detail(id: String, hash: String) -> String {
        "/eapi/book/\(id)/\(hash)"
    }

    public static func formats(id: String, hash: String) -> String {
        "/eapi/book/\(id)/\(hash)/formats"
    }

    public static func similar(id: String, hash: String) -> String {
        "/eapi/book/\(id)/\(hash)/similar"
    }

    public static func file(id: String, hash: String) -> String {
        "/eapi/book/\(id)/\(hash)/file"
    }

    public static func saveBook(id: String) -> String {
        "/eapi/user/book/\(id)/save"
    }

    public static func unsaveBook(id: String) -> String {
        "/eapi/user/book/\(id)/unsave"
    }

    public static func deleteHistory(id: String) -> String {
        "/eapi/user/book/\(id)/delete"
    }
}
