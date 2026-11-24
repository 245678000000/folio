import Foundation

/// 书库统一领域服务协议（隔离真实 EAPI 与离线演示模式）
public protocol LibraryServiceProtocol: Sendable {
    var isDemoMode: Bool { get }

    func profile(session: Session?) async throws -> AccountProfile
    func mostPopular(session: Session?, fallbackDomain: String?) async throws -> [Book]
    func recently(session: Session?, fallbackDomain: String?) async throws -> [Book]
    func recommended(session: Session?) async throws -> [Book]
    func search(query: SearchQuery, page: Int, limit: Int, session: Session?, fallbackDomain: String?) async throws -> BookPage
    func bookDetail(id: String, hash: String, session: Session?, fallbackDomain: String?) async throws -> Book
    func bookFormats(id: String, hash: String, session: Session?) async throws -> [BookFormat]
    func similarBooks(id: String, hash: String, session: Session?, fallbackDomain: String?) async throws -> [Book]
    func savedBooks(page: Int, limit: Int, session: Session?) async throws -> BookPage
    func setBookSaved(id: String, saved: Bool, session: Session?) async throws
    func downloadedBooks(page: Int, limit: Int, session: Session?) async throws -> BookPage
    func deleteDownloadHistory(id: String, session: Session?) async throws
    func filterOptions(domain: String?) async throws -> SearchFilterOptions
}
