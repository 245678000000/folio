import Foundation

/// EAPI 与本地服务统一领域错误
public enum EapiError: Error, LocalizedError, Equatable, Sendable {
    case noDomain
    case invalidDomain(String)
    case notLoggedIn
    case sessionExpired
    case searchRefused
    case quotaExhausted(String)
    case domainBlocked(Int)
    case server(statusCode: Int, message: String)
    case parse(String)
    case network(String)
    case storage(String)
    case invalidParameters(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noDomain:
            return "尚未配置服务器域名，请在登录或设置中填写可用的 Z-Library 域名。"
        case .invalidDomain(let raw):
            return "域名格式无效（\(raw)），请填写标准主机名或 HTTPS 地址。"
        case .notLoggedIn:
            return "尚未登录账号，请先登录后再执行此操作。"
        case .sessionExpired:
            return "登录会话已失效，请重新登录或更新 remix_userid / remix_userkey。"
        case .searchRefused:
            return "搜索接口返回拒绝访问（Access denied）。建议切换个人专属域名或检查代理与账号会话状态。"
        case .quotaExhausted(let detail):
            return detail.isEmpty ? "今日下载额度已用完，请明天再试或检查账户配额。" : detail
        case .domainBlocked(let code):
            return "当前域名访问受限（HTTP \(code)），请切换个人专属域名或检查代理节点。"
        case .server(let code, let message):
            if message.isEmpty {
                return "服务端返回异常（HTTP \(code)），请稍后重试。"
            }
            return "服务端异常（HTTP \(code)）：\(message)"
        case .parse(let reason):
            return "响应数据解析失败：\(reason)"
        case .network(let reason):
            return "网络请求失败：\(reason)"
        case .storage(let reason):
            return "本地文件或存储异常：\(reason)"
        case .invalidParameters(let reason):
            return "请求参数无效：\(reason)"
        case .cancelled:
            return "操作已取消。"
        }
    }

    /// 面向用户的下一步操作建议
    public var recoverySuggestion: String? {
        switch self {
        case .noDomain, .invalidDomain, .domainBlocked:
            return "可在「设置 → 账号与域名」中更换个人专属域名并测试连通性。"
        case .notLoggedIn, .sessionExpired:
            return "点击左下角账户卡片重新登录，或切换为浏览器 Cookie Token 直连。"
        case .searchRefused:
            return "Z-Library 上游近期会校验客户端标识与域名权限；请确认已登录并优先使用个人专属域名。"
        case .quotaExhausted:
            return "每日配额会在次日重置，你仍可以先将感兴趣的书加入云端收藏。"
        case .network:
            return "请检查网络连接或在「设置 → 网络与代理」中确认代理配置。"
        default:
            return nil
        }
    }
}
