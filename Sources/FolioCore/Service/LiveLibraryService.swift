import Foundation

/// 真实 Z-Library EAPI 书库服务实现
public final class LiveLibraryService: LibraryServiceProtocol, Sendable {
    public let client: EapiClient
    public var isDemoMode: Bool { false }

    public init(client: EapiClient) {
        self.client = client
    }

    public func profile(session: Session?) async throws -> AccountProfile {
        guard let session else { throw EapiError.notLoggedIn }
        return try await client.profile(session: session)
    }

    public func mostPopular(session: Session?, fallbackDomain: String?) async throws -> [Book] {
        try await client.mostPopular(session: session, fallbackDomain: fallbackDomain)
    }

    public func recently(session: Session?, fallbackDomain: String?) async throws -> [Book] {
        try await client.recently(session: session, fallbackDomain: fallbackDomain)
    }

    public func recommended(session: Session?) async throws -> [Book] {
        guard let session else { throw EapiError.notLoggedIn }
        return try await client.recommended(session: session)
    }

    public func search(
        query: SearchQuery,
        page: Int,
        limit: Int,
        session: Session?,
        fallbackDomain: String?
    ) async throws -> BookPage {
        try await client.search(
            query: query,
            page: page,
            limit: limit,
            session: session,
            fallbackDomain: fallbackDomain
        )
    }

    public func bookDetail(id: String, hash: String, session: Session?, fallbackDomain: String?) async throws -> Book {
        try await client.bookDetail(id: id, hash: hash, session: session, fallbackDomain: fallbackDomain)
    }

    public func bookFormats(id: String, hash: String, session: Session?) async throws -> [BookFormat] {
        guard let session else { throw EapiError.notLoggedIn }
        return try await client.bookFormats(id: id, hash: hash, session: session)
    }

    public func similarBooks(id: String, hash: String, session: Session?, fallbackDomain: String?) async throws -> [Book] {
        try await client.similarBooks(id: id, hash: hash, session: session, fallbackDomain: fallbackDomain)
    }

    public func savedBooks(page: Int, limit: Int, session: Session?) async throws -> BookPage {
        guard let session else { throw EapiError.notLoggedIn }
        return try await client.savedBooks(page: page, limit: limit, session: session)
    }

    public func setBookSaved(id: String, saved: Bool, session: Session?) async throws {
        guard let session else { throw EapiError.notLoggedIn }
        try await client.setBookSaved(id: id, saved: saved, session: session)
    }

    public func downloadedBooks(page: Int, limit: Int, session: Session?) async throws -> BookPage {
        guard let session else { throw EapiError.notLoggedIn }
        return try await client.downloadedBooks(page: page, limit: limit, session: session)
    }

    public func deleteDownloadHistory(id: String, session: Session?) async throws {
        guard let session else { throw EapiError.notLoggedIn }
        try await client.deleteDownloadHistory(id: id, session: session)
    }

    public func filterOptions(domain: String?) async throws -> SearchFilterOptions {
        guard let domain, !domain.isEmpty else {
            return .fallback
        }
        return (try? await client.filterOptions(domain: domain)) ?? .fallback
    }
}
