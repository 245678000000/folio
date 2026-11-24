import Foundation

/// 跨域重定向凭据剥离代理：跳转到外部主机时自动移除认证头与 Cookie，并阻止 HTTPS 降级
public final class RedirectCredentialStripper: NSObject, URLSessionTaskDelegate, Sendable {
    public override init() {
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let targetURL = request.url else {
            completionHandler(nil)
            return
        }

        // 阻止从 HTTPS 降级至明文 HTTP
        if targetURL.scheme?.lowercased() != "https" {
            completionHandler(nil)
            return
        }

        let originalHost = task.originalRequest?.url?.host?.lowercased()
        let nextHost = targetURL.host?.lowercased()

        // 同一主机保留原始请求；一旦跨域则彻底剥离所有敏感认证信息
        if originalHost != nil && originalHost == nextHost {
            completionHandler(request)
            return
        }

        var sanitized = request
        if let headers = sanitized.allHTTPHeaderFields {
            for key in headers.keys {
                if EapiHeaders.sensitiveHeaderNames.contains(key.lowercased()) {
                    sanitized.setValue(nil, forHTTPHeaderField: key)
                }
            }
        }
        sanitized.httpShouldHandleCookies = false
        completionHandler(sanitized)
    }
}

/// URLSession 配置工厂（支持系统代理、HTTP 代理与 SOCKS5 代理）
public enum ProxySessionFactory {
    /// 生成带代理策略与超时配置的 URLSessionConfiguration
    public static func makeConfiguration(
        proxy: ProxyConfiguration,
        timeoutInterval: TimeInterval = 25,
        resourceTimeout: TimeInterval = 300,
        protocolClasses: [AnyClass]? = nil
    ) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = resourceTimeout
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        if let protocolClasses {
            config.protocolClasses = protocolClasses
        }

        let trimmedHost = proxy.host.trimmingCharacters(in: .whitespacesAndNewlines)
        switch proxy.mode {
        case .system:
            // 不覆盖 connectionProxyDictionary 即自动继承 macOS 系统代理（含 Clash / Surge 等）
            config.connectionProxyDictionary = nil
        case .http:
            if proxy.isValidManualProxy {
                config.connectionProxyDictionary = [
                    "HTTPEnable": 1,
                    "HTTPProxy": trimmedHost,
                    "HTTPPort": proxy.port,
                    "HTTPSEnable": 1,
                    "HTTPSProxy": trimmedHost,
                    "HTTPSPort": proxy.port,
                ]
            }
        case .socks5:
            if proxy.isValidManualProxy {
                config.connectionProxyDictionary = [
                    "SOCKSEnable": 1,
                    "SOCKSProxy": trimmedHost,
                    "SOCKSPort": proxy.port,
                ]
            }
        }
        return config
    }

    /// 创建配置好凭据剥离代理的 URLSession
    public static func makeSession(
        proxy: ProxyConfiguration,
        timeoutInterval: TimeInterval = 25,
        resourceTimeout: TimeInterval = 300,
        protocolClasses: [AnyClass]? = nil
    ) -> URLSession {
        let config = makeConfiguration(
            proxy: proxy,
            timeoutInterval: timeoutInterval,
            resourceTimeout: resourceTimeout,
            protocolClasses: protocolClasses
        )
        return URLSession(configuration: config, delegate: RedirectCredentialStripper(), delegateQueue: nil)
    }
}
