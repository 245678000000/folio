import Foundation
import Testing
@testable import FolioCore

/// 线程安全的测试用 Mock URLProtocol 路由器
private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [String: Handler] = [:]

    static func register(host: String, handler: @escaping Handler) {
        lock.lock()
        handlers[host.lowercased()] = handler
        lock.unlock()
    }

    static func unregister(host: String) {
        lock.lock()
        handlers.removeValue(forKey: host.lowercased())
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host?.lowercased() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        let handler = Self.handlers[host]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// 读取 URLRequest 的请求体（兼容 httpBody 与 httpBodyStream）
private func readBodyString(from request: URLRequest) -> String {
    if let body = request.httpBody {
        return String(data: body, encoding: .utf8) ?? ""
    }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return String(data: data, encoding: .utf8) ?? ""
}

@Suite("EAPI 网络协议层全链路测试")
struct EapiClientTests {
    @Test("搜索请求必须附带 source: android 头并正确编码多选数组参数")
    func searchSendsRequiredHeadersAndEncodedForm() async throws {
        let host = "search-ok.folio.test"
        defer { MockURLProtocol.unregister(host: host) }

        MockURLProtocol.register(host: host) { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/eapi/book/search")
            #expect(request.value(forHTTPHeaderField: "source") == "android")
            #expect(request.value(forHTTPHeaderField: "remix-userid") == "42")
            #expect(request.value(forHTTPHeaderField: "remix-userkey") == "secretKey")

            let body = readBodyString(from: request)
            #expect(body.contains("message=Swift"))
            #expect(body.contains("e=1"))
            #expect(body.contains("yearFrom=2020"))
            #expect(body.contains("languages%5B%5D=chinese"))
            #expect(body.contains("extensions%5B%5D=epub"))
            #expect(body.contains("order=popular"))

            let payload = """
            {
              "success": 1,
              "books": [
                {"id": "101", "hash": "abc111", "title": "Swift 进阶", "author": "王巍", "extension": "epub", "year": "2024"}
              ],
              "pagination": {"current": 1, "total_pages": 3, "next": 2}
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(payload.utf8))
        }

        let client = EapiClient(protocolClasses: [MockURLProtocol.self])
        let session = Session(remixUserID: "42", remixUserKey: "secretKey", domain: host)
        let query = SearchQuery(
            message: "Swift",
            exact: true,
            yearFrom: 2020,
            languages: ["chinese"],
            extensions: ["epub"],
            sort: .popular
        )

        let page = try await client.search(query: query, page: 1, limit: 20, session: session)
        #expect(page.books.count == 1)
        #expect(page.books[0].title == "Swift 进阶")
        #expect(page.totalPages == 3)
        #expect(page.hasMore)
    }

    @Test("搜索接口返回 Access denied 时精准映射为 searchRefused 错误")
    func searchAccessDeniedMapsToSearchRefused() async throws {
        let host = "search-denied.folio.test"
        defer { MockURLProtocol.unregister(host: host) }

        MockURLProtocol.register(host: host) { request in
            let payload = #"{"success":0,"error":"Access denied"}"#
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(payload.utf8))
        }

        let client = EapiClient(protocolClasses: [MockURLProtocol.self])
        let session = Session(remixUserID: "42", remixUserKey: "secretKey", domain: host)

        await #expect(throws: EapiError.searchRefused) {
            _ = try await client.search(query: SearchQuery(message: "Design"), session: session)
        }
    }

    @Test("登录接口正确提取用户 JSON 与 Set-Cookie 中的 remix 凭据")
    func loginExtractsCredentials() async throws {
        let host = "login.folio.test"
        defer { MockURLProtocol.unregister(host: host) }

        MockURLProtocol.register(host: host) { request in
            #expect(request.value(forHTTPHeaderField: "source") == "android")
            let payload = """
            {
              "success": 1,
              "user": {
                "id": 9988,
                "email": "reader@example.com",
                "remix_userkey": "key_from_json"
              }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json",
                    "Set-Cookie": "remix_userid=9988; Path=/",
                ]
            )!
            return (response, Data(payload.utf8))
        }

        let client = EapiClient(protocolClasses: [MockURLProtocol.self])
        let session = try await client.login(domain: host, email: "reader@example.com", password: "pw")
        #expect(session.remixUserID == "9988")
        #expect(session.remixUserKey == "key_from_json")
        #expect(session.domain == host)
        #expect(session.cookieHeader.contains("remix_userid=9988"))
        #expect(session.cookieHeader.contains("remix_userkey=key_from_json"))
    }

    @Test("下载接口支持 JSON downloadLink 二次解析且不向外部 CDN 泄漏凭据")
    func resolveTwoStageDownloadLinkStripsCredentialsForExternalCDN() async throws {
        let host = "download-json.folio.test"
        defer { MockURLProtocol.unregister(host: host) }

        MockURLProtocol.register(host: host) { request in
            let payload = """
            {
              "success": 1,
              "file": {
                "allowDownload": true,
                "downloadLink": "https://cdn-files.external.test/signed/book.epub?token=xyz",
                "description": "深度工作",
                "extension": "epub"
              }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(payload.utf8))
        }

        let client = EapiClient(protocolClasses: [MockURLProtocol.self])
        let session = Session(remixUserID: "7", remixUserKey: "secret", domain: host)
        let target = try await client.resolveDownloadTarget(id: "123", hash: "abc456", session: session)

        #expect(target.request.url?.absoluteString == "https://cdn-files.external.test/signed/book.epub?token=xyz")
        #expect(target.suggestedFilename == "深度工作.epub")
        #expect(target.request.value(forHTTPHeaderField: "remix-userid") == nil)
        #expect(target.request.value(forHTTPHeaderField: "remix-userkey") == nil)
        #expect(target.request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test("下载接口返回每日限额 HTML 页面时抛出 quotaExhausted 错误")
    func downloadDailyLimitHtmlThrowsQuotaExhausted() async throws {
        let host = "download-quota.folio.test"
        defer { MockURLProtocol.unregister(host: host) }

        MockURLProtocol.register(host: host) { request in
            let html = "<html><body><h1>Daily limit reached</h1></body></html>"
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            )!
            return (response, Data(html.utf8))
        }

        let client = EapiClient(protocolClasses: [MockURLProtocol.self])
        let session = Session(remixUserID: "7", remixUserKey: "secret", domain: host)

        do {
            _ = try await client.resolveDownloadTarget(id: "123", hash: "abc456", session: session)
            Issue.record("预期抛出 quotaExhausted，但未抛出错误")
        } catch EapiError.quotaExhausted {
            // 符合预期
        } catch {
            Issue.record("错误类型不符：\(error)")
        }
    }
}
