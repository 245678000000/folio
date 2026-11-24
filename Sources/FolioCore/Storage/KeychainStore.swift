import Foundation
import Security

/// 会话凭据安全存储协议
public protocol SessionStoreProtocol: Sendable {
    func loadSession() -> Session?
    func saveSession(_ session: Session) throws
    func clearSession() throws
}

/// 基于 macOS 原生 Keychain 的会话凭据存储
public final class KeychainSessionStore: SessionStoreProtocol, Sendable {
    private let service: String
    private let account: String

    public init(service: String = "com.folio.zlibrary", account: String = "active_session") {
        self.service = service
        self.account = account
    }

    public func loadSession() -> Session? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public func saveSession(_ session: Session) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw EapiError.storage("无法序列化会话数据：\(error.localizedDescription)")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw EapiError.storage("写入 macOS 钥匙串失败（状态码 \(addStatus)）")
            }
            return
        }

        throw EapiError.storage("更新 macOS 钥匙串失败（状态码 \(updateStatus)）")
    }

    public func clearSession() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EapiError.storage("清除 macOS 钥匙串凭据失败（状态码 \(status)）")
        }
    }
}

/// 内存会话存储（用于单元测试隔离）
public final class InMemorySessionStore: SessionStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Session?

    public init(initial: Session? = nil) {
        self.stored = initial
    }

    public func loadSession() -> Session? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public func saveSession(_ session: Session) throws {
        lock.lock()
        stored = session
        lock.unlock()
    }

    public func clearSession() throws {
        lock.lock()
        stored = nil
        lock.unlock()
    }
}
