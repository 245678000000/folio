import Testing
@testable import FolioCore

@Suite("域名策略校验")
struct DomainPolicyTests {
    @Test("规范化标准域名与带协议路径的输入")
    func normalizeValidDomains() throws {
        #expect(try DomainPolicy.normalizeHost("z-lib.gs") == "z-lib.gs")
        #expect(try DomainPolicy.normalizeHost("  HTTPS://My-Personal.Z-Lib.FM/books/123  ") == "my-personal.z-lib.fm")
        #expect(try DomainPolicy.normalizeHost("singlelogin.re/") == "singlelogin.re")
        #expect(try DomainPolicy.baseURL(for: "example.org") == "https://example.org")
    }

    @Test("拒绝非 HTTPS 协议、空输入、用户信息注入与非法主机名")
    func rejectInvalidDomains() {
        #expect(throws: EapiError.self) {
            _ = try DomainPolicy.normalizeHost("")
        }
        #expect(throws: EapiError.self) {
            _ = try DomainPolicy.normalizeHost("http://insecure.example.com")
        }
        #expect(throws: EapiError.self) {
            _ = try DomainPolicy.normalizeHost("https://user:pass@example.com")
        }
        #expect(throws: EapiError.self) {
            _ = try DomainPolicy.normalizeHost("not a host")
        }
        #expect(throws: EapiError.self) {
            _ = try DomainPolicy.normalizeHost("localhost")
        }
    }
}
