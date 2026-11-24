import Foundation
import Testing
@testable import FolioCore

@Suite("下载文件名清洗与防重名策略")
struct DownloadFilenamePolicyTests {
    @Test("移除路径非法字符并确保附加规范扩展名")
    func sanitizeFilename() {
        let name = DownloadFilenamePolicy.sanitize(
            suggestedName: "思考: 快/与*慢?.pdf",
            fallbackTitle: "备用名",
            fileExtension: "PDF"
        )
        #expect(name == "思考 快 与 慢.pdf")

        let fallback = DownloadFilenamePolicy.sanitize(
            suggestedName: nil,
            fallbackTitle: "设计心理学",
            author: "唐纳德·诺曼",
            fileExtension: "epub"
        )
        #expect(fallback == "设计心理学 - 唐纳德·诺曼.epub")
    }

    @Test("目标目录存在同名文件时自动递增编号防覆盖")
    func uniqueDestinationAutoIncrements() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-name-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let first = DownloadFilenamePolicy.uniqueDestinationURL(in: tempDir, filename: "Book.epub")
        #expect(first.lastPathComponent == "Book.epub")
        try Data("a".utf8).write(to: first)

        let second = DownloadFilenamePolicy.uniqueDestinationURL(in: tempDir, filename: "Book.epub")
        #expect(second.lastPathComponent == "Book (1).epub")
        try Data("b".utf8).write(to: second)

        let third = DownloadFilenamePolicy.uniqueDestinationURL(in: tempDir, filename: "Book.epub")
        #expect(third.lastPathComponent == "Book (2).epub")
    }
}
