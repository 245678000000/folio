import CoreGraphics
import CoreText
import Foundation

/// 离线演示书库服务（无账号时提供完整拟真体验）
public actor DemoLibraryService: LibraryServiceProtocol {
    public nonisolated var isDemoMode: Bool { true }

    private let catalog: [Book]
    private var savedIDs: Set<String>
    private var downloadedIDs: [String]
    private var usedToday: Int
    private let dailyLimit: Int

    public init() {
        self.catalog = Self.sampleCatalog
        self.savedIDs = ["10001", "10003", "10008"]
        self.downloadedIDs = ["10002", "10005"]
        self.usedToday = 2
        self.dailyLimit = 10
    }

    public func profile(session: Session?) async throws -> AccountProfile {
        AccountProfile(
            id: "demo",
            email: "demo@folio.local",
            name: "离线演示书库",
            kindleEmail: "",
            domain: "demo.folio.local",
            quota: DownloadQuota(usedToday: usedToday, dailyLimit: dailyLimit, resetDescription: "演示模式每日自动重置"),
            isDemo: true
        )
    }

    public func mostPopular(session: Session?, fallbackDomain: String?) async throws -> [Book] {
        Array(catalog.prefix(10))
    }

    public func recently(session: Session?, fallbackDomain: String?) async throws -> [Book] {
        catalog.sorted { $0.year > $1.year }
    }

    public func recommended(session: Session?) async throws -> [Book] {
        Array(catalog.reversed().prefix(8))
    }

    public func search(
        query: SearchQuery,
        page: Int,
        limit: Int,
        session: Session?,
        fallbackDomain: String?
    ) async throws -> BookPage {
        let keyword = query.message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else {
            throw EapiError.invalidParameters("搜索关键词不能为空")
        }

        var filtered = catalog.filter { book in
            let haystack = "\(book.title) \(book.subtitle) \(book.authors) \(book.publisher) \(book.description) \(book.categories.joined(separator: " ")) \(book.isbn13)".lowercased()
            if query.exact {
                return book.title.lowercased().contains(keyword) || book.authors.lowercased().contains(keyword)
            }
            let terms = keyword.split(whereSeparator: \.isWhitespace).map(String.init)
            return terms.allSatisfy { haystack.contains($0) }
        }

        if !query.languages.isEmpty {
            let allowed = Set(query.languages.map { $0.lowercased() })
            filtered = filtered.filter { allowed.contains($0.language.lowercased()) }
        }

        if !query.extensions.isEmpty {
            let allowed = Set(query.extensions.map { $0.lowercased() })
            filtered = filtered.filter { allowed.contains($0.fileExtension.lowercased()) }
        }

        if let from = query.yearFrom {
            filtered = filtered.filter { (Int($0.year) ?? 0) >= from }
        }

        if let to = query.yearTo {
            filtered = filtered.filter {
                guard let y = Int($0.year) else { return false }
                return y <= to
            }
        }

        switch query.sort {
        case .bestMatch:
            break
        case .popular:
            filtered.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .year, .date:
            filtered.sort { (Int($0.year) ?? 0) > (Int($1.year) ?? 0) }
        case .title:
            filtered.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .fileSize:
            filtered.sort { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        }

        let safePage = max(1, page)
        let safeLimit = max(1, limit)
        let totalPages = max(1, Int(ceil(Double(filtered.count) / Double(safeLimit))))
        let start = (safePage - 1) * safeLimit
        let slice = start < filtered.count ? Array(filtered[start..<min(filtered.count, start + safeLimit)]) : []

        return BookPage(books: slice, page: safePage, totalPages: totalPages)
    }

    public func bookDetail(id: String, hash: String, session: Session?, fallbackDomain: String?) async throws -> Book {
        guard let book = catalog.first(where: { $0.id == id }) else {
            throw EapiError.server(statusCode: 404, message: "演示书库中未找到该书籍")
        }
        return book
    }

    public func bookFormats(id: String, hash: String, session: Session?) async throws -> [BookFormat] {
        let baseSize = catalog.first(where: { $0.id == id })?.sizeBytes ?? 2_400_000
        return [
            BookFormat(id: id, hash: hash, fileExtension: "epub", sizeBytes: baseSize, sizeText: ByteCountFormatter.string(fromByteCount: baseSize, countStyle: .file)),
            BookFormat(id: id, hash: "\(hash)pdf", fileExtension: "pdf", sizeBytes: baseSize * 2, sizeText: ByteCountFormatter.string(fromByteCount: baseSize * 2, countStyle: .file)),
            BookFormat(id: id, hash: "\(hash)txt", fileExtension: "txt", sizeBytes: max(120_000, baseSize / 6), sizeText: ByteCountFormatter.string(fromByteCount: max(120_000, baseSize / 6), countStyle: .file)),
        ]
    }

    public func similarBooks(id: String, hash: String, session: Session?, fallbackDomain: String?) async throws -> [Book] {
        guard let target = catalog.first(where: { $0.id == id }) else { return [] }
        let targetCats = Set(target.categories)
        let matched = catalog.filter { $0.id != id && !targetCats.isDisjoint(with: $0.categories) }
        if !matched.isEmpty {
            return Array(matched.prefix(5))
        }
        return Array(catalog.filter { $0.id != id }.prefix(4))
    }

    public func savedBooks(page: Int, limit: Int, session: Session?) async throws -> BookPage {
        let books = catalog.filter { savedIDs.contains($0.id) }
        return BookPage(books: books, page: 1, totalPages: 1)
    }

    public func setBookSaved(id: String, saved: Bool, session: Session?) async throws {
        if saved {
            savedIDs.insert(id)
        } else {
            savedIDs.remove(id)
        }
    }

    public func downloadedBooks(page: Int, limit: Int, session: Session?) async throws -> BookPage {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateText = formatter.string(from: Date())
        let books = downloadedIDs.compactMap { id -> Book? in
            guard let book = catalog.first(where: { $0.id == id }) else { return nil }
            return Book(
                id: book.id,
                hash: book.hash,
                title: book.title,
                subtitle: book.subtitle,
                authors: book.authors,
                publisher: book.publisher,
                year: book.year,
                language: book.language,
                fileExtension: book.fileExtension,
                sizeBytes: book.sizeBytes,
                sizeText: book.sizeText,
                isbn10: book.isbn10,
                isbn13: book.isbn13,
                coverURL: book.coverURL,
                description: book.description,
                categories: book.categories,
                edition: book.edition,
                pages: book.pages,
                rating: book.rating,
                href: book.href,
                historyDate: dateText
            )
        }
        return BookPage(books: books, page: 1, totalPages: 1)
    }

    public func deleteDownloadHistory(id: String, session: Session?) async throws {
        downloadedIDs.removeAll { $0 == id }
    }

    public func filterOptions(domain: String?) async throws -> SearchFilterOptions {
        .fallback
    }

    /// 演示模式记录一次本地下载并增加今日配额计数
    public func recordDemoDownload(bookID: String) {
        downloadedIDs.removeAll { $0 == bookID }
        downloadedIDs.insert(bookID, at: 0)
        usedToday = min(dailyLimit, usedToday + 1)
    }

    /// 生成真实可被系统阅读器（Apple Books / 预览）打开的演示电子书二进制内容
    public static func makeDemoBookData(for book: Book, fileExtension: String) -> Data {
        switch fileExtension.lowercased() {
        case "epub":
            return DemoEPUBBuilder.build(book: book)
        case "pdf":
            return DemoPDFBuilder.build(book: book)
        default:
            let content = """
            《\(book.title)》
            作者：\(book.authors)
            出版社：\(book.publisher)（\(book.year)）
            ISBN：\(book.displayISBN)

            ----------------------------------------
            内容简介
            ----------------------------------------
            \(book.description)

            ----------------------------------------
            说明
            ----------------------------------------
            本文件由 Folio macOS 客户端演示模式生成，用于体验从检索、下载到调用系统默认阅读器打开的完整流程。
            登录你的 Z-Library 账号后，即可下载真实完整电子书。
            """
            return Data(content.utf8)
        }
    }

    // MARK: - 精选演示书目

    private static let sampleCatalog: [Book] = [
        Book(
            id: "10001", hash: "f1a2b3", title: "设计心理学", subtitle: "日常的设计",
            authors: "唐纳德·诺曼", publisher: "中信出版社", year: "2015", language: "chinese",
            fileExtension: "epub", sizeBytes: 3_420_160, sizeText: "3.26 MB",
            isbn13: "9787508648330",
            description: "交互设计领域不可逾越的经典之作。诺曼从人类认知与行为心理出发，系统阐述了示能、意符、反馈与概念模型，揭示好设计为何既简洁美观又符合直觉。",
            categories: ["设计", "人机交互"], pages: 320, rating: 4.9
        ),
        Book(
            id: "10002", hash: "c4d5e6", title: "数据密集型应用系统设计", subtitle: "Designing Data-Intensive Applications",
            authors: "Martin Kleppmann", publisher: "中国电力出版社", year: "2018", language: "chinese",
            fileExtension: "epub", sizeBytes: 12_845_056, sizeText: "12.25 MB",
            isbn13: "9787519823429",
            description: "全面剖析现代分布式系统、存储引擎、数据编码、复制分区与流处理的底层原理，帮助架构师在可靠性、可扩展性与可维护性之间做出清晰权衡。",
            categories: ["计算机", "架构"], pages: 616, rating: 4.9
        ),
        Book(
            id: "10003", hash: "a7b8c9", title: "The Elements of Typographic Style", subtitle: "Version 4.0",
            authors: "Robert Bringhurst", publisher: "Hartley & Marks", year: "2019", language: "english",
            fileExtension: "pdf", sizeBytes: 8_912_896, sizeText: "8.50 MB",
            isbn13: "9780881792126",
            description: "被誉为排印与书籍设计界的圣经，从字距、行高、版心比例到字体历史娓娓道来，为纸质与数字界面排版树立审美基准。",
            categories: ["设计", "排版"], pages: 398, rating: 4.8
        ),
        Book(
            id: "10004", hash: "d0e1f2", title: "三体全集", subtitle: "地球往事三部曲",
            authors: "刘慈欣", publisher: "重庆出版社", year: "2020", language: "chinese",
            fileExtension: "epub", sizeBytes: 4_718_592, sizeText: "4.50 MB",
            isbn13: "9787229042066",
            description: "宏大的宇宙社会学图景与硬核科幻想象交织，从红岸基地的一声电波开始，跨越数百年展开人类文明与三体文明的存亡博弈。",
            categories: ["科幻", "文学"], pages: 880, rating: 4.9
        ),
        Book(
            id: "10005", hash: "e3f4a5", title: "Swift Programming: The Big Nerd Ranch Guide", subtitle: "3rd Edition",
            authors: "Matthew Mathias, John Gallagher", publisher: "Big Nerd Ranch", year: "2022", language: "english",
            fileExtension: "epub", sizeBytes: 6_291_456, sizeText: "6.00 MB",
            isbn13: "9780135264201",
            description: "深入浅出地讲解 Swift 类型系统、值语义、协议导向编程与现代并发模型，适合从基础迈向原生 macOS 与 iOS 工程实践。",
            categories: ["计算机", "Swift"], pages: 448, rating: 4.7
        ),
        Book(
            id: "10006", hash: "b6c7d8", title: "置身事内", subtitle: "中国政府与经济发展",
            authors: "兰小欢", publisher: "上海人民出版社", year: "2021", language: "chinese",
            fileExtension: "epub", sizeBytes: 2_621_440, sizeText: "2.50 MB",
            isbn13: "9787208171336",
            description: "以清晰克制的笔触拆解地方财政、土地金融、产业升级与宏观债务之间的内在机制，让普通读者也能看懂中国经济运行的真实逻辑。",
            categories: ["经济", "社会"], pages: 368, rating: 4.8
        ),
        Book(
            id: "10007", hash: "f9a0b1", title: "A Philosophy of Software Design", subtitle: "2nd Edition",
            authors: "John Ousterhout", publisher: "Yaknyam Press", year: "2021", language: "english",
            fileExtension: "pdf", sizeBytes: 3_145_728, sizeText: "3.00 MB",
            isbn13: "9781732102217",
            description: "聚焦软件工程中最根本的敌人——复杂性。提出深模块、信息隐藏与清晰注释等实用原则，篇幅凝练而洞见深刻。",
            categories: ["计算机", "架构"], pages: 196, rating: 4.8
        ),
        Book(
            id: "10008", hash: "c2d3e4", title: "人类简史", subtitle: "从动物到上帝",
            authors: "尤瓦尔·赫拉利", publisher: "中信出版社", year: "2017", language: "chinese",
            fileExtension: "epub", sizeBytes: 5_242_880, sizeText: "5.00 MB",
            isbn13: "9787508660752",
            description: "横跨认知革命、农业革命与科学革命三条脉络，重新审视智人如何依靠共同想象构建货币、法律与现代文明。",
            categories: ["历史", "人文"], pages: 440, rating: 4.7
        ),
        Book(
            id: "10009", hash: "a5b6c7", title: "简约至上", subtitle: "交互式设计四策略",
            authors: "Giles Colborne", publisher: "人民邮电出版社", year: "2019", language: "chinese",
            fileExtension: "epub", sizeBytes: 4_194_304, sizeText: "4.00 MB",
            isbn13: "9787115499820",
            description: "系统总结删除、组织、隐藏、转移四大简化策略，告诉产品与界面设计师如何在不牺牲能力的前提下让工具保持轻盈克制。",
            categories: ["设计", "产品"], pages: 232, rating: 4.6
        ),
        Book(
            id: "10010", hash: "e8f9a0", title: "The Pragmatic Programmer", subtitle: "20th Anniversary Edition",
            authors: "David Thomas, Andrew Hunt", publisher: "Addison-Wesley", year: "2019", language: "english",
            fileExtension: "epub", sizeBytes: 5_767_168, sizeText: "5.50 MB",
            isbn13: "9780135957059",
            description: "面向软件工匠的常青指南，涵盖正交设计、可逆架构、自动化验证与持续学习，帮助工程师建立经得起时间检验的职业方法论。",
            categories: ["计算机", "工程"], pages: 352, rating: 4.9
        ),
        Book(
            id: "10011", hash: "b1c2d3", title: "长安的荔枝", subtitle: "",
            authors: "马伯庸", publisher: "湖南文艺出版社", year: "2022", language: "chinese",
            fileExtension: "epub", sizeBytes: 1_572_864, sizeText: "1.50 MB",
            isbn13: "9787572608582",
            description: "盛唐小吏李善德接下一桩几乎不可能完成的“荔枝转运”任务，以精妙的统筹实验与人性挣扎折射庞大帝国的运转细节。",
            categories: ["文学", "历史"], pages: 224, rating: 4.7
        ),
        Book(
            id: "10012", hash: "d4e5f6", title: "思考，快与慢", subtitle: "Thinking, Fast and Slow",
            authors: "丹尼尔·卡尼曼", publisher: "中信出版社", year: "2016", language: "chinese",
            fileExtension: "pdf", sizeBytes: 7_340_032, sizeText: "7.00 MB",
            isbn13: "9787508633558",
            description: "诺贝尔经济学奖得主卡尼曼毕生研究结晶，以系统 1 与系统 2 双轨心智模型揭示直觉偏差、锚定效应与决策陷阱。",
            categories: ["心理学", "人文"], pages: 424, rating: 4.8
        ),
        Book(
            id: "10013", hash: "a7c8e9", title: "Refactoring UI", subtitle: "The Book",
            authors: "Adam Wathan, Steve Schoger", publisher: "Tailwind Labs", year: "2023", language: "english",
            fileExtension: "pdf", sizeBytes: 15_728_640, sizeText: "15.00 MB",
            isbn13: "9781732568006",
            description: "从开发者视角出发的界面美学实战手册：通过层级对比、留白节奏、中性色微调与精致阴影，让应用界面瞬间告别廉价模板感。",
            categories: ["设计", "界面"], pages: 252, rating: 4.8
        ),
        Book(
            id: "10014", hash: "f2d3b4", title: "万历十五年", subtitle: "1587, a Year of No Significance",
            authors: "黄仁宇", publisher: "生活·读书·新知三联书店", year: "2018", language: "chinese",
            fileExtension: "epub", sizeBytes: 2_097_152, sizeText: "2.00 MB",
            isbn13: "9787108009821",
            description: "以公元 1587 年为切口，借万历皇帝、张居正、海瑞、戚继光与李贽五人命运，透视传统礼法体制在现代化转型前的深层困境。",
            categories: ["历史", "人文"], pages: 312, rating: 4.9
        ),
        Book(
            id: "10015", hash: "c5a6d7", title: "Rust 编程之道", subtitle: "深入理解所有权与零成本抽象",
            authors: "张汉东", publisher: "电子工业出版社", year: "2020", language: "chinese",
            fileExtension: "pdf", sizeBytes: 9_437_184, sizeText: "9.00 MB",
            isbn13: "9787121355615",
            description: "从语言设计哲学切入，透彻讲解 Rust 的所有权、借用检查、生命周期与异步并发机制。",
            categories: ["计算机", "系统编程"], pages: 512, rating: 4.6
        ),
        Book(
            id: "10016", hash: "e9b0c1", title: "雪国", subtitle: "川端康成代表作",
            authors: "川端康成", publisher: "南海出版公司", year: "2018", language: "japanese",
            fileExtension: "epub", sizeBytes: 1_153_434, sizeText: "1.10 MB",
            isbn13: "9787544265201",
            description: "“穿过县界长长的隧道，便是雪国。”清冽空灵的物哀美学，勾勒北国雪夜中转瞬即逝的微光与孤寂。",
            categories: ["文学", "经典"], pages: 192, rating: 4.7
        ),
    ]
}

// MARK: - 演示电子书生成器（合规 EPUB 3.0 与 CoreGraphics PDF）

/// 轻量级标准 EPUB 3.0 打包器（纯 Swift 无压缩 Store ZIP，Apple Books 可直接打开阅读）
private enum DemoEPUBBuilder {
    static func build(book: Book) -> Data {
        let escapedTitle = escapeXML(book.title)
        let escapedAuthor = escapeXML(book.authors.isEmpty ? "佚名" : book.authors)
        let escapedDesc = escapeXML(book.description.isEmpty ? "由 Folio 演示模式生成的精装样书。" : book.description)
        let escapedPub = escapeXML(book.publisher.isEmpty ? "Folio Press" : book.publisher)

        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """

        let contentOPF = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">urn:folio:demo:\(book.id)</dc:identifier>
            <dc:title>\(escapedTitle)</dc:title>
            <dc:creator>\(escapedAuthor)</dc:creator>
            <dc:publisher>\(escapedPub)</dc:publisher>
            <dc:language>zh-CN</dc:language>
            <meta property="dcterms:modified">2026-11-24T00:00:00Z</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        let navXHTML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>目录</title></head>
        <body>
          <nav epub:type="toc">
            <h1>目录</h1>
            <ol><li><a href="chapter1.xhtml">\(escapedTitle)</a></li></ol>
          </nav>
        </body>
        </html>
        """

        let chapterXHTML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
          <title>\(escapedTitle)</title>
          <style>
            body { font-family: Georgia, "Songti SC", serif; line-height: 1.8; margin: 2em; color: #222; }
            h1 { font-size: 1.8em; margin-bottom: 0.3em; }
            .meta { color: #666; font-size: 0.92em; margin-bottom: 1.8em; border-bottom: 1px solid #ddd; padding-bottom: 1em; }
            .note { margin-top: 2em; padding: 1em; background: #f6f4ef; border-radius: 8px; font-size: 0.9em; color: #555; }
          </style>
        </head>
        <body>
          <h1>\(escapedTitle)</h1>
          <div class="meta">\(escapedAuthor) · \(escapedPub) · \(escapeXML(book.year))</div>
          <p>\(escapedDesc)</p>
          <div class="note">本电子书由 Folio macOS 客户端的离线演示模式生成。连接你的 Z-Library 个人专属域名并登录后，即可下载完整原书。</div>
        </body>
        </html>
        """

        let entries: [(name: String, data: Data)] = [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(containerXML.utf8)),
            ("OEBPS/content.opf", Data(contentOPF.utf8)),
            ("OEBPS/nav.xhtml", Data(navXHTML.utf8)),
            ("OEBPS/chapter1.xhtml", Data(chapterXHTML.utf8)),
        ]
        return buildStoreZip(entries: entries)
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func buildStoreZip(entries: [(name: String, data: Data)]) -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let content = entry.data
            let crc = crc32(content)
            let localOffset = UInt32(archive.count)

            // Local File Header
            archive.appendLE(UInt32(0x04034B50))
            archive.appendLE(UInt16(20)) // version needed
            archive.appendLE(UInt16(0))  // flags
            archive.appendLE(UInt16(0))  // store (no compression)
            archive.appendLE(UInt16(0))  // mod time
            archive.appendLE(UInt16(0))  // mod date
            archive.appendLE(crc)
            archive.appendLE(UInt32(content.count))
            archive.appendLE(UInt32(content.count))
            archive.appendLE(UInt16(nameData.count))
            archive.appendLE(UInt16(0))  // extra length
            archive.append(nameData)
            archive.append(content)

            // Central Directory Header
            centralDirectory.appendLE(UInt32(0x02014B50))
            centralDirectory.appendLE(UInt16(20)) // version made by
            centralDirectory.appendLE(UInt16(20)) // version needed
            centralDirectory.appendLE(UInt16(0))  // flags
            centralDirectory.appendLE(UInt16(0))  // store
            centralDirectory.appendLE(UInt16(0))  // time
            centralDirectory.appendLE(UInt16(0))  // date
            centralDirectory.appendLE(crc)
            centralDirectory.appendLE(UInt32(content.count))
            centralDirectory.appendLE(UInt32(content.count))
            centralDirectory.appendLE(UInt16(nameData.count))
            centralDirectory.appendLE(UInt16(0))  // extra
            centralDirectory.appendLE(UInt16(0))  // comment
            centralDirectory.appendLE(UInt16(0))  // disk
            centralDirectory.appendLE(UInt16(0))  // internal attr
            centralDirectory.appendLE(UInt32(0))  // external attr
            centralDirectory.appendLE(localOffset)
            centralDirectory.append(nameData)
        }

        let cdOffset = UInt32(archive.count)
        let cdSize = UInt32(centralDirectory.count)
        archive.append(centralDirectory)

        // End of Central Directory Record
        archive.appendLE(UInt32(0x06054B50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(cdSize)
        archive.appendLE(cdOffset)
        archive.appendLE(UInt16(0))
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}

/// 轻量级 CoreGraphics 演示 PDF 生成器
private enum DemoPDFBuilder {
    static func build(book: Book) -> Data {
        let mutableData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        ctx.beginPDFPage(nil)
        // 宣纸暖白背景
        ctx.setFillColor(CGColor(red: 0.98, green: 0.975, blue: 0.955, alpha: 1))
        ctx.fill(mediaBox)

        // 顶部细装饰线
        ctx.setFillColor(CGColor(red: 0.16, green: 0.24, blue: 0.34, alpha: 1))
        ctx.fill(CGRect(x: 56, y: 760, width: 48, height: 3))

        drawText(book.title, in: CGRect(x: 56, y: 650, width: 483, height: 96), fontSize: 28, bold: true, ctx: ctx)
        let meta = [book.authors, book.publisher, book.year].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        drawText(meta, in: CGRect(x: 56, y: 615, width: 483, height: 32), fontSize: 13, bold: false, ctx: ctx)
        drawText(book.description, in: CGRect(x: 56, y: 340, width: 483, height: 240), fontSize: 14, bold: false, ctx: ctx)
        drawText("由 Folio macOS 客户端演示模式生成 · 登录后可下载真实完整电子书", in: CGRect(x: 56, y: 80, width: 483, height: 40), fontSize: 11, bold: false, ctx: ctx)

        ctx.endPDFPage()
        ctx.closePDF()
        return mutableData as Data
    }

    private static func drawText(_ text: String, in rect: CGRect, fontSize: CGFloat, bold: Bool, ctx: CGContext) {
        let fontName = bold ? "PingFangSC-Semibold" : "PingFangSC-Regular"
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.16, alpha: 1),
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, ctx)
    }
}
