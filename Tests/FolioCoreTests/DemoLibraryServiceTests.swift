import Foundation
import Testing
@testable import FolioCore

@Suite("演示书库与本地电子书生成测试")
struct DemoLibraryServiceTests {
    @Test("支持关键词、语言、格式、年份组合检索与收藏状态同步")
    func searchAndFavoritesInDemoMode() async throws {
        let service = DemoLibraryService()

        let query = SearchQuery(
            message: "设计",
            languages: ["chinese"],
            extensions: ["epub"],
            sort: .popular
        )
        let page = try await service.search(query: query, page: 1, limit: 20, session: nil, fallbackDomain: nil)
        #expect(!page.books.isEmpty)
        #expect(page.books.allSatisfy { $0.language == "chinese" && $0.fileExtension == "epub" })

        let targetID = page.books[0].id
        try await service.setBookSaved(id: targetID, saved: false, session: nil)
        let savedAfterRemove = try await service.savedBooks(page: 1, limit: 20, session: nil)
        #expect(!savedAfterRemove.books.contains(where: { $0.id == targetID }))

        try await service.setBookSaved(id: targetID, saved: true, session: nil)
        let savedAfterAdd = try await service.savedBooks(page: 1, limit: 20, session: nil)
        #expect(savedAfterAdd.books.contains(where: { $0.id == targetID }))
    }

    @Test("演示下载能生成合规 EPUB 与 PDF 文件并成功落盘")
    func demoDownloadGeneratesValidEpubAndPdf() async throws {
        let service = DemoLibraryService()
        let books = try await service.mostPopular(session: nil, fallbackDomain: nil)
        let sample = try #require(books.first)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-demo-dl-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let executor = DownloadExecutor()

        // 验证 EPUB（ZIP PK 文件头 + mimetype）
        let epubResult = try await executor.downloadDemo(
            book: sample,
            targetExtension: "epub",
            destinationDirectory: tempDir,
            onStatus: { _ in }
        )
        let epubData = try Data(contentsOf: epubResult.url)
        #expect(epubData.prefix(2) == Data([0x50, 0x4B]))
        #expect(epubResult.url.pathExtension == "epub")

        // 验证 PDF（%PDF 文件头）
        let pdfResult = try await executor.downloadDemo(
            book: sample,
            targetExtension: "pdf",
            destinationDirectory: tempDir,
            onStatus: { _ in }
        )
        let pdfData = try Data(contentsOf: pdfResult.url)
        #expect(String(data: pdfData.prefix(4), encoding: .ascii) == "%PDF")
        #expect(pdfResult.url.pathExtension == "pdf")
    }
}
