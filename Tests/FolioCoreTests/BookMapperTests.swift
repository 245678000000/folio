import Foundation
import Testing
@testable import FolioCore

@Suite("书籍 JSON 映射与安全校验")
struct BookMapperTests {
    @Test("完整解析混合类型字段、ISBN 与下载历史日期")
    func parseMixedTypeBookPayload() throws {
        let jsonString = """
        {
          "success": 1,
          "books": [
            {
              "id": 123456,
              "hash": "ab12cd",
              "title": "设计心理学",
              "subtitle": "日常的设计",
              "author": "唐纳德·诺曼",
              "publisher": "中信出版社",
              "year": 2015,
              "language": "chinese",
              "extension": "EPUB",
              "filesize": "2457600",
              "filesizeString": "2.34 MB",
              "identifier": "978-7-5086-4833-0, 750864833X",
              "cover": "https://covers.example.com/covers/123456.jpg",
              "description": "一本经典交互设计著作。",
              "categories": "设计, 心理学",
              "pages": "320",
              "interestScore": "4.8",
              "date_download": "2026-11-20 14:30:00"
            }
          ]
        }
        """
        let data = try #require(jsonString.data(using: .utf8))
        let root = try EapiJSONParser.parseObject(from: data)
        let books = BookMapper.list(from: root, includeHistoryDate: true)

        #expect(books.count == 1)
        let book = try #require(books.first)
        #expect(book.id == "123456")
        #expect(book.hash == "ab12cd")
        #expect(book.title == "设计心理学")
        #expect(book.year == "2015")
        #expect(book.fileExtension == "epub")
        #expect(book.sizeBytes == 2_457_600)
        #expect(book.isbn13 == "9787508648330")
        #expect(book.isbn10 == "750864833X")
        #expect(book.pages == 320)
        #expect(book.rating == 4.8)
        #expect(book.categories == ["设计", "心理学"])
        #expect(book.coverURL == "https://covers.example.com/covers/123456.jpg")
        #expect(book.historyDate == "2026-11-20 14:30:00")
    }

    @Test("过滤占位坏封面、双斜杠路径与非法引用字符")
    func filterInvalidCoversAndUnsafeRefs() throws {
        let jsonString = """
        {
          "books": [
            {
              "id": "../etc/passwd",
              "hash": "abc123",
              "title": "恶意路径书"
            },
            {
              "id": "999",
              "hash": "validHash9",
              "title": "坏封面书",
              "cover": "https://covers.example.com//cover-not-exists.png"
            },
            {
              "id": "1000",
              "hash": "validHash10",
              "title": "非 HTTPS 封面书",
              "cover": "http://covers.example.com/a.jpg"
            }
          ]
        }
        """
        let data = try #require(jsonString.data(using: .utf8))
        let root = try EapiJSONParser.parseObject(from: data)
        let books = BookMapper.list(from: root)

        #expect(books.count == 2)
        #expect(books[0].id == "999")
        #expect(books[0].coverURL.isEmpty)
        #expect(books[1].id == "1000")
        #expect(books[1].coverURL.isEmpty)
        #expect(!BookMapper.isSafeRef("../bad", "abc"))
        #expect(BookMapper.isSafeRef("12345", "a1b2c3"))
    }
}
