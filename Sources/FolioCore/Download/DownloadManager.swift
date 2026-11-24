import Foundation

/// 单个下载任务的状态机
public enum DownloadItemStatus: Equatable, Sendable {
    case queued
    case resolving
    case downloading(receivedBytes: Int64, totalBytes: Int64?)
    case completed(localPath: String, fileSize: Int64)
    case failed(message: String)
    case cancelled

    public var isActive: Bool {
        switch self {
        case .queued, .resolving, .downloading:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }

    public var progress: Double? {
        switch self {
        case .downloading(let received, let total):
            guard let total, total > 0 else { return nil }
            return min(1.0, max(0.0, Double(received) / Double(total)))
        case .completed:
            return 1.0
        default:
            return nil
        }
    }
}

/// 下载任务列表项快照
public struct DownloadTaskItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let book: Book
    public let targetID: String
    public let targetHash: String
    public let targetExtension: String
    public let createdAt: Date
    public var status: DownloadItemStatus

    public var displayExtension: String {
        targetExtension.uppercased()
    }

    public var localFileURL: URL? {
        if case .completed(let path, _) = status {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    public init(
        id: UUID = UUID(),
        book: Book,
        targetID: String,
        targetHash: String,
        targetExtension: String,
        createdAt: Date = Date(),
        status: DownloadItemStatus = .queued
    ) {
        self.id = id
        self.book = book
        self.targetID = targetID
        self.targetHash = targetHash
        self.targetExtension = targetExtension.isEmpty ? "epub" : targetExtension.lowercased()
        self.createdAt = createdAt
        self.status = status
    }
}

/// 电子书流式下载执行引擎（兼容真实 EAPI 两阶段下载与离线演示下载）
public actor DownloadExecutor {
    private var proxy: ProxyConfiguration
    private var transferSession: URLSession

    public init(proxy: ProxyConfiguration = .systemDefault) {
        self.proxy = proxy
        self.transferSession = ProxySessionFactory.makeSession(
            proxy: proxy,
            timeoutInterval: 30,
            resourceTimeout: 600
        )
    }

    public func updateProxy(_ newProxy: ProxyConfiguration) {
        guard newProxy != proxy else { return }
        self.proxy = newProxy
        self.transferSession.finishTasksAndInvalidate()
        self.transferSession = ProxySessionFactory.makeSession(
            proxy: newProxy,
            timeoutInterval: 30,
            resourceTimeout: 600
        )
    }

    /// 执行真实 EAPI 文件下载并原子落盘
    public func downloadLive(
        book: Book,
        targetID: String,
        targetHash: String,
        targetExtension: String,
        session: Session,
        client: EapiClient,
        destinationDirectory: URL,
        onStatus: @escaping @Sendable (DownloadItemStatus) -> Void
    ) async throws -> (url: URL, size: Int64) {
        onStatus(.resolving)
        try ensureDirectoryExists(destinationDirectory)

        let resolved = try await client.resolveDownloadTarget(
            id: targetID,
            hash: targetHash,
            session: session
        )

        let ext = targetExtension.isEmpty ? (book.fileExtension.isEmpty ? "epub" : book.fileExtension) : targetExtension

        // 情况 A：第一阶段已直接返回完整文件数据
        if let directData = resolved.directData {
            guard !directData.isEmpty else {
                throw EapiError.parse("下载的文件内容为空")
            }
            let filename = DownloadFilenamePolicy.sanitize(
                suggestedName: resolved.suggestedFilename,
                fallbackTitle: book.title,
                author: book.authors,
                fileExtension: ext
            )
            let finalURL = DownloadFilenamePolicy.uniqueDestinationURL(in: destinationDirectory, filename: filename)
            try directData.write(to: finalURL, options: [.atomic])
            let size = Int64(directData.count)
            onStatus(.completed(localPath: finalURL.path, fileSize: size))
            return (finalURL, size)
        }

        // 情况 B：流式下载二阶段链接
        let (asyncBytes, response) = try await transferSession.bytes(for: resolved.request)
        guard let http = response as? HTTPURLResponse else {
            throw EapiError.network("下载服务器未返回有效的 HTTP 响应")
        }

        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("text/html") {
            throw EapiError.server(statusCode: http.statusCode, message: "下载地址返回了网页而非电子书，可能已触发限流或链接过期")
        }
        guard (200...299).contains(http.statusCode) else {
            throw EapiError.server(statusCode: http.statusCode, message: "文件下载失败（HTTP \(http.statusCode)）")
        }

        let expectedTotal = http.expectedContentLength > 0 ? http.expectedContentLength : nil
        let suggested = resolved.suggestedFilename ?? http.suggestedFilename
        let filename = DownloadFilenamePolicy.sanitize(
            suggestedName: suggested,
            fallbackTitle: book.title,
            author: book.authors,
            fileExtension: ext
        )
        let partURL = destinationDirectory.appendingPathComponent(".\(UUID().uuidString).folio.part")
        FileManager.default.createFile(atPath: partURL.path, contents: nil)

        let fileHandle = try FileHandle(forWritingTo: partURL)
        var receivedBytes: Int64 = 0
        var lastReportedBytes: Int64 = 0
        var chunkBuffer = Data()
        chunkBuffer.reserveCapacity(65_536)

        do {
            onStatus(.downloading(receivedBytes: 0, totalBytes: expectedTotal))
            for try await byte in asyncBytes {
                try Task.checkCancellation()
                chunkBuffer.append(byte)
                if chunkBuffer.count >= 65_536 {
                    try fileHandle.write(contentsOf: chunkBuffer)
                    receivedBytes += Int64(chunkBuffer.count)
                    chunkBuffer.removeAll(keepingCapacity: true)
                    if receivedBytes - lastReportedBytes >= 65_536 {
                        lastReportedBytes = receivedBytes
                        onStatus(.downloading(receivedBytes: receivedBytes, totalBytes: expectedTotal))
                    }
                }
            }
            if !chunkBuffer.isEmpty {
                try fileHandle.write(contentsOf: chunkBuffer)
                receivedBytes += Int64(chunkBuffer.count)
            }
            try fileHandle.close()
        } catch {
            try? fileHandle.close()
            try? FileManager.default.removeItem(at: partURL)
            if error is CancellationError {
                throw EapiError.cancelled
            }
            throw EapiError.network(error.localizedDescription)
        }

        guard receivedBytes > 0 else {
            try? FileManager.default.removeItem(at: partURL)
            throw EapiError.parse("下载的文件为空（0 字节）")
        }

        let finalURL = DownloadFilenamePolicy.uniqueDestinationURL(in: destinationDirectory, filename: filename)
        do {
            try FileManager.default.moveItem(at: partURL, to: finalURL)
        } catch {
            try? FileManager.default.removeItem(at: partURL)
            throw EapiError.storage("保存文件到目标目录失败：\(error.localizedDescription)")
        }

        onStatus(.completed(localPath: finalURL.path, fileSize: receivedBytes))
        return (finalURL, receivedBytes)
    }

    /// 执行离线演示模式模拟流式下载并生成可被 Apple Books / 预览打开的真实电子书
    public func downloadDemo(
        book: Book,
        targetExtension: String,
        destinationDirectory: URL,
        onStatus: @escaping @Sendable (DownloadItemStatus) -> Void
    ) async throws -> (url: URL, size: Int64) {
        onStatus(.resolving)
        try ensureDirectoryExists(destinationDirectory)

        let ext = targetExtension.isEmpty ? (book.fileExtension.isEmpty ? "epub" : book.fileExtension) : targetExtension
        let payload = DemoLibraryService.makeDemoBookData(for: book, fileExtension: ext)
        let total = Int64(payload.count)

        // 模拟平滑进度反馈（总耗时约 0.5 秒）
        for step in 1...5 {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(90))
            let received = total * Int64(step) / 5
            onStatus(.downloading(receivedBytes: received, totalBytes: total))
        }

        let filename = DownloadFilenamePolicy.sanitize(
            suggestedName: nil,
            fallbackTitle: book.title,
            author: book.authors,
            fileExtension: ext
        )
        let finalURL = DownloadFilenamePolicy.uniqueDestinationURL(in: destinationDirectory, filename: filename)
        try payload.write(to: finalURL, options: [.atomic])
        onStatus(.completed(localPath: finalURL.path, fileSize: total))
        return (finalURL, total)
    }

    private func ensureDirectoryExists(_ directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw EapiError.storage("无法创建下载目录 \(directory.path)：\(error.localizedDescription)")
        }
    }
}
