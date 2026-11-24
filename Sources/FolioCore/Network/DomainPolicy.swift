import Foundation

/// 服务器域名规范化与安全校验策略
public enum DomainPolicy {
    /// 校验单个域名标签（仅允许小写字母、数字与中间连字符）
    private static func isValidHost(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return false }
            guard let first = label.first, let last = label.last,
                  (first.isASCII && (first.isLetter || first.isNumber)),
                  (last.isASCII && (last.isLetter || last.isNumber)) else {
                return false
            }
            let allValid = label.allSatisfy { ch in
                ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-")
            }
            if !allValid { return false }
        }
        return true
    }

    /// 将用户输入（裸主机名或完整 HTTPS URL）清洗为规范的小写主机名
    public static func normalizeHost(_ rawInput: String) throws -> String {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EapiError.invalidDomain("空域名")
        }

        // 明确拒绝明文 HTTP 或其他非常规协议
        if let schemeRange = trimmed.range(of: "://") {
            let scheme = trimmed[..<schemeRange.lowerBound].lowercased()
            guard scheme == "https" else {
                throw EapiError.invalidDomain(trimmed)
            }
        }

        // 拒绝包含空白字符或用户信息注入（user:pass@host）
        guard !trimmed.contains(where: { $0.isWhitespace }),
              !trimmed.contains("@") else {
            throw EapiError.invalidDomain(trimmed)
        }

        let candidateURLString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidateURLString),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            throw EapiError.invalidDomain(trimmed)
        }

        // 必须为标准多段域名（拒绝 localhost 或畸形字符）
        guard isValidHost(host) else {
            throw EapiError.invalidDomain(trimmed)
        }

        if let port = components.port {
            guard (1...65535).contains(port) else {
                throw EapiError.invalidDomain(trimmed)
            }
            return "\(host):\(port)"
        }
        return host
    }

    /// 生成标准的 HTTPS 基础地址（不带尾部斜杠）
    public static func baseURL(for rawInput: String) throws -> String {
        let host = try normalizeHost(rawInput)
        return "https://\(host)"
    }
}
