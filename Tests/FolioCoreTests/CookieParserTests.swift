import Foundation
import Testing
@testable import FolioCore

@Suite("Cookie 解析与官网会话提取测试")
struct CookieParserTests {
    @Test("从原始 Cookie 请求头提取 remix 凭据")
    func parseRawCookieHeader() throws {
        let raw = "Cookie: remix_userid=556677; remix_userkey=abcdef123456; siteLanguageV2=zh; Path=/"
        let parsed = try CookieParser.parse(rawText: raw)
        #expect(parsed.remixUserID == "556677")
        #expect(parsed.remixUserKey == "abcdef123456")
        #expect(parsed.cookies["siteLanguageV2"] == "zh")
        #expect(parsed.cookies["Path"] == nil)
    }

    @Test("从浏览器导出的 JSON 数组提取 remix 凭据")
    func parseJsonArrayCookies() throws {
        let json = """
        [
          {"name": "remix_userid", "value": "8899"},
          {"name": "remix_userkey", "value": "key_xyz"}
        ]
        """
        let parsed = try CookieParser.parse(rawText: json)
        #expect(parsed.remixUserID == "8899")
        #expect(parsed.remixUserKey == "key_xyz")
    }

    @Test("从 HTTPCookie 集合按域名匹配提取凭据并忽略无关域")
    func extractFromHTTPCookies() throws {
        let matchingID = try #require(HTTPCookie(properties: [
            .domain: ".z-lib.gd",
            .path: "/",
            .name: "remix_userid",
            .value: "1122",
        ]))
        let matchingKey = try #require(HTTPCookie(properties: [
            .domain: "my.z-lib.gd",
            .path: "/",
            .name: "remix_userkey",
            .value: "secret_token",
        ]))
        let unrelated = try #require(HTTPCookie(properties: [
            .domain: "other.example.com",
            .path: "/",
            .name: "remix_userkey",
            .value: "wrong_token",
        ]))

        let extracted = try #require(
            CookieParser.extract(from: [matchingID, matchingKey, unrelated], matchingHost: "my.z-lib.gd")
        )
        #expect(extracted.remixUserID == "1122")
        #expect(extracted.remixUserKey == "secret_token")
    }
}
